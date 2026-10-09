# hacking-vm.ps1 - run the "Hacking: The Art of Exploitation, 2nd Ed." LiveCD in QEMU on Windows.
# Usually started through hacking-vm.cmd, e.g.:  hacking-vm.cmd rip   /   hacking-vm.cmd run
param(
    [Parameter(Position = 0)] [string] $Command = "help",
    [Parameter(Position = 1)] [string] $Drive = ""
)
$ErrorActionPreference = "Stop"

$Root        = $PSScriptRoot
$IsoDir      = Join-Path $Root "iso"
$Iso         = Join-Path $IsoDir "hacking-live-1.0.iso"
$Shared      = Join-Path $Root "shared"
$Md5Official = "bd7a7dfa2e0ce37e3115cdd8f3830783"
$IsoUrl      = "https://resources.oreilly.com/examples/9781593271442/-/raw/master/hacking-live-1.0.iso"
$InfoUrl     = "https://nostarch.com/hackingCD.htm"

$Memory    = if ($env:HACKING_VM_MEMORY) { $env:HACKING_VM_MEMORY } else { "512" }
$Vga       = if ($env:HACKING_VM_VGA)    { $env:HACKING_VM_VGA }    else { "std" }
$NoShared  = $env:HACKING_VM_NO_SHARED -eq "1"

