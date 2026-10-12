"""Turns Studio's base64 model export into .rbxm files (no Save to File clicking needed).

    python3 -I tools/decode_rbxm_export.py OUT_DIR EXPORT.txt [EXPORT.txt ...]

Each EXPORT file holds lines "Name:<base64>" and ends with a line "END", as printed in
Studio by running SerializationService:SerializeInstancesAsync({ instance }) through a base64
encoder (e.g. via the Studio MCP execute_luau tool). Writes OUT_DIR/Name.rbxm for each line.
"""
import base64
import re
import sys
from pathlib import Path


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    out_dir = Path(argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    for path in argv[2:]:
        text = Path(path).read_text()
        if not text.rstrip().endswith("END"):
            sys.exit(f"{path} is cut off (no END line): export fewer instances per run")
        for name, data in re.findall(r"^([A-Za-z0-9_]+):([A-Za-z0-9+/=]+)$", text, re.M):
            model = base64.b64decode(data)
            if not model.startswith(b"<roblox!"):
                sys.exit(f"{name} in {path} isn't a binary Roblox model")
            (out_dir / f"{name}.rbxm").write_bytes(model)
            print(f"wrote {out_dir / name}.rbxm ({len(model)} bytes)")


if __name__ == "__main__":
    main(sys.argv)
