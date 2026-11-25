#!/usr/bin/env bash
# Read-only secret scan for check 13 (and part of checks 3 and 15).
# Run from anywhere inside the project: bash path/to/find_secrets.sh
# Prints file paths and masked matches. Never prints full secret values.
#
# Exit codes:
#   0  nothing found
#   1  possible secret exposure found (so it can be used in CI or a pre-commit hook)
#   2  not a Git repository

set -u

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a Git repository. Run this from inside the project."
  exit 2
fi
cd "$(git rev-parse --show-toplevel)" || exit 2

found=0
section() { printf '\n== %s\n' "$1"; }

# Key patterns: name|regex (POSIX ERE). Names starting with "Generic" are noisy
# and are skipped in the Git history scan.
PATTERNS=(
  "Stripe secret key|sk_(live|test)_[0-9A-Za-z]{10,}"
  "Stripe restricted key|rk_(live|test)_[0-9A-Za-z]{10,}"
  "Anthropic key|sk-ant-[A-Za-z0-9_-]{20,}"
  "OpenAI key|(sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,})"
  "AWS access key|AKIA[0-9A-Z]{16}"
  "Google API key|AIza[0-9A-Za-z_-]{35}"
  "GitHub token|(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"
  "Slack token|xox[abposr]-[A-Za-z0-9-]{10,}"
  "Polar token|polar_[a-z_]{2,8}_[A-Za-z0-9]{20,}"
  "Resend key|re_[A-Za-z0-9]{8,}_[A-Za-z0-9]{16,}"
  "Private key|-----BEGIN [A-Z ]*PRIVATE KEY-----"
  "Supabase secret key|sb_secret_[A-Za-z0-9_-]{20,}"
  "Supabase service role JWT|[Ss][Ee][Rr][Vv][Ii][Cc][Ee]_[Rr][Oo][Ll][Ee][A-Za-z_]*['\"]?[[:space:]]*[:=][[:space:]]*['\"]?eyJ[A-Za-z0-9_-]{20,}"
  "Generic secret assignment|(SECRET|PRIVATE|PASSWORD|TOKEN)[A-Z_]*[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9_/+=-]{16,}"
)

mask() {
  # Keep the first 4 characters of each long token, hide the rest.
  sed -E \
    -e 's/((sk|rk)_(live|test)_|sk-ant-|sk-proj-|sk-svcacct-|sk-admin-|sk-|AKIA|AIza|gh[pousr]_|github_pat_|xox[abposr]-|sb_secret_|polar_[a-z_]{2,8}_|re_|eyJ)([A-Za-z0-9]{4})[A-Za-z0-9_./+=-]+/\1\4****/g' \
    -e "s/(=[[:space:]]*['\"]?|:[[:space:]]+['\"]?|:['\"])([A-Za-z0-9]{4})[A-Za-z0-9_/+=-]{12,}/\1\2****/g"
}

EXCLUDES=(':!*.lock' ':!package-lock.json' ':!pnpm-lock.yaml' ':!yarn.lock' ':!*.min.js' ':!*.map')

section "1. Env files tracked by Git"
tracked_env=$(git ls-files | grep -E '(^|/)\.env($|\.)' | grep -v -E '\.(example|sample|template)$' || true)
if [ -n "$tracked_env" ]; then
  echo "$tracked_env" | sed 's/^/  TRACKED: /'
  echo "  -> Run: git rm --cached <file>, add it to .gitignore, then rotate its keys."
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
if [ -f .gitignore ] && grep -qE '^[[:space:]]*/?\.env' .gitignore; then
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
  hits=$(git grep -n -I -E "$regex" -- . "${EXCLUDES[@]}" 2>/dev/null | head -20 || true)
  if [ -n "$hits" ]; then
    echo "  [$name]"
    echo "$hits" | cut -c1-200 | mask | sed 's/^/    /'
    found=1
    pattern_found=1
  fi
done
[ "$pattern_found" -eq 0 ] && echo "  none"

section "5. Secrets behind public env prefixes (shipped to the browser/app)"
public_hits=$(git grep -n -I -E '(NEXT_PUBLIC_|VITE_|EXPO_PUBLIC_|REACT_APP_|PUBLIC_)[A-Z0-9_]*(SECRET|PRIVATE|SERVICE_ROLE|OPENAI|ANTHROPIC|STRIPE_SECRET|API_KEY|TOKEN)' -- . "${EXCLUDES[@]}" 2>/dev/null | head -30 || true)
if [ -n "$public_hits" ]; then
  echo "$public_hits" | cut -c1-200 | mask | sed 's/^/  /'
  echo "  -> Check each one: is it really a publishable key (Stripe pk_, Supabase anon/publishable, Firebase web config)? If not, move the call to the server."
  found=1
else
  echo "  none"
fi

section "6. Build output and source maps tracked by Git"
build_hits=$(git ls-files | grep -E '(^|/)(\.next|dist|build|out)/|\.map$' | grep -v -E '(^|/)node_modules/' | head -20 || true)
if [ -n "$build_hits" ]; then
  echo "$build_hits" | sed 's/^/  TRACKED: /'
  echo "  -> Build output can contain inlined env values and full source. Remove it from Git and check check 15."
  found=1
else
  echo "  none"
fi

section "7. Key patterns in Git history (last 500 commits)"
hist_hits=""
for entry in "${PATTERNS[@]}"; do
  name=${entry%%|*}
  regex=${entry#*|}
  case "$name" in Generic*) continue ;; esac  # too noisy for history
  h=$(git log --all -n 500 -E -G "$regex" --pretty=format:%h 2>/dev/null | head -5 | tr '\n' ' ' || true)
  if [ -n "$h" ]; then
    hist_hits="$hist_hits  [$name] commits: $h\n"
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
  exit 1
fi
echo "Result: nothing found by this scan. This does not prove there are no leaks."
exit 0
