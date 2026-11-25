# vibe-coding-security

A Claude Code skill that checks your vibe-coded app for the 18 most common security holes.
It reads your code like an attacker would, reports every issue with the file and line, and fixes them after you approve.

Most security checklists stop at "turn on RLS" and "don't commit your keys". This one also checks the business logic that AI-built apps get wrong: prices sent from the browser, payments that are never verified, coupons that can be used 50 times at once, and sign-up forms that let you pick your own role.

## The 18 checks

Your app's logic and data:


1. Can `/admin` be opened without logging in, or by a normal user?
2. Does changing the ID in the URL show someone else's data?
3. Are API keys shipped to the browser?
4. Does the price come from the client?
5. Are negative, zero or absurd quantities accepted?
6. Can an order be marked as paid without a real payment?
7. Can the same coupon or reward be used again and again?
8. Can someone make themselves admin at sign-up?
9. Can the login code be guessed by brute force?
10. Can the app's AI be tricked with "ignore your instructions"?
11. Does a script in a username run on the page (XSS)?
12. Can someone upload a file that is not a photo?
13. Is `.env` tracked in Git or in Git history?
14. Can someone query your database directly (SQL injection, missing RLS)?

How it is deployed and built:

15. Are source maps, `.git`, debug pages or API docs public? Is CORS open to every site? Are security headers missing?
16. Did the AI add a package that is fake, brand new, or full of known vulnerabilities?
17. Can someone make your server fetch an internal URL (SSRF)?
18. Does the mobile app keep tokens in plain storage or trust any deep link?

Check 1 also covers Server Actions and API routes with no auth check, auth that lives only in middleware, and JWTs that are decoded but not verified.

## Example

[`examples/vulnerable-app`](examples/vulnerable-app) is a small Next.js app with holes added on purpose. [`examples/sample-report.md`](examples/sample-report.md) is the report the skill gives for it.

## Install

Clone it into your Claude Code skills folder:

```bash
git clone https://github.com/canberkhayretdag/vibe-coding-security ~/.claude/skills/vibe-coding-security
```

To use it in one project only, clone it inside the project:

```bash
git clone https://github.com/canberkhayretdag/vibe-coding-security .claude/skills/vibe-coding-security
```

## Usage

Open Claude Code in your project folder and type one of these:

```
/vibe-coding-security
```

```
Run a security check on my app
```

The skill first maps your app: framework, database, auth, payments, AI, uploads, mobile and deployment.
Then it goes through the 18 checks and gives you one table, sorted by severity.
It does not touch any file until you say so.

There is also a small script for the `.env` and secret key scan. You can run it on its own:

```bash
bash ~/.claude/skills/vibe-coding-security/scripts/find_secrets.sh
```

The script is read-only. It shows only the first 4 characters of any key it finds.
It exits with `1` when it finds something, so you can also use it in CI or as a pre-commit hook:

```bash
# .git/hooks/pre-commit
bash ~/.claude/skills/vibe-coding-security/scripts/find_secrets.sh >/dev/null || {
  echo "find_secrets.sh found a possible secret. Run it to see the details."
  exit 1
}
```

## Tests

```bash
bash tests/test_find_secrets.sh
```

The tests build small Git repos with fake keys and check what the script reports. They run on Linux and macOS in CI.

## Good to know

- The skill reviews your code and tests on localhost. It never sends attack requests to a live site or to systems you don't own.
- Some settings live only in a dashboard: Supabase RLS policies, Firebase rules, payment provider settings, AI spend limits. The skill marks these as "Could not verify" and tells you where to look.
- If a key was ever committed to Git, deleting the file does not help. Revoke it at the provider and create a new one.
- This skill does not replace a professional security audit. It is there to catch the most common mistakes before you launch.

## Author

Built by [Canberk Hayretdag](https://github.com/canberkhayretdag), security researcher with Hall of Fame recognition from Apple, Google, Netflix, Uber and others.

## License

MIT
