# RELATÓRIO DE SESSÃO — Moonrider Port muOS: do quebrado ao jogável

**Data:** 2026-07-15 (~6 horas de sessão)
**Autor:** Rafael + Hermes
**Projeto:** Vengeful Guardian: Moonrider (Construct 2 / HTML5) sobre WPE WebKit
aarch64, portado para Anbernic RG40xx H / muOS 2508.4 (H700 / Mali-G31).
**Resultado:** JOGÁVEL — vídeo + som + gamepad OK, confirmado empiricamente.

> Objetivo deste documento: permitir **reproduzir o estado jogável de forma
> limpa**, entendendo POR QUE cada peça é necessária. Foram ~6h de tentativa;
> este relatório existe pra que ninguém tenha que redescobrir isto.

---

## 1. SUMÁRIO EXECUTIVO

O port estava subindo o runtime WPE mas **o WebProcess morria antes do 1º frame**
(tela sem render) e, quando renderizava, **a música cortava**. Duas causas-raiz
distintas, ambas resolvidas:

1. **Vídeo não renderizava** → o `libepoxy` resolvia o `libGL.so.1` do **gl4es**,
   que NÃO exporta `glXGetCurrentContext`; o WebProcess abortava a init GL.
   **Fix:** uma `libGL.so.1` **stub própria** (todos os símbolos GLX → NULL)
   colocada em `runtime/libs/`, que precede `/usr/lib/gl4es` no `LD_LIBRARY_PATH`.
   Assim o epoxy conclui "sem contexto GLX" e usa o caminho **EGL** (correto p/
   fbdev/Mali).

2. **Música do seletor de fase "tocava rapidinho e parava"** → o console tinha o
   conjunto de áudio **v8 sem PLAYPAIR** (handoff intro→loop via `setTimeout` no
   ghost, que falhava). **Fix:** deploy do **trio PLAYPAIR** (launcher + ghost
   v11 + mixer nativo) que emenda intro→loop no mixer.

Fixes de apoio: parar o frontend do muOS de verdade (`SAFE_QUIT`) e tirar
`libs/` do `GST_PLUGIN_PATH` (evita o scan da `libgstgl`).

---

## 2. AMBIENTE / TOPOLOGIA

- **Device:** RG40xx H, muOS 2508.4 LOOSE GOOSE, H700 (ARM aarch64), Mali-G31.
  Só fbdev + GLES (SEM Vulkan, SEM /dev/dri, SEM KMSDRM, SEM X11).
- **IP:** atribuído por DHCP e omitido do repositório público. SSH root, sem pubkey.
- **Runtime WPE:** WebKit `libWPEWebKit-1.1.so.0.2.9` (md5 08bd49e1), libepoxy
  1.5.10 (2022, md5 fb6ba41d).
- **Backend de render:** `libWPEBackend-mali-fbdev.so` (md5 e43e27ac) — EGL
  fullscreen fbdev, sem X. Próprio (compilado no container wpebuild:cpp).
- **Áudio:** mixer NATIVO IPC (miniaudio + libvorbis) FORA do WebProcess, porque
  o único sink GStreamer disponível trava no sandbox. PipeWire no device
  (socket /run/pipewire-0); ALSA default → PipeWire.

Paths no device:
```
/mnt/sdcard/ports/moonrider/runtime/bin/moonrider-launch   (launcher)
/mnt/sdcard/ports/moonrider/runtime/lib/libWPEBackend-mali-fbdev.so
/mnt/sdcard/ports/moonrider/runtime/lib/glx-stub.so        (LD_PRELOAD)
/mnt/sdcard/ports/moonrider/runtime/libs/                  (WebKit + libGL stub)
/mnt/sdcard/ports/moonrider/runtime/gst-plugins/           (plugins de audio)
/mnt/sdcard/ports/moonrider/game/                          (c2runtime + ghost + 283 oggs)
/mnt/mmc/mr-ctl.sh, mr-v8style.sh, mr-play.sh              (runners de teste)
/mnt/mmc/moonrider-diag.log, mr-*.log                      (logs)
```

---

## 3. AS DUAS CAUSAS-RAIZ (em detalhe)

### 3.1 VÍDEO — o WebProcess morria no glX

