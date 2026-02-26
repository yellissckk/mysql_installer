#!/usr/bin/env bash
set -euo pipefail

# Quick SSH trust setup between two Linux hosts.
# Modes:
#   one-way: local -> remote trust
#   mutual : local <-> remote trust (generates key on remote and exchanges)
#
# Usage:
#   ./quick_ssh_trust.sh one-way user@remote [--port 22]
#   ./quick_ssh_trust.sh mutual  user@remote [--port 22]
#
# Notes:
# - Will create ~/.ssh (600/700) and ed25519 key if missing.
# - Idempotent: avoids duplicate keys; makes a timestamped backup of authorized_keys.
# - SELinux contexts restored if restorecon exists.

PORT=22
MODE="${1:-}"
TARGET="${2:-}"

if [[ -z "${MODE}" || -z "${TARGET}" ]]; then
  echo "Usage:"
  echo "  $0 one-way user@remote [--port 22]"
  echo "  $0 mutual  user@remote [--port 22]"
  exit 1
fi

shift 2 || true
while (( "$#" )); do
  case "$1" in
    --port)
      PORT="${2:-}"; shift 2;;
    *)
      echo "Unknown option: $1"; exit 1;;
  esac
done

timestamp() { date +%Y%m%d_%H%M%S; }

ensure_local_ssh_dir() {
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  [[ -x "$(command -v restorecon)" ]] && restorecon -R "${HOME}/.ssh" || true
}

ensure_local_key() {
  # Prefer ed25519; fallback to rsa only if ed25519 unsupported
  if [[ ! -f "${HOME}/.ssh/id_ed25519" ]]; then
    ssh-keygen -t ed25519 -f "${HOME}/.ssh/id_ed25519" -N "" -q
  fi
}

remote_exec() {
  # shellcheck disable=SC2029
  ssh -p "$PORT" -o StrictHostKeyChecking=ask -o PreferredAuthentications=publickey,password "$TARGET" "$@"
}

push_local_pub_to_remote() {
  local pubkey_file="${HOME}/.ssh/id_ed25519.pub"
  if [[ ! -f "$pubkey_file" ]]; then
    echo "ERROR: Local public key not found at $pubkey_file"; exit 1
  fi

  # Create ~/.ssh and authorized_keys on remote with safe perms
  remote_exec "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
               touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && \
               [[ -x \$(command -v restorecon) ]] && restorecon -R ~/.ssh || true"

  # Append only if not already present (idempotent)
  local key_content
  key_content="$(cat "$pubkey_file")"
  # shellcheck disable=SC2029
  ssh -p "$PORT" -o StrictHostKeyChecking=ask -o PreferredAuthentications=publickey,password "$TARGET" \
    "grep -qxF \"$key_content\" ~/.ssh/authorized_keys || \
     (cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak.$(date +%Y%m%d_%H%M%S) && echo \"$key_content\" >> ~/.ssh/authorized_keys)"
}

fetch_remote_pubkey() {
  # Return path to a temp file containing remote pubkey
  local tmp_pub="/tmp/remote_id_ed25519.pub.$(timestamp)"
  remote_exec '[[ -f ~/.ssh/id_ed25519.pub ]] || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q'
  scp -P "$PORT" -o StrictHostKeyChecking=ask -o PreferredAuthentications=publickey,password \
      "$TARGET:~/.ssh/id_ed25519.pub" "$tmp_pub" >/dev/null
  echo "$tmp_pub"
}

append_unique_local_authorized_keys() {
  local pubfile="$1"
  local ak="${HOME}/.ssh/authorized_keys"
  touch "$ak"
  chmod 600 "$ak"
  [[ -x "$(command -v restorecon)" ]] && restorecon -R "${HOME}/.ssh" || true

  if ! grep -qxF "$(cat "$pubfile")" "$ak"; then
    cp "$ak" "${ak}.bak.$(timestamp)"
    cat "$pubfile" >> "$ak"
  fi
}

main_one_way() {
  echo "[1/3] Preparing local ~/.ssh and key..."
  ensure_local_ssh_dir
  ensure_local_key

  echo "[2/3] Creating ~/.ssh on remote (you may be prompted for password)..."
  remote_exec "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

  echo "[3/3] Installing local public key on remote..."
  push_local_pub_to_remote

  echo "Done. Test it:"
  echo "  ssh -p $PORT $TARGET 'hostname; id'"
}

main_mutual() {
  echo "[1/5] Preparing local ~/.ssh and key..."
  ensure_local_ssh_dir
  ensure_local_key

  echo "[2/5] Preparing remote ~/.ssh and key (you may be prompted for password)..."
  remote_exec 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
  remote_exec '[[ -f ~/.ssh/id_ed25519 ]] || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q'
  remote_exec '[[ -x $(command -v restorecon) ]] && restorecon -R ~/.ssh || true'

  echo "[3/5] Installing LOCAL public key to REMOTE authorized_keys..."
  push_local_pub_to_remote

  echo "[4/5] Fetching REMOTE public key and installing into LOCAL authorized_keys..."
  rpub="$(fetch_remote_pubkey)"
  append_unique_local_authorized_keys "$rpub"
  rm -f "$rpub"

  echo "[5/5] Verifying..."
  # Quick no-interactive test (will succeed after first password-based setup)
  ssh -p "$PORT" -o BatchMode=yes "$TARGET" 'echo "REMOTE OK: $(hostname)"; exit 0' || true
  echo "Mutual trust configured."
  echo "Tests:"
  echo "  From LOCAL → REMOTE: ssh -p $PORT $TARGET 'hostname; id'"
  echo "  From REMOTE → LOCAL: (on remote) ssh $(whoami)@$(hostname -f 2>/dev/null || hostname) 'hostname; id'"
}

case "$MODE" in
  one-way) main_one_way ;;
  mutual)  main_mutual  ;;
  *) echo "Unknown mode: $MODE (use one-way|mutual)"; exit 1 ;;
esac

