<# 
SynologySafeRename_Robust4.ps1

Fixes Robust3 bug:
- Allows empty file extensions during collision resolution (folders + extensionless files).
- Keeps in-batch collision resolution + two-step preview + logging + pause.

Defaults tuned for ENCRYPTED Synology shares:
- MaxNameChars = 140
- MaxPathChars = 2048
#>

[CmdletBinding()]
param(
  [string]$Folder,
  [string]$Phrase,
  [int]$MaxNameChars = 140,
  [int]$MaxPathChars = 2048,
  [switch]$IncludeFolders = $true
)

$ErrorActionPreference = "Stop"

# --- Logging ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path $ScriptDir ("SynologySafeRename_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
Start-Transcript -Path $LogFile -Force | Out-Null

try {

function Apply-CharMap {
  param([Parameter(Mandatory=$true)][string]$Text)

  $map = @(
    @('ß','ss'),
    @('Ä','Ae'), @('Ö','Oe'), @('Ü','Ue'),
    @('ä','ae'), @('ö','oe'), @('ü','ue'),

    @('Æ','Ae'), @('æ','ae'),
    @('Œ','Oe'), @('œ','oe'),

    @('Ł','L'),  @('ł','l'),
    @('Đ','D'),  @('đ','d'),

    @('Þ','Th'), @('þ','th'),
    @('Ð','D'),  @('ð','d'),

    @('Ĳ','IJ'), @('ĳ','ij'),

    # Ligatures
    @('ﬀ','ff'), @('ﬁ','fi'), @('ﬂ','fl'), @('ﬃ','ffi'), @('ﬄ','ffl'),
    @('ﬅ','ft'), @('ﬆ','st')
  )

  foreach ($pair in $map) {
    $Text = $Text.Replace($pair[0], $pair[1])
  }
  return $Text
}

function Strip-CombiningMarks {
  param([Parameter(Mandatory=$true)][string]$Text)
  $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $normalized.ToCharArray()) {
    $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
    if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark -and
        $cat -ne [Globalization.UnicodeCategory]::SpacingCombiningMark -and
        $cat -ne [Globalization.UnicodeCategory]::EnclosingMark) {
      [void]$sb.Append($ch)
    }
  }
  return $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function Sanitize-Name {
  param([Parameter(Mandatory=$true)][string]$Name)

  # Replace control chars + Unicode "Format" (often invisible marks) with '-'
  $chars = $Name.ToCharArray() | ForEach-Object {
    $c = [char]$_
    $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($c)
    if ([int]$c -lt 32 -or [int]$c -eq 127) { return '-' }
    if ($cat -eq [Globalization.UnicodeCategory]::Format) { return '-' }
    return $c
  }
  $Name = -join $chars

  $Name = Apply-CharMap -Text $Name
  $Name = Strip-CombiningMarks -Text $Name

  # Replace Windows-invalid filename characters with '_'
  $Name = $Name -replace '[<>:"/\\|?*]', '_'

  # Normalize dash variants to hyphen
  $Name = $Name -replace '[\u2013\u2014]', '-'

  # Collapse whitespace
  $Name = ($Name -replace '\s{2,}', ' ').Trim()

  # Windows: no trailing dots/spaces
  $Name = $Name.TrimEnd(' ', '.')

  if ([string]::IsNullOrWhiteSpace($Name)) { $Name = '_' }

  # Avoid reserved device names (case-insensitive) for basenames
  $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
  $ext  = [System.IO.Path]::GetExtension($Name)
  $reserved = @('CON','PRN','AUX','NUL') + (1..9 | ForEach-Object { "COM$_" }) + (1..9 | ForEach-Object { "LPT$_" })
  if ($reserved -contains $base.ToUpperInvariant()) {
    $base = "${base}_"
    $Name = "$base$ext"
  }

  return $Name
}

function Compute-AllowedNameCharsForParent {
  param(
    [Parameter(Mandatory=$true)][string]$ParentFullPath,
    [Parameter(Mandatory=$true)][int]$MaxNameChars,
    [Parameter(Mandatory=$true)][int]$MaxPathChars
  )
  $budget = $MaxPathChars - ($ParentFullPath.Length + 1)
  if ($budget -lt 1) { return 0 }
  return [Math]::Min($MaxNameChars, $budget)
}

function Get-TruncatedName {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][int]$AllowedChars
  )

  if ($AllowedChars -lt 1) { return $Name }
  if ($Name.Length -le $AllowedChars) { return $Name }

  $ext  = [System.IO.Path]::GetExtension($Name)
  $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)

  $baseMax = $AllowedChars - $ext.Length
  if ($baseMax -lt 1) { $baseMax = $AllowedChars }

  if ($base.Length -gt $baseMax) { $base = $base.Substring(0, $baseMax) }

  $base = $base.TrimEnd(' ','.')
  if ($base.Length -eq 0) { $base = "_" }

  $candidate = "$base$ext"
  if ($candidate.Length -gt $AllowedChars) {
    $candidate = $candidate.Substring(0, $AllowedChars).TrimEnd(' ','.')
    if ($candidate.Length -eq 0) { $candidate = "_" }
  }
  return $candidate
}

