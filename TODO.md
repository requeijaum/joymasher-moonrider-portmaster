# TODO — Moonrider Port muOS (RG40xx H)

Estado: JOGÁVEL (vídeo + som + gamepad OK, 2026-07-15). Este arquivo lista
bugs e pendências para as próximas sessões. Referência técnica completa:
`reports/RELATORIO-BREAKTHROUGH-20260715.md`.

---

## BUGS DE ÁUDIO

### [x] BUG-1 (P1) — Loops de SFX muito curtos: som de correr e da moto
Sintoma: comparado ao celular, o som do Moonrider **correndo** e **na moto**
tem períodos de loop muito curtos — parece "picotado"/repetindo rápido demais.
Reportado por Rafael (2026-07-15) comparando o port muOS vs versão do celular.

Hipótese: os SFX contínuos (run/moto) são sons que deveriam tocar em loop
sustentado enquanto a ação dura, mas o mixer nativo/ghost está reiniciando o
sample em janelas curtas (retrigger a cada tick em vez de loop contínuo), ou
o `loop=` não está sendo respeitado para esses tags específicos.

Investigar:
- Nos logs (`MUOS_PLAY name=... loop=?`): ver se run/moto vêm com loop=0 e são
  re-disparados a cada frame, vs loop=1 sustentado.
- Comparar com o comportamento esperado no c2runtime (Construct 2 usa tags de
  áudio "looping" — checar se o ghost mapeia isso corretamente).
- Ver se o mixer nativo (muos_audio_mixer.c) faz retrigger indevido quando
  recebe PLAY do mesmo tag já tocando (deveria continuar, não reiniciar).
- Candidatos de nome: MR_RUN, MRRUN, moto/bike/ride SFX — grepar os .ogg e
  os tags no c2runtime.
Corrigido no ghost V12: tags são case-insensitive e `Audio:Is tag playing`
consulta o estado das vozes nativas, impedindo o retrigger por tick.

---

## FASE 1 — BASE JOGÁVEL REPRODUZÍVEL

### [x] TASK-1 — Consolidar fixes dentro de moonrider-pm
Fontes canônicas agora vivem em `native/` + `shims/`; o build não depende mais
das fontes transitórias em `/tmp` nem do template antigo. `Moonrider.sh` aplica
SAFE_QUIT + cleanup idempotente do frontend.

### [x] TASK-2 — Empacotar libGL.so.1 stub no runtime montado
`assemble-runtime-fresh.sh` instala a stub compilada (fallback para o artefato
versionado) e aborta se faltarem stub, PLAYPAIR ou o GST path limpo.

### [x] TASK-3 — Transformação determinística dos assets BYO
`apply-port-layer.py` copia gamepad/ghost PLAYPAIR, injeta-os antes do
c2runtime.js e é idempotente. `extract-assets.sh` executa essa etapa em staging
gravável.

### [x] TASK-4 — Gate anti-regressão PLAYABLE-V1
`scripts/verify-playable-contract.sh` valida fontes, trio PLAYPAIR, libGL stub,
GST_PLUGIN_PATH, SAFE_QUIT e a ordem/idempotência da camada do jogo.

---

## FASE 3 — HIGIENE / RELEASE

### [x] TASK-5 (P3) — Silenciar warning benigno libgstgl
Log mostra: `libgstgl-1.0.so: undefined symbol: glXChooseFBConfig` (warning,
não afeta o jogo). Há 2 cópias: a versionada `.so.0` já fora do scan, mas a
`.so` sem sufixo ainda é tentada. Mover/renomear a `.so` sem sufixo para
`libs-disabled/` deve limpar. Verificar antes que a WebKit não precisa dela
via NEEDED (só o NEEDED versionado importa). O smoke test V2 não emitiu o warning.

### [ ] TASK-6 (P2) — Validação sensorial estendida
Rafael jogar sessão longa: performance/FPS, todas as fases, cutscenes,
pausar/retomar (áudio), sair pelo combo L2+R1, verificar se não há travas.

### [x] TASK-7 (P3) — Atualizar docs/DEVICE.md com IP .116
IP atual do device é 192.168.1.116 (pode mudar por DHCP após reboot).

### [x] TASK-8 (P3) — Restore de frontend sem reboot
O controller usa SAFE_QUIT, fallback STOP/CONT por PID exato e `FRONTEND start`.
O smoke test terminou limpo e confirmou `muxfrontend` ativo novamente.

---

## REFERÊNCIA RÁPIDA (fixes já aplicados — NÃO regredir)

- **libGL.so.1 STUB** em `runtime/libs/` (precede /usr/lib/gl4es). Sem ela o
  WebProcess aborta no glX. NÃO remover libGL (libepoxy NEEDED → exit 127).
- **Trio PLAYPAIR** (launcher 5fb4cbd4 + ghost v12 516892a3 + mixer): música
  emenda intro→loop. O v8 sem PLAYPAIR causava "música toca rapidinho e para".
- **GST_PLUGIN_PATH** só `gst-plugins` (sem `:libs`): evita scan da libgstgl.
- **SAFE_QUIT=/run/muos_safe_quit** antes de FRONTEND stop (senão muxfrontend
  não sai e segura o fb0).
- Export desktop correto: external backup drive/Portsmaster/moonrider-game-desktop-known-good-20260715/
- O manifesto PLAYABLE-V2 rejeita o export Android/raw que introduz overlay móvel.
- Backup v8 anterior no console: /mnt/mmc/backup-v8-noplaypair/
