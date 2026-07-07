param(
  [string]$Drive = "C",
  [int]$Top = 60,
  [string]$UserProfile = $env:USERPROFILE
)

$ErrorActionPreference = "SilentlyContinue"
$driveName = $Drive.TrimEnd(":")

function Get-Bytes {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  $item = Get-Item -LiteralPath $Path -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return 0 }
  if ($item.PSIsContainer) {
    return [int64]((Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
  }
  return [int64]$item.Length
}

Write-Host "== Drives =="
Get-PSDrive C,D,E | Select-Object Name,@{n="UsedGB";e={[math]::Round($_.Used/1GB,2)}},@{n="FreeGB";e={[math]::Round($_.Free/1GB,2)}} | Format-Table -AutoSize

Write-Host "`n== Top root children =="
$roots = @("$driveName`:\Users", "$driveName`:\ProgramData", "$driveName`:\Program Files", "$driveName`:\Program Files (x86)", "$driveName`:\Windows")
$rows = New-Object System.Collections.Generic.List[object]
foreach ($root in $roots) {
  if (-not (Test-Path -LiteralPath $root)) { continue }
  foreach ($child in Get-ChildItem -LiteralPath $root -Force) {
    $link = (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    $bytes = if ($link) { 0 } else { Get-Bytes $child.FullName }
    $rows.Add([pscustomobject]@{
      Root = $root
      Path = $child.FullName
      GB = [math]::Round($bytes / 1GB, 2)
      Link = $link
    }) | Out-Null
  }
}
$rows | Sort-Object GB -Descending | Select-Object -First $Top | Format-Table -AutoSize

Write-Host "`n== Known cleanup candidates =="
$targets = @(
  "$driveName`:\hiberfil.sys",
  "$driveName`:\pagefile.sys",
  "$driveName`:\swapfile.sys",
  "$driveName`:\Windows\SoftwareDistribution\Download",
  "$driveName`:\Windows\Temp",
  (Join-Path $UserProfile "AppData\Local\Temp"),
  (Join-Path $UserProfile "AppData\Local\Microsoft\Windows\INetCache"),
  (Join-Path $UserProfile "AppData\Local\CrashDumps"),
  (Join-Path $UserProfile ".codex")
)
$targetRows = foreach ($path in $targets) {
  if (Test-Path -LiteralPath $path) {
    $item = Get-Item -LiteralPath $path -Force
    $link = (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    $bytes = if ($link) { 0 } else { Get-Bytes $path }
    [pscustomobject]@{ Path = $path; GB = [math]::Round($bytes / 1GB, 3); Link = $link; Attributes = $item.Attributes }
  }
}
$targetRows | Sort-Object GB -Descending | Format-Table -AutoSize

Write-Host "`n== Running processes with common cache/app names =="
Get-Process | Where-Object {
  $_.ProcessName -match "docker|arduino|code|codex|antigravity|gemini|hermes|chrome|msedge|qq|tencent|python|node"
} | Select-Object ProcessName,Id,@{n="Path";e={$_.Path}} | Sort-Object ProcessName | Format-Table -AutoSize
