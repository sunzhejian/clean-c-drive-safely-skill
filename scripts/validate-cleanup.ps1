param(
  [string]$MigrationLog,
  [double]$TargetFreeGB = 0,
  [switch]$CheckDocker,
  [switch]$CheckArduino,
  [switch]$CheckWsl,
  [switch]$CheckNode,
  [switch]$CheckPython
)

$ErrorActionPreference = "Continue"

Write-Host "== Drives =="
$drives = Get-PSDrive C,D,E
$drives | Select-Object Name,@{n="UsedGB";e={[math]::Round($_.Used/1GB,2)}},@{n="FreeGB";e={[math]::Round($_.Free/1GB,2)}} | Format-Table -AutoSize
if ($TargetFreeGB -gt 0) {
  $c = $drives | Where-Object Name -eq "C"
  if (($c.Free / 1GB) -lt $TargetFreeGB) {
    Write-Warning ("C free space below target: {0:N2} GB < {1:N2} GB" -f ($c.Free / 1GB), $TargetFreeGB)
  } else {
    Write-Host ("C free space target met: {0:N2} GB >= {1:N2} GB" -f ($c.Free / 1GB), $TargetFreeGB)
  }
}

if ($MigrationLog) {
  Write-Host "`n== Migration log =="
  $rows = Import-Csv -LiteralPath $MigrationLog
  $migrated = $rows | Where-Object Status -eq "migrated"
  $bad = foreach ($row in $migrated) {
    $srcItem = Get-Item -LiteralPath $row.Source -Force -ErrorAction SilentlyContinue
    $srcLink = $false
    if ($srcItem) { $srcLink = (($srcItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) }
    $dstExists = Test-Path -LiteralPath $row.Destination
    if (-not $srcLink -or -not $dstExists) {
      [pscustomobject]@{ Source = $row.Source; Destination = $row.Destination; SourceLink = $srcLink; DestExists = $dstExists }
    }
  }
  Write-Host "Migrated count: $($migrated.Count)"
  if ($bad) {
    Write-Warning "Some migrations failed validation"
    $bad | Format-Table -AutoSize
  } else {
    Write-Host "All migrated paths have a source junction and destination."
  }
  $rows | Where-Object Status -eq "error" | Select-Object Source,GB,Note | Format-Table -AutoSize
}

Write-Host "`n== Tool checks =="
if ($CheckPython) {
  python --version
  python -m pip --version
}
if ($CheckNode) {
  node --version
  npm --version
  npm config get cache
}
if ($CheckWsl) {
  wsl --list --verbose
}
if ($CheckDocker) {
  docker info --format "Docker Server={{.ServerVersion}} Containers={{.Containers}} Driver={{.Driver}}"
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
}
if ($CheckArduino) {
  arduino-cli version
  arduino-cli core list
}
