#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  Beeuni CLI — one-click install                                              ║
# ║                                                                              ║
# ║      curl -fsSL https://beeuni.ai/install | bash                               ║
# ║                                                                              ║
# ║  Downloads the prebuilt `beeuni` binary for your OS + arch from              ║
# ║  GitHub Releases and drops it on PATH.                                       ║
# ║                                                                              ║
# ║  Re-run any time to update (or use `beeuni update`).                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
REPO="${BEEUNI_REPO:-BeeuniLab/beeuni-cli}"
INSTALL_HOME="${BEEUNI_HOME:-$HOME/.beeuni}"
BINARY_NAME="beeuni"
CHANNEL="${BEEUNI_CHANNEL:-prod}"
# Stable releases are tagged `vX.Y.Z` (unified version). The dev channel uses
# the mutable `dev-latest` prerelease.
DEV_TAG="dev-latest"
CHECKSUM_ASSET="SHA256SUMS"

cleanup() {
  rm -f "${TMP_BIN:-}" "${TMP_SUMS:-}"
}
trap cleanup EXIT

# ─── Colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[0;31m'; G=$'\033[0;32m'; Y=$'\033[1;33m'; C=$'\033[0;36m'
  W=$'\033[1;37m'; B=$'\033[1m'; D=$'\033[2m'; F=$'\033[2;37m'; N=$'\033[0m'
else
  R='' G='' Y='' C='' W='' B='' D='' F='' N=''
fi

info()    { printf "  ${C}▸${N}  %s\n" "$*"; }
ok()      { printf "  ${G}✓${N}  %s\n" "$*"; }
warn()    { printf "  ${Y}!${N}  ${Y}%s${N}\n" "$*"; }
fatal()   { printf "  ${R}✗${N}  ${R}%s${N}\n" "$*" >&2; exit 1; }
section() { printf "\n  ${W}${B}%s${N}\n  ${F}%s${N}\n" "$1" "────────────────────────────────────────────────"; }

print_banner() {
  printf "\n"
  printf "${C}"
  cat <<'EOF'
    ██╗   ██╗ █████╗ ██╗     ██╗  ██╗ ██████╗ ██████╗
    ██║   ██║██╔══██╗██║     ██║ ██╔╝██╔═══██╗██╔══██╗
    ██║   ██║███████║██║     █████╔╝ ██║   ██║██████╔╝
    ╚██╗ ██╔╝██╔══██║██║     ██╔═██╗ ██║   ██║██╔══██╗
     ╚████╔╝ ██║  ██║███████╗██║  ██╗╚██████╔╝██║  ██║
      ╚═══╝  ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝
EOF
  printf "${N}\n"
  printf "    ${W}The operating system for AI workers${N}\n"
  printf "    ${F}One-click CLI installer${N}\n"
  printf "\n"
}

# ─── Detect platform + arch ──────────────────────────────────────────────────
detect_platform() {
  local uname_s uname_m
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"
  case "$uname_s" in
    Darwin) OS=darwin ;;
    Linux)  OS=linux ;;
    *) fatal "Unsupported OS: $uname_s. Beeuni CLI builds for darwin + linux only." ;;
  esac
  case "$uname_m" in
    x86_64|amd64) ARCH=x64 ;;
    arm64|aarch64) ARCH=arm64 ;;
    *) fatal "Unsupported architecture: $uname_m. Need x86_64 or arm64." ;;
  esac
  ASSET="${BINARY_NAME}-${OS}-${ARCH}"
}

# ─── Resolve target version ──────────────────────────────────────────────────
resolve_version() {
  if [ -n "${BEEUNI_VERSION:-}" ]; then
    # Tolerate either `0.9.0` or `v0.9.0`.
    case "$BEEUNI_VERSION" in
      v*) VERSION="$BEEUNI_VERSION" ;;
      *)  VERSION="v${BEEUNI_VERSION}" ;;
    esac
    info "Pinned version (from \$BEEUNI_VERSION): $VERSION"
    return
  fi

  case "$CHANNEL" in
    prod|"")
      ;;
    dev)
      VERSION="$DEV_TAG"
      info "Dev channel selected (from \$BEEUNI_CHANNEL): $VERSION"
      return
      ;;
    *)
      fatal "Unsupported BEEUNI_CHANNEL: $CHANNEL. Use 'prod' or 'dev'."
      ;;
  esac

  info "Resolving latest release from GitHub…"
  # The latest non-prerelease GitHub Release is the unified `vX.Y.Z` build.
  local api_url="https://api.github.com/repos/${REPO}/releases/latest"
  local tag
  tag=$(curl -fsSL --connect-timeout 5 "$api_url" 2>/dev/null \
    | grep -E '"tag_name":' \
    | head -1 \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' || true)
  if [ -z "$tag" ]; then
    fatal "Could not find a vX.Y.Z release on github.com/${REPO}. Pin one with \`BEEUNI_VERSION=0.1.0 …\` or use the dev channel (\`BEEUNI_CHANNEL=dev\`)."
  fi
  VERSION="$tag"
  ok "Latest release: $VERSION"
}

