#!/usr/bin/env bash
# hacking-vm.sh - run the "Hacking: The Art of Exploitation, 2nd Ed." LiveCD in QEMU.
# Works on Linux and macOS. On Windows use hacking-vm.cmd (wraps hacking-vm.ps1).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_DIR="$ROOT/iso"
ISO="$ISO_DIR/hacking-live-1.0.iso"
SHARED="$ROOT/shared"
MD5_OFFICIAL="bd7a7dfa2e0ce37e3115cdd8f3830783"
ISO_URL="https://resources.oreilly.com/examples/9781593271442/-/raw/master/hacking-live-1.0.iso"
INFO_URL="https://nostarch.com/hackingCD.htm"

MEMORY="${HACKING_VM_MEMORY:-512}"     # MB of RAM for the VM
VGA="${HACKING_VM_VGA:-std}"           # try "cirrus" if the desktop looks wrong
NO_SHARED="${HACKING_VM_NO_SHARED:-0}" # set to 1 to skip the shared folder

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: ./hacking-vm.sh <command> [options]

Commands:
  rip [device]   Copy the LiveCD from your optical drive into iso/
                 (Linux default: /dev/sr0 or /dev/cdrom; macOS: auto-detected)
  download       Download the official ISO (published free by No Starch) instead
  verify         Check the ISO against the official MD5
  run            Boot the LiveCD in a QEMU virtual machine
  help           Show this message

Environment overrides:
  HACKING_VM_MEMORY=512   HACKING_VM_VGA=std   HACKING_VM_NO_SHARED=0
EOF
}

md5_of() {
  if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then md5 -q "$1"
  else die "no md5sum or md5 command found"; fi
}

# Size of an ISO9660 filesystem in bytes, read from the primary volume descriptor
# (sector 16, offset 80 = volume space size in 2048-byte blocks, little-endian).
iso_bytes() {
  local hex
  hex="$(dd if="$1" bs=1 skip=$((16*2048+80)) count=4 2>/dev/null | od -An -tu4 | tr -d ' \n')"
  [[ -n "$hex" && "$hex" -gt 0 ]] && echo $(( hex * 2048 ))
}

cmd_verify() {
  [[ -f "$ISO" ]] || die "No ISO at $ISO - run './hacking-vm.sh rip' or './hacking-vm.sh download' first."
  say "Computing MD5 of $(basename "$ISO") ..."
  local sum; sum="$(md5_of "$ISO")"
  if [[ "$sum" == "$MD5_OFFICIAL" ]]; then
    say "MD5 matches the official image ($sum)."
  else
    warn "MD5 is $sum, official is $MD5_OFFICIAL."
    warn "A copy ripped from a disc can differ slightly and still boot fine; a download should match exactly."
    return 1
  fi
}

copy_device() {  # copy_device <source> <use_sudo 0|1>
  local src="$1" sudo_cmd=()
  [[ "$2" == "1" ]] && sudo_cmd=(sudo)
  local bytes; bytes="$("${sudo_cmd[@]}" bash -c "$(declare -f iso_bytes); iso_bytes '$src'" || true)"
  if [[ -n "$bytes" ]]; then
    say "Disc filesystem is $(( bytes / 1048576 )) MB; copying exactly that much ..."
    "${sudo_cmd[@]}" dd if="$src" of="$ISO.part" bs=2048 count=$(( bytes / 2048 ))
  else
    warn "Couldn't read the ISO9660 header; copying the whole device."
    "${sudo_cmd[@]}" dd if="$src" of="$ISO.part" bs=2048
  fi
  [[ "$2" == "1" ]] && sudo chown "$(id -u):$(id -g)" "$ISO.part"
  return 0
}

