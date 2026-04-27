from pathlib import Path
import argparse
import os
import sys

REPLACEMENTS = {
    "Kelizo": "Kelizo",
    "kelizo": "kelizo",
    "zhilsinger": "zhilsinger",
    "zhilsinger": "zhilsinger"
    
}

EXCLUDED_DIRS = {
    ".git",
    ".gradle",
    "node_modules",
    "build",
    "dist",
    ".idea",
    ".vscode",
}

MAX_FILE_SIZE_MB = 25


def replace_words(text: str) -> str:
    for old, new in REPLACEMENTS.items():
        text = text.replace(old, new)
    return text


def name_after_replacement(name: str) -> str:
    for old, new in REPLACEMENTS.items():
        name = name.replace(old, new)
    return name


def looks_like_text(text: str) -> bool:
    if not text:
        return True

    bad_chars = 0
    for ch in text:
        if ch in "\n\r\t":
            continue
        if ord(ch) < 32:
            bad_chars += 1

    return bad_chars / max(len(text), 1) < 0.02


def read_text_file(path: Path):
    raw = path.read_bytes()

    encodings = ["utf-8-sig", "utf-8", "utf-16", "utf-16-le", "utf-16-be", "cp1252"]

    for enc in encodings:
        try:
            text = raw.decode(enc)
            if looks_like_text(text):
                return text, enc
        except UnicodeDecodeError:
            continue

    return None, None


def should_skip_path(path: Path, root: Path) -> bool:
    try:
        rel_parts = path.relative_to(root).parts
    except ValueError:
        return True

    return any(part in EXCLUDED_DIRS for part in rel_parts)


def replace_inside_files(root: Path, apply_changes: bool):
    changed_files = 0
    skipped_files = 0

    for dirpath, dirnames, filenames in os.walk(root):
        current_dir = Path(dirpath)

        dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS]

        for filename in filenames:
            path = current_dir / filename

            if should_skip_path(path, root):
                continue

            if path.is_symlink():
                skipped_files += 1
                continue

            try:
                size_mb = path.stat().st_size / (1024 * 1024)
                if size_mb > MAX_FILE_SIZE_MB:
                    skipped_files += 1
                    continue

                text, encoding = read_text_file(path)

                if text is None:
                    skipped_files += 1
                    continue

                new_text = replace_words(text)

                if new_text != text:
                    changed_files += 1
                    print(f"[CONTENT] {path}")

                    if apply_changes:
                        path.write_bytes(new_text.encode(encoding))

            except Exception as e:
                skipped_files += 1
                print(f"[SKIPPED] {path} — {e}")

    return changed_files, skipped_files


def collect_rename_targets(root: Path):
    targets = []

    for dirpath, dirnames, filenames in os.walk(root):
        current_dir = Path(dirpath)

        dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS]

        for filename in filenames:
            path = current_dir / filename
            new_name = name_after_replacement(path.name)

            if new_name != path.name:
                targets.append(path)

        for dirname in dirnames:
            path = current_dir / dirname
            new_name = name_after_replacement(path.name)

            if new_name != path.name:
                targets.append(path)

    # Deepest paths first so child folders/files are renamed before parent folders
    targets.sort(key=lambda p: len(p.parts), reverse=True)

    return targets


def rename_files_and_folders(root: Path, apply_changes: bool):
    renamed = 0
    conflicts = 0

    targets = collect_rename_targets(root)

    for old_path in targets:
        if not old_path.exists():
            continue

        new_name = name_after_replacement(old_path.name)
        new_path = old_path.with_name(new_name)

        if old_path == new_path:
            continue

        if new_path.exists():
            conflicts += 1
            print(f"[CONFLICT] Cannot rename:")
            print(f"  FROM: {old_path}")
            print(f"  TO:   {new_path}")
            print(f"  Reason: target already exists")
            continue

        renamed += 1
        print(f"[RENAME] {old_path}")
        print(f"   --->  {new_path}")

        if apply_changes:
            old_path.rename(new_path)

    return renamed, conflicts


def main():
    parser = argparse.ArgumentParser(
        description="Replace words inside project files, file names, and folder names."
    )

    parser.add_argument(
        "project_folder",
        help="Path to the project folder"
    )

    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually make changes. Without this, the script only previews changes."
    )

    args = parser.parse_args()

    root = Path(args.project_folder).resolve()

    if not root.exists() or not root.is_dir():
        print(f"Project folder does not exist or is not a folder: {root}")
        sys.exit(1)

    print()
    print(f"Project folder: {root}")

    if args.apply:
        print("Mode: APPLY CHANGES")
    else:
        print("Mode: PREVIEW ONLY")
        print("No files will be changed unless you run again with --apply")

    print()
    print("Replacements:")
    for old, new in REPLACEMENTS.items():
        print(f"  {old} -> {new}")

    print()
    print("Step 1: Checking file contents...")
    changed_files, skipped_files = replace_inside_files(root, args.apply)

    print()
    print("Step 2: Checking file and folder names...")
    renamed, conflicts = rename_files_and_folders(root, args.apply)

    print()
    print("Done.")
    print(f"Files with changed contents: {changed_files}")
    print(f"Files/folders renamed: {renamed}")
    print(f"Skipped files: {skipped_files}")
    print(f"Rename conflicts: {conflicts}")

    if not args.apply:
        print()
        print("This was only a preview.")
        print("To actually make the changes, run the same command again with --apply")


if __name__ == "__main__":
    main()