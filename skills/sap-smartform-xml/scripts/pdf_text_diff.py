"""Compares the text of two preview PDFs (e.g. standard form vs changed copy).

Usage:
    python pdf_text_diff.py before.pdf after.pdf

Prints "Identical text" or the different lines in diff format. Needs pypdf
(pip install pypdf). Compares text only: positions, fonts and images are not covered.
"""
import difflib
import sys

from pypdf import PdfReader


def pdf_lines(path: str) -> list[str]:
    reader = PdfReader(path)
    return "\n".join(page.extract_text() or "" for page in reader.pages).splitlines()


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    before, after = pdf_lines(sys.argv[1]), pdf_lines(sys.argv[2])
    if before == after:
        print(f"Identical text ({len(before)} lines)")
        return 0
    diff = difflib.unified_diff(before, after, fromfile=sys.argv[1], tofile=sys.argv[2], lineterm="", n=1)
    print("\n".join(diff))
    return 1


if __name__ == "__main__":
    sys.exit(main())
