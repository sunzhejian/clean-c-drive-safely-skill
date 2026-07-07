param(
  [Parameter(Mandatory=$true)]
  [string[]]$SourcePaths,
  [Parameter(Mandatory=$true)]
  [string]$DestinationRoot,
  [string]$LogDir = "E:\DevCaches\MigrationLogs",
  [int64]$MinBytes = 50MB,
  [switch]$Execute,
  [switch]$AllowCodex
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $DestinationRoot, $LogDir | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogDir "c-drive-migration_$timestamp.csv"
$destRootFull = [IO.Path]::GetFullPath($DestinationRoot)

function Get-DirBytes {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  $item = Get-Item -LiteralPath $Path -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return 0 }
  if ($item.PSIsContainer) {
    return [int64]((Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
  }
  return [int64]$item.Length
}

function Get-Destination {
  param([string]$Source)
  $relative = $Source.Substring(3)
  return [IO.Path]::GetFullPath((Join-Path $destRootFull $relative))
}

$processes = Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
  try {
    if ($_.Path) { [pscustomobject]@{ Name = $_.ProcessName; Id = $_.Id; Path = $_.Path } }
  } catch {}
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($raw in $SourcePaths) {
  $source = [IO.Path]::GetFullPath($raw)
  $dest = if ($source.StartsWith("C:\", [StringComparison]::OrdinalIgnoreCase)) { Get-Destination $source } else { "" }
  $status = "pending"
  $note = ""
  $bytes = 0
  try {
    if (-not $source.StartsWith("C:\", [StringComparison]::OrdinalIgnoreCase)) { throw "source outside C" }
    if (-not $dest.StartsWith($destRootFull, [StringComparison]::OrdinalIgnoreCase)) { throw "destination outside DestinationRoot" }
    if (-not $AllowCodex -and $source.StartsWith((Join-Path $env:USERPROFILE ".codex"), [StringComparison]::OrdinalIgnoreCase)) { throw ".codex protected by default" }
    if (-not (Test-Path -LiteralPath $source)) { $status = "skip_missing"; throw "logged" }
    $srcItem = Get-Item -LiteralPath $source -Force
    if (($srcItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $status = "skip_link"; throw "logged" }
    $active = $processes | Where-Object { $_.Path -and $_.Path.StartsWith($source, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 5
    if ($active) {
      $status = "skip_running"
      $note = ($active | ForEach-Object { "$($_.Name):$($_.Id)" }) -join ";"
      throw "logged"
    }
    $bytes = Get-DirBytes $source
    if ($bytes -lt $MinBytes) { $status = "skip_too_small"; throw "logged" }
    if (Test-Path -LiteralPath $dest) { $status = "skip_dest_exists"; throw "logged" }
    if (-not $Execute) { $status = "dry_run"; throw "logged" }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Move-Item -LiteralPath $source -Destination $dest -ErrorAction Stop
    New-Item -ItemType Junction -Path $source -Target $dest -ErrorAction Stop | Out-Null
    $junction = Get-Item -LiteralPath $source -Force
    if (($junction.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw "junction verification failed" }
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
  Write-Host ("{0,-15} {1,7:N3} GB  {2}" -f $status, ($bytes / 1GB), $source)
}

$results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $logPath
Write-Host "LOG=$logPath"
Get-PSDrive C,D,E | Select-Object Name,@{n="UsedGB";e={[math]::Round($_.Used/1GB,2)}},@{n="FreeGB";e={[math]::Round($_.Free/1GB,2)}} | Format-Table -AutoSize
