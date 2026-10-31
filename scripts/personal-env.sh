#!/usr/bin/env bash
# Source this file from project scripts; do not modify the user's shell profile.
PERSONAL_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CARGO_HOME="${CARGO_HOME:-$HOME/.local/share/localsend-toolchains/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.local/share/localsend-toolchains/rustup}"
export PATH="$PERSONAL_PROJECT_ROOT/support/submodules/flutter/bin:$CARGO_HOME/bin:$PATH"
