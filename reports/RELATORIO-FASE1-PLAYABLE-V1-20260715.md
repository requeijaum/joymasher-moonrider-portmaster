# Relatório — Fase 1: baseline jogável reproduzível

Data: 2026-07-15
Escopo: somente `moonrider-pm/`
Contrato: `PLAYABLE-V1`

## Resultado

O estado anteriormente validado no RG40xx H deixou de depender do runtime
mutado manualmente no console e de fontes transitórias em `/tmp`. O repositório
agora contém as fontes customizadas, shims e regras necessárias para reconstruir
a mesma baseline.

## Consolidação

- `native/backend/`: launcher, gamepad, exit combo e backend Mali/fbdev canônicos.
- `native/audio-mixer/`: mixer nativo com protocolo PLAYPAIR e dependências-fonte.
- `shims/`: gamepad shim e ghost PLAYPAIR canônicos.
- `runtime-fixes/libgl-stub.c`: fonte da libGL no-op que força libepoxy a EGL.
- `manifests/PLAYABLE-V1.json`: hashes e invariantes da baseline.
- `scripts/apply-port-layer.py`: transformação idempotente dos assets BYO.
- `scripts/verify-playable-contract.sh`: gate anti-regressão.

## Correções de montagem/execução

- `assemble-runtime-fresh.sh` compila/instala `runtime/libs/libGL.so.1` e aborta
  se stub, PLAYPAIR ou configuração GStreamer estiverem ausentes.
- `run-moonrider.sh` não escaneia mais `runtime/libs` como plugins GStreamer.
- `Moonrider.sh` cria/exporta `SAFE_QUIT`, possui fallback SIGSTOP/SIGCONT e
  restauração idempotente do frontend via trap EXIT.
- `extract-assets.sh` aplica gamepad + ghost antes de `c2runtime.js`.
- Fontes do backend jogável v8 foram mantidas como baseline; uma alteração
  posterior não validada em `tgt_destroy` foi deliberadamente excluída.

## Execução real

Cross-build arm64 em `wpebuild:cpp`:

- `moonrider-launch`: 707744 bytes
- `libWPEBackend-mali-fbdev.so`: 72072 bytes
- `libGL.so.1`: 70224 bytes

Staging clean montado em `/tmp/moonrider-pm-port-phase1`:

- 2 arquivos em `runtime/bin`
- 10 arquivos em `runtime/lib`
- 151 arquivos em `runtime/libs`
- 24 plugins em `runtime/gst-plugins`
- tamanho total: 350 MB

Hashes MD5 reproduzidos:

- launcher: `5fb4cbd47ee802dfb1636f65bd27d41d`
- backend: `e43e27acee6960a5ac8ee2ca0011dd02`
- libGL stub: `1115e827437465a2221e0baf8611379e`
- ghost PLAYPAIR: `317334f0045bd2c2aef423a164db8124`

Resultado do gate:

```text
OK: canonical source hashes match PLAYABLE-V1 manifest
OK: coupled PLAYPAIR trio present
OK: runtime/frontend configuration contract
OK: libGL EGL-forcing stub contract
OK: game-layer injection is ordered and idempotent
OK: assembled artifact hashes match PLAYABLE-V1 manifest
PASS: Moonrider PLAYABLE-V1 contract
```

## Limite da Fase 1

A baseline foi reconstruída e verificada localmente, mas este staging clean ainda
não foi implantado no handheld. O teste no device pertence à Fase 3 para não
misturar consolidação com deploy/release. A Fase 2 permanece reservada à
investigação cuidadosa dos SFX contínuos de corrida/moto.
