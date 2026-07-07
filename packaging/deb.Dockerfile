# syntax=docker/dockerfile:1.7
#
# Builds an OpenSlide .deb for a given Debian/Ubuntu base image and
# architecture, exported via the `export` stage. `smoke-test` installs that
# .deb with `apt install` in a clean container to check it actually works.
#
# Usage:
#   docker buildx build \
#     --platform linux/amd64 \
#     --build-arg BASE_IMAGE=debian:trixie-slim \
#     --build-arg DISTRO_LABEL=debian-trixie \
#     --target export \
#     --output type=local,dest=dist \
#     -f packaging/deb.Dockerfile .
#
#   docker buildx build \
#     --platform linux/amd64 \
#     --build-arg BASE_IMAGE=debian:trixie-slim \
#     --target smoke-test \
#     -f packaging/deb.Dockerfile .

ARG BASE_IMAGE=debian:trixie-slim

FROM ${BASE_IMAGE} AS builder

ARG TARGETARCH
ARG DISTRO_LABEL=unknown

ENV DEBIAN_FRONTEND=noninteractive \
    DEB_BUILD_OPTIONS=nocheck

# dh-meson builds with buildtype=plain (Debian's own -O2), so -O3 has to come
# in via this Debian-native append hook instead of meson's -Dbuildtype.
ENV DEB_CFLAGS_MAINT_APPEND="-O3" \
    DEB_CXXFLAGS_MAINT_APPEND="-O3"

# jpeg-dev package name differs between Debian and Ubuntu.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    . /etc/os-release && \
    case "$ID" in \
      debian) JPEG_DEV=libjpeg-dev ;; \
      ubuntu) JPEG_DEV=libjpeg-turbo8-dev ;; \
      *) echo "Unsupported base image ID=$ID" >&2; exit 1 ;; \
    esac && \
    apt-get update && apt-get upgrade -y && \
    apt-get install --no-install-recommends -y \
      build-essential ninja-build meson pkg-config git debhelper fakeroot \
      ca-certificates python3 \
      libcairo2-dev libglib2.0-dev "$JPEG_DEV" libopenjp2-7-dev libpng-dev \
      libsqlite3-dev libtiff-dev libxml2-dev libzstd-dev zlib1g-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/src/openslide
COPY . .
COPY packaging/debian debian

# libdicom/uthash only exist as Meson wraps, but dh-meson builds with
# --wrap-mode=nodownload. This throwaway setup pre-fetches them into
# subprojects/packagecache/ while network access is still allowed.
RUN meson setup --prefix /usr -Db_lto=true -Dtest=disabled -Ddoc=disabled builddir && \
    rm -rf builddir

# Version comes from meson.build so it can't drift from what was built.
RUN VERSION=$(grep -oP "^\s*version\s*:\s*'\K[^']+" meson.build | head -1) && \
    test -n "$VERSION" && \
    echo "$VERSION" > /tmp/version && \
    sed -i "s/@VERSION@/${VERSION}/; s/@DATE@/$(date -R)/" debian/changelog && \
    dpkg-buildpackage -rfakeroot -us -uc -b

# Verify openslide.pc is packaged, then stage both artifacts under their
# final distro/arch-disambiguated names.
RUN VERSION=$(cat /tmp/version) && \
    ARCH=$(dpkg --print-architecture) && \
    DEV_DEB=$(ls ../libopenslide-dev_"$VERSION"-1_*.deb) && \
    RUNTIME_DEB=$(ls ../libopenslide1_"$VERSION"-1_*.deb) && \
    dpkg -c "$DEV_DEB" | grep -qE 'usr/lib/.*/pkgconfig/openslide\.pc' \
      || { echo "ERROR: openslide.pc missing from $DEV_DEB" >&2; exit 1; } && \
    mkdir -p /export && \
    cp "$RUNTIME_DEB" /export/libopenslide1_"${VERSION}"-1_"${DISTRO_LABEL}"_"${ARCH}".deb && \
    cp "$DEV_DEB" /export/libopenslide-dev_"${VERSION}"-1_"${DISTRO_LABEL}"_"${ARCH}".deb

FROM scratch AS export
COPY --from=builder /export/*.deb /

# Installs both .debs with `apt install` (resolves Depends: automatically,
# unlike `dpkg -i`) in a clean container, then compiles+links+runs a program
# against it to prove the dev package actually works for a consumer.
FROM ${BASE_IMAGE} AS smoke-test

COPY --from=builder /export/*.deb /tmp/

RUN apt-get update && \
    apt-get install --no-install-recommends -y gcc libc6-dev pkg-config /tmp/libopenslide1_*.deb /tmp/libopenslide-dev_*.deb && \
    rm -rf /var/lib/apt/lists/* /tmp/*.deb && \
    ldconfig && \
    ldconfig -p | grep -q 'libopenslide\.so' && \
    pkg-config --exists openslide && \
    pkg-config --modversion openslide && \
    printf '%s\n' \
      '#include <openslide.h>' \
      '#include <stdio.h>' \
      'int main(void) {' \
      '  const char *v = openslide_detect_vendor("/nonexistent");' \
      '  printf("openslide_detect_vendor: %s\n", v ? v : "(null)");' \
      '  return 0;' \
      '}' \
      > /tmp/test.c && \
    cc /tmp/test.c $(pkg-config --cflags --libs openslide) -o /tmp/test && \
    ! ldd /tmp/test | grep -qi 'not found' && \
    /tmp/test
