"""Copies the kit (ABAP sources + ARC-1 extension) replacing the object prefix.

Usage:
    python set_prefix.py --to ZXYZ --dest C:/progetti/mio-progetto/sap-kit
    python set_prefix.py --to ZAI   --in-place          (rewrites the kit assets)

The current prefix of the assets is read from assets/PREFIX. Both file names and content
are replaced, keeping upper/lower case (ZAI_... / zai_...). The new prefix must start
with Z or Y and have at most 10 characters: the longest names of the kit
(e.g. <PREFIX>_PRINT_CALL_ROUTINE) must stay within the 30 characters allowed by SAP.
"""
import argparse
import re
import shutil
import sys
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent
ASSETS = KIT / "assets"
TEXT_SUFFIXES = {".abap", ".ts", ".mjs", ".json", ".md", ".txt"}
SKIP_DIRS = {"node_modules", "dist"}


def replacer(old: str, new: str):
    pattern = re.compile(rf"{re.escape(old)}(?=_)", re.IGNORECASE)

    def repl(match: re.Match) -> str:
        return new.lower() if match.group(0).islower() else new.upper()

    return lambda text: pattern.sub(repl, text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--to", required=True, help="New prefix, e.g. ZXYZ")
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--dest", help="Target folder of the copy")
    target.add_argument("--in-place", action="store_true", help="Rewrites the kit assets")
    args = parser.parse_args()

    new = args.to.upper().rstrip("_")
    if not re.fullmatch(r"[ZY][A-Z0-9]{0,9}", new):
        print(f"Invalid prefix: {args.to} (starts with Z/Y, letters/digits, max 10 characters)")
        return 1
    old = (ASSETS / "PREFIX").read_text(encoding="utf-8").strip()
    convert = replacer(old, new)

    dest = ASSETS if args.in_place else Path(args.dest).resolve()
    if not args.in_place:
        if dest.exists() and any(dest.iterdir()):
            print(f"Folder {dest} exists and is not empty")
            return 1
        shutil.copytree(ASSETS, dest, ignore=shutil.ignore_patterns(*SKIP_DIRS))

    for path in sorted(dest.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.is_file() and path.suffix in TEXT_SUFFIXES:
            text = path.read_text(encoding="utf-8")
            path.write_text(convert(text), encoding="utf-8", newline="\n")
        renamed = path.with_name(convert(path.name))
        if renamed != path:
            path.rename(renamed)

    (dest / "PREFIX").write_text(new + "\n", encoding="utf-8")
    print(f"Prefix {old} -> {new} in {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