**Sintoma no log:**
```
[mali-fbdev] TARGET resize 640x480
glXGetCurrentContext() not found: /usr/lib/gl4es/libGL.so.1: undefined symbol: glXGetCurrentContext
[launch] main loop encerrado; saindo limpo
```
0 frames renderizados; WebProcess saía "limpo" (sem segfault) logo após o resize.
O v8 known-good NUNCA teve essa linha — chegava a 95+ `dispatch_frame_complete`.

**Cadeia causal (confirmada):**
- A mensagem `%s() not found: %s` é emitida pelo **libepoxy** (não pelo gl4es).
- O `libepoxy.so.0` tem `NEEDED libGL.so.1`. No `LD_LIBRARY_PATH` havia
  `/usr/lib/gl4es`, cujo `libGL.so.1` exporta apenas `glXGetProcAddress` — **NÃO**
  exporta `glXGetCurrentContext`.
- Na init, o epoxy resolve `glXGetCurrentContext` via o `libGL.so.1` do gl4es,
  não encontra o símbolo e **aborta a inicialização GL do WebProcess** antes do
  primeiro frame.

**Por que o glx-stub (LD_PRELOAD) não bastava:** o glx-stub.so exporta o símbolo,
mas o epoxy resolve o símbolo especificamente via o `libGL.so.1` (dlopen do
NEEDED), não pelo preload global — então o gl4es "ganhava".

**Por que não dá pra só remover o gl4es do path:** o `libepoxy` tem o NEEDED
`libGL.so.1`; sem NENHUM `libGL.so.1` alcançável, o launcher nem carrega:
```
error while loading shared libraries: libGL.so.1: cannot open shared object file
(exit 127)
```

**FIX — libGL.so.1 stub própria:**
Uma `libGL.so.1` que **exporta os ~21 símbolos GLX retornando NULL/0**, colocada
em `runtime/libs/` (que precede `/usr/lib/gl4es` no path). O epoxy carrega a
stub, conclui "nenhum contexto GLX ativo" e cai no caminho **EGL** — que é o
correto pro Mali/fbdev. O backend usa EGL + GLES via `eglGetProcAddress`, então
nenhuma função desktop-GL real é chamada em runtime.

Fonte: `runtime-fixes/libgl-stub.c`. Compilada no container `wpebuild:cpp`:
```
aarch64-linux-gnu-gcc -O2 -fPIC -shared -Wl,-soname,libGL.so.1 \
    libgl-stub.c -o libGL.so.1
```

### 3.2 ÁUDIO — música do seletor de fase cortava

**Sintoma (Rafael):** a música do seletor de fase (mapa) "toca rapidinho e para".

**Causa:** durante a caça ao bug de vídeo, o console ficou com o conjunto de
áudio **v8 SEM PLAYPAIR** (`muos_audio_ghost.js` 18759 B, PLAYPAIR=0; launcher
sem handler PLAYPAIR). Nesse v8 o handoff intro→loop da música era feito por
`setTimeout` no ghost, que falhava — a intro tocava e o loop não emendava.

Existia um **trio PLAYPAIR** mais novo e coerente no
`moonrider-portmaster-template/`:
- launcher com handler `PLAYPAIR` + `muos_mixer_play_pair`
- ghost v11 que emite `PLAYPAIR|intro_id|loop_id|vol|intro_ms|intro_path|loop_path`
- mixer nativo (`muos_audio_mixer.c`) que toca a intro e **agenda o loop pra
  emendar** quando a intro acaba; parar a intro cancela o loop agendado.

**FIX:** deploy do trio PLAYPAIR. Confirmado no log:
```
[mixer] PLAYPAIR intro=1268309330 loop=363882720 ms=5116 ...
```
Rafael confirmou: **música rodou OK**.

### 3.3 Fixes de apoio

- **Frontend não parava** → o `FRONTEND stop` do muOS só faz o `muxfrontend`
  SAIR quando `$SAFE_QUIT` está setado (ele grava um flag-file p/ o handler de
  sinal saber que o quit é intencional). Lançado por SSH não herdávamos a env.
  **Fix:** setar `SAFE_QUIT=/run/muos_safe_quit` + `: > $SAFE_QUIT` antes do
  stop; fallback `SIGSTOP`/`SIGCONT` no muxfrontend (congela sem matar, libera
  o fb0). **Restore do frontend por SSH NÃO persiste → só volta com reboot.**
