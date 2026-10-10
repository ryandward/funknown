"""Check that every quote in statements.json appears verbatim (whitespace-normalised
only) in the vendored file it cites, and that every vendored file still matches the
sha256 recorded in PROVENANCE.md.

Usage: python3 -I verify_statements.py   (run from anywhere)
"""
import hashlib
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REFS = HERE.parent


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


def main():
    failures = 0
    statements = json.loads((HERE / "statements.json").read_text(encoding="utf-8"))
    texts = {}
    ids = set()
    for st in statements:
        if st["id"] in ids:
            print(f"DUPLICATE id {st['id']}")
            failures += 1
        ids.add(st["id"])
        path = REFS / st["file"]
        if path not in texts:
            texts[path] = norm(path.read_text(encoding="utf-8"))
        if norm(st["quote"]) not in texts[path]:
            print(f"QUOTE NOT FOUND {st['id']} in {st['file']}")
            failures += 1

    rows = re.findall(r"^\| `([^`]+)` \| ([0-9a-f]{64}) \|", (HERE / "PROVENANCE.md").read_text(encoding="utf-8"), re.M)
    for rel, digest in rows:
        actual = hashlib.sha256((HERE / rel).read_bytes()).hexdigest()
        if actual != digest:
            print(f"SHA256 MISMATCH {rel}")
            failures += 1

    print(f"{len(statements)} statements, {len(rows)} hashed files, {failures} failures")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
