# Research preservation index

This branch preserves the complete pre-cleanup research tree and the reachable
history of every experimental line that informed the Moonrider port.

## Preserved branch histories

- `main`: original dense research/product tree before cleanup
- `diagnostics/input-stall-20260715`: WebProcess input-stall instrumentation
- `perf/wpe-cache-a53`: Cortex-A53 and WPE 2.42 performance experiments
- `wpe`, `servo`, `westonpack`: aliases of the validated WPE pilot history
- `hardening/post-release-review`: release hardening work
- `release/reproducible-timezone`: timezone reproducibility work
- `ci/action-gh-release-v3`, `ci/checkout-v7`: CI experiments
- `release/v0.1.0-alpha.1`, `release/v0.1.0-alpha.2`: release history

The diagnostics branch descends from the performance/WPE line. It was merged
with Git's `ours` strategy so this branch keeps the original research snapshot
as its working tree while making all experimental commits reachable from
`research`.

## Recovering an experimental file

```bash
git log --graph --oneline research
git show diagnostics/input-stall-20260715:reports/RELATORIO-INPUT-STALL-20260715.md
git show perf/wpe-cache-a53:reports/RELATORIO-WPE-CACHE-DATA-ORIENTED-20260715.md
```

Product development belongs on `cleanup` and, after review, `main`. Do not
reintroduce this branch's diagnostic density into the product tree.
