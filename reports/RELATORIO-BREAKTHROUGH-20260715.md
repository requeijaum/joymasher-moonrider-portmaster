# RELATÓRIO — MOONRIDER RODANDO (video+som+gamepad) — 2026-07-15

## RESULTADO: META ATINGIDA ✅

"Vengeful Guardian: Moonrider" (Construct 2/HTML5 sobre WPE WebKit aarch64)
está RODANDO no RG40xx H / muOS com **vídeo + som + gamepad OK**.

Confirmado empiricamente (log mr-play.log, sessão de 90s):
- 86 sons reproduzidos (MUOS_PLAY): intro logo, cutscene, SFX de gameplay
  (MRSPINJUMP2 pulo, MRSLASH3 ataque, MRLAND aterrissagem)
- Layouts percorridos: intrologo → cutscene_intro → options (menu) →
  map (seleção de fase) → stage → stageTUTORIAL
- Gamepad: "Using XBOX buttons" + navegação de menu + ações in-game
- Zero erros glX; WebProcess sobrevive e renderiza

## CAUSA-RAIZ (dupla) E CORREÇÕES

### Fix 1 — Frontend não parava (framebuffer preso)
O `FRONTEND stop` do muOS só faz o muxfrontend SAIR quando `$SAFE_QUIT`
está setado (ele grava esse flag-file p/ o handler de sinal saber que o
quit é intencional). Lançado por SSH não herdávamos a env do muOS.
CORREÇÃO: setar `SAFE_QUIT=/run/muos_safe_quit` + `: > $SAFE_QUIT` antes do
`FRONTEND stop`; fallback SIGSTOP/SIGCONT no muxfrontend (congela sem matar,
libera o fb0). Restauração no fim.

### Fix 2 — WebProcess morria na init GL (o bloqueio real)
O **libepoxy** tem `NEEDED libGL.so.1`. No path havia `/usr/lib/gl4es`, cujo
libGL.so.1 **NÃO exporta glXGetCurrentContext**. O epoxy resolvia o gl4es,
não achava o símbolo e **abortava a init GL do WebProcess ANTES do 1º frame**
("glXGetCurrentContext() not found: /usr/lib/gl4es/libGL.so.1: undefined symbol").
Sem WebProcess → sem render → main loop encerrava.

CORREÇÃO: compilar uma **libGL.so.1 STUB própria** (runtime-fixes/libgl-stub.c)
que exporta os ~21 símbolos glX retornando NULL/0, e colocá-la em
`runtime/libs/` — que PRECEDE `/usr/lib/gl4es` no LD_LIBRARY_PATH. Assim o
epoxy carrega a stub, conclui "nenhum contexto GLX ativo" e cai no caminho
EGL (correto p/ fbdev/Mali-G31). O backend mali-fbdev usa EGL+GLES via
eglGetProcAddress, então nenhuma função desktop-GL real é chamada.

Nota: a libGL.so.1 NÃO pode ser simplesmente removida — o libepoxy tem o
NEEDED e sem o arquivo dá exit 127 ("cannot open libGL.so.1"). Precisa da
stub presente.

### Fix 3 (menor) — GST_PLUGIN_PATH
Removido `$D/libs` do GST_PLUGIN_PATH (deixado só `$D/gst-plugins`) para o
scanner não tentar carregar `libgstgl-1.0.so` como plugin (falha em
glXMakeCurrent). Plugins de áudio reais vivem em gst-plugins/; libgstgl fica
em libs/ só p/ satisfazer o NEEDED da libWPEWebKit (não é mais escaneada).

## ARTEFATOS
- runtime-fixes/libgl-stub.c — fonte da stub
- runtime-fixes/libGL.so.1 — stub compilada (aarch64, 21 símbolos glX)
- scripts/mr-ctl.sh — controller atualizado (SAFE_QUIT + env comprovado)
- Device: /mnt/mmc/mr-v8style.sh (runner known-good), mr-play.sh (run longo),
  mr-ctl.sh (controller)
- Stub deployada em: /mnt/sdcard/ports/moonrider/runtime/libs/libGL.so.1

## ENV COMPROVADO (mr-v8style.sh / mr-ctl.sh inner)
LD_LIBRARY_PATH="$D/libs:$D/lib:/usr/lib/gl4es:/usr/lib:/lib"  # libs/ tem a stub
LIBGL_FB=2 LIBGL_ES=2 WEBKIT_GST_DISABLE_GL_SINK=1
GST_PLUGIN_PATH="$D/gst-plugins"  # SEM :libs
GST_REGISTRY_FORK=no  # carga in-process (device sem gst-plugin-scanner)
XDG_RUNTIME_DIR=/run PIPEWIRE_RUNTIME_DIR=/run  # ALSA default->pipewire
WPE_BACKEND="$D/lib/libWPEBackend-mali-fbdev.so"
WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 WEBKIT_FORCE_COMPOSITING_MODE=1
LD_PRELOAD="$D/lib/glx-stub.so"

## PENDÊNCIAS
- Consolidar no Moonrider.sh (launcher PortMaster oficial) o env + a stub.
- Empacotar libGL.so.1 stub no runtime distribuído do template.
- Reiniciar handheld p/ restaurar frontend (o restore via SSH não persiste).
- Validação sensorial estendida (gameplay completo, performance/FPS).
- Atualizar docs/DEVICE.md com IP .116.

## ATUALIZAÇÃO — ÁUDIO PLAYPAIR OK (20260715 ~08:49)

Sintoma: música do seletor de fase "tocava rapidinho e parava" (handoff
intro->loop quebrado no ghost v8 que usava só PLAY+setTimeout).

CAUSA: o console tinha o conjunto v8 SEM PLAYPAIR (deployado durante a caça ao
bug de vídeo). Existia um trio PLAYPAIR mais novo e coerente no template.

CORREÇÃO: deploy do TRIO PLAYPAIR do moonrider-portmaster-template/:
- launcher: bin/moonrider-launch (PLAYPAIR=4, md5 5fb4cbd4...) — handler
  PLAYPAIR + muos_mixer_play_pair no mixer nativo embutido
- ghost: shims/muos_audio_ghost.js v11 (PLAYPAIR=5, md5 317334f0...)
- mixer: já embutido no launcher (audio-mixer/muos_audio_mixer.c PLAYPAIR=4)

Protocolo: ghost emite "PLAYPAIR|intro_id|loop_id|vol|intro_ms|intro_path|loop_path";
o mixer nativo toca a intro e agenda o loop pra emendar no fim. Parar a intro
cancela o loop agendado.

RESULTADO (log mr-play.log): "[mixer] PLAYPAIR intro=1268309330 loop=363882720
ms=5116" — intro+loop emendando. Rafael confirmou: música rodou OK.
Trio PLAYPAIR compatível com o fix de vídeo (libGL stub é ortogonal).

Backup do v8 anterior: /mnt/mmc/backup-v8-noplaypair/ (ghost + launcher).
Warning benigno remanescente: libgstgl-1.0.so undefined symbol glXChooseFBConfig
(só warning GStreamer; libgstgl fica em libs/ p/ NEEDED da WebKit; não afeta jogo).
