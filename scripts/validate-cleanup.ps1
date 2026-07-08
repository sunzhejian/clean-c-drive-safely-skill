param(
  [string]$MigrationLog = "",
  [string]$SystemDrive = "C",
  [double]$TargetFreeGB = 0,
  [string[]]$Checks = @(),
  [switch]$RefreshUserPath
)

$ErrorActionPreference = "Continue"

if ($RefreshUserPath) {
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
}

Write-Host "== Fixed drives =="
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null -and $_.Free -ne $null }
$drives | Select-Object Name,@{n="UsedGB";e={[math]::Round($_.Used/1GB,2)}},@{n="FreeGB";e={[math]::Round($_.Free/1GB,2)}} | Format-Table -AutoSize
if ($TargetFreeGB -gt 0) {
  $system = $drives | Where-Object Name -eq $SystemDrive.TrimEnd(":")
  if ($system -and (($system.Free / 1GB) -ge $TargetFreeGB)) {
    Write-Host ("Target met: {0} has {1:N2} GB free >= {2:N2} GB" -f $SystemDrive, ($system.Free / 1GB), $TargetFreeGB)
  } else {
    Write-Warning ("Target not met: {0} free space is below {1:N2} GB" -f $SystemDrive, $TargetFreeGB)
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

function Invoke-Check {
  param([string]$Name)
  Write-Host "`n== Check: $Name =="
  switch ($Name.ToLowerInvariant()) {
    "python" {
      python --version
      python -m pip --version
      Get-Command python -All | Select-Object Source,Version | Format-Table -AutoSize
    }
    "node" {
      node --version
      npm --version
      npm config get cache
    }
    "wsl" {
      wsl --list --verbose
    }
    "docker" {
      docker info --format "Docker Server={{.ServerVersion}} Containers={{.Containers}} Driver={{.Driver}}"
      docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    }
    "arduino" {
      arduino-cli version
      arduino-cli core list
    }
    "git" {
      git --version
      git config --global --get user.name
    }
    "rust" {
      cargo --version
      rustup show active-toolchain
    }
    default {
      Write-Warning "Unknown named check '$Name'. Add a project-specific validation command manually."
    }
  }
}

$normalizedChecks = foreach ($check in $Checks) {
  foreach ($part in ($check -split ",")) {
    $trimmed = $part.Trim()
    if ($trimmed) { $trimmed }
  }
}

foreach ($check in $normalizedChecks) {
  Invoke-Check $check
}
