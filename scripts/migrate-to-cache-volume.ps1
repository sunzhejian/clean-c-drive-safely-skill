param(
  [Parameter(Mandatory=$true)]
  [string[]]$SourcePaths,
  [Parameter(Mandatory=$true)]
  [string]$DestinationRoot,
  [string]$SourceDrive = "C",
  [string]$LogDir = "",
  [int64]$MinBytes = 50MB,
  [string[]]$ProtectedPaths = @(),
  [switch]$Execute,
  [switch]$AllowProtected
)

$ErrorActionPreference = "Stop"
$sourceDriveName = $SourceDrive.TrimEnd(":")
$sourceRoot = [IO.Path]::GetFullPath("$sourceDriveName`:\")
$destRootFull = [IO.Path]::GetFullPath($DestinationRoot)
if (-not $LogDir) { $LogDir = Join-Path $destRootFull "MigrationLogs" }
New-Item -ItemType Directory -Force -Path $DestinationRoot, $LogDir | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogDir "drive-migration_$timestamp.csv"

function Test-ReparsePoint {
  param([System.IO.FileSystemInfo]$Item)
  return (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-PathBytes {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  $item = Get-Item -LiteralPath $Path -Force
  if (Test-ReparsePoint $item) { return 0 }
  if ($item.PSIsContainer) {
    return [int64]((Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
  }
  return [int64]$item.Length
}

function Convert-ToDestination {
  param([string]$Source)
  $relative = $Source.Substring($sourceRoot.Length)
  return [IO.Path]::GetFullPath((Join-Path $destRootFull $relative))
}

function Test-ProtectedPath {
  param([string]$Source)
  $defaults = @(
    (Join-Path $env:USERPROFILE ".codex"),
    (Join-Path $env:USERPROFILE ".ssh"),
    (Join-Path $env:USERPROFILE "Documents"),
    (Join-Path $env:USERPROFILE "Desktop")
  )
  foreach ($protected in ($defaults + $ProtectedPaths)) {
    if (-not $protected) { continue }
    $full = [IO.Path]::GetFullPath($protected).TrimEnd("\")
    if ($Source.Equals($full, [StringComparison]::OrdinalIgnoreCase) -or
        $Source.StartsWith($full + "\", [StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  return $false
}

$processes = Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
  try {
    if ($_.Path) { [pscustomobject]@{ Name = $_.ProcessName; Id = $_.Id; Path = $_.Path } }
  } catch {}
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($raw in $SourcePaths) {
  $source = [IO.Path]::GetFullPath($raw)
  $dest = if ($source.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) { Convert-ToDestination $source } else { "" }
  $status = "pending"
  $note = ""
  $bytes = 0
  try {
    if (-not $source.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "source outside source drive root" }
    if (-not $dest.StartsWith($destRootFull, [StringComparison]::OrdinalIgnoreCase)) { throw "destination outside DestinationRoot" }
    if (-not $AllowProtected -and (Test-ProtectedPath $source)) { throw "protected path" }
    if (-not (Test-Path -LiteralPath $source)) { $status = "skip_missing"; throw "logged" }
    $srcItem = Get-Item -LiteralPath $source -Force
    if (Test-ReparsePoint $srcItem) { $status = "skip_link"; throw "logged" }
    $active = $processes | Where-Object { $_.Path -and $_.Path.StartsWith($source, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 5
    if ($active) {
      $status = "skip_running"
      $note = ($active | ForEach-Object { "$($_.Name):$($_.Id)" }) -join ";"
      throw "logged"
    }
    $bytes = Get-PathBytes $source
    if ($bytes -lt $MinBytes) { $status = "skip_too_small"; throw "logged" }
    if (Test-Path -LiteralPath $dest) { $status = "skip_dest_exists"; throw "logged" }
    if (-not $Execute) { $status = "dry_run"; throw "logged" }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Move-Item -LiteralPath $source -Destination $dest -ErrorAction Stop
    New-Item -ItemType Junction -Path $source -Target $dest -ErrorAction Stop | Out-Null
    $junction = Get-Item -LiteralPath $source -Force
    if (-not (Test-ReparsePoint $junction)) { throw "junction verification failed" }
    if (-not (Test-Path -LiteralPath $dest)) { throw "destination verification failed" }
    $status = "migrated"
    $note = "ok"
  } catch {
    if ($_.Exception.Message -ne "logged") {
      $status = "error"
      $note = $_.Exception.Message
    }
  }
  $row = [pscustomobject]@{ Source = $source; Destination = $dest; GB = [math]::Round($bytes / 1GB, 3); Status = $status; Note = $note }
  $results.Add($row) | Out-Null
  Write-Host ("{0,-16} {1,8:N3} GB  {2}" -f $status, ($bytes / 1GB), $source)
}

$results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $logPath
Write-Host "LOG=$logPath"
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null -and $_.Free -ne $null } |
  Select-Object Name,@{n="UsedGB";e={[math]::Round($_.Used/1GB,2)}},@{n="FreeGB";e={[math]::Round($_.Free/1GB,2)}} |
  Format-Table -AutoSize
