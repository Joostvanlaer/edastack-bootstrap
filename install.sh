#!/usr/bin/env bash
#
# Edastack colleague bootstrap — one command from a fresh Mac to a running Claude Code
# session in your own copy of the stack. Public + DATA-FREE: only install/clone logic,
# no confidential data. This file is the canonical source; it is mirrored to the public
# `edastack-bootstrap` repo as install.sh (see meta/edastack-knowledge-runbook.md / the
# onboarding doc for how it's published).
#
# The colleague pastes ONE line (run from a FILE, not piped to bash, so the GitHub sign-in
# reads the keyboard, not the script):
#
#   curl -fsSL https://raw.githubusercontent.com/Joostvanlaer/edastack-bootstrap/main/install.sh \
#     -o /tmp/edastack.sh && bash /tmp/edastack.sh <your-repo-name>
#
# e.g. ... bash /tmp/edastack.sh joostap   → sets up edastack-joostap
#
# Idempotent: safe to re-run; it skips whatever is already done. No Homebrew, no sudo —
# Claude Code and the GitHub CLI go into ~/.local/bin. The only interactive step is the
# one-time GitHub browser sign-in.

set -euo pipefail

OWNER="Joostvanlaer"
NAME="${1:-}"
[ -n "$NAME" ] || { echo "Usage: bash edastack.sh <your-repo-name>   (e.g. joostap → edastack-joostap)"; exit 1; }
REPO="edastack-$NAME"
DIR="$HOME/$REPO"
BIN="$HOME/.local/bin"

say() { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }

mkdir -p "$BIN"
export PATH="$BIN:$PATH"

# 0. git (Apple command-line tools). If missing, trigger the install and ask to re-run.
if ! command -v git >/dev/null 2>&1; then
  say "Installing Apple command-line tools (needed for git)…"
  xcode-select --install || true
  echo "When the popup finishes installing, run this same command again."
  exit 1
fi

# 1. Claude Code — native installer (no Node, auto-updates), into ~/.local/bin.
if ! command -v claude >/dev/null 2>&1; then
  say "Installing Claude Code…"
  curl -fsSL https://claude.ai/install.sh | bash
fi

# 2. GitHub CLI — official release binary into ~/.local/bin (no Homebrew, no sudo).
if ! command -v gh >/dev/null 2>&1; then
  say "Installing the GitHub CLI…"
  arch="$(uname -m)"; case "$arch" in arm64) arch="arm64";; x86_64) arch="amd64";; esac
  ver="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
         | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$ver" ] || { echo "Could not determine the latest gh version — check your connection."; exit 1; }
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/cli/cli/releases/download/v${ver}/gh_${ver}_macOS_${arch}.tar.gz" -o "$tmp/gh.tgz"
  tar -xzf "$tmp/gh.tgz" -C "$tmp"
  cp "$tmp/gh_${ver}_macOS_${arch}/bin/gh" "$BIN/gh"
  rm -rf "$tmp"
fi

# 3. Persist ~/.local/bin on PATH for future terminals.
if ! grep -q '.local/bin' "$HOME/.zprofile" 2>/dev/null; then
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zprofile"
fi

# 4. GitHub sign-in — the one interactive step. Skip if already signed in.
if ! gh auth status >/dev/null 2>&1; then
  say "Sign in to GitHub — a browser opens; sign in as YOUR own account:"
  gh auth login --hostname github.com --git-protocol https --web
fi
gh auth setup-git >/dev/null 2>&1 || true

# 5. Clone your copy (skip if it's already there).
if [ ! -d "$DIR/.git" ]; then
  say "Cloning $REPO…"
  git clone "https://github.com/$OWNER/$REPO.git" "$DIR"
fi
cd "$DIR"

# 6. Pull the latest shared tools and commit them, so the pull's safety guard never blocks you.
say "Updating tools to the latest…"
bash meta/tools/pull-engine.sh || true
if ! git diff --quiet || ! git diff --cached --quiet; then
  git add -A && git commit -q -m "update tools to latest (bootstrap)" || true
fi

# 7. Open Claude Code straight into the guided onboarding.
say "All set — opening Claude Code. Try: \"give me the Monday brief\""
exec claude "run colleague onboarding"
