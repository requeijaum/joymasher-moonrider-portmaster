# wpebuild — container de build cross-compile ARM64 para o launcher Moonrider (muOS/RG40XX H).
#
# Reproduz a imagem wpebuild:cpp usada nesta sessao (Debian 12 bookworm arm64) e ADICIONA
# git + utilitarios que faltavam (unzip/rsync/file/curl/cmake), para que o build seja
# reproduzivel a partir do codigo, sem depender de uma imagem efemera no daemon local.
#
# A imagem e NATIVA arm64: no host amd64 roda emulada via binfmt/qemu (docker buildx/qemu-user).
# Os headers/libs do WPE-WebKit NAO sao instalados via apt — vem montados em /work/engine/root
# (host: /tmp/wpe-spike/engine). Ver scripts/build-launcher-backend.sh.
#
# Build:
#   docker buildx build --platform linux/arm64 -t wpebuild:cpp -f docker/Dockerfile .
# (garanta o binfmt do qemu no host: docker run --privileged --rm tonistiigi/binfmt --install arm64)
#
# Uso (compilar o launcher):
#   docker run --rm -v "$PWD":/work -v /tmp/wpe-spike/engine:/work/engine -w /work \
#     wpebuild:cpp bash scripts/build-launcher-backend.sh

FROM --platform=linux/arm64 debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

# Toolchain de build + dependencias -dev usadas pelo launcher/mixer, e utilitarios de
# empacotamento/versionamento (git, unzip, rsync, file, curl) que faltavam na imagem antiga.
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      gcc g++ \
      make cmake meson ninja-build pkg-config \
      libglib2.0-dev \
      libvorbis-dev libogg-dev \
      libasound2-dev \
      ca-certificates \
      git unzip rsync file curl \
    && rm -rf /var/lib/apt/lists/*

# Marca o /work como safe.directory para o git operar em repos montados como volume
# (evita "detected dubious ownership" quando o UID do host difere do container).
RUN git config --system --add safe.directory /work \
 && git config --system --add safe.directory '*'

WORKDIR /work

CMD ["bash"]