# ─── Download the binary to a temp file ──────────────────────────────────────
download_binary() {
  local url="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
  TMP_BIN="$(mktemp -t beeuni-install.XXXXXX)"
  info "Downloading ${ASSET}…"
  printf "    ${F}from ${url}${N}\n"
  if ! curl -fsSL "$url" -o "$TMP_BIN"; then
    rm -f "$TMP_BIN"
    fatal "Failed to download $url. Check the release page on github.com/${REPO}/releases."
  fi
  chmod +x "$TMP_BIN"
  ok "Downloaded ($(du -h "$TMP_BIN" | awk '{print $1}'))"
}

download_and_verify_checksum() {
  local sums_url="https://github.com/${REPO}/releases/download/${VERSION}/${CHECKSUM_ASSET}"
  TMP_SUMS="$(mktemp -t beeuni-checksums.XXXXXX)"
  info "Downloading ${CHECKSUM_ASSET}…"
  if ! curl -fsSL "$sums_url" -o "$TMP_SUMS"; then
    rm -f "$TMP_SUMS"
    fatal "Failed to download ${CHECKSUM_ASSET} from $sums_url. Refusing to install an unverified binary."
  fi

  local expected actual
  expected="$(awk -v target="$ASSET" '$2 == target || $2 == "*" target { print $1; exit }' "$TMP_SUMS")"
  [ -n "$expected" ] || fatal "${ASSET} is missing from ${CHECKSUM_ASSET}. Refusing to install an unverified binary."

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$TMP_BIN" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$TMP_BIN" | awk '{print $1}')"
  else
    fatal "Neither sha256sum nor shasum is available; cannot verify the downloaded binary."
  fi
  [ "$actual" = "$expected" ] || fatal "Checksum verification failed for ${ASSET}."
  ok "Checksum verified"
}

# ─── Install the binary ──────────────────────────────────────────────────────
install_binary() {
  mkdir -p "$INSTALL_HOME"
  local target="$INSTALL_HOME/$BINARY_NAME"
  mv "$TMP_BIN" "$target"
  chmod +x "$target"
  ok "Installed binary at ${target}"
}

# ─── Symlink it onto $PATH ───────────────────────────────────────────────────
link_onto_path() {
  local target="$INSTALL_HOME/$BINARY_NAME"
  # Preferred: /usr/local/bin (already on most PATHs).
  if [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
    ln -sf "$target" "/usr/local/bin/${BINARY_NAME}"
    ok "Symlinked /usr/local/bin/${BINARY_NAME} → ${target}"
    return
  fi
  # Fallback: ~/.local/bin if it exists.
  local local_bin="$HOME/.local/bin"
  if [ -d "$local_bin" ]; then
    mkdir -p "$local_bin"
    ln -sf "$target" "${local_bin}/${BINARY_NAME}"
    ok "Symlinked ${local_bin}/${BINARY_NAME} → ${target}"
    case ":$PATH:" in
      *":${local_bin}:"*) ;;
      *)
        warn "${local_bin} isn't on your PATH. Add this to your shell rc:"
        printf "    ${C}export PATH=\"\$HOME/.local/bin:\$PATH\"${N}\n"
        ;;
    esac
    return
  fi
  # Last resort: try sudo for /usr/local/bin.
  if command -v sudo >/dev/null 2>&1; then
    info "Linking via sudo (you may be prompted for your password)…"
    if sudo ln -sf "$target" "/usr/local/bin/${BINARY_NAME}"; then
      ok "Symlinked /usr/local/bin/${BINARY_NAME} → ${target}"
      return
    fi
  fi
  warn "Could not put beeuni on PATH automatically."
  printf "    Run this when convenient:\n"
  printf "    ${C}sudo ln -sf ${target} /usr/local/bin/beeuni${N}\n"
}

# ─── Verify installed binary works ───────────────────────────────────────────
verify_install() {
  local target
  target="$(command -v "$BINARY_NAME" 2>/dev/null || true)"
  if [ -z "$target" ]; then
    target="$INSTALL_HOME/$BINARY_NAME"
  fi
  if ! "$target" version >/dev/null 2>&1; then
    warn "Binary installed but \`beeuni version\` failed. Try running it directly: $target"
    return
  fi
  ok "valkor --version → $("$target" version | head -1 | sed 's/^[[:space:]]*//')"
}

print_next_steps() {
  printf "\n"
  printf "  ${W}${B}Get started:${N}\n\n"
  printf "    ${C}beeuni login${N}           ${F}browser opens — one click to authorize${N}\n"
  printf "    ${C}beeuni projects ls${N}     ${F}list your projects${N}\n"
  printf "    ${C}beeuni projects link${N}   ${F}bind this directory to a project${N}\n"
  printf "    ${C}beeuni --help${N}          ${F}every command${N}\n"
  printf "\n"
  printf "  ${F}Update later:${N} ${C}beeuni update${N}\n"
  printf "  ${F}Remove:${N}      ${C}beeuni uninstall${N}\n"
  printf "\n"
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  print_banner
  section "Preflight"
  command -v curl >/dev/null 2>&1 || fatal "curl is required."
  ok "curl available"
  detect_platform
  ok "Platform detected: ${OS}-${ARCH}"

  section "Fetching binary"
  resolve_version
  download_binary
  download_and_verify_checksum

  section "Installing"
  install_binary
  link_onto_path

  section "Verifying"
  verify_install

  print_next_steps
}

main "$@"
