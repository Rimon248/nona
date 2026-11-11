#!/usr/bin/env python3
"""Work around Dart AOT issue flutter/flutter#191575 in a disposable SDK.

The script changes only the five FFI structs named in the upstream report.
It fails if the pinned Flutter SDK layout differs, so the workaround cannot
silently patch unrelated framework code.
"""

from pathlib import Path
import sys


if len(sys.argv) != 2:
    raise SystemExit("usage: patch-flutter-aot.py FLUTTER_ROOT")

source = (
    Path(sys.argv[1])
    / "packages/flutter/lib/src/widgets/_window_macos.dart"
)
original = source.read_text()
updated = original
for class_name in (
    "_WindowCreationRequest",
    "_Size",
    "_Offset",
    "_Rect",
    "_Constraints",
):
    declaration = f"final class {class_name} extends Struct {{"
    annotated = "@pragma('vm:entry-point')\n" + declaration
    if updated.count(annotated) == 1:
        continue
    if updated.count(declaration) != 1:
        raise SystemExit(f"unexpected Flutter source for {class_name}")
    updated = updated.replace(declaration, annotated, 1)

if updated != original:
    source.write_text(updated)
print("Verified macOS AOT FFI struct retention workaround")
