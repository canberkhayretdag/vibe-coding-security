#!/usr/bin/env bash
# Read-only secret scan for check 13 (and part of check 3).
# Run from the project root: bash path/to/find_secrets.sh
# Prints file paths and masked matches. Never prints full secret values.

set -u

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a Git repository. Run this from the project root."
  exit 1
fi

found=0
section() { printf '\n== %s\n' "$1"; }

# Key patterns: name|regex
PATTERNS=(
  "Stripe secret key|sk_(live|test)_[0-9A-Za-z]{10,}"
  "Stripe restricted key|rk_(live|test)_[0-9A-Za-z]{10,}"
  "OpenAI key|sk-(proj-)?[A-Za-z0-9_-]{20,}"
  "Anthropic key|sk-ant-[A-Za-z0-9_-]{20,}"
  "AWS access key|AKIA[0-9A-Z]{16}"
  "Google API key|AIza[0-9A-Za-z_-]{35}"
  "GitHub token|gh[pousr]_[A-Za-z0-9]{30,}"
  "Slack token|xox[abposr]-[A-Za-z0-9-]{10,}"
  "Private key|-----BEGIN [A-Z ]*PRIVATE KEY-----"
  "Supabase service role|service_role"
  "Generic secret assignment|(SECRET|PRIVATE|PASSWORD|TOKEN)[A-Z_]*[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9_/+=-]{16,}"
)

mask() {
  # Keep the first 4 characters of each long token, hide the rest.
  sed -E \
    -e 's/((sk|rk)_(live|test)_|sk-ant-|sk-proj-|sk-|AKIA|AIza|gh[pousr]_|xox[abposr]-)([A-Za-z0-9]{4})[A-Za-z0-9_/+=-]+/\1\4****/g' \
    -e "s/([:=][[:space:]]*['\"]?)([A-Za-z0-9]{4})[A-Za-z0-9_/+=-]{12,}/\1\2****/g"
}

section "1. Env files tracked by Git"
tracked_env=$(git ls-files | grep -E '(^|/)\.env($|\.)' | grep -v -E '\.(example|sample|template)$' || true)
if [ -n "$tracked_env" ]; then
  echo "$tracked_env" | sed 's/^/  TRACKED: /'
  found=1
else
  echo "  none"
fi

section "2. Env files anywhere in Git history"
history_env=$(git log --all --pretty=format: --name-only --diff-filter=A 2>/dev/null \
  | grep -E '(^|/)\.env($|\.)' | grep -v -E '\.(example|sample|template)$' | sort -u || true)
if [ -n "$history_env" ]; then
  echo "$history_env" | sed 's/^/  IN HISTORY: /'
  echo "  -> Keys in these files must be rotated, even if the file is deleted now."
  found=1
else
  echo "  none"
fi

section "3. .gitignore covers .env"
if [ -f .gitignore ] && grep -qE '^\s*/?\.env' .gitignore; then
  echo "  ok"
else
  echo "  MISSING: add '.env*' and '!.env.example' to .gitignore"
  found=1
fi

section "4. Key patterns in tracked files"
pattern_found=0
for entry in "${PATTERNS[@]}"; do
  name=${entry%%|*}
  regex=${entry#*|}
  hits=$(git grep -n -I -E "$regex" -- ':!*.lock' ':!package-lock.json' ':!pnpm-lock.yaml' ':!yarn.lock' 2>/dev/null | head -20 || true)
  if [ -n "$hits" ]; then
    echo "  [$name]"
    echo "$hits" | cut -c1-200 | mask | sed 's/^/    /'
    found=1
    pattern_found=1
  fi
done
[ "$pattern_found" -eq 0 ] && echo "  none"

section "5. Secrets behind public env prefixes (shipped to the browser/app)"
public_hits=$(git grep -n -I -E '(NEXT_PUBLIC_|VITE_|EXPO_PUBLIC_|REACT_APP_|PUBLIC_)[A-Z0-9_]*(SECRET|PRIVATE|SERVICE_ROLE|OPENAI|ANTHROPIC|STRIPE_SECRET|API_KEY|TOKEN)' 2>/dev/null | head -30 || true)
if [ -n "$public_hits" ]; then
  echo "$public_hits" | cut -c1-200 | mask | sed 's/^/  /'
  echo "  -> Check each one: is it really a publishable key? If not, move the call to the server."
  found=1
else
  echo "  none"
fi

section "6. Key patterns in Git history (last 500 commits)"
hist_hits=""
for entry in "${PATTERNS[@]}"; do
  regex=${entry#*|}
  case "$regex" in *"[A-Z_]*"*) continue ;; esac  # skip the noisy generic rule here
  h=$(git log --all -n 500 -E -G "$regex" --pretty=format:%h 2>/dev/null | head -5 | tr '\n' ' ' || true)
  if [ -n "$h" ]; then
    hist_hits="$hist_hits  [${entry%%|*}] commits: $h\n"
  fi
done
if [ -n "$hist_hits" ]; then
  printf "%b" "$hist_hits"
  echo "  -> Inspect with: git show <commit>. Rotate any real key found."
  found=1
else
  echo "  none"
fi

echo
if [ "$found" -eq 1 ]; then
  echo "Result: possible secret exposure found. Review each item above."
else
  echo "Result: nothing found by this scan. This does not prove there are no leaks."
fi
