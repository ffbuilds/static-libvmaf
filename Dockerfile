# syntax=docker/dockerfile:1

# bump: vmaf /VMAF_VERSION=([\d.]+)/ https://github.com/Netflix/vmaf.git|*
# bump: vmaf after ./hashupdate Dockerfile VMAF $LATEST
# bump: vmaf link "Release" https://github.com/Netflix/vmaf/releases/tag/v$LATEST
# bump: vmaf link "Source diff $CURRENT..$LATEST" https://github.com/Netflix/vmaf/compare/v$CURRENT..v$LATEST
ARG VMAF_VERSION=2.3.1
ARG VMAF_URL="https://github.com/Netflix/vmaf/archive/refs/tags/v$VMAF_VERSION.tar.gz"
ARG VMAF_SHA256=8d60b1ddab043ada25ff11ced821da6e0c37fd7730dd81c24f1fc12be7293ef2

# Must be specified
ARG ALPINE_VERSION

FROM alpine:${ALPINE_VERSION} AS base

FROM base AS download
ARG VMAF_URL
ARG VMAF_SHA256
ARG WGET_OPTS="--retry-on-host-error --retry-on-http-error=429,500,502,503 -nv"
WORKDIR /tmp
RUN \
  apk add --no-cache --virtual download \
    coreutils wget tar && \
  wget $WGET_OPTS -O vmaf.tar.gz "$VMAF_URL" && \
  echo "$VMAF_SHA256  vmaf.tar.gz" | sha256sum --status -c - && \
  mkdir vmaf && \
  tar xf vmaf.tar.gz -C vmaf --strip-components=1 && \
  rm vmaf.tar.gz && \
  apk del download

FROM base AS build
COPY --from=download /tmp/vmaf/ /tmp/vmaf/
WORKDIR /tmp/vmaf/libvmaf
RUN \
  apk add --no-cache --virtual build \
    build-base meson ninja nasm xxd pkgconf && \
  meson build --buildtype=release -Ddefault_library=static -Dbuilt_in_models=true -Denable_tests=false -Denable_docs=false -Denable_avx512=true -Denable_float=true && \
  ninja -j$(nproc) -vC build install && \
  # extra libs stdc++ is for vmaf https://github.com/Netflix/vmaf/issues/788
  sed -i 's/-lvmaf /-lvmaf -lstdc++ /' /usr/local/lib/pkgconfig/libvmaf.pc && \
  # Sanity tests
  pkg-config --exists --modversion --path libvmaf && \
  ar -t /usr/local/lib/libvmaf.a && \
  readelf -h /usr/local/lib/libvmaf.a && \
  # Cleanup
  apk del build

FROM scratch
ARG VMAF_VERSION
COPY --from=build /usr/local/lib/pkgconfig/libvmaf.pc /usr/local/lib/pkgconfig/libvmaf.pc
COPY --from=build /usr/local/lib/libvmaf.a /usr/local/lib/libvmaf.a
COPY --from=build /usr/local/include/libvmaf/ /usr/local/include/libvmaf/