function Split-BaseExt {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [switch]$IsDirectory
  )
  if ($IsDirectory) {
    return ,@($Name, "")
  } else {
    return ,@([System.IO.Path]::GetFileNameWithoutExtension($Name), [System.IO.Path]::GetExtension($Name))
  }
}

function Build-UniqueName {
  param(
    [Parameter(Mandatory=$true)][string]$Base,
    [AllowEmptyString()][string]$Ext,
    [Parameter(Mandatory=$true)][int]$AllowedChars,
    [Parameter(Mandatory=$true)][int]$Index
  )

  if ($null -eq $Ext) { $Ext = "" }

  if ($Index -le 0) {
    return "$Base$Ext"
  }

  $suffix = "~$Index"
  $baseMax = $AllowedChars - $suffix.Length - $Ext.Length
  if ($baseMax -lt 1) {
    $cand = (("$Base$Ext").Substring(0, $AllowedChars)).TrimEnd(' ','.')
    if ([string]::IsNullOrWhiteSpace($cand)) { $cand = "_" }
    return $cand
  }

  $b = $Base
  if ($b.Length -gt $baseMax) { $b = $b.Substring(0, $baseMax) }
  $b = $b.TrimEnd(' ','.')
  if ($b.Length -eq 0) { $b = "_" }

  return "$b$suffix$Ext"
}

function Resolve-CollisionsInBatch {
  param(
    [Parameter(Mandatory=$true)]$Ops,
    [switch]$IsDirectory
  )

  $groups = $Ops | Group-Object Parent

  foreach ($g in $groups) {
    $parent = $g.Name
    $reserved = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    # Seed with existing entries
    try {
      Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$reserved.Add($_.Name)
      }
    } catch { }

    $items = $g.Group | Sort-Object From

    foreach ($op in $items) {
      $allowed = [int]$op.Allowed
      $desired = [string]$op.ToName

      $baseExt = Split-BaseExt -Name $desired -IsDirectory:$IsDirectory
      $base = [string]$baseExt[0]
      $ext  = [string]$baseExt[1]  # may be ""

      $idx = 0
      while ($true) {
        $candidate = Build-UniqueName -Base $base -Ext $ext -AllowedChars $allowed -Index $idx
        if (-not $reserved.Contains($candidate)) {
          $op.ToName = $candidate
          $op.ToFull = Join-Path $parent $candidate
          [void]$reserved.Add($candidate)
          break
        }
        $idx++
        if ($idx -gt 2000) { throw "Too many collisions in '$parent' while resolving '$desired'." }
      }
    }
  }

  return $Ops
}

# ---- Prompts ----
if ([string]::IsNullOrWhiteSpace($Folder)) {
  $Folder = Read-Host "Enter full folder path to process (e.g. K:\eBooks\Book Files)"
}
if (-not (Test-Path -LiteralPath $Folder)) {
  throw "Folder not found: $Folder"
}

if ($null -eq $Phrase) {
  $Phrase = Read-Host "Enter the EXACT phrase to remove (leave blank to skip phrase removal)"
}
$doPhrase = -not [string]::IsNullOrWhiteSpace($Phrase)
$escaped = if ($doPhrase) { [regex]::Escape($Phrase) } else { $null }

if ($MaxNameChars -le 0) { $MaxNameChars = 140 }
if ($MaxPathChars -le 0) { $MaxPathChars = 2048 }

Write-Host ""
Write-Host "---- PREVIEW (no changes yet) ----" -ForegroundColor Yellow
Write-Host "Folder: $Folder"
Write-Host "Remove phrase: " -NoNewline
if ($doPhrase) { Write-Host "'$Phrase'" } else { Write-Host "(none)" }
Write-Host "Max name length (characters): $MaxNameChars"
Write-Host "Max path length (characters): $MaxPathChars"
Write-Host "Include folders: $IncludeFolders"
Write-Host "Log file: $LogFile"
Write-Host ""

# -------------------------
# Plan folder renames first
# -------------------------
$dirOps = New-Object System.Collections.Generic.List[object]

