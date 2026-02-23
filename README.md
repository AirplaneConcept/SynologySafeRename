# SynologySafeRename

*User Guide & Reference*

**Version:** Robust4 &nbsp;·&nbsp; **Platform:** Windows PowerShell &nbsp;·&nbsp; **February 2026**

> *This was inspired by the miguno / sauber project, but this is designed to clean up file names in a PC folder so they can be cleanly synced to a Synology NAS rather than files that are already on the Synology NAS. This was created by AI.*
> 
> *Renames files and folders on your Windows drive so they back up cleanly to an encrypted Synology NAS — stripping diacritics, illegal characters, oversized names, and optional phrase patterns, with a full two-stage preview before anything is changed.*

---

## Table of Contents

1. [Requirements](#requirements)
2. [What It Does](#what-it-does)
3. [Workflow](#workflow)
4. [How to Use It](#how-to-use-it)
5. [Recommended Workflow for First-Time Use](#recommended-workflow-for-first-time-use)
6. [Troubleshooting & Known Limitations](#troubleshooting--known-limitations)

---

## Requirements

Before running the script for the first time, confirm the following are in place on your Windows PC.

### System Requirements

| Component | Requirement |
|---|---|
| **Operating System** | Windows 10 / Windows 11 (64-bit) |
| **PowerShell** | Windows PowerShell 5.1 (built-in) or PowerShell 7+ (`pwsh`). PowerShell 7 is recommended for best compatibility. |
| **Execution Policy** | Must allow script execution. The included `.bat` launcher passes `-ExecutionPolicy Bypass` automatically — no permanent policy change needed. |
| **Drive / Network Share** | The target folder must be accessible as a mapped Windows drive letter (e.g. `K:\`) or a local path. The Synology share does NOT need to be connected — the script renames files on your Windows drive, not on the NAS. |
| **Disk Space** | No extra disk space required. Only file and folder names are changed — no data is copied or duplicated. |
| **Administrator Rights** | Not required. Standard user privileges are sufficient, provided you have write access to the target folder. |

### Files Required

Place both files in the same folder (e.g. `K:\eBooks\Scripts\SynologySafeRename\`):

| File | Purpose |
|---|---|
| `SynologySafeRename_Robust4.ps1` | The main PowerShell script. Contains all renaming logic. |
| `RunSynologySafeRename_Robust4.bat` | Double-click launcher. Finds PowerShell automatically and runs the script. |

> **⚠ Note:** The `.bat` file and `.ps1` file must be in the same folder. The script also writes its log file to the same folder it lives in.

### Optional: Installing PowerShell 7

PowerShell 7 (`pwsh`) is faster and handles Unicode edge cases better. The `.bat` launcher automatically uses it if installed, or falls back to the built-in Windows PowerShell 5.1.

Download from: https://aka.ms/powershell

---

## What It Does

SynologySafeRename processes every file and folder under a chosen root folder and renames them so they are fully compatible with encrypted Synology NAS shares. It never touches file contents — only names are changed.

### The Five Transformations

Each name passes through the following steps in order:

**1 · Phrase Removal (optional)**

If you supply a phrase, it is removed everywhere it appears in the name. Extra whitespace left behind is collapsed and the result is trimmed. Leave the phrase blank to skip this step entirely.

Example: `Some Book (Hello World) Vol 1.pdf` → `Some Book Vol 1.pdf`

---

**2 · Explicit Character Expansion**

Certain multi-character substitutions that Unicode normalization alone cannot handle are applied first:

- `ß` → `ss`
- `Ä/Ö/Ü` → `Ae/Oe/Ue` and `ä/ö/ü` → `ae/oe/ue`
- `Æ/æ` → `Ae/ae`, `Œ/œ` → `Oe/oe`
- `Ł/ł` → `L/l`, `Đ/đ` → `D/d`, `Þ/þ` → `Th/th`
- Typographic ligatures: `ﬁ`→`fi`, `ﬂ`→`fl`, `ﬀ`→`ff`, `ﬃ`→`ffi`, `ﬄ`→`ffl`, `ﬅ`→`ft`, `ﬆ`→`st`

---

**3 · Diacritic Stripping**

The name is decomposed to Unicode FormD and all combining marks (accents, umlauts, etc.) are removed. The result is recomposed to FormC. This converts `é`→`e`, `ñ`→`n`, `ç`→`c`, and so on.

---

**4 · Character Sanitization**

Remaining problem characters are replaced:

- Control characters (ASCII < 32 and DEL 127) → hyphen
- Unicode Format-category characters (invisible marks) → hyphen
- Windows-illegal filename characters `< > : " / \ | ? *` → underscore
- En dash and em dash → hyphen
- Consecutive whitespace collapsed; leading/trailing whitespace trimmed
- Trailing dots or spaces removed (Windows restriction)
- Windows reserved device names (`CON`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`) get `_` appended

---

**5 · Length Enforcement**

Names are truncated to stay within both limits simultaneously:

- `MaxNameChars` (default `140`) — the basename character limit per encrypted Synology share spec
- `MaxPathChars` (default `2048`) — the full path length limit

File extensions are always preserved. If truncation would leave a trailing dot or space, those are trimmed. If a parent path is already too long to fit any name within the budget, the item is flagged `SKIP: path budget exhausted at parent` and left unchanged.

---

### Collision Handling

If two items in the same folder would be renamed to the same target name, the script automatically appends a suffix to make them unique — always staying within the length limits:

```
MyBook.epub
MyBook~1.epub
MyBook~2.epub   (and so on)
```

The collision check also accounts for files that already exist in the folder but are not themselves being renamed.

---

## Workflow

The script is divided into two separate stages — folder renames and file renames — each with its own preview and confirmation prompt. Nothing is changed until you explicitly approve it.

### Stage 1 — Folder Renames

1. Double-click `RunSynologySafeRename_Robust4.bat` to launch the script in a console window.
2. You are prompted to enter the full path of the root folder to process (e.g. `K:\eBooks\Book Files`). Type or paste it and press Enter.
3. You are prompted to enter a phrase to remove from names. Press Enter with no input to skip phrase removal.
4. **PREVIEW —** The console displays a full list of every folder that would be renamed, showing the current name and the proposed new name. No changes have been made yet.
5. Review the list carefully. When satisfied, type `Y` and press Enter to apply folder renames.
6. Folder renames are applied deepest-first (so that child folder paths remain valid as parent folders are renamed above them).

> **✔ Tip:** You can type `N` at the folder confirmation prompt to cancel the entire run before any changes are made.

### Stage 2 — File Renames

7. The script immediately re-scans the folder tree — now using the updated folder names from Stage 1 — to produce accurate file paths.
8. **PREVIEW —** A full list of every file that would be renamed is displayed, showing current name and proposed new name. Still no changes to files.
9. Review the file list. When satisfied, type `Y` and press Enter to apply file renames.
10. All file renames are applied.

> **⚠ Note:** If you type `N` at the file confirmation prompt, folder renames already applied in Stage 1 will remain. Only the file renames are cancelled.

### Log File

A timestamped log file is written to the same folder as the script for every run, regardless of whether changes were made or the run was cancelled:

```
SynologySafeRename_YYYYMMDD_HHMMSS.log
```

The log captures the full console output, including the preview lists, your confirmation choices, and any errors. Keep these logs until you have verified your backup is working correctly.

---

## How to Use It

### Method 1 — Double-Click Launcher (Easiest)

1. Place `SynologySafeRename_Robust4.ps1` and `RunSynologySafeRename_Robust4.bat` in the same folder.
2. Double-click `RunSynologySafeRename_Robust4.bat`.
3. Follow the prompts in the console window.

The `.bat` file detects whether PowerShell 7 (`pwsh`) is installed and uses it automatically, falling back to the built-in Windows PowerShell 5.1 if not.

### Method 2 — Command Line (Advanced)

Open PowerShell or a terminal in the script folder and run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\SynologySafeRename_Robust4.ps1 `
     -Folder "K:\eBooks\Book Files" `
     -Phrase "(Hello World)" `
     -MaxNameChars 140 `
     -MaxPathChars 2048
```

Passing parameters on the command line skips the interactive prompts for `Folder` and `Phrase`, which is useful for scripted or scheduled runs.

### Parameters Reference

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Folder` | string | *(prompt)* | Full path of the root folder to process. All subfolders are included recursively. |
| `-Phrase` | string | *(prompt)* | Exact phrase to remove from every name. Leave blank or omit to skip phrase removal. |
| `-MaxNameChars` | int | `140` | Maximum allowed characters in a single file or folder name (basename). Tuned for encrypted Synology shares. |
| `-MaxPathChars` | int | `2048` | Maximum allowed characters in the full path. Items whose parent path already exceeds this budget are skipped. |
| `-IncludeFolders` | switch | `$true` | When true (the default), folders are renamed in Stage 1 before files. Set to `$false` to rename files only. |

---

## Recommended Workflow for First-Time Use

> **⚠ Important:** Always test on a small sample before running on your full library. Renaming thousands of files at once is difficult to undo without a backup.

1. **Back up first.** Ensure you have a working backup or can restore from your NAS before proceeding. The script only renames — it does not delete anything — but having a safety net is strongly recommended.
2. **Copy a small test set.** Copy 10–50 representative files and folders to a temporary location (e.g. `C:\Temp\TestRename`).
3. **Run on the test folder.** Launch the script pointing at your test folder. Review the preview carefully and confirm.
4. **Check the results.** Open the test folder in Windows Explorer and verify the renamed files look correct.
5. **Run on the full folder.** Once satisfied, run the script on your actual library folder (e.g. `K:\eBooks\Book Files`).
6. **Start your Synology backup.** Trigger or wait for your next Hyper Backup / Cloud Sync run and verify files transfer without errors.
7. **Keep the logs.** Retain the timestamped log files until your backup has completed successfully.

### What to Expect in the Preview

During the preview phase you will see output like this:

```
---- FOLDER RENAME PREVIEW ----
[Dir ] K:\eBooks\Ästhetik  -->  Asthetik
[Dir ] K:\eBooks\Ré Éditions  -->  Re Editions

---- FILE RENAME PREVIEW ----
[File] K:\eBooks\Asthetik\Schön_Book_über_Kunst.epub  -->  Schon_Book_uber_Kunst.epub
[File] K:\eBooks\Asthetik\ThisVeryLongTitleThatExceedsTheMaximumAllowedCharacterLimit...epub  -->  ThisVeryLongTitleThatExceedsTheMaximumAllowed...epub
```

Items that require no change are not listed. Items that cannot be fixed (path budget exhausted) are listed with a note but are not renamed.

---

## Troubleshooting & Known Limitations

### "Cannot bind argument to parameter 'Ops' because it is null"

This error occurred in earlier versions of the script when no renames were needed for a given stage (zero folders or zero files required changes). It has been fixed in Robust4. If you see this error, ensure you are running the latest version of the `.ps1` file.

### "SKIP: path budget exhausted at parent"

This means the parent folder path is already longer than `MaxPathChars`, leaving no room for any child name. The item is left unchanged. To resolve this, shorten higher-level folder names first (run the script on a parent directory), or reduce folder nesting depth manually.

### Execution Policy Error

If you see a message like *"cannot be loaded because running scripts is disabled"*, do not change your system execution policy. Instead, always launch via the provided `.bat` file, which passes `-ExecutionPolicy Bypass` automatically and only affects that one session.

### Character Counts vs. Byte Counts

This script enforces length limits by character count (`.Length` in PowerShell), not by UTF-8 byte count. Synology's underlying limits are byte-based in some contexts. After sanitization the vast majority of remaining characters are ASCII (1 byte each), so this distinction is rarely significant in practice.

### Folder Renames Applied, File Renames Cancelled

If you approve folder renames (Stage 1) but then cancel at the file confirmation prompt (Stage 2), folder renames already applied are not reversed. You can re-run the script on the same folder; folders that already have clean names will simply show no change in the next preview.

### What Is NOT Changed

- File contents are never modified.
- File timestamps (created, modified) are preserved by `Rename-Item`.
- Files and folders whose names are already compliant appear in no preview list and are untouched.
- Items flagged `SKIP` are left exactly as found.
