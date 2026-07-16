#!/usr/bin/env python3
"""Obsolete compatibility entry point.

Moonrider's maintained launcher injects the port layer at document start. Game
exports must remain unchanged; modifying index.html would execute the shims twice.
"""

raise SystemExit(
    "apply-port-layer.py is obsolete: keep game assets unchanged and use the "
    "runtime-injected patches shipped in moonrider/patches/"
)
