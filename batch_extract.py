#!/usr/bin/env python3
"""
batch_extract.py — Batch-extract code blocks from a monolithic Dart file into
                    separate files using a JSON manifest.

This script is designed to handle hundreds/thousands of extraction operations
from a large main.dart (20k+ lines) safely and efficiently.

Strategy:
  1. Read the manifest JSON which lists each block to extract with:
     - start_line / end_line (1-indexed, inclusive)
     - dest_file (relative path like "lib/widgets/foo.dart")
     - imports (list of import lines needed in the new file)
     - export_line (the export statement to leave behind in main.dart)
     - description (optional, for logging)
  2. Validate all ranges (no overlaps, within bounds).
  3. Sort extractions by start_line DESCENDING so we process from bottom-up
     (this avoids any line-number shift issues).
  4. For each extraction:
     a. Cut the specified lines from the in-memory source
     b. Write them to the destination file with proper imports header
     c. Replace the cut region with the export_line in the source
  5. Write the modified source file once at the end.
  6. Optionally verify with `dart analyze`.

Usage:
  python3 batch_extract.py manifest.json [--execute] [--no-backup]
  python3 batch_extract.py manifest.json --dry-run   (default: dry-run)

Manifest format (manifest.json):
{
  "source": "lib/main.dart",
  "extractions": [
    {
      "start_line": 53,
      "end_line": 445,
      "dest_file": "lib/widgets/glass_widgets.dart",
      "imports": [
        "import 'dart:ui' show ImageFilter;",
        "import 'package:flutter/material.dart';"
      ],
      "export_line": "export 'package:nexon/widgets/glass_widgets.dart';",
      "description": "Liquid glass / warm glass UI widgets"
    }
  ]
}
"""

import argparse
import json
import os
import sys
import shutil
from datetime import datetime
from typing import List, Dict, Any, Tuple


def read_file(path: str) -> str:
    """Read entire file as string."""
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def read_lines(path: str) -> List[str]:
    """Read file as list of lines (each ending with \\n)."""
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.readlines()


def write_file(path: str, content: str):
    """Write string to file, creating parent directories."""
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def write_lines(path: str, lines: List[str]):
    """Write list of lines to file, creating parent directories."""
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)


def validate_manifest(manifest: Dict[str, Any], total_lines: int) -> List[str]:
    """Validate manifest data. Returns list of error messages (empty = OK)."""
    errors = []

    if "source" not in manifest:
        errors.append("Manifest missing 'source' field")
        return errors

    if "extractions" not in manifest or not manifest["extractions"]:
        errors.append("Manifest missing or empty 'extractions' array")
        return errors

    extractions = manifest["extractions"]

    for i, ext in enumerate(extractions):
        label = ext.get("description", f"extraction #{i+1}")

        # Required fields
        for field in ["start_line", "end_line", "dest_file"]:
            if field not in ext:
                errors.append(f"[{label}] Missing required field: {field}")

        if "start_line" in ext and "end_line" in ext:
            s, e = ext["start_line"], ext["end_line"]
            if s < 1:
                errors.append(f"[{label}] start_line {s} < 1")
            if e > total_lines:
                errors.append(f"[{label}] end_line {e} > total lines {total_lines}")
            if s > e:
                errors.append(f"[{label}] start_line {s} > end_line {e}")

    # Check for overlapping ranges
    sorted_exts = sorted(
        [(ext["start_line"], ext["end_line"], ext.get("description", f"#{i+1}"))
         for i, ext in enumerate(extractions)
         if "start_line" in ext and "end_line" in ext]
    )

    for i in range(len(sorted_exts) - 1):
        _, end_a, label_a = sorted_exts[i]
        start_b, _, label_b = sorted_exts[i + 1]
        if end_a >= start_b:
            errors.append(
                f"Overlapping ranges: [{label_a}] ends at {end_a} but "
                f"[{label_b}] starts at {start_b}"
            )

    # Check for duplicate dest_files
    dest_files = [ext["dest_file"] for ext in extractions if "dest_file" in ext]
    seen = {}
    for df in dest_files:
        if df in seen:
            errors.append(f"Duplicate dest_file: {df}")
        seen[df] = True

    return errors


