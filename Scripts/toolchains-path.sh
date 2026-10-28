#!/bin/bash

# Resolve the shared local toolchain directory from an explicit override or by
# walking upward from the source repository until a .toolchains directory is
# found. Relative overrides are anchored at the source repository.
mikansei_toolchains_dir() {
  local repo_root="$1"
  local current_root
  repo_root="$(cd "$repo_root" && pwd -P)" || return 1

  if [[ -n "${MIKANSEI_TOOLCHAINS_DIR:-}" ]]; then
    case "$MIKANSEI_TOOLCHAINS_DIR" in
      /*) printf '%s\n' "$MIKANSEI_TOOLCHAINS_DIR" ;;
      *) printf '%s\n' "$repo_root/$MIKANSEI_TOOLCHAINS_DIR" ;;
    esac
    return 0
  fi

  current_root="$repo_root"
  while :; do
    if [[ -d "$current_root/.toolchains" ]]; then
      printf '%s\n' "$current_root/.toolchains"
      return 0
    fi
    [[ "$current_root" == "/" ]] && break
    current_root="$(dirname "$current_root")"
  done
}

# Resolve the sibling delivery root. Relative overrides are anchored at the
# source repository, matching Scripts/path_helpers.py.
mikansei_releases_dir() {
  local repo_root="$1"
  repo_root="$(cd "$repo_root" && pwd -P)" || return 1

  if [[ -n "${MIKANSEI_RELEASES_DIR:-}" ]]; then
    case "$MIKANSEI_RELEASES_DIR" in
      /*) printf '%s\n' "$MIKANSEI_RELEASES_DIR" ;;
      *) printf '%s\n' "$repo_root/$MIKANSEI_RELEASES_DIR" ;;
    esac
  else
    printf '%s\n' "$(dirname "$repo_root")/Releases"
  fi
}
