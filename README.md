# Hacking LiveCD VM

A small, portable launcher that runs the LiveCD from Jon Erickson's
*Hacking: The Art of Exploitation, 2nd Edition* (No Starch Press) inside a
[QEMU](https://www.qemu.org) virtual machine — on Linux, macOS (Intel or Apple
Silicon) or Windows — without rebooting your computer or burning a disc.

Clone this repo on any machine, put the ISO in place once (from your disc or
the official download), and run one command.

> The ISO itself is **not** stored in this repo: it's ~700 MB (GitHub rejects
> files over 100 MB) and it's No Starch's to distribute. The scripts copy it
> from your physical disc or fetch it from the official link No Starch
> publishes at <https://nostarch.com/hackingCD.htm>.

## Quick start

### 1. Install QEMU

| OS | Command |
|---|---|
| Windows | `winget install SoftwareFreedomConservancy.QEMU` (then open a new terminal) |
| macOS | `brew install qemu` |
| Debian/Ubuntu | `sudo apt install qemu-system-x86` |
| Fedora | `sudo dnf install qemu-system-x86` |

### 2. Get the ISO (once per machine)

With the disc in the drive:

```bash
./hacking-vm.sh rip          # Linux / macOS
hacking-vm.cmd rip           # Windows (or: hacking-vm.cmd rip E:)
```

No disc on this machine? Download the official copy instead:

```bash
./hacking-vm.sh download     # Linux / macOS
hacking-vm.cmd download      # Windows
```

Either way it lands in `iso/hacking-live-1.0.iso`. `verify` checks it against
the official MD5 (`bd7a7dfa2e0ce37e3115cdd8f3830783`).

### 3. Boot it

```bash
./hacking-vm.sh run          # Linux / macOS
hacking-vm.cmd run           # Windows — or just double-click hacking-vm.cmd
```

The LiveCD boots straight to the Ubuntu desktop with the book's tools and
source code (in `~/booksrc`). Click inside the window to use it; press
**Ctrl+Alt+G** to get your mouse back.

## Saving your work

A LiveCD forgets everything when it shuts down. To keep your code, the
launcher attaches this repo's `shared/` folder to the VM as a small FAT disk.
Inside the VM, open a terminal and run:

```bash
sudo mkdir -p /mnt/shared
sudo mount -t vfat /dev/hdb1 /mnt/shared  || sudo mount -t vfat /dev/sdb1 /mnt/shared
cp -r ~/booksrc/myexploit.c /mnt/shared/
sync && sudo umount /mnt/shared          # always unmount before shutting down
```

Files appear in `shared/` on your real computer. Keep the shared folder small
(well under 500 MB); it's for source files and notes, not large data. It's
ignored by git so your work stays local — remove `shared/*` from
`.gitignore` if you'd rather commit it and carry it between machines.

Set `HACKING_VM_NO_SHARED=1` to boot without it.

## Options

| Variable | Default | Meaning |
|---|---|---|
| `HACKING_VM_MEMORY` | `512` | RAM in MB (the 2008-era LiveCD is happy with 256–1024) |
| `HACKING_VM_VGA` | `std` | Display adapter; try `cirrus` if the desktop looks wrong |
| `HACKING_VM_NO_SHARED` | `0` | `1` disables the shared folder |

Examples: `HACKING_VM_MEMORY=1024 ./hacking-vm.sh run`, or on Windows
`set HACKING_VM_VGA=cirrus` then `hacking-vm.cmd run`.

## Putting it on GitHub

```bash
cd hacking-livecd-vm
git remote add origin https://github.com/<you>/hacking-livecd-vm.git
git push -u origin main
```

On another device: `git clone`, then steps 1–3 above.

## Troubleshooting

- **Black screen or garbled desktop** — set `HACKING_VM_VGA=cirrus`.
- **Very slow on Linux** — make sure you're in the `kvm` group
  (`sudo usermod -aG kvm $USER`, then log out and back in) so hardware
  acceleration is used.
- **Apple Silicon Macs** run the 32-bit x86 guest in software emulation. It
  works, just more slowly; the terminal-heavy exercises in the book are fine.
- **Windows rip fails to open the drive** — run the command prompt as
  Administrator, or pass the drive letter explicitly (`hacking-vm.cmd rip E:`).
- **No network inside the VM** — QEMU's user-mode networking gives the guest
  outbound internet; `ping` doesn't work through it, but `wget` does.
- **Ripped ISO's MD5 doesn't match** — copies from a physical disc can differ
  slightly and still boot. If it won't boot, use `download` instead.

## Files

| File | Purpose |
|---|---|
| `hacking-vm.sh` | Linux/macOS launcher (`rip`, `download`, `verify`, `run`) |
| `hacking-vm.ps1` | Windows launcher, same commands |
| `hacking-vm.cmd` | Windows wrapper so the PowerShell script runs without policy changes |
| `iso/` | Where the ISO goes (git-ignored) |
| `shared/` | Folder shared into the VM (git-ignored) |

## Credits

The LiveCD and book are by Jon Erickson, published by No Starch Press. The
CD's software is open source (Ubuntu plus tools). This repo only contains
launcher scripts.
