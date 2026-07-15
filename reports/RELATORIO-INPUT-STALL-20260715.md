# Relatório — slowdown, fila de input e estado lógico incorreto

**Data:** 2026-07-15
**Plataforma:** RG40xx H / H700 / muOS
**Fluxo reproduzido:** tela Ports do muOS
**Engine desta captura:** WPE WebKit 2.38 (baseline PLAYABLE-V2)

## 1. Relato físico

Durante o teste no aparelho, o desempenho observado foi de aproximadamente **23 fps**, com slowdowns visíveis para **7 fps** e **13 fps**.

Esses valores foram lidos visualmente e relatados pelo operador. Eles não possuem timestamps instrumentais no log e, portanto, não devem ser apresentados como benchmark automatizado.

O comportamento de interesse é a degradação ou perda dos controles quando uma tecla é mantida durante slowdown, flicker ou black frame.

## 2. Instrumentação utilizada

Foi implantado temporariamente um launcher com rastreamento das seguintes fronteiras:

1. evento recebido do evdev: `[evdev-trace]`;
2. heartbeat e gaps do callback GLib: `[pad-pulse]`;
3. envio de snapshot para o WebProcess: `[pad-pulse] PUSH`;
4. conclusão assíncrona da execução JavaScript: `[pad-js] ACK`;
5. chegada ao shim: `MUOS_PAD_PUSH`;
6. consulta do estado pelo jogo: `MUOS_PAD_READ`.

Um watchdog atômico independente do `GMainLoop` também monitorou períodos sem execução de `gamepad_pulse()`; nesta captura ele não detectou stall acima do limite de 250 ms.

O log bruto foi preservado fora do repositório em mídia externa, sob:

```text
/path/to/external-backup/Portsmaster/moonrider-input-trace-20260715/captures/
  ports-wpe238-fps-slowdown-live.log
```

Tamanho da captura:

- 1.738 linhas;
- 131.674 bytes;
- 342 eventos evdev numerados.

## 3. Resultados quantitativos

### 3.1 Caminho nativo

- eventos evdev: **342** (`seq=1..342`);
- snapshots enviados pelo launcher: **335**;
- maior gap observado em `gamepad_pulse()`: **217.967 µs**;
- gaps acima de 100 ms: **4** (`110.357`, `112.257`, `130.884` e `217.967 µs`);
- stalls de `gamepad_pulse()` acima do limite de 250 ms: **0**.

Sete sequências não aparecem como push individual: `14`, `16`, `89`, `127`, `295`, `341` e `342`.

- `14`, `16`, `89`, `127` e `295` foram coalescidas por eventos posteriores antes do próximo snapshot;
- `341` e `342` estavam no fim da captura e podem representar somente a fronteira temporal da cópia do log.

Não há evidência nesta captura de morte da thread evdev nem de paralisação prolongada do `GMainLoop` do launcher.

### 3.2 UIProcess → WebProcess

Todos os **335** pushes registrados tiveram:

- `MUOS_PAD_PUSH` correspondente;
- `[pad-js] ACK` correspondente;
- `status=ok`;
- nenhum erro de execução JavaScript.

Latência de ACK:

| Métrica | Latência |
|---|---:|
| mínima | 1.641 µs |
| mediana | 26.364 µs |
| p90 | 125.178 µs |
| p95 | 575.332 µs |
| p99 | 1.661.381 µs |
| máxima | 1.792.183 µs |

A combinação de `GMainLoop` ativo com ACKs de até **1,79 s** localiza o congestionamento no WebProcess/JavaScript/Construct/render, e não na captura física evdev.

### 3.3 Consultas do Construct 2

Foram observadas **281** leituras `MUOS_PAD_READ` para 335 pushes. Essa diferença é compatível com múltiplas atualizações executadas antes da próxima consulta do jogo.

## 4. Evidência da corrupção lógica causada pela fila

O launcher continuou enfileirando chamadas JavaScript enquanto o WebProcess estava atrasado. Quando o WebProcess voltou a progredir, executou estados históricos em rajada.

