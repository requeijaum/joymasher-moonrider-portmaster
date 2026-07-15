# Relatório de Sessão — Moonrider PortMaster (rebuild + runtime fresh)

**Data:** 2026-07-15
**Projeto:** `moonrider-pm/` — template PortMaster limpo para *Vengeful Guardian: Moonrider* (Construct 2 / HTML5 sobre runtime WPE WebKit aarch64)
**Alvo testado:** Anbernic RG40xx H · muOS 2508.4 "LOOSE GOOSE" (H700, Mali-G31, kernel 4.9.170, aarch64)
**Remoto:** `git@github.com:requeijaum/joymasher-moonrider-portmaster.git`

---

## ⚖️ Nota sobre direitos autorais / pirataria

Este relatório e o repositório **não contêm, não distribuem e não referenciam fontes de** conteúdo protegido do jogo:

- **Assets do jogo** (`c2runtime.js`, `data.js`, `images/`, `media/`, `asteristic_logo.mp4` etc.) são **bring-your-own**: o usuário final deve fornecê-los a partir de uma **cópia legítima que ele possua**. Ficam em `moonrider/game/`, que é **gitignored** — nunca versionados, nunca empacotados na distribuição canônica.
- **Runtime WPE aarch64** (bibliotecas WPEWebKit/GStreamer/ICU etc.) é software com suas próprias licenças (majoritariamente LGPL/BSD/MIT); é **gitignored** e montado a partir de uma cadeia de build própria — não é conteúdo do jogo.
- Nenhuma ROM, dump, chave, BIOS ou binário proprietário do jogo é incluído.
- O template é **apenas o encanamento** (launcher, scripts de build, runtime livre) que roda um jogo que o usuário **já possui legalmente**.

Não há nenhum caminho, link ou instrução neste projeto para **obter** o jogo por meios não autorizados.

---

## Objetivo da sessão

Auditar o template recém-criado ("verifique se não erramos/esquecemos"), garantir que a documentação de containers/cross-compile fosse **fiel** (não inventada), reconstruir o ambiente de build **do zero** com backup, e montar um **runtime fresh** reproduzível — deixando o repositório auto-contido e honesto quanto ao que é verificado vs. pendente de teste em hardware.

---

## Linha do tempo do que foi feito

### 1. Auditoria da documentação de containers (corrigida)

A `docs/CROSS-COMPILE.md` original **inventava** a cadeia Docker. Comparada à receita real do template known-good:

| Invenção antiga | Realidade documentada |
|---|---|
| `Dockerfile.1-arm64` = "sysroot + toolchain" | só `gcc + libglib2.0-dev + pkg-config` |
| `Dockerfile.2-epoxy` = "libepoxy/GL glue" | só `meson + ninja-build` |
| `Dockerfile.3-cpp` = "WPEWebKit + cog + deps" | só `g++` |
| "runtime buildado no container" | headers/libs WPE são **bind-mounted** de `/tmp/wpe-spike/engine`, não compilados via apt |

Ações: vendorados `docker/Dockerfile` + `docker/original-chain/` reais; `scripts/build-launcher-backend.sh` real trazido; doc reescrita fielmente.

### 2. Remoção de fabricações no launcher e nos controles

- `Moonrider.sh` inventava `cog`, `COG_MODULEDIR`, `pm_platform_helper` → reescrito para o mecanismo real (parar o frontend do muOS, lockfile, `runtime/run-moonrider.sh`).
- `moonrider.gptk` + toda menção a **gptokeyb** removidos: o port lê **evdev diretamente** dentro do launcher (`evdev_gamepad.c` + `exit_combo.h`).
- **Tabela de controles do jogo** (A=Jump, B=Attack…) era **inventada** → substituída por nota honesta "mapeamento in-game definido pelo jogo, não confirmado on-device".
- **Combo de saída** corrigido: não é hold simples, é **L2 + R1 pressionado 2× em 2s** (double-edge, `btn[6]`=L2, `btn[5]`=R1).
- `port.json` alinhado ao formato canônico (`version: 3`, `desc_pt`, `reqs: ["gles"]`); `build_zip.json` limpo.

### 3. Rebuild do ambiente Docker do zero (com backup)

- **Backup do insubstituível primeiro:** `/tmp/wpe-spike` (engine WPE aarch64, não reproduzível pelo Dockerfile, some no reboot) zipado para o pendrive **external backup drive** antes de qualquer exclusão.
- Apagadas as 3 imagens `wpebuild` (cpp/epoxy/arm64) + `/tmp/wpe-spike` — recomeço 100% limpo (autorizado).
- **Rebuild** de `wpebuild:cpp` a partir de `docker/Dockerfile`: imagem `ffe2c1bfc409`, arm64/debian bookworm, ~286s (emulado), verificada dentro (gcc/g++ 12.2, glib 2.74.6, vorbis 1.3.7, ogg 1.3.5, alsa 1.2.8).

### 4. Cross-compile do launcher backend

Engine restaurado do backup para `/tmp/wpe-spike` (591 MB). Build dentro de `wpebuild:cpp` com `/tmp/wpe-spike` montado como `/work`:

| Artefato | Tamanho | Tipo |
|---|---|---|
| `moonrider-launch` | 692 KB | ELF aarch64 PIE executable |
| `libWPEBackend-mali-fbdev.so` | 71 KB | ELF aarch64 shared object |
| `muos_audio_mixer.o` | 849 KB | ELF aarch64 relocatable |