def build_dest_content(
    block_lines: List[str],
    imports: List[str],
    source_name: str,
    start_line: int,
    end_line: int,
) -> str:
    """Build the content for the destination file with header + imports + code."""
    parts = []

    # Header comment
    parts.append(f"// Extracted from {source_name} lines {start_line}-{end_line}\n")
    parts.append(f"// Extracted on: {datetime.now().isoformat()}\n")
    parts.append("\n")

    # Imports
    if imports:
        for imp in imports:
            line = imp.strip()
            if not line.endswith(";"):
                line += ";"
            parts.append(line + "\n")
        parts.append("\n")

    # The actual code block
    parts.extend(block_lines)

    # Ensure file ends with newline
    content = "".join(parts)
    if not content.endswith("\n"):
        content += "\n"

    return content


def perform_extractions(
    src_lines: List[str],
    extractions: List[Dict[str, Any]],
    source_basename: str,
    execute: bool,
    base_dir: str,
) -> Tuple[List[str], List[Dict[str, str]]]:
    """
    Perform all extractions on the source lines.

    Processes extractions in reverse order (bottom-up) to avoid line-shift issues.

    Returns:
        (modified_src_lines, results_log)
    """
    # Sort by start_line DESCENDING (process bottom-up)
    sorted_exts = sorted(extractions, key=lambda x: x["start_line"], reverse=True)

    results = []
    modified = list(src_lines)  # Work on a copy

    for ext in sorted_exts:
        start = ext["start_line"]
        end = ext["end_line"]
        dest = ext["dest_file"]
        imports = ext.get("imports", [])
        export_line = ext.get("export_line", "")
        desc = ext.get("description", dest)

        # Extract the block (1-indexed to 0-indexed)
        block = modified[start - 1 : end]
        block_count = len(block)

        # Build replacement lines for source
        replacement = []
        if export_line:
            # Support multi-line export_line (e.g. two export statements)
            for line in export_line.strip().split("\n"):
                line = line.strip()
                if line:
                    if not line.endswith("\n"):
                        line += "\n"
                    replacement.append(line)

        # Perform the cut-and-replace in memory
        modified = modified[: start - 1] + replacement + modified[end:]

        # Build destination file content
        dest_content = build_dest_content(
            block, imports, source_basename, start, end
        )

        dest_path = os.path.join(base_dir, dest)

        result = {
            "description": desc,
            "start": start,
            "end": end,
            "lines_extracted": block_count,
            "dest_file": dest,
            "dest_path": dest_path,
            "export_line": export_line,
            "status": "dry-run",
        }

        if execute:
            # Check if dest already exists
            if os.path.exists(dest_path):
                result["status"] = "SKIPPED (dest exists)"
                results.append(result)
                # Undo the in-memory modification (re-insert the block)
                modified = modified[: start - 1] + block + modified[start - 1 + len(replacement):]
                print(f"  ⚠ SKIP {dest} — file already exists")
                continue

            write_file(dest_path, dest_content)
            result["status"] = "written"

        results.append(result)

        # Preview
        first_line = block[0].rstrip() if block else ""
        last_line = block[-1].rstrip() if block else ""
        print(f"  {'✓' if execute else '○'} [{start}-{end}] ({block_count} lines) → {dest}")
        print(f"      First: {first_line[:80]}")
        print(f"      Last:  {last_line[:80]}")
        if export_line:
            print(f"      Export: {export_line}")
        print()

    return modified, results


