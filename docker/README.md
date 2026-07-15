# Container de build — wpebuild

Este diretório versiona a **receita do container** que cross-compila o launcher ARM64
do Moonrider (`bin/moonrider-launch`) e o backend WPE, para que o build seja reproduzível
a partir do código — sem depender de uma imagem efêmera no daemon Docker local.

## `Dockerfile` (canônico — use este)

Estágio único, `linux/arm64` sobre `debian:bookworm`. Consolida a cadeia de 3 imagens
originais **e adiciona** o que faltava na imagem antiga: `git`, `unzip`, `rsync`, `file`,
`curl`, além das libs `-dev` de vorbis/ogg/asound usadas pelo mixer.

### Build da imagem
```sh
# garante o binfmt do qemu no host (host amd64 rodando imagem arm64):
docker run --privileged --rm tonistiigi/binfmt --install arm64

docker buildx build --platform linux/arm64 -t wpebuild:cpp -f docker/Dockerfile .
```

### Compilar o launcher
Os headers/libs do WPE-WebKit NÃO vêm de apt — são montados de `/tmp/wpe-spike/engine`
(host) em `/work/engine` (container). Ver `scripts/build-launcher-backend.sh`.
```sh
docker run --rm \
  -v "$PWD":/work \
  -v /tmp/wpe-spike/engine:/work/engine \
  -w /work \
  wpebuild:cpp bash scripts/build-launcher-backend.sh
```
O launcher sai em `backend/moonrider-launch` (ARM64). Copie para `bin/` e faça deploy
com `scripts/deploy-rsync-release.sh`.

## `original-chain/` (proveniência histórica)

A imagem `wpebuild:cpp` desta sessão foi construída como 3 camadas encadeadas
(recuperadas de `/tmp/wpe-spike/Dockerfile.*`):

```
debian:bookworm-slim
  └─ Dockerfile.1-arm64  : +gcc libglib2.0-dev pkg-config   → wpebuild:arm64
       └─ Dockerfile.2-epoxy : +meson ninja-build            → wpebuild:epoxy
            └─ Dockerfile.3-cpp : +g++                       → wpebuild:cpp
```

O `Dockerfile` canônico acima é um superset correto dessas 3 camadas (mesma base,
mesmos pacotes, mais utilitários). A cadeia fica preservada apenas para referência —
não é necessária para buildar.

`build-launcher-backend.sh.spike` é a cópia do script de build como estava no diretório
de spike (`/tmp/wpe-spike`), guardada para diff histórico com `scripts/build-launcher-backend.sh`.