Dependências `NEEDED` verificadas via `readelf`, todas satisfeitas pelo runtime + libs do device. O `moonrider-launch` resultante bate (byte-count) com o known-good (707.744 vs 707.704 B — diferença esperada de timestamps/paths).

### 5. Runtime fresh remontado (`scripts/assemble-runtime-fresh.sh`)

Decisão do usuário: runtime **fresh** (remontado das fontes verdadeiras), **gitignored**, com **backup**. O script de montagem reconstrói cada subtree com proveniência conhecida:

| Subtree | Fonte | Arquivos |
|---|---|---|
| `libs/` | engine/root `.so` flat + krb5/keyutils/spake | 150 |
| `lib/` | WPE processes, cog modules, injected bundle (engine) + **backend fresh** + glx-stub | 9 |
| `gst-plugins/` | audio set preparado + core elements/tracers (engine) | 24 |
| `bin/` | **`moonrider-launch` fresh** + `cog` (engine) | 2 |
| `run-moonrider.sh` | vendorado de `runtime-config/` (config, não binário) | — |

`registry.bin` intencionalmente omitido (regenerado em tmpfs no device pelo `run-moonrider.sh`).

**Gaps reais encontrados e corrigidos durante a montagem:** gst-plugins core (`coreelements`/`coretracers`) e deps krb5 (`com_err`/`keyutils`/`spake`) estavam em subdirs fora do `maxdepth 1` inicial — script ajustado.

**Validação:** montado em `/tmp/moonrider-runtime-fresh` (350 MB); **0 dependências não resolvidas** em `moonrider-launch` + `WPEWebProcess` + backend mali-fbdev (excluindo libs de sistema/device). `moonrider-launch` no tree é byte-a-byte o recém-buildado.

### 6. Correções de consistência dos scripts (auto-contido)

Auditoria dos scripts importados encontrou 3 defeitos reais, todos corrigidos:

- `import-runtime-from-scratch.sh`: destino `$ROOT/runtime` (layout antigo) → `$ROOT/moonrider/runtime`.
- `import-device-devlibs.sh`: destino inexistente `$ROOT/audio-mixer/devlibs` → scratch de build (`DEVLIBS_DEST`); `SSHPASS` deixou de ter default enganoso `root`, agora exige senha explícita.
- `assemble-runtime-fresh.sh`: `REF_RUN` dependia do repo externo `../moonrider-portmaster-template` → **vendorado** `runtime-config/run-moonrider.sh`. **Repo agora auto-contido.**

### 7. `.gitignore` corrigido

Descoberto que `moonrider/runtime/` **não** estava sendo ignorado (só `game/`). Adicionada regra: `moonrider/runtime/*` ignorado, `README.md` preservado. Binários aarch64 nunca versionados; instalador no device monta (copia) ou verifica (já no zip).

---

## Backups no pendrive external backup drive (`Portsmaster/`)

| Zip | Tamanho | Conteúdo |
|---|---|---|
| `wpe-spike-engine-backup-20260715.zip` | 244 MB | engine + backend + audio-mixer scratch |
| `moonrider-runtime-known-good-20260715.zip` | 105 MB | runtime de referência do template antigo |
| `moonrider-runtime-fresh-20260715.zip` | 134 MB | runtime recém-montado |

Todos verificados com `unzip -t`. Nenhuma escrita no SSD (que está em 100%, ~3,4 GB livres) — montagem e zips feitos em `/tmp` (tmpfs) e direto no pendrive.

---

## Commits da sessão

```
7d3bcf9 fix: self-contained scripts (correct paths, vendored run-moonrider.sh)
3c62d41 runtime: fresh-assembly script + import scripts + gitignore runtime
b2702a0 build: cross-compile launcher backend from restored engine
6077c54 docs: from-scratch rebuild of wpebuild:cpp with backup provenance
8467531 docs: stop asserting unverified controls; fix quit combo semantics
891bb8c docs/containers: replace invented recipe with the real cross-compile chain
```

(Base da sessão: `d3b3fc1`, `cf19304`, `41384f2`.)

---

## Estado final

- Repositório **auto-contido**, sem paths quebrados nem dependência de repo externo.
- Documentação **honesta**: separa o que foi verificado do que é fabricação removida; cadeia de build reproduzível a partir do backup + `docker/Dockerfile`.
- Runtime fresh validado (0 deps órfãs) e com backup.
- `wpebuild:cpp` reconstruída e verificada.

## Pendências (requerem hardware)

1. Empacotar o zip do port **com o runtime fresh** em `/tmp` (nunca no SSD).
2. Deploy no RG40xx H (`<device-ip>`).
3. Boot pelo menu Ports e validar: vídeo (WPE/fbdev/Mali), áudio (mixer + ALSA), intro `asteristic_logo.mp4`, e o combo de saída **L2 + R1 (2×)**.
4. Confirmar o mapeamento in-game real dos botões (hoje documentado como não confirmado).

## Notas de manutenção (fora do escopo do port)

- SSD em **100%** (~3,4 GB livres) — evitar qualquer escrita de artefato grande no `/`.
- Checkpoint store do Hermes inchado (**~7,7 GB**) com objeto git corrompido, gerando avisos de "sibling subagent" falso-positivos — candidato a limpeza em passo separado.