def main():
    parser = argparse.ArgumentParser(
        description="Batch-extract code blocks from a monolithic Dart file"
    )
    parser.add_argument(
        "manifest", help="Path to the JSON manifest file"
    )
    parser.add_argument(
        "--execute", action="store_true",
        help="Actually write files (default: dry-run)"
    )
    parser.add_argument(
        "--no-backup", action="store_true",
        help="Skip creating .bak backup of source"
    )
    parser.add_argument(
        "--verify", action="store_true",
        help="Run 'dart analyze' after extraction"
    )
    args = parser.parse_args()

    # Load manifest
    print(f"\n{'='*70}")
    print(f"  BATCH CODE EXTRACTOR")
    print(f"  Mode: {'EXECUTE' if args.execute else 'DRY-RUN (use --execute to write)'}")
    print(f"  Manifest: {args.manifest}")
    print(f"{'='*70}\n")

    if not os.path.exists(args.manifest):
        print(f"ERROR: Manifest not found: {args.manifest}")
        sys.exit(1)

    with open(args.manifest, "r") as f:
        manifest = json.load(f)

    source = manifest["source"]

    # Determine base directory (where source is relative to)
    # If source starts with 'lib/', we use the directory containing 'lib/'
    base_dir = "."
    if "/" in source:
        # Find the project root — the dir that contains lib/
        parts = source.split("/")
        if "lib" in parts:
            idx = parts.index("lib")
            base_dir = os.path.join(*parts[:idx]) if idx > 0 else "."

    if not os.path.exists(source):
        print(f"ERROR: Source file not found: {source}")
        sys.exit(1)

    src_lines = read_lines(source)
    total = len(src_lines)
    print(f"Source: {source} ({total} lines)")

    # Validate
    errors = validate_manifest(manifest, total)
    if errors:
        print("\n❌ VALIDATION ERRORS:")
        for err in errors:
            print(f"  • {err}")
        sys.exit(1)

    extractions = manifest["extractions"]
    total_extract_lines = sum(
        ext["end_line"] - ext["start_line"] + 1 for ext in extractions
    )
    print(f"Extractions: {len(extractions)} blocks, {total_extract_lines} total lines")
    print(f"Expected result: ~{total - total_extract_lines + len(extractions)} lines in source\n")

    # Process
    print("Processing extractions (bottom-up):\n")
    modified_lines, results = perform_extractions(
        src_lines, extractions, os.path.basename(source), args.execute, base_dir
    )

    # Summary
    written = sum(1 for r in results if r["status"] == "written")
    skipped = sum(1 for r in results if "SKIP" in r["status"])
    dry_run = sum(1 for r in results if r["status"] == "dry-run")

    print(f"\n{'='*70}")
    print(f"  SUMMARY")
    print(f"{'='*70}")
    print(f"  Source before: {total} lines")
    print(f"  Source after:  {len(modified_lines)} lines")
    print(f"  Lines removed: {total - len(modified_lines)}")
    print(f"  Files created: {written}")
    print(f"  Files skipped: {skipped}")
    if dry_run:
        print(f"  Dry-run only:  {dry_run}")
    print()

    if not args.execute:
        print("  ⓘ  This was a DRY RUN. No files were modified.")
        print("  ⓘ  Re-run with --execute to apply changes.")
        print()
        return

    # Backup source
    if not args.no_backup:
        bak = source + ".bak"
        shutil.copy2(source, bak)
        print(f"  Backup: {bak}")

    # Write modified source
    write_lines(source, modified_lines)
    print(f"  Written: {source} ({len(modified_lines)} lines)")

    # Verify line count
    verify = read_lines(source)
    print(f"  Verify:  {len(verify)} lines in source")

    # Optional dart analyze
    if args.verify:
        print("\n  Running dart analyze...")
        import subprocess
        result = subprocess.run(
            ["dart", "analyze", source],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print("  ✓ dart analyze passed")
        else:
            print("  ✗ dart analyze found issues:")
            print(result.stdout)
            print(result.stderr)

    # Write results log
    log_path = args.manifest.replace(".json", "_results.json")
    with open(log_path, "w") as f:
        json.dump({
            "timestamp": datetime.now().isoformat(),
            "source": source,
            "lines_before": total,
            "lines_after": len(modified_lines),
            "results": results,
        }, f, indent=2)
    print(f"  Log: {log_path}")

    print(f"\n  Done! Run 'flutter build apk' or 'dart analyze' to verify.\n")


if __name__ == "__main__":
    main()