if ($IncludeFolders) {
  $dirs = Get-ChildItem -LiteralPath $Folder -Recurse -Directory -Force -ErrorAction SilentlyContinue |
    Sort-Object { $_.FullName.Length } -Descending

  foreach ($d in $dirs) {
    $newName = $d.Name

    if ($doPhrase -and $newName -match $escaped) {
      $newName = ($newName -replace $escaped, "") -replace "\s{2,}", " "
      $newName = $newName.Trim()
    }

    $newName = Sanitize-Name -Name $newName

    $allowed = Compute-AllowedNameCharsForParent -ParentFullPath $d.Parent.FullName -MaxNameChars $MaxNameChars -MaxPathChars $MaxPathChars
    if ($allowed -lt 1) {
      $dirOps.Add([pscustomobject]@{ Type="Dir"; From=$d.FullName; Parent=$d.Parent.FullName; ToName=$null; Allowed=0; Note="SKIP: path budget exhausted at parent" })
      continue
    }

    $newName = Get-TruncatedName -Name $newName -AllowedChars $allowed

    if ($newName -ne $d.Name) {
      $dirOps.Add([pscustomobject]@{
        Type="Dir"
        From=$d.FullName
        Parent=$d.Parent.FullName
        ToName=$newName
        ToFull=$null
        Allowed=$allowed
        Note=""
      })
    }
  }

  $dirChanges = $dirOps | Where-Object { $_.ToName }
  $dirSkips   = $dirOps | Where-Object { -not $_.ToName -and $_.Note }

  if ($dirChanges) { $dirChanges = Resolve-CollisionsInBatch -Ops $dirChanges -IsDirectory }

  Write-Host "---- FOLDER RENAME PREVIEW ----" -ForegroundColor Yellow
  if ($dirChanges.Count -eq 0) {
    Write-Host "No folder renames needed." -ForegroundColor Cyan
  } else {
    foreach ($op in ($dirChanges | Sort-Object From)) {
      Write-Host "[Dir ] $($op.From)  -->  $($op.ToName)"
    }
  }
  foreach ($op in ($dirSkips | Sort-Object From)) {
    Write-Host "[Dir ] $($op.From)  -->  (no change)  ($($op.Note))" -ForegroundColor DarkYellow
  }

  Write-Host ""
  Write-Host "Next: files will be scanned AFTER folder renames (so paths are accurate)." -ForegroundColor Cyan
  Write-Host ""
  $confirm = Read-Host "Apply FOLDER renames now? (Y/N)"
  if ($confirm -notmatch '^[Yy]$') {
    Write-Host "Cancelled. No changes made." -ForegroundColor Red
    throw "User cancelled at folder confirmation."
  }

  foreach ($op in ($dirChanges | Sort-Object { $_.From.Length } -Descending)) {
    Rename-Item -LiteralPath $op.From -NewName $op.ToName -ErrorAction Stop
  }

  Write-Host ""
  Write-Host "Folder renames applied." -ForegroundColor Green
  Write-Host ""
}

# -------------------------
# Now scan files and plan
# -------------------------
Write-Host "Scanning files..." -ForegroundColor Cyan
$files = Get-ChildItem -LiteralPath $Folder -Recurse -File -Force -ErrorAction SilentlyContinue

$fileOps = New-Object System.Collections.Generic.List[object]

foreach ($f in $files) {
  $newName = $f.Name

  if ($doPhrase -and $newName -match $escaped) {
    $newName = ($newName -replace $escaped, "") -replace "\s{2,}", " "
    $newName = $newName.Trim()
  }

  $newName = Sanitize-Name -Name $newName

  $allowed = Compute-AllowedNameCharsForParent -ParentFullPath $f.DirectoryName -MaxNameChars $MaxNameChars -MaxPathChars $MaxPathChars
  if ($allowed -lt 1) {
    $fileOps.Add([pscustomobject]@{ Type="File"; From=$f.FullName; Parent=$f.DirectoryName; ToName=$null; Allowed=0; Note="SKIP: path budget exhausted at parent" })
    continue
  }

  $newName = Get-TruncatedName -Name $newName -AllowedChars $allowed

  if ($newName -ne $f.Name) {
    $fileOps.Add([pscustomobject]@{
      Type="File"
      From=$f.FullName
      Parent=$f.DirectoryName
      ToName=$newName
      ToFull=$null
      Allowed=$allowed
      Note=""
    })
  }
}

$fileChanges = $fileOps | Where-Object { $_.ToName }
$fileSkips   = $fileOps | Where-Object { -not $_.ToName -and $_.Note }

if ($fileChanges) { $fileChanges = Resolve-CollisionsInBatch -Ops $fileChanges }

Write-Host "---- FILE RENAME PREVIEW ----" -ForegroundColor Yellow
if ($fileChanges.Count -eq 0) {
  Write-Host "No file renames needed." -ForegroundColor Cyan
} else {
  foreach ($op in ($fileChanges | Sort-Object From)) {
    Write-Host "[File] $($op.From)  -->  $($op.ToName)"
  }
}
foreach ($op in ($fileSkips | Sort-Object From)) {
  Write-Host "[File] $($op.From)  -->  (no change)  ($($op.Note))" -ForegroundColor DarkYellow
}

Write-Host ""
$confirm2 = Read-Host "Apply FILE renames now? (Y/N)"
if ($confirm2 -notmatch '^[Yy]$') {
  Write-Host "File renames cancelled. (Folders may already have been renamed.)" -ForegroundColor DarkYellow
  throw "User cancelled at file confirmation."
}

foreach ($op in ($fileChanges | Sort-Object From)) {
  Rename-Item -LiteralPath $op.From -NewName $op.ToName -ErrorAction Stop
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Log file: $LogFile"

} catch {

  if ($_.Exception.Message -notmatch '^User cancelled') {
    Write-Host ""
    Write-Host "ERROR OCCURRED:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
  }
  Write-Host "See log: $LogFile" -ForegroundColor Yellow

} finally {
  try { Stop-Transcript | Out-Null } catch { }
  Read-Host "Press Enter to exit"
}