O shim V3 mantinha releases por `LATCH_READS=2`, reduzindo o latch apenas em chamadas a `navigator.getGamepads()`. Como vários pushes eram executados antes da próxima leitura, releases antigos de botões diferentes se acumulavam como estados pressionados simultâneos.

### Janela `seq=44..58`

O usuário alternou fisicamente A, B, X e Y durante aproximadamente 1,7 s de backlog. Os ACKs mais antigos chegaram com até 1,79 s de atraso.

Antes da próxima leitura do Construct, o shim acumulou:

```text
seq=44  mask=0x00001
seq=48  mask=0x00005
seq=52  mask=0x0000d
seq=58  mask=0x0000f
```

A leitura correspondente foi:

```text
MUOS_PAD_READ seq=58 mask=0x0000f
```

Assim, o Construct observou **A+B+X+Y simultaneamente pressionados**, embora o log evdev mostre press/release alternados.

### Janela `seq=104..113`

Uma segunda fila apresentou ACKs de até 1,77 s. A, B e X foram alternados fisicamente, mas o shim acumulou:

```text
seq=104 mask=0x00001
seq=106 mask=0x00003
seq=112 mask=0x00007
MUOS_PAD_READ seq=113 mask=0x00007
```

O Construct recebeu **A+B+X simultaneamente pressionados**.

## 5. Diagnóstico

A captura separa dois fenômenos:

1. **slowdown de render/execução:** o WebProcess passa a responder com centenas de milissegundos ou até 1,79 s de atraso;
2. **corrupção do estado lógico de input:** o replay dos snapshots atrasados interage com o latch baseado em número de leituras e cria combinações fantasmas de botões.

Portanto:

- o dispositivo evdev continuou fornecendo eventos;
- o launcher continuou produzindo snapshots;
- o `GMainLoop` nativo não apresentou stall ≥250 ms;
- o gargalo observado está depois do launcher, no WebProcess/Construct/render;
- a fila histórica e o latch V3 transformaram taps alternados em botões simultâneos;
- isso explica controles incorretos ou aparentemente presos depois de um slowdown.

A captura não prova ainda qual componente interno origina a queda de 23 fps para 7/13 fps. Possibilidades não discriminadas incluem JavaScript/Construct 2, render EGL/GLES, frame pacing e trabalho interno do WebKit.

## 6. Correção discutida, mas não aplicada

Foi discutida, sem implementação, a seguinte direção:

- limitar a uma chamada JS em voo;
- coalescer backlog para o estado físico mais recente, sem replay histórico;
- aplicar o snapshot pendente no momento de `getGamepads()`;
- tornar o combo de saída independente da fila JavaScript.

O operador decidiu explicitamente: **sem correção nesta sessão; apenas documentar e encerrar o trabalho do dia**.

## 7. Estado ao encerrar

- nenhuma correção funcional foi aplicada após a leitura dos logs;
- nenhum novo build ou deploy foi feito depois do diagnóstico;
- o jogo não foi encerrado remotamente para produzir este relatório;
- os fontes da instrumentação e seus testes permanecem como alterações locais não commitadas;
- a instrumentação implantada no aparelho continua sendo experimental;
- o launcher e o shim anteriores foram preservados no backup externo `device-backup-before-trace/`;
- o baseline publicado permanece no commit `bfa55e5`;
- o piloto WPE 2.42 publicado permanece separado no commit `ed025e4` da branch `perf/wpe-cache-a53`.

## 8. Retomada futura

Se o projeto for retomado, verificar primeiro:

1. `git status` e os arquivos locais de instrumentação;
2. se o Moonrider ainda está em execução no aparelho;
3. se a versão instrumentada deve ser mantida ou restaurada pelo backup;
4. se a próxima sessão será somente diagnóstico ou terá autorização explícita para corrigir;
5. somente então implementar e comparar uma política `latest-state` sem replay histórico.