- **GST_PLUGIN_PATH** → remover `$D/libs` (deixar só `$D/gst-plugins`) evita o
  scanner tentar carregar `libgstgl-1.0.so` como plugin (falha em
  `glXMakeCurrent`). Os plugins de áudio reais estão em `gst-plugins/`; a
  libgstgl fica em `libs/` só p/ satisfazer o NEEDED da WebKit.

---

## 4. ESTADO JOGÁVEL — MANIFESTO (md5 / caminhos)

Arquivos-chave no console no momento em que ficou jogável:

| Arquivo | md5 | Tamanho | Caminho no device |
|---|---|---|---|
| moonrider-launch | `5fb4cbd47ee802dfb1636f65bd27d41d` | 707744 B | runtime/bin/ |
| muos_audio_ghost.js (v11 PLAYPAIR) | `317334f0045bd2c2aef423a164db8124` | 31502 B | game/ |
| libGL.so.1 (STUB) | `1115e827437465a2221e0baf8611379e` | 70224 B | runtime/libs/ |
| libWPEBackend-mali-fbdev.so | `e43e27acee6960a5ac8ee2ca0011dd02` | — | runtime/lib/ |
| glx-stub.so (LD_PRELOAD) | `36f68035bcc7232807af76b59d0e2ea5` | — | runtime/lib/ |

- game/media: **283 .ogg**
- libgstgl (597224 B) presente em `libs/` como `.so`, `.so.0`, `.so.0.2200.0`
  — mantida só p/ NEEDED da WebKit; fora do GST_PLUGIN_PATH (não escaneada).

---

## 5. RECEITA DE REPRODUÇÃO LIMPA (do zero)

Pré-requisito: runtime WPE base + game já no cartão (dos zips grandes
`Moonrider-playable`/`moonrider-runtime-*` de 2026-07-15 01:xx no external backup drive), OU
o pacote `moonrider-ESTADO-JOGAVEL-*.zip` que já traz os 3 arquivos de fix.

1. **Backend + WebKit + backend fbdev** já no runtime (base). Confirmar
   `libWPEBackend-mali-fbdev.so` md5 e43e27ac e `glx-stub.so` presentes.

2. **Instalar a libGL stub** (CRÍTICO p/ vídeo):
   ```
   cp libGL.so.1  ->  runtime/libs/libGL.so.1
   ```
   (Precede /usr/lib/gl4es no LD_LIBRARY_PATH. NÃO remover: libepoxy NEEDED.)

3. **Instalar o trio PLAYPAIR** (CRÍTICO p/ áudio):
   ```
   cp moonrider-launch      ->  runtime/bin/moonrider-launch   (md5 5fb4cbd4)
   cp muos_audio_ghost.js   ->  game/muos_audio_ghost.js       (md5 317334f0, v11)
   chmod +x runtime/bin/moonrider-launch
   ```
   (O mixer PLAYPAIR está embutido no binário do launcher.)

4. **Env de execução** (ver `mr-ctl.sh` / `mr-v8style.sh`, valores comprovados):
   ```sh
   D=<...>/runtime; GAMEDIR=<...>
   LD_LIBRARY_PATH="$D/libs:$D/lib:/usr/lib/gl4es:/usr/lib:/lib"   # libs/ tem a stub
   LIBGL_FB=2 LIBGL_ES=2 WEBKIT_GST_DISABLE_GL_SINK=1
   GST_PLUGIN_PATH="$D/gst-plugins"          # SEM :libs
   GST_PLUGIN_SYSTEM_PATH="$D/gst-plugins"
   GST_REGISTRY_UPDATE=yes GST_REGISTRY_FORK=no   # device sem gst-plugin-scanner
   XDG_RUNTIME_DIR=/run PIPEWIRE_RUNTIME_DIR=/run # ALSA default->PipeWire
   WPE_BACKEND="$D/lib/libWPEBackend-mali-fbdev.so"
   WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 WEBKIT_FORCE_COMPOSITING_MODE=1
   LD_PRELOAD="$D/lib/glx-stub.so"
   exec "$D/bin/moonrider-launch" "file://$GAMEDIR/game/index.html"
   ```

