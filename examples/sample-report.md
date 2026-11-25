# Sample report: `examples/vulnerable-app`

This is the kind of report the skill gives. The project is a small Next.js app with holes added on purpose.

## App map

- Stack: Next.js 14.1.0 (App Router), TypeScript, hosting not set in the repo.
- Backend: route handlers under `app/api`, one Server Action in `app/actions.ts`.
- Auth: own cookie session (`lib/session.ts`), roles on the `user` row, middleware only on `/admin`.
- Data: PostgreSQL through Prisma. No raw SQL.
- Money: Stripe Checkout with `price_data`, no webhook handler. Coupons give credits.
- AI: OpenAI called from the browser (`lib/ai.ts`).
- Uploads: none.
- Mobile: none.

## Findings

| # | Check | Status | Severity | Evidence | Fix |
|---|-------|--------|----------|----------|-----|
| 6 | Fake payments | Vulnerable | Critical | `app/checkout/success/page.tsx:5` sets `plan: "pro"` for whoever opens the URL. | Grant Pro only from a verified Stripe webhook. |
| 4 | Editing the price | Vulnerable | Critical | `app/api/checkout/route.ts:16` uses `unit_amount: price` from the request body. | Send product IDs only; use Stripe Price IDs on the server. |
| 3 | API keys in the browser | Vulnerable | Critical | `lib/ai.ts:6` reads `NEXT_PUBLIC_OPENAI_API_KEY` in a client file with `dangerouslyAllowBrowser`. | Move the OpenAI call to a route handler and rotate the key. |
| 1 | Open admin routes and endpoints | Vulnerable | Critical | `app/admin/page.tsx:6` checks the role from `localStorage`; `/api/admin/users` is outside the middleware matcher (`middleware.ts:11`); `app/actions.ts:6` deletes any project with no session check. | Check session and role inside every handler and Server Action. |
| 2 | ID swapping (IDOR) | Vulnerable | Critical | `app/api/orders/[id]/route.ts:5` loads any order by numeric ID, with no session or owner check. | Query with `{ id, userId: session.user.id }`. |
| 8 | Self-assigned admin | Vulnerable | Critical | `app/api/signup/route.ts:8` spreads the whole body into `user.create`. | Pick `email` and `password` explicitly. |
| 7 | Coupon reuse | Vulnerable | High | `app/api/coupons/redeem/route.ts:10-17` checks `used` and writes it in separate queries. | One atomic `updateMany({ where: { code, used: false } })` and check the count. |
| 5 | Negative quantities | Vulnerable | High | `app/api/checkout/route.ts:17` passes `quantity` from the body with no validation. | Validate with zod: integer, 1 to 20. |
| 17 | SSRF | Vulnerable | High | `app/api/preview/route.ts:4` fetches any `url` query param and returns the body. | Allow only http(s), block private IPs, check after redirects. |
| 11 | XSS | Vulnerable | High | `components/Comment.tsx:5` renders `body` with `dangerouslySetInnerHTML`. | Render as text, or sanitize with DOMPurify. |
| 15 | Deployment and config | Vulnerable | High | `next.config.js:3` ships source maps; `next.config.js:9-10` sets CORS `*` with credentials. | Turn off source maps, list allowed origins, add security headers. |
| 16 | Dependencies | Vulnerable | High | `package.json:6` pins `next` 14.1.0, which is affected by the middleware bypass CVE-2025-29927. | Upgrade Next.js; run `npm audit`. |
| 13 | .env in Git | Vulnerable | Medium | `.gitignore` does not list `.env*`. No env file tracked or in history. | Add `.env*` and `!.env.example`. |
| 9 | Guessing login codes | Could not verify | - | No login route in the repo. | See below. |
| 10 | Prompt injection | Could not verify | - | The AI call is client-side; prompts and tools are not in the repo. | See below. |
| 14 | SQL injection / open DB | OK | - | Only Prisma query methods, no `$queryRawUnsafe`. | - |
| 12 | Uploads | Not applicable | - | No upload feature. | - |
| 18 | Mobile | Not applicable | - | No mobile app. | - |

## How someone would abuse this

- **Free Pro plan.** Anyone can open `/checkout/success?order=<their user id>` and get Pro without paying.
- **Pay 1 cent.** The browser tells the server the price. Change `price` to `1` in the request and Stripe charges one cent.
- **Use your OpenAI key.** The key is in the JavaScript that every visitor downloads. Anyone can copy it and run up your bill.
- **Read every order.** Orders have numbers. Change `/api/orders/124` to `/api/orders/125` and you see someone else's order, without even logging in.
- **Become admin.** Add `"role": "admin"` to the sign-up request.
- **Delete other people's projects.** The `deleteProject` action can be called by anyone with any project ID.
- **Unlimited credits.** Send the same coupon 50 times at once; most requests pass before it is marked used.
- **Read internal services.** `/api/preview?url=http://169.254.169.254/latest/meta-data/` can return cloud credentials on some hosts.
- **Steal sessions with a comment.** A comment with `<img src=x onerror=...>` runs in every reader's browser, including admins.

## Could not verify

- **Check 9:** the login and password reset flow is not in this repo. Check that codes expire, have attempt limits, and that the login route is rate limited.
- **Check 10:** check the OpenAI project dashboard for usage limits, and once the call moves to the server, review the system prompt and any tools.

## Outside the code

- Rotate the OpenAI key at platform.openai.com → API keys. It has been public.
- Add a Stripe webhook endpoint and set `STRIPE_WEBHOOK_SECRET` in the hosting environment.
- Set a monthly spend limit in the OpenAI dashboard.
