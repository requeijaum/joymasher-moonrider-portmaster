#!/usr/bin/env python3
"""Apply the reproducible muOS/WPE layer to a BYO Construct 2 export.

Copies the versioned gamepad/audio shims and injects their script tags before
c2runtime.js. Idempotent: a second run replaces the generated block.
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

BEGIN = "<!-- BEGIN MOONRIDER-MUOS-LAYER (generated; do not edit) -->"
END = "<!-- END MOONRIDER-MUOS-LAYER -->"


def fail(message: str) -> None:
    raise SystemExit(f"ERRO: {message}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("game_dir", type=Path)
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    game = args.game_dir.resolve()
    index = game / "index.html"
    runtime = game / "c2runtime.js"
    source_shims = root / "shims"

    if not index.is_file() or not runtime.is_file():
        fail(f"game_dir precisa conter index.html e c2runtime.js: {game}")
    if game.is_symlink():
        fail("game_dir é symlink; aplique a camada em um staging gravável, não nos assets originais")

    runtime_text = runtime.read_text(encoding="utf-8", errors="replace")
    required_apis = ("cr_getC2Runtime", "running_layout", "cr.plugins_.Audio")
    missing = [name for name in required_apis if name not in runtime_text]
    if missing:
        fail("export Construct 2 incompatível; APIs ausentes: " + ", ".join(missing))

    for name in ("muos_gamepad_shim.js", "muos_audio_ghost.js"):
        source = source_shims / name
        if not source.is_file():
            fail(f"shim versionado ausente: {source}")
        shutil.copy2(source, game / name)

    ghost = (game / "muos_audio_ghost.js").read_text(encoding="utf-8")
    if "PLAYPAIR|" not in ghost or "MUOS_PLAYPAIR" not in ghost:
        fail("ghost copiado não implementa o contrato PLAYPAIR")

    html = index.read_text(encoding="utf-8", errors="replace")
    html = re.sub(
        re.escape(BEGIN) + r".*?" + re.escape(END) + r"\s*",
        "",
        html,
        flags=re.DOTALL,
    )
    # Remove loose tags from manual/older runs so the generated block is unique.
    html = re.sub(
        r"\s*<script\b[^>]*\bsrc=[\"']muos_(?:gamepad_shim|audio_ghost)\.js[\"'][^>]*>\s*</script>\s*",
        "\n",
        html,
        flags=re.IGNORECASE,
    )

    block = f"""{BEGIN}
<script>
window.__muos_debug = false;
window.__muos_perf_probe = false;
window.__muos_lowres = false;
</script>
<script src=\"muos_gamepad_shim.js\"></script>
<script src=\"muos_audio_ghost.js\"></script>
{END}
"""
    c2_tag = re.search(
        r"<script\b[^>]*\bsrc=[\"'][^\"']*c2runtime\.js[\"'][^>]*>\s*</script>",
        html,
        flags=re.IGNORECASE,
    )
    if c2_tag is None:
        fail("tag <script src=...c2runtime.js> não encontrada em index.html")
    assert c2_tag is not None
    html = html[: c2_tag.start()] + block + html[c2_tag.start() :]
    index.write_text(html, encoding="utf-8")

    if html.count(BEGIN) != 1 or html.count("muos_audio_ghost.js") != 1:
        fail("injeção não-idempotente: bloco/tags duplicados")
    if html.index("muos_audio_ghost.js") > html.index("c2runtime.js"):
        fail("ordem inválida: ghost deve carregar antes do c2runtime")

    print(f"Camada muOS aplicada em {game}")
    print("Contrato: gamepad shim + ghost PLAYPAIR antes de c2runtime.js")
    return 0


if __name__ == "__main__":
    sys.exit(main())
