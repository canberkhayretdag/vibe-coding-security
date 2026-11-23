# vibe-coding-security

A Claude Code skill that checks your vibe-coded app for the 14 most common security holes.
It reads your code like an attacker would, reports every issue with the file and line, and fixes them after you approve.

## The 14 checks

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

The skill first maps your app: framework, database, auth, payments, AI and uploads.
Then it goes through the 14 checks and gives you one table, sorted by severity.
It does not touch any file until you say so.

There is also a small script for the `.env` and secret key scan. You can run it on its own:

```bash
bash ~/.claude/skills/vibe-coding-security/scripts/find_secrets.sh
```

The script is read-only. It shows only the first 4 characters of any key it finds.

## Good to know

- The skill reviews your code and tests on localhost. It never sends attack requests to a live site or to systems you don't own.
- Some settings live only in a dashboard: Supabase RLS policies, Firebase rules, payment provider settings. The skill marks these as "Could not verify" and tells you where to look.
- If a key was ever committed to Git, deleting the file does not help. Revoke it at the provider and create a new one.
- This skill does not replace a professional security audit. It is there to catch the most common mistakes before you launch.

## License

MIT
