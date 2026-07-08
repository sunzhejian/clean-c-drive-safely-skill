param(
  [Parameter(Mandatory=$true)]
  [string[]]$Roots,
  [string[]]$NamePatterns = @(),
  [string[]]$Extensions = @(),
  [int]$OlderThanDays = 0,
  [string]$LogDir = "",
  [string[]]$ProtectedPaths = @(),
  [switch]$Execute,
  [switch]$AllowProtected
)

$ErrorActionPreference = "Stop"
if (-not $LogDir) {
  $fallbackDrive = (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -gt 1GB -and $_.Name -ne "C" } | Sort-Object Free -Descending | Select-Object -First 1).Name
  if ($fallbackDrive) { $LogDir = "$fallbackDrive`:\CleanupLogs" } else { $LogDir = Join-Path $env:TEMP "CleanupLogs" }
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogDir "approved-delete_$timestamp.csv"
$cutoff = if ($OlderThanDays -gt 0) { (Get-Date).AddDays(-1 * $OlderThanDays) } else { $null }

function Test-ReparsePoint {
  param([System.IO.FileSystemInfo]$Item)
  return (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-ProtectedPath {
  param([string]$Path)
  $defaults = @(
    (Join-Path $env:USERPROFILE ".codex"),
    (Join-Path $env:USERPROFILE ".ssh"),
    (Join-Path $env:USERPROFILE "Documents"),
    (Join-Path $env:USERPROFILE "Desktop")
  )
  foreach ($protected in ($defaults + $ProtectedPaths)) {
    if (-not $protected) { continue }
    $full = [IO.Path]::GetFullPath($protected).TrimEnd("\")
    if ($Path.Equals($full, [StringComparison]::OrdinalIgnoreCase) -or
        $Path.StartsWith($full + "\", [StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  return $false
}

function Test-NameMatch {
  param([System.IO.FileInfo]$File)
  $nameOk = ($NamePatterns.Count -eq 0)
  foreach ($pattern in $NamePatterns) {
    if ($File.Name -like $pattern) { $nameOk = $true; break }
  }
  $extOk = ($Extensions.Count -eq 0)
  foreach ($ext in $Extensions) {
    $normalized = if ($ext.StartsWith(".")) { $ext.ToLowerInvariant() } else { ".$($ext.ToLowerInvariant())" }
    if ($File.Extension.ToLowerInvariant() -eq $normalized) { $extOk = $true; break }
  }
  $ageOk = ($cutoff -eq $null -or $File.LastWriteTime -lt $cutoff)
  return ($nameOk -and $extOk -and $ageOk)
}

$candidates = New-Object System.Collections.Generic.List[object]
foreach ($rootRaw in $Roots) {
  $root = [IO.Path]::GetFullPath($rootRaw)
  if (-not (Test-Path -LiteralPath $root)) { continue }
  $rootItem = Get-Item -LiteralPath $root -Force
  if (Test-ReparsePoint $rootItem) { continue }
  if (-not $AllowProtected -and (Test-ProtectedPath $root)) { continue }
  Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
    if (Test-NameMatch $_) {
      if (-not $AllowProtected -and (Test-ProtectedPath $_.FullName)) { return }
      $candidates.Add([pscustomobject]@{
        Path = $_.FullName
        MB = [math]::Round($_.Length / 1MB, 3)
        Bytes = $_.Length
        LastWriteTime = $_.LastWriteTime
        Status = if ($Execute) { "pending" } else { "dry_run" }
        Note = ""
      }) | Out-Null
    }
  }
}

$freed = [int64]0
$deleted = 0
$failed = 0
if ($Execute) {
  foreach ($candidate in $candidates) {
    try {
      Remove-Item -LiteralPath $candidate.Path -Force -ErrorAction Stop
      $candidate.Status = "deleted"
      $freed += [int64]$candidate.Bytes
      $deleted++
    } catch {
      $candidate.Status = "error"
      $candidate.Note = $_.Exception.Message
      $failed++
    }
  }
}

$candidates | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $logPath
Write-Host "LOG=$logPath"
Write-Host ("CANDIDATES={0} DELETED={1} FAILED={2} FREED_MB={3:N2}" -f $candidates.Count, $deleted, $failed, ($freed / 1MB))
$candidates | Sort-Object Bytes -Descending | Select-Object -First 40 Path,MB,LastWriteTime,Status,Note | Format-Table -AutoSize
