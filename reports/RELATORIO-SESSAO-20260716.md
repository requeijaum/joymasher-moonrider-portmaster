# Relatório de sessão — Moonrider audio-worker release candidate

Data: 2026-07-16
Alvo: Anbernic RG40xx H, muOS 2508.4 LOOSE GOOSE
Classificação: candidato PortMaster BYO privado; runtime ainda não autorizado para redistribuição pública

## Resultado

O travamento permanente provocado pelo mixer nativo não ocorreu após a substituição do acesso direto ao miniaudio por um worker single-owner. O teste físico que anteriormente reproduzia o crash foi repetido com áudio nativo ativo e passou. O usuário continuou jogando e iniciou a geração da primeira fase.

## Evidência anterior

No A/B com `MOONRIDER_DISABLE_AUDIO=1`, o jogo permaneceu estável enquanto milhares de comandos Audio Ghost foram descartados. Isso isolou o mixer nativo como condição necessária do travamento. A implementação anterior executava criação, stop, volume, reap e `ma_sound_uninit()` diretamente no GMainLoop, incluindo recursos inicializados de forma assíncrona.

## Correção congelada

- fila bounded de 128 comandos;
- coalescência por voz para eventos redundantes;
- thread dedicada como única proprietária das APIs de controle do miniaudio;
- caminho WebKit/GLib estritamente enqueue-only;
- remoção de `MA_SOUND_FLAG_ASYNC`;
- STOP idempotente;
- retirement de vozes por 150 ms antes de `ma_sound_uninit()`;
- reap executado no owner thread;
- shutdown limitado a 250 ms;
- watchdog por operação, incluindo INIT, PLAY, REAP e SHUTDOWN;
- circuit breaker após 2 s sem progresso;
- queue e counters expostos no heartbeat;
- mailbox de input latest-state com preservação de rising edges.

## Sessão física com áudio ativo

Captura ao vivo realizada sem interromper o jogo:

- início registrado: 2026-07-16 14:18:20 -03;
- 504 heartbeats consecutivos;
- aproximadamente 19.800 frames registrados, cerca de 39,29 fps no intervalo observado;
- 24.292 comandos de áudio processados, cerca de 48,20 comandos/s;
- 474 comandos de áudio coalescidos;
- profundidade instantânea máxima da queue: 5;
- high-water mark: 9 de 128;
- comandos descartados: 0;
- stalls detectados: 0;
- circuit breaker: nunca abriu;
- worker permaneceu em RUNNING;
- nenhum erro, abort, segmentation fault ou crash no log;
- teste físico que provocava o crash: PASS.

O maior `age_ms` amostrado foi 1.208 ms, abaixo do limiar de 2 s, sem perda do heartbeat do GMainLoop.

## Identidade do candidato executado

SHA-256 do launcher aarch64 executado no handheld:

`dca3cc458d8c8fd0431c27866dd5b05e52de27a144a35f07c55176c6d662a4b6`

Os hashes do wrapper, Audio Ghost, gamepad shim, runtime launcher e fontes locais foram comparados com os arquivos ativos no aparelho. Os componentes principais eram byte a byte idênticos.

## Gates concluídos

- testes funcionais da queue: PASS;
- testes do worker bloqueado em PLAY: PASS;
- testes do worker bloqueado em REAP: PASS;
- ASan/UBSan nos testes host: PASS;
- contrato enqueue-only: PASS;
- contrato de lifecycle/retirement: PASS;
- Audio Ghost: PASS;
- Input V4/latest-state: PASS;
- contrato BYO e wrapper: PASS;
- compilação com warnings fatais para código próprio: PASS;
- cross-build aarch64: PASS;
- validação do ELF e strings de diagnóstico: PASS;
- smoke test físico com áudio real e cenário de crash: PASS.

A revisão delegada independente não foi executada porque o provider configurado recusou o modelo via Responses API. Isso não foi contado como aprovação externa.

## Evidência preservada

- `reports/evidence/audio-worker-release-20260716/device-live.log`
- `reports/evidence/audio-worker-release-20260716/device-state.txt`
- arquivos pequenos de provenance, licença e metadados em `reports/evidence/audio-worker-release-20260716/device-files/`

## Release PortMaster

O runtime recuperado do handheld contém `RUNTIME-PROVENANCE.md` e `PRIVATE-TEST-NOTICE.txt` declarando explicitamente que ele não está aprovado para redistribuição. O ZIP congelado nesta sessão deve ser tratado como backup privado/BYO para o proprietário do aparelho. Publicação no GitHub ou catálogo PortMaster permanece bloqueada até reconstrução de versões, fontes correspondentes, patches, build flags, codecs e licenças de todos os componentes do runtime.

O arquivo comercial do jogo não integra o ZIP. O usuário continua responsável por copiar sua exportação desktop legítima para `moonrider/game/`.
