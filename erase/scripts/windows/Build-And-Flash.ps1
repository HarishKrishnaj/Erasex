param(
  [Parameter(Mandatory=$false)][int]$DiskNumber,
  [Parameter(Mandatory=$true)][string]$BusyboxPath,
  [Parameter(Mandatory=$false)][string]$KernelPath = "/boot/vmlinuz",
  [Parameter(Mandatory=$false)][int]$DelaySeconds = 10,
  [switch]$Force
)

function Confirm-Action($Message) {
  if ($Force) { return $true }
  $resp = Read-Host "$Message Type 'YES' to continue"
  return $resp -eq 'YES'
}

function Select-UsbDiskInteractive() {
  $disks = Get-Disk | Where-Object { $_.BusType -in @('USB') -or $_.IsRemovable -eq $true }
  if (-not $disks) { throw "No removable/USB disks found." }

  $grid = Get-Command Out-GridView -ErrorAction SilentlyContinue
  if ($grid) {
    $sel = $disks |
      Select-Object Number, FriendlyName, BusType, IsRemovable,
        @{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}}, OperationalStatus |
      Out-GridView -Title 'Select target USB disk' -PassThru
    if ($sel) { return $sel.Number }
    throw "Selection cancelled."
  } else {
    Write-Host "Removable/USB disks:" -ForegroundColor Cyan
    $disks | ForEach-Object {
      Write-Host ("  Disk {0}: {1} {2}GB ({3})" -f $_.Number, $_.FriendlyName, ([math]::Round($_.Size/1GB,2)), $_.BusType)
    }
    $n = Read-Host "Enter Disk Number"
    if ($n -match '^[0-9]+$') { return [int]$n }
    throw "Invalid disk number."
  }
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) { Write-Error "wsl.exe not found. Please install WSL."; exit 1 }

if (-not (Test-Path $BusyboxPath)) { Write-Error "BusyBox not found: $BusyboxPath"; exit 1 }

if (-not $PSBoundParameters.ContainsKey('DiskNumber')) {
  try { $DiskNumber = Select-UsbDiskInteractive } catch { Write-Error $_; exit 1 }
}

$disk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
if (-not $disk) { Write-Error "Disk $DiskNumber not found"; exit 1 }
Write-Host "Selected Disk $DiskNumber : $($disk.FriendlyName) Size=$([math]::Round($disk.Size/1GB,2))GB"
if (-not (Confirm-Action "This will build an ISO and ERASE ALL DATA on Disk $DiskNumber.")) { exit 2 }

$repoRoot = (Resolve-Path ".").Path
$repoRootWsl = & $wsl.Source -e wslpath -a "$repoRoot"
$busyboxWsl = & $wsl.Source -e wslpath -a "$BusyboxPath"

$wslCmd = @(
  "bash","-lc",
  (
"set -euo pipefail; cd '$repoRootWsl'; \
mkdir -p build out; cd build; cmake .. >/dev/null; make -j securewipe_boot; cd ..; \
./scripts/build_initramfs.sh out/initramfs.cpio.gz build/securewipe_boot '$busyboxWsl'; \
./scripts/make_boot_iso.sh out/securewipe.iso '$KernelPath' out/initramfs.cpio.gz; \
ls -lh out/securewipe.iso"
  )
)

$proc = Start-Process -FilePath $wsl.Source -ArgumentList $wslCmd -NoNewWindow -PassThru -Wait
if ($proc.ExitCode -ne 0) { Write-Error "WSL build failed with exit code $($proc.ExitCode)"; exit $proc.ExitCode }

$isoPathWin = Join-Path $repoRoot "out\securewipe.iso"
if (-not (Test-Path $isoPathWin)) { Write-Error "ISO not found: $isoPathWin"; exit 1 }

Write-Host "Flashing ISO to Disk $DiskNumber..."
powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\windows\Write-IsoToUsb.ps1') -IsoPath $isoPathWin -DiskNumber $DiskNumber -Force:$Force

Write-Host "Done. You can now boot from the USB. At GRUB, you can press 'e' to edit and add sw_delay=$DelaySeconds or sw_device=/dev/sdX as needed."