5. **Parar o frontend antes** (senão fb0 preso):
   ```sh
   . /opt/muos/script/var/func.sh
   export SAFE_QUIT=/run/muos_safe_quit; : > "$SAFE_QUIT"
   FRONTEND stop
   pgrep -x muxfrontend >/dev/null && kill -STOP "$(pgrep -x muxfrontend)"  # fallback
   ```
   No fim: `kill -CONT` se congelou; senão **reboot** p/ o menu voltar.

6. **Validar no log** (`mr-play.log`):
   - vídeo: `TARGET resize 640x480` seguido de progressão de layouts
     (`intrologo → cutscene_intro → options → map → stage`), `glX not found`
     count = 0.
   - áudio: `[mixer] PLAYPAIR intro=... loop=...` (música emendando).
   - gamepad: `Using XBOX buttons` + eventos evdev.

---

## 6. ARMADILHAS (o que NÃO fazer)

- **NÃO remover a libGL.so.1** achando que "não precisa de GL" → exit 127
  (libepoxy tem NEEDED). Use a STUB.
- **NÃO usar o gl4es libGL.so.1** para satisfazer o NEEDED → falta
  `glXGetCurrentContext`, WebProcess morre. A stub tem que preceder o gl4es.
- **NÃO incluir `libs` no GST_PLUGIN_PATH** → scanner tenta libgstgl, falha glX.
- **NÃO confiar no restore de frontend por SSH** → não persiste; use reboot.
- **NÃO deployar só parte do trio PLAYPAIR** → launcher + ghost + mixer são
  acoplados (protocolo PLAYPAIR). Ghost novo com launcher v8 = música não toca.
- **NÃO matar processos com kill -KILL**; usar TERM/CONT.
- **SSD `/` da máquina de dev ~94-98% cheio** → nunca escrever no SSD; usar /tmp
  (tmpfs) e o backup externo external backup drive.

---

## 7. BACKUPS (em /path/to/external-backup/Portsmaster/)

- `moonrider-ESTADO-JOGAVEL-playpair+libGLstub-20260715.zip` (292 KB) — os 3
  arquivos de fix + runners + README de restore + este tipo de relatório.
  **Este é o backup canônico do estado jogável.**
- `moonrider-FIX-breakthrough-20260715.zip` (11 KB) — só o fix de vídeo.
- `Moonrider-playable-20260715.zip` (274 MB) — runtime + game COMPLETO, mas de
  01:xx (ANTES dos 2 fixes). Base p/ reconstrução.
- `moonrider-runtime-{fresh,known-good}-20260715.zip` — runtimes base.
- `wpe-spike-engine-backup-20260715.zip` (255 MB) — engine/debs de build.
- Backup do v8 anterior NO CONSOLE: `/mnt/mmc/backup-v8-noplaypair/`.

Reconstrução limpa = descompactar `Moonrider-playable` (base) + sobrepor os 3
arquivos do `ESTADO-JOGAVEL` nos caminhos da seção 5.

---

## 8. PENDÊNCIAS

Ver `TODO.md`. Destaques:
- **BUG-1 (P1):** loops de SFX curtos demais (som de correr / moto) vs celular —
  provável retrigger indevido no mixer/ghost p/ SFX contínuos.
- Consolidar os fixes no `Moonrider.sh` oficial e empacotar a libGL stub no
  runtime de release (senão um rebuild regride o vídeo).
- Silenciar warning benigno `libgstgl … glXChooseFBConfig`.
- Validação sensorial estendida; docs/DEVICE.md com IP .116; restore de
  frontend sem reboot.

---

## 9. ARTEFATOS NO REPO (moonrider-pm/)

- `runtime-fixes/libgl-stub.c` — fonte da stub
- `runtime-fixes/libGL.so.1` — stub compilada (aarch64, 21 símbolos glX)
- `runtime-fixes/muos_audio_ghost.PLAYPAIR-v11.js` — ghost com PLAYPAIR
- `scripts/mr-ctl.sh` — controller (SAFE_QUIT + env comprovado)
- `scripts/build-launcher-backend.sh` — build do launcher/backend/mixer
- `reports/RELATORIO-BREAKTHROUGH-20260715.md` — narrativa do breakthrough
- `TODO.md` — bugs e pendências
- `reports/RELATORIO-SESSAO-COMPLETA-20260715.md` — ESTE documento
