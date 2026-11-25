#!/usr/bin/env bash
# Tests for scripts/find_secrets.sh. Run: bash tests/test_find_secrets.sh
# Fake keys are built at runtime from pieces so this file itself never contains
# anything that looks like a real secret.

set -u
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/find_secrets.sh"
pass=0
fail=0

ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1"; }

new_repo() {
  dir=$(mktemp -d)
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  echo "$dir"
}

commit_all() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }

run_scan() { (cd "$1" && bash "$SCRIPT" 2>&1); }

# Fake values
FAKE_STRIPE="sk_""live_""$(printf 'a%.0s' {1..24})"
FAKE_ANTHROPIC="sk-""ant-""api03-""$(printf 'b%.0s' {1..30})"
FAKE_OPENAI="sk-""proj-""$(printf 'c%.0s' {1..30})"
FAKE_AWS="AKIA""ABCDEFGHIJKLMNOP"

echo "find_secrets.sh"

# 1. Not a Git repo -> exit 2
d=$(mktemp -d)
(cd "$d" && bash "$SCRIPT" >/dev/null 2>&1); code=$?
[ "$code" -eq 2 ] && ok "exit 2 outside a Git repo" || bad "exit 2 outside a Git repo (got $code)"

# 2. Clean repo -> exit 0
d=$(new_repo)
printf '.env*\n!.env.example\n' > "$d/.gitignore"
printf 'export const x = 1;\n' > "$d/index.ts"
printf 'OPENAI_API_KEY=\n' > "$d/.env.example"
commit_all "$d" init
out=$(run_scan "$d"); code=$?
[ "$code" -eq 0 ] && ok "clean repo exits 0" || { bad "clean repo exits 0 (got $code)"; echo "$out"; }

# 3. .env committed then deleted -> found in history, exit 1
d=$(new_repo)
printf 'STRIPE_SECRET_KEY=%s\n' "$FAKE_STRIPE" > "$d/.env"
commit_all "$d" add-env
git -C "$d" rm -q --cached .env && rm "$d/.env"
printf '.env*\n' > "$d/.gitignore"
commit_all "$d" remove-env
out=$(run_scan "$d"); code=$?
[ "$code" -eq 1 ] && ok "deleted .env still fails the scan" || bad "deleted .env still fails the scan (got $code)"
echo "$out" | grep -q "IN HISTORY: .env" && ok ".env listed in history" || bad ".env listed in history"
echo "$out" | grep -q "\[Stripe secret key\] commits:" && ok "Stripe key found in history" || bad "Stripe key found in history"

# 4. Masking: full values never printed
d=$(new_repo)
printf '.env*\n' > "$d/.gitignore"
printf 'const a = "%s";\nconst b = "%s";\nconst c = "%s";\n' "$FAKE_STRIPE" "$FAKE_OPENAI" "$FAKE_AWS" > "$d/keys.ts"
commit_all "$d" keys
out=$(run_scan "$d")
leaked=0
for v in "$FAKE_STRIPE" "$FAKE_OPENAI" "$FAKE_AWS"; do
  echo "$out" | grep -qF "$v" && leaked=1
done
[ "$leaked" -eq 0 ] && ok "full key values are masked" || bad "full key values are masked"
echo "$out" | grep -q "const a = \"sk_live_aaaa\*\*\*\*\"" && ok "mask keeps prefix and 4 chars" || bad "mask keeps prefix and 4 chars"

# 5. Variable names stay readable after masking
d=$(new_repo)
printf '.env*\n' > "$d/.gitignore"
printf 'OPENAI_API_KEY=%s\n' "$FAKE_OPENAI" > "$d/config.txt"
commit_all "$d" cfg
out=$(run_scan "$d")
echo "$out" | grep -q "config.txt:1:OPENAI_API_KEY=sk-proj-cccc\*\*\*\*" && ok "variable name is not masked" || { bad "variable name is not masked"; echo "$out" | grep config.txt; }

# 6. Anthropic key is not reported as an OpenAI key
d=$(new_repo)
printf '.env*\n' > "$d/.gitignore"
printf 'ANTHROPIC_API_KEY=%s\n' "$FAKE_ANTHROPIC" > "$d/config.txt"
commit_all "$d" anth
out=$(run_scan "$d")
section4=$(echo "$out" | sed -n '/== 4/,/== 5/p')
echo "$section4" | grep -q "\[Anthropic key\]" && ok "Anthropic key detected" || bad "Anthropic key detected"
echo "$section4" | grep -q "\[OpenAI key\]" && bad "Anthropic key not double reported as OpenAI" || ok "Anthropic key not double reported as OpenAI"

# 7. A comment mentioning service_role is not flagged
d=$(new_repo)
printf '.env*\n' > "$d/.gitignore"
printf '// never use the service_role key in the browser\n' > "$d/notes.ts"
commit_all "$d" notes
out=$(run_scan "$d"); code=$?
[ "$code" -eq 0 ] && ok "service_role comment is not flagged" || { bad "service_role comment is not flagged (got $code)"; echo "$out"; }

# 8. Secret behind a public env prefix
d=$(new_repo)
printf '.env*\n' > "$d/.gitignore"
printf 'const k = process.env.NEXT_PUBLIC_OPENAI_API_KEY;\n' > "$d/page.tsx"
commit_all "$d" public
out=$(run_scan "$d"); code=$?
echo "$out" | sed -n '/== 5/,/== 6/p' | grep -q "page.tsx" && ok "public env prefix secret flagged" || bad "public env prefix secret flagged"

# 9. Tracked source maps
d=$(new_repo)
printf '.env*\n' > "$d/.gitignore"
mkdir -p "$d/dist" && printf '{}' > "$d/dist/app.js.map"
commit_all "$d" map
out=$(run_scan "$d")
echo "$out" | grep -q "TRACKED: dist/app.js.map" && ok "tracked source map flagged" || bad "tracked source map flagged"

# 10. Works from a subfolder
d=$(new_repo)
printf 'const k = "%s";\n' "$FAKE_AWS" > "$d/k.ts"
mkdir -p "$d/src/deep"
commit_all "$d" sub
out=$(cd "$d/src/deep" && bash "$SCRIPT" 2>&1)
echo "$out" | grep -q "k.ts:1" && ok "runs from a subfolder" || bad "runs from a subfolder"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
