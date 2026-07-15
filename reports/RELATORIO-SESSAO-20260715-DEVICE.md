# Relatório de Sessão — Teste no Device (RG40xx H) e Diagnóstico do "Tela Preta"
**Data:** 2026-07-15
**Projeto:** moonrider-pm (Vengeful Guardian: Moonrider — Construct 2 / WPE WebKit / muOS)
**Device:** RG40xx H, muOS 2508.4 LOOSE GOOSE, H700/Mali-G31, aarch64, SSH root@<device-ip>

---

## Objetivo da sessão
Empacotar o port com o runtime fresh, fazer deploy no device e validar o boot.
Resultado: **runtime PROVADO funcional** (backend carrega, WebProcess spawna, JS e shims
muOS rodam), mas o jogo **ainda não renderiza** — travado na inicialização do contexto
gráfico do WebProcess. Três defeitos encontrados e corrigidos; um quarto isolado (aberto).

---

## Método de trabalho estabelecido
- **Deploy = rsync manual** (NÃO autoinstall PortMaster/zip). rsync `-rlptD --no-o --no-g`
  (unionfs/fuse não permite chown; sem essas flags o rsync falha). Incremental resolve
  o timeout do `cp -a` local no device.
- **Controlador de teste no device:** `scripts/mr-ctl.sh` (instalado em `/mnt/mmc/mr-ctl.sh`).
  Subcomandos `run [secs] | kill | status | log [n] | rawlog`. O `run` gera um runner
  interno detached (nohup+setsid, stdio redirecionado) que **sobrevive ao drop de SSH**
  causado pelo `FRONTEND stop`. Log persistente em `/mnt/mmc/moonrider-diag.log` (eMMC,
  sobrevive ao wipe de /run e ao drop de SSH). Kill sempre com TERM, nunca KILL.

---

## Defeitos encontrados e CORRIGIDOS (na ordem em que apareceram)

### 1. `libWPEBackend-default.so` ausente no runtime fresh  ✅ CORRIGIDO
- **Sintoma:** backend não carregava; tela preta, sem `[mali-fbdev]` no log.
- **Causa:** libwpe 1.x carrega o backend pelo nome FIXO `libWPEBackend-default.so` e
  IGNORA `WPE_BACKEND`/`WPE_BACKEND_LIBRARY`. O `assemble-runtime-fresh.sh` copiava o
  `libWPEBackend-mali-fbdev.so` mas o alias `default.so` vinha de `cp $ENGINE/... || true`
  (arquivo inexistente no engine) → falhava em silêncio.
- **Fix:** `assemble-runtime-fresh.sh` agora cria `default.so` como cópia do mali-fbdev.
  Commit `b3c8f...`.

### 2. `WEBKIT_EXEC_PATH` ausente no launcher  ✅ CORRIGIDO
- **Sintoma:** backend carregava mas o WPEWebProcess não spawnava; tela preta.
- **Causa:** `libWPEWebKit` tem o libexecdir compilado hardcoded
  (`/usr/lib/aarch64-linux-gnu/wpe-webkit-1.1`). Sem `WEBKIT_EXEC_PATH`, o WebKit procura
  o WebProcess FORA do port. Só "funcionava" antes porque um setup anterior instalou o
  WPEWebProcess no `/usr` do device (dependência oculta — runtime não era auto-contido).
- **Fix:** `runtime-config/run-moonrider.sh` agora exporta
  `WEBKIT_EXEC_PATH=$HERE/lib/wpe-webkit-1.1` + `WEBKIT_INJECTED_BUNDLE_PATH`.
  **Confirmado no log:** `(WPEWebProcess:NNNN)` passou a aparecer. Runtime auto-contido.
  Commit `cf51d63`+ (run-moonrider.sh).

### 3. `game/` era o build ERRADO (web/APK cru, sem camada muOS)  ✅ CORRIGIDO
- **Sintoma:** backend + WebProcess OK, mas o C2 nunca inicializava o render.
- **Causa:** o `extract-assets.sh` puxou o build web/APK (`settings.js`, `touch-controls.js`,
  `options-menu.js`) em vez do build known-good (Electron + shims muOS). Faltavam:
  `muos_gamepad_shim.js`, `muos_audio_ghost.js`, e o bloco de flags `__muos_*` no index.
- **Fix:** aplicada a camada muOS ao NOSSO build web (mantendo touch-controls):
  - copiados `muos_gamepad_shim.js` (4,6 KB) + `muos_audio_ghost.js` (31,5 KB) para `game/`
  - `index.html` reescrito com ordem correta: flags `__muos_*` → gamepad shim →
    audio ghost → jquery/settings/touch-controls → **c2runtime.js** → options-menu.
  - backup do index web original salvo no device: `game/index.html.web-orig`.
- **Compatibilidade verificada:** os hooks que os shims usam existem no NOSSO c2runtime
  fresh — `cr_getC2Runtime`(4), `cr_createRuntime`, `running_layout`(61),
  `all_global_vars`(4), `loadingprogress`(5), `cr.plugins_.Audio`. Ambos são Construct 2,
  `data.js` praticamente idêntico (diff de 633 B — mesmo jogo).
- **Confirmado no log após o fix:** o JS roda de verdade —
  `[JS-PROBE] script executou`, `DOMContentLoaded`, `MUOS_IPC native=true`,
  `MUOS_ACTS_WRAPPED_V11`, `MUOS_WINDOW_CLOSE_INTERCEPTOR installed`. **Os shims muOS
  funcionam com nosso runtime web.**

