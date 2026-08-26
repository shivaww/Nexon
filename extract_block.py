#!/usr/bin/env python3
"""
extract_block.py — Safely extract a line range from one file into another,
replacing the original lines with an import/export statement.

Usage (interactive):
    python3 extract_block.py

Usage (CLI args):
    python3 extract_block.py --src main.dart --start 100 --end 200 \
        --dst models/chat_message.dart --import "export 'package:nexon/models/chat_message.dart';"

It will:
1. Read the source file
2. Extract lines [start, end] (1-indexed, inclusive)
3. Write those lines to the destination file (creating it)
4. Replace the extracted range in the source with the provided import line(s)
5. Print a summary for verification

Safety:
- Dry-run mode by default (shows what it would do, doesn't write)
- Use --execute to actually write
- Creates .bak backup of source file before writing
"""

import argparse
import os
import sys
import shutil
from datetime import datetime


def read_lines(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.readlines()


def write_lines(path, lines):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)


def main():
    parser = argparse.ArgumentParser(description="Extract code block from one file to another")
    parser.add_argument("--src", help="Source file path")
    parser.add_argument("--start", type=int, help="Start line (1-indexed, inclusive)")
    parser.add_argument("--end", type=int, help="End line (1-indexed, inclusive)")
    parser.add_argument("--dst", help="Destination file path")
    parser.add_argument("--import", dest="import_line", default="",
                        help="Line(s) to replace extracted block in source (use \\n for multi-line)")
    parser.add_argument("--execute", action="store_true", help="Actually write (default: dry-run)")
    parser.add_argument("--no-backup", action="store_true", help="Skip .bak backup")
    args = parser.parse_args()

    # Interactive mode if no args
    if not args.src:
        print("=== Block Extractor ===")
        args.src = input("Source file path: ").strip()
        args.start = int(input("Start line (1-indexed): ").strip())
        args.end = int(input("End line (1-indexed, inclusive): ").strip())
        args.dst = input("Destination file path: ").strip()
        args.import_line = input("Import/export line to replace block (\\n for multi-line, Enter for none): ").strip()
        execute_input = input("Execute? (y/N): ").strip().lower()
        args.execute = execute_input == "y"

    if not os.path.exists(args.src):
        print(f"ERROR: Source file not found: {args.src}")
        sys.exit(1)

    src_lines = read_lines(args.src)
    total_lines = len(src_lines)

    if args.start < 1 or args.end > total_lines or args.start > args.end:
        print(f"ERROR: Invalid range {args.start}-{args.end} (file has {total_lines} lines)")
        sys.exit(1)

    # Extract the block (1-indexed to 0-indexed)
    block = src_lines[args.start - 1 : args.end]
    block_text = "".join(block)
    block_lines = len(block)

    # Build replacement lines
    if args.import_line:
        replacement = args.import_line.replace("\\n", "\n")
        if not replacement.endswith("\n"):
            replacement += "\n"
        replacement_lines = [replacement]
    else:
        replacement_lines = []

    # Show preview
    print(f"\n{'='*60}")
    print(f"Source:  {args.src} ({total_lines} lines)")
    print(f"Range:   lines {args.start}-{args.end} ({block_lines} lines)")
    print(f"Dest:    {args.dst}")
    if replacement_lines:
        print(f"Replace: {replacement_lines[0].rstrip()}")
    print(f"Mode:    {'EXECUTE' if args.execute else 'DRY-RUN (--execute to write)'}")
    print(f"{'='*60}")

    # Show first/last 3 lines of block
    print(f"\nFirst 3 lines of block:")
    for l in block[:3]:
        print(f"  {l.rstrip()}")
    print(f"\nLast 3 lines of block:")
    for l in block[-3:]:
        print(f"  {l.rstrip()}")

    if not args.execute:
        print("\n[DRY RUN] No files written. Re-run with --execute to apply.")
        return

    # Backup source
    if not args.no_backup:
        bak = args.src + ".bak"
        shutil.copy2(args.src, bak)
        print(f"Backup: {bak}")

    # Write destination file
    # Add a header comment
    header = f"// Extracted from {os.path.basename(args.src)} lines {args.start}-{args.end}\n"
    header += f"// Extracted: {datetime.now().isoformat()}\n\n"
    write_lines(args.dst, [header] + block)
    print(f"Wrote: {args.dst} ({block_lines + 2} lines)")

    # Modify source: remove block, insert replacement
    new_src = src_lines[: args.start - 1] + replacement_lines + src_lines[args.end :]
    write_lines(args.src, new_src)
    print(f"Updated: {args.src} ({len(new_src)} lines, was {total_lines})")

    # Verify
    verify_lines = read_lines(args.src)
    print(f"Verify: {len(verify_lines)} lines in source after edit")
    if replacement_lines:
        check_start = args.start - 1
        actual = verify_lines[check_start].rstrip() if check_start < len(verify_lines) else "EOF"
        print(f"Verify: line {args.start} is now: {actual}")

    print(f"\nDone! Run 'flutter build apk' or 'dart analyze' to verify.")


if __name__ == "__main__":
    main()
