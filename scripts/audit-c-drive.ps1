param(
  [string]$SystemDrive = "C",
  [string[]]$DataDrives = @(),
  [string[]]$Roots = @(),
  [int]$Top = 60,
  [string]$UserProfile = $env:USERPROFILE,
  [string]$OutputDir = "",
  [string]$ProcessPattern = "docker|podman|wsl|vmware|virtualbox|arduino|code|cursor|jetbrains|python|node|java|rust|cargo|npm|pnpm|yarn|chrome|msedge|firefox|postgres|mysql|redis|mongo|codex"
)

$ErrorActionPreference = "SilentlyContinue"
$systemDriveName = $SystemDrive.TrimEnd(":")
$systemRoot = "$systemDriveName`:\"

function Test-ReparsePoint {
  param([System.IO.FileSystemInfo]$Item)
  return (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-Bytes {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  $item = Get-Item -LiteralPath $Path -Force
  if (Test-ReparsePoint $item) { return 0 }
  if ($item.PSIsContainer) {
    return [int64]((Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
  }
  return [int64]$item.Length
}

if (-not $Roots -or $Roots.Count -eq 0) {
  $Roots = @(
    "$systemDriveName`:\Users",
    "$systemDriveName`:\ProgramData",
    "$systemDriveName`:\Program Files",
    "$systemDriveName`:\Program Files (x86)",
    "$systemDriveName`:\Windows"
  )
}

Write-Host "== Fixed drives =="
$driveRows = Get-PSDrive -PSProvider FileSystem | Where-Object {
  $_.Used -ne $null -and $_.Free -ne $null
} | Select-Object Name,@{n="UsedGB";e={[math]::Round($_.Used/1GB,2)}},@{n="FreeGB";e={[math]::Round($_.Free/1GB,2)}},Root
$driveRows | Format-Table -AutoSize

Write-Host "`n== Top children under audited roots =="
$rows = New-Object System.Collections.Generic.List[object]
foreach ($root in $Roots) {
  if (-not (Test-Path -LiteralPath $root)) { continue }
  foreach ($child in Get-ChildItem -LiteralPath $root -Force) {
    $link = Test-ReparsePoint $child
    $bytes = if ($link) { 0 } else { Get-Bytes $child.FullName }
    $rows.Add([pscustomobject]@{
      Root = $root
      Path = $child.FullName
      GB = [math]::Round($bytes / 1GB, 2)
      Link = $link
    }) | Out-Null
  }
}
$topRows = $rows | Sort-Object GB -Descending | Select-Object -First $Top
$topRows | Format-Table -AutoSize

Write-Host "`n== Known disposable or special candidates =="
$knownTargets = @(
  "$systemDriveName`:\hiberfil.sys",
  "$systemDriveName`:\pagefile.sys",
  "$systemDriveName`:\swapfile.sys",
  "$systemDriveName`:\Windows\SoftwareDistribution\Download",
  "$systemDriveName`:\Windows\Temp",
  (Join-Path $UserProfile "AppData\Local\Temp"),
  (Join-Path $UserProfile "AppData\Local\Microsoft\Windows\INetCache"),
  (Join-Path $UserProfile "AppData\Local\CrashDumps"),
  (Join-Path $UserProfile ".codex"),
  (Join-Path $UserProfile ".ssh")
)
$candidateRows = foreach ($path in $knownTargets) {
  if (Test-Path -LiteralPath $path) {
    $item = Get-Item -LiteralPath $path -Force
    $link = Test-ReparsePoint $item
    $bytes = if ($link) { 0 } else { Get-Bytes $path }
    [pscustomobject]@{ Path = $path; GB = [math]::Round($bytes / 1GB, 3); Link = $link; Attributes = $item.Attributes }
  }
}
$candidateRows | Sort-Object GB -Descending | Format-Table -AutoSize

Write-Host "`n== Running processes matching app/tool pattern =="
$processRows = Get-Process | Where-Object {
  $_.ProcessName -match $ProcessPattern
} | Select-Object ProcessName,Id,@{n="Path";e={$_.Path}} | Sort-Object ProcessName
$processRows | Format-Table -AutoSize

if ($OutputDir) {
  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $topCsv = Join-Path $OutputDir "drive-audit-top_$stamp.csv"
  $candidateCsv = Join-Path $OutputDir "drive-audit-candidates_$stamp.csv"
  $processCsv = Join-Path $OutputDir "drive-audit-processes_$stamp.csv"
  $topRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $topCsv
  $candidateRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $candidateCsv
  $processRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $processCsv
  Write-Host "AUDIT_TOP=$topCsv"
  Write-Host "AUDIT_CANDIDATES=$candidateCsv"
  Write-Host "AUDIT_PROCESSES=$processCsv"
}