---

## Defeito 4 — ABERTO: WebProcess congela na init do contexto gráfico

### Sintomas observados
- Com run curto: `main loop encerrado` logo após `glXGetCurrentContext() not found`.
- Com run longo (25s): `moonrider-launch` fica **vivo**, WebProcess **vivo**, mas
  **fb0 estático** (não renderiza) e — em alguns runs — **ZERO console.log** (o WebProcess
  nem executa o JS). Comportamento **INCONSISTENTE entre runs** (condição de corrida):
  às vezes o JS roda até `MUOS_ACTS_WRAPPED_V11` e trava; às vezes trava antes de qualquer JS.
- Nunca aparece `[JS-PROBE] window.load` nem o `go()` do C2 → o jogo nunca termina de bootar.

### Evidências técnicas apuradas
- **glx-stub INCOMPLETO:** `nm -D glx-stub.so` exporta `glXGetCurrentContext` (T) mas
  **NÃO** `glXMakeCurrent`. Por isso `libgstgl-1.0.so: undefined symbol: glXMakeCurrent`
  (falha 2×) e a init GL do WebProcess é instável.
- **LD_PRELOAD do glx-stub CHEGA no WebProcess** (confirmado: `/proc/PID/environ` tem
  `LD_PRELOAD=.../glx-stub.so`, `maps` mostra 4 mapeamentos do stub). Então não é
  propagação de env — é o stub **faltar símbolos** que o caminho WPE-multiprocess exige.
- **Runtime fresh == known-good nos binários que importam:** `moonrider-launch` (707744 B,
  mesmas strings — só metadados de build diferem no md5), `WPEWebProcess` (md5 idêntico),
  `libWPEWebKit-1.1.so.0` (md5 idêntico), `glx-stub.so` (md5 idêntico). Fresh tem 150 libs
  = superset dos 136 do known-good; nenhuma lib faltante.
- Warning recorrente (não confirmado como causa): `Using cross-namespace EXTERNAL
  authentication (this will deadlock if server is GDBus < 2.73.3)` — aparece no pai e no
  WebProcess. GLib do sistema é 2.76.

### Hipótese principal (a validar na próxima sessão)
O known-good que "funcionava" rodava com o build **Electron** (processo único; caminho GL
sem GLX multiprocess). Nosso caminho **WPE puro multiprocess** exercita GLX dentro do
WPEWebProcess, e o **glx-stub cobre só parte dos símbolos GLX** (`glXGetCurrentContext`
sim, `glXMakeCurrent` não) → init de contexto gráfico instável → WebProcess congela antes
de renderizar. A condição de corrida bate com timing de init GL.

### Próximos passos sugeridos (não executados)
1. **Completar o glx-stub:** adicionar stubs para `glXMakeCurrent`, `glXGetProcAddress`,
   e demais símbolos GLX que gl4es/libgstgl referenciam. Recompilar no `wpebuild:cpp`.
2. **Alternativa:** desabilitar de vez o `libgstgl-1.0.so` (mover para fora de gst-plugins)
   e forçar C2 a caminho canvas2d (`__muos_lowres`/sem WebGL) para isolar se o travamento
   é do WebGL do C2 ou do GStreamer-GL.
3. Adicionar `WEBKIT_DEBUG` mais granular / capturar stderr do WebProcess isolado.
4. A/B com o `game/` Electron known-good completo (troca temporária) para confirmar se o
   travamento some — isolando build-do-jogo vs runtime.

---

## Estado do device ao fim da sessão
- Port instalado em `/mnt/union/ports/moonrider/` (runtime fresh + game web + camada muOS).
- Instalação antiga preservada: `/mnt/mmc/moonrider-old-backup-20260715/` (676 MB, known-good).
- Backup do index web original: `game/index.html.web-orig`.
- `game/index.html` atual tem sondas de diagnóstico injetadas (JS-PROBE, MUOS_RTWATCH) e
  `__muos_debug=true` — **remover antes do release**.
- App morto, frontend (muxfrontend) restaurado.
- Controlador `/mnt/mmc/mr-ctl.sh` + runner `/mnt/mmc/mr-run-inner.sh` presentes.

## Saúde do ambiente (host)
- **SSD `/` bateu 100% durante a sessão.** Liberados 8,7 GB apagando checkpoints de MAIO
  (`~/.hermes/checkpoints/legacy-20260510-220420` + `731beeced6b3bbd2`). Sobrou
  `~/.hermes/checkpoints/store` (8,1 GB, ativo, 16× acima do limite de 500 MB) — podar
  quando o Hermes estiver ocioso (também mata os avisos falsos de "sibling").
- Todo o trabalho (runtime/staging/zip) ficou em `/tmp` (tmpfs/RAM) — nunca tocou o SSD.

## Arquivos alterados/commitados nesta sessão
- `scripts/assemble-runtime-fresh.sh` — alias `default.so` (fix #1).
- `runtime-config/run-moonrider.sh` — `WEBKIT_EXEC_PATH` (fix #2).
- `scripts/deploy.sh` — reescrito para rsync manual + flags unionfs.
- `scripts/mr-ctl.sh` — NOVO, controlador de teste no device.
- `game/` no device — camada muOS aplicada (fix #3), não versionado (bring-your-own).
