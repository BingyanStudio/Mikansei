#!/bin/bash
# Print one --dart-define=KEY=VALUE line per configured Supabase value.
# Values live in the git-ignored LocalInstall/supabase.env; see
# Scripts/supabase.env.example and Documentation/SUPABASE_SETUP.md.
mks_root="$(cd "$(dirname "$0")/.." && pwd)"
mks_env="$mks_root/LocalInstall/supabase.env"
if [[ ! -f "$mks_env" ]]; then
  exit 0
fi
for mks_key in SUPABASE_URL SUPABASE_ANON_KEY; do
  mks_value="$(grep -E "^${mks_key}=" "$mks_env" | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"
  if [[ -n "$mks_value" ]]; then
    printf '%s\n' "--dart-define=${mks_key}=${mks_value}"
  fi
done