function Say($m)  { Write-Host "==> $m" -ForegroundColor Green }
function Warn($m) { Write-Host "warning: $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "error: $m" -ForegroundColor Red; exit 1 }

function Show-Usage {
@"
Usage: hacking-vm.cmd <command> [drive]

Commands:
  rip [D:]   Copy the LiveCD from your optical drive into iso\
  download   Download the official ISO (published free by No Starch) instead
  verify     Check the ISO against the official MD5
  run        Boot the LiveCD in a QEMU virtual machine
  help       Show this message

Environment overrides: HACKING_VM_MEMORY=512  HACKING_VM_VGA=std  HACKING_VM_NO_SHARED=0
"@ | Write-Host
}

function Invoke-Verify {
    if (-not (Test-Path $Iso)) { Die "No ISO at $Iso - run 'hacking-vm.cmd rip' or 'hacking-vm.cmd download' first." }
    Say "Computing MD5 of hacking-live-1.0.iso ..."
    $sum = (Get-FileHash -Algorithm MD5 $Iso).Hash.ToLower()
    if ($sum -eq $Md5Official) { Say "MD5 matches the official image ($sum)."; return $true }
    Warn "MD5 is $sum, official is $Md5Official."
    Warn "A copy ripped from a disc can differ slightly and still boot fine; a download should match exactly."
    return $false
}

Add-Type -ErrorAction SilentlyContinue -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class RawDisk {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern SafeFileHandle CreateFile(string name, uint access, uint share,
        IntPtr sec, uint disposition, uint flags, IntPtr template);
}
"@

function Invoke-Rip {
    New-Item -ItemType Directory -Force -Path $IsoDir | Out-Null
    if (-not $Drive) {
        $cd = Get-CimInstance Win32_CDROMDrive | Where-Object { $_.MediaLoaded } | Select-Object -First 1
        if (-not $cd) { Die "No disc found in any CD/DVD drive. Insert the LiveCD or pass the letter, e.g. hacking-vm.cmd rip E:" }
        $Drive = $cd.Drive
    }
    $Drive = $Drive.TrimEnd('\').TrimEnd(':') + ":"
    $devicePath = "\\.\$Drive"
    Say "Reading disc in $Drive ..."

    # GENERIC_READ, share read|write, OPEN_EXISTING
    $handle = [RawDisk]::CreateFile($devicePath, 0x80000000, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($handle.IsInvalid) { Die "Couldn't open $devicePath (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())). Try running the command prompt as Administrator." }
    $in = New-Object System.IO.FileStream($handle, [System.IO.FileAccess]::Read, 65536)
    try {
        # ISO9660 primary volume descriptor: sector 16, offset 80 = size in 2048-byte blocks.
        $sector = New-Object byte[] 2048
        $in.Position = 16 * 2048
        [void]$in.Read($sector, 0, 2048)
        $blocks = [BitConverter]::ToUInt32($sector, 80)
        if ($blocks -le 0) { Die "This doesn't look like an ISO9660 disc." }
        $total = [int64]$blocks * 2048
        Say ("Disc filesystem is {0} MB; copying to {1} ..." -f [math]::Round($total / 1MB), $Iso)

        $in.Position = 0
        $part = "$Iso.part"
        $out = [System.IO.File]::Create($part)
        try {
            $buf = New-Object byte[] (2048 * 512)   # 1 MB, a multiple of the sector size
            $done = [int64]0
            while ($done -lt $total) {
                $want = [int][math]::Min($buf.Length, $total - $done)
                $n = $in.Read($buf, 0, $want)
                if ($n -le 0) { Die "Read error at byte $done - the disc may be scratched." }
                $out.Write($buf, 0, $n)
                $done += $n
                Write-Progress -Activity "Copying LiveCD" -PercentComplete ([int](100 * $done / $total))
            }
        } finally { $out.Close() }
    } finally { $in.Close() }
    Write-Progress -Activity "Copying LiveCD" -Completed
    Move-Item -Force "$Iso.part" $Iso
    Say "Saved $Iso"
    [void](Invoke-Verify)
}

function Invoke-Download {
    New-Item -ItemType Directory -Force -Path $IsoDir | Out-Null
    Say "Downloading the official ISO (~700 MB) ..."
    try {
        $ProgressPreference = "SilentlyContinue"   # makes Invoke-WebRequest much faster
        Invoke-WebRequest -Uri $IsoUrl -OutFile "$Iso.part" -UseBasicParsing
    } catch { Die "Download failed. Get the ISO manually from $InfoUrl and save it as $Iso" }
    Move-Item -Force "$Iso.part" $Iso
    if (-not (Invoke-Verify)) { Die "Downloaded file doesn't match the official MD5. Delete it and fetch manually from $InfoUrl" }
}

function Find-Qemu {
    foreach ($name in "qemu-system-i386.exe", "qemu-system-x86_64.exe") {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
        foreach ($dir in "$env:ProgramFiles\qemu", "${env:ProgramFiles(x86)}\qemu") {
            $p = Join-Path $dir $name
            if (Test-Path $p) { return $p }
        }
    }
    Die "QEMU not found. Install it with:  winget install SoftwareFreedomConservancy.QEMU   (or from https://www.qemu.org/download/#windows), then open a new terminal."
}

function Invoke-Run {
    if (-not (Test-Path $Iso)) { Die "No ISO at $Iso - run 'hacking-vm.cmd rip' (from your disc) or 'hacking-vm.cmd download' first." }
    $qemu = Find-Qemu
    $qargs = @(
        "-name", "Hacking-LiveCD",
        "-accel", "tcg",
        "-m", $Memory,
        "-cdrom", "`"$Iso`"",
        "-boot", "d",
        "-vga", $Vga,
        "-nic", "user,model=rtl8139",
        "-rtc", "base=localtime"
    )
    if (-not $NoShared) {
        New-Item -ItemType Directory -Force -Path $Shared | Out-Null
        $qargs += @("-drive", "`"file=fat:rw:$Shared,format=raw,if=ide,index=1`"")
    }
    Say "Booting the LiveCD with QEMU ($Memory MB RAM). Click in the window to use it; Ctrl+Alt+G releases the mouse."
    if (-not $NoShared) { Say "Shared folder: see 'Saving your work' in README.md" }
    Start-Process -FilePath $qemu -ArgumentList $qargs -Wait -NoNewWindow
}

switch ($Command.ToLower()) {
    "rip"      { Invoke-Rip }
    "download" { Invoke-Download }
    "verify"   { if (-not (Invoke-Verify)) { exit 1 } }
    "run"      { Invoke-Run }
    default    { Show-Usage }
}
