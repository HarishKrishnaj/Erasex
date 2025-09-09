param(
  [Parameter(Mandatory=$true)][string]$IsoPath,
  [Parameter(Mandatory=$true)][int]$DiskNumber,
  [switch]$Force
)

function Confirm-Action($Message) {
  if ($Force) { return $true }
  $resp = Read-Host "$Message Type 'YES' to continue"
  return $resp -eq 'YES'
}

if (-not (Test-Path $IsoPath)) {
  Write-Error "ISO not found: $IsoPath"
  exit 1
}

$disk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
if (-not $disk) { Write-Error "Disk $DiskNumber not found"; exit 1 }
if (-not $disk.IsRemovable -and $disk.BusType -ne 'USB') {
  Write-Warning "Disk $DiskNumber does not appear to be removable/USB."
}

Write-Host "Selected Disk $DiskNumber : $($disk.FriendlyName) Size=$([math]::Round($disk.Size/1GB,2))GB"
if (-not (Confirm-Action "ALL DATA on Disk $DiskNumber will be ERASED.")) { exit 2 }

try {
  Write-Host "Preparing disk $DiskNumber..."
  Set-Disk -Number $DiskNumber -IsOffline $true -ErrorAction SilentlyContinue | Out-Null
} catch {}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) { Write-Error "wsl.exe not found. Please install WSL to use raw dd."; exit 3 }

$phys = "\\.\PhysicalDrive$DiskNumber"
$isoFull = (Resolve-Path $IsoPath).Path

Write-Host "Writing ISO to $phys using WSL dd... this may take several minutes"

$ddCmd = @(
  "bash","-lc",
  ("set -euo pipefail; " +
   "in=\"$(wslpath -a `"$isoFull`")\"; " +
   "out=\"/mnt/wsl/PHYS$DiskNumber\"; " +
   "sudo mkdir -p /mnt/wsl; " +
   "sudo umount \"$out\" >/dev/null 2>&1 || true; " +
   "sudo mount -t drvfs '$phys' \"$out\" -o metadata || true; " +
   "sudo dd if=\"$in\" of=\"$out\" bs=4M status=progress conv=fsync; " +
   "sync; sudo umount \"$out\" || true")
)

$proc = Start-Process -FilePath $wsl.Source -ArgumentList $ddCmd -NoNewWindow -PassThru -Wait
if ($proc.ExitCode -ne 0) {
  Write-Error "WSL dd failed with exit code $($proc.ExitCode)"
  exit $proc.ExitCode
}

try {
  Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction SilentlyContinue | Out-Null
} catch {}

Write-Host "ISO written successfully to Disk $DiskNumber."