cmd_rip() {
  mkdir -p "$ISO_DIR"
  local dev="${1:-}"
  case "$(uname -s)" in
    Linux)
      if [[ -z "$dev" ]]; then
        for d in /dev/sr0 /dev/cdrom /dev/dvd; do [[ -e "$d" ]] && { dev="$d"; break; }; done
      fi
      [[ -n "$dev" && -e "$dev" ]] || die "No optical drive found. Pass the device, e.g. ./hacking-vm.sh rip /dev/sr1"
      say "Copying $dev -> $ISO (about 700 MB, a few minutes) ..."
      if [[ -r "$dev" ]]; then copy_device "$dev" 0; else copy_device "$dev" 1; fi
      ;;
    Darwin)
      if [[ -z "$dev" ]]; then
        dev="$(drutil status 2>/dev/null | awk '/Name:/ {print $NF; exit}')"
      fi
      [[ -n "$dev" ]] || die "No disc found. Find it with 'diskutil list' and pass it, e.g. ./hacking-vm.sh rip /dev/disk4"
      say "Unmounting $dev ..."
      diskutil unmountDisk "$dev" >/dev/null || true
      local raw="/dev/r${dev#/dev/}"
      say "Copying $raw -> $ISO (about 700 MB; may ask for your password) ..."
      copy_device "$raw" 1
      diskutil mountDisk "$dev" >/dev/null 2>&1 || true
      ;;
    *) die "Unsupported OS for this script. On Windows run: hacking-vm.cmd rip" ;;
  esac
  mv "$ISO.part" "$ISO"
  say "Saved $ISO"
  cmd_verify || true
}

cmd_download() {
  mkdir -p "$ISO_DIR"
  command -v curl >/dev/null 2>&1 || die "curl is required"
  say "Downloading the official ISO (~700 MB) ..."
  curl -fL --retry 3 -C - -o "$ISO.part" "$ISO_URL" \
    || die "Download failed. Get the ISO manually from $INFO_URL and save it as $ISO"
  mv "$ISO.part" "$ISO"
  cmd_verify || die "Downloaded file doesn't match the official MD5. Delete it and fetch manually from $INFO_URL"
}

find_qemu() {
  for q in qemu-system-i386 qemu-system-x86_64; do
    command -v "$q" >/dev/null 2>&1 && { echo "$q"; return; }
  done
  case "$(uname -s)" in
    Darwin) die "QEMU not found. Install it with: brew install qemu" ;;
    *)      die "QEMU not found. Install it, e.g.: sudo apt install qemu-system-x86   (Fedora: sudo dnf install qemu-system-x86)" ;;
  esac
}

cmd_run() {
  [[ -f "$ISO" ]] || die "No ISO at $ISO - run './hacking-vm.sh rip' (from your disc) or './hacking-vm.sh download' first."
  local qemu; qemu="$(find_qemu)"

  local accel=()
  case "$(uname -s)" in
    Linux)  [[ -w /dev/kvm ]] && accel+=(-accel kvm) ;;
    Darwin) [[ "$(uname -m)" == "x86_64" ]] && accel+=(-accel hvf) ;;
  esac
  accel+=(-accel tcg)   # software emulation fallback (works everywhere, incl. Apple Silicon)

  # shellcheck disable=SC2054  # commas are part of QEMU option values
  local args=(
    -name "Hacking-LiveCD"
    -m "$MEMORY"
    -cdrom "$ISO"
    -boot d
    -vga "$VGA"
    -nic user,model=rtl8139
    -rtc base=localtime
  )

  if [[ "$NO_SHARED" != "1" ]]; then
    mkdir -p "$SHARED"
    # Exposes ./shared as a small FAT disk so your work survives reboots of the LiveCD.
    args+=(-drive "file=fat:rw:$SHARED,format=raw,if=ide,index=1")
  fi

  say "Booting the LiveCD with $qemu (${MEMORY} MB RAM). Click in the window to use it; Ctrl+Alt+G releases the mouse."
  [[ "$NO_SHARED" != "1" ]] && say "Shared folder: see 'Saving your work' in README.md"
  exec "$qemu" "${accel[@]}" "${args[@]}"
}

case "${1:-help}" in
  rip)      shift; cmd_rip "${1:-}" ;;
  download) cmd_download ;;
  verify)   cmd_verify ;;
  run)      cmd_run ;;
  help|-h|--help) usage ;;
  *) usage; exit 1 ;;
esac
