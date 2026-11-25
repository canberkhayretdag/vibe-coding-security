---
name: vibe-coding-security
description: Audit a vibe-coded web or mobile app for the 18 most common security holes (open admin routes and Server Actions, ID swapping, exposed API keys, client-side prices, negative quantities, fake payments, coupon reuse, self-assigned admin, guessable login codes, prompt injection, XSS, unsafe uploads, leaked .env, SQL injection / open database, deployment leaks like source maps and open CORS, hallucinated or vulnerable dependencies, SSRF, insecure mobile storage and deep links) and fix them. Use when the user asks for a security check, security audit, "is my app safe", "check my app for vulnerabilities", or wants to review an AI-built / vibe-coded app before launch.
---

# Vibe Coding Security

Apps built fast with AI usually work, but they trust the browser too much. This skill reviews the codebase like an attacker would and checks 18 concrete holes, then fixes them with the user's approval.

Reply in the user's language.

## Ground rules

- Review the code and run things locally. Never send attack requests to a production URL, a third-party service, or anything the user does not own.
- Do not invent findings. Every finding needs evidence: a file path and line, a config value, or a command output. If something cannot be checked from the code (for example, database rules that live only in a dashboard), mark it "Could not verify" and tell the user exactly where to look.
- Do not print secret values in full. Show the first 4 characters and the file location.
- Do not change code before the report is shown. Fixes come after the user says go.

## Step 1: Map the app

Before checking anything, find out:

- Stack: framework (Next.js, Remix, Vite + React, Express, FastAPI, Rails, Flutter, React Native...), language, hosting.
- Backend: own API routes, server actions, edge functions, or a BaaS (Supabase, Firebase, Appwrite, PocketBase).
- Auth: which provider, where sessions are checked, how roles are stored.
- Data: database, ORM or raw SQL, row level security rules.
- Money: Stripe, Polar, Lemon Squeezy, Paddle, RevenueCat, iyzico or similar. Coupons, credits, trials.
- AI: any LLM calls, tools the model can call, system prompts.
- Uploads: where files go, who can read them.
- Outbound fetches: any feature where the server fetches a URL (link preview, import, webhooks, AI browsing).
- Mobile: React Native, Expo, Flutter or native client; how it stores tokens and handles deep links.
- Deployment: build config, hosting config, CORS and headers, framework version.

Read `package.json` (or the equivalent), the route/API folder, middleware, every `"use server"` file, auth helpers, database schema and migrations, `.env.example`, build and hosting config, and the config of any BaaS. Write a 5-10 line map for the user before the checks.

## Step 2: Run the 18 checks

Go through every check in [references/checks.md](references/checks.md). Each check lists what the attacker does, where to look, red flags, and the fix. Skip a check only when the feature does not exist in the app (no payments, no uploads, no AI, no mobile client), and say that it was skipped and why. Checks 15 (deployment) and 16 (dependencies) apply to every app.

For check 13 (leaked secrets) run the helper script from inside the project:

```bash
bash <skill-dir>/scripts/find_secrets.sh
```

It is read-only. It looks for tracked `.env` files, `.env` files in Git history, common key patterns in tracked files and history, secrets exposed through public env prefixes (`NEXT_PUBLIC_`, `VITE_`, `EXPO_PUBLIC_`, `REACT_APP_`), and build output or source maps committed to Git. It exits with `1` when it finds something, `0` when it finds nothing, `2` outside a Git repo. A non-zero exit is a finding, not a failure of the script.

For check 16 (dependencies) run the stack's audit command (`npm audit`, `pip-audit`...) and check unfamiliar packages against the registry, as described in the check. If there is no network access, mark it "Could not verify" and give the user the commands.

## Step 3: Report

Show one table, sorted by severity:

| # | Check | Status | Severity | Evidence | Fix |
|---|-------|--------|----------|----------|-----|

- Status: `Vulnerable`, `OK`, `Could not verify`, `Not applicable`.
- Severity: `Critical` (anyone can take money, data or admin access now), `High`, `Medium`, `Low`.
- Evidence: `path/to/file.ts:42` plus one short sentence.
- Fix: one sentence. Details go below the table.

After the table, for each `Vulnerable` item write a short explanation of how someone would abuse it, in plain words a non-developer understands. Then list the `Could not verify` items with the exact place the user has to check (for example: "Supabase dashboard → Authentication → Policies → table `orders`").

If a real secret was found in Git history, say clearly that deleting the file is not enough: the key has to be rotated (revoked and re-created) at the provider.

See [examples/sample-report.md](examples/sample-report.md) for a full example of the expected report.

## Step 4: Fix

Ask the user whether to fix everything or only Critical and High. Then:

1. Fix one check at a time, starting from Critical.
2. Move trust to the server: the server decides prices, roles, ownership, payment status and limits. Client-side checks stay only as UX.
3. Prefer the framework's own tools (middleware, ORM parameters, RLS policies, webhook signature helpers, schema validation with zod / pydantic) over hand-written code.
4. After each fix, write one line: what changed and in which file.
5. If tests exist, run them. If there are none, describe how the user can check the fix manually on localhost.

Finish with the list of things the user has to do outside the code: rotating keys, enabling RLS in the dashboard, setting webhook secrets in the hosting env, turning on rate limiting at the provider, setting spend limits on AI providers, upgrading the framework.
