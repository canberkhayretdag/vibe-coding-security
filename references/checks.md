# The 14 checks

Each check has four parts: the attack, where to look, red flags, and the fix. Code search hints use `rg` (ripgrep); fall back to `grep -rn` if it is missing.

---

## 1. Open admin routes

**Attack:** Type `/admin`, `/dashboard`, `/api/admin/...` into the address bar without logging in, or as a normal user.

**Where to look:** Route folders (`app/admin`, `pages/admin`, `src/routes/admin`), API handlers under `admin`, `middleware.ts`, route guards, layout files.

```bash
rg -n -i "admin" --glob '!node_modules' -l
```

**Red flags:**
- The admin page hides its content with a client-side check only (`if (!user.isAdmin) return null`, `useEffect` redirect) while the data comes from an API that does not check the role.
- Middleware matcher does not cover the admin API routes.
- The role is read from `localStorage`, a cookie the client can edit, or a query param.

**Fix:** Check the session and the role on the server for every admin page and every admin API route. Return 401/403 from the API itself. Read the role from the database or a signed token, never from client input.

---

## 2. Changing the ID in the URL (IDOR)

**Attack:** Open `/orders/123`, change it to `/orders/124`, and see someone else's order. Same for API calls like `GET /api/invoices?id=124` or `PATCH /api/users/124`.

**Where to look:** Every route or server action that takes an `id`, `userId`, `orderId`, `slug` from the URL, query or body.

```bash
rg -n "params\.(id|userId)|searchParams\.get\(|req\.query|req\.params|findUnique|findFirst|\.eq\(\"id\"" --glob '!node_modules'
```

**Red flags:**
- `db.order.findUnique({ where: { id } })` with no `userId` / owner condition.
- The `userId` comes from the request body instead of the session.
- Supabase/Firebase queries from the client with no RLS / security rules on the table.
- Sequential numeric IDs on sensitive objects.

**Fix:** Scope every query by the logged-in user: `where: { id, userId: session.user.id }`. Take the user ID from the session only. Use RLS (Supabase) or security rules (Firebase) that compare the owner column with `auth.uid()`. Random IDs (UUID) help but do not replace the ownership check.

---

## 3. API keys visible in the browser

**Attack:** Open DevTools → Sources or Network, search the JS bundle for `sk_`, `key`, `secret`, copy the key and use it directly.

**Where to look:** Client components, files under `src/` that run in the browser, env variables with a public prefix, mobile app config.

```bash
rg -n "NEXT_PUBLIC_|VITE_|EXPO_PUBLIC_|REACT_APP_" --glob '!node_modules'
rg -n "sk_live|sk_test|sk-[A-Za-z0-9]|service_role|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}" --glob '!node_modules'
```

**Red flags:**
- OpenAI / Anthropic / Stripe secret / Supabase `service_role` / Resend / Twilio keys in a public env variable or a client file.
- The frontend calls a paid API (OpenAI, ElevenLabs...) directly from the browser.
- Keys hardcoded in a mobile app (they can be extracted from the bundle).

**Fix:** Move the call to the server (API route, server action, edge function) and keep the key in a non-public env variable. Only publishable keys meant for the client may stay (Stripe `pk_`, Supabase `anon` key, Firebase web config), and those are safe only when RLS / security rules are on. Rotate every key that was ever shipped to the browser.

---

## 4. Editing the price

**Attack:** Change the price in the request body (`{"price": 1}`) or in the hidden form field, then check out.

**Where to look:** Checkout, cart, order creation, Stripe Checkout session creation, in-app credit purchase.

```bash
rg -n "price|amount|total|unit_amount" --glob '!node_modules' --glob '!*.lock'
```

**Red flags:**
- `stripe.checkout.sessions.create({ line_items: [{ price_data: { unit_amount: body.price } }] })`
- Order total calculated in the browser and saved as is.
- Discount percentage sent from the client.

**Fix:** The client sends only product IDs and quantities. The server loads prices from the database or uses Stripe Price IDs, applies discounts itself, and calculates the total.

---

## 5. Ordering -1 items

**Attack:** Send `quantity: -1`, `0`, `0.5`, `999999999` or a string. A negative quantity can turn the total negative, give credits back, or break stock.

**Where to look:** The same handlers as check 4, plus credit/balance transfers, stock updates, any numeric input.

**Red flags:**
- No validation schema on the request body.
- `parseInt` / `Number()` without range checks.
- Balance updated with `balance + amount` where `amount` comes from the client.

**Fix:** Validate every input on the server with a schema (zod, valibot, pydantic, Joi): integer, minimum 1, a sensible maximum. Add database constraints (`CHECK (quantity > 0)`, `CHECK (balance >= 0)`).

---

## 6. Fake payments

**Attack:** Skip the payment page and open the success URL directly (`/checkout/success?order=123`), or send a fake webhook to `/api/webhooks/stripe`.

**Where to look:** Success/thank-you pages, webhook handlers, code that sets `paid = true`, `plan = "pro"`, adds credits.

```bash
rg -n -i "webhook|constructEvent|success|paid|isPro|plan\s*=" --glob '!node_modules'
```

**Red flags:**
- The success page marks the order as paid or upgrades the user.
- Webhook handler does not verify the signature (`stripe.webhooks.constructEvent` with the raw body and the webhook secret, or the provider's equivalent).
- The client tells the server "payment done" and the server believes it.
- Mobile in-app purchases unlocked on the device without server-side receipt validation.

**Fix:** Grant access only from a verified webhook (or by fetching the session/payment from the provider's API on the server). Verify the signature with the raw body. Make the handler idempotent: store the event ID and ignore duplicates.

---

## 7. Redeeming the same thing 100 times

**Attack:** Use the same coupon, referral bonus, free trial or one-time credit again and again, or send 100 requests at the same moment so they all pass the "already used?" check.

**Where to look:** Coupon/promo code logic, referral rewards, trial creation, daily free credits, gift cards.

**Red flags:**
- "Check if used, then mark as used" in two separate queries with no transaction or lock.
- Usage tracked only in the browser (`localStorage`).
- Trial tied to email only, so `+1` aliases get new trials.

**Fix:** Store each redemption in a table with a unique constraint (`UNIQUE (coupon_id, user_id)`). Do the check and the write in one atomic step: a transaction, `UPDATE ... WHERE used = false RETURNING`, or an `INSERT` that fails on conflict. Add per-user limits on the server.

---

## 8. Making yourself admin at sign-up

**Attack:** Add `"role": "admin"` or `"isAdmin": true` to the sign-up or profile update request.

**Where to look:** Sign-up handlers, profile update routes, `user_metadata` writes, ORM `create` / `update` calls that pass the whole body.

```bash
rg -n "\.\.\.(req\.)?body|data:\s*(req\.)?body|role|isAdmin|is_admin|user_metadata" --glob '!node_modules'
```

**Red flags:**
- `db.user.update({ where: { id }, data: req.body })` (mass assignment).
- Role stored in Supabase `user_metadata` (users can edit it themselves) instead of `app_metadata` or a separate table.
- RLS policy lets users update their own row including the `role` column.

**Fix:** Whitelist the fields a user may change (pick them explicitly or use a schema). Keep roles in a place users cannot write: a separate `roles` table, `app_metadata`, or custom claims set by the server. In RLS, block updates to the role column.

---

## 9. Guessing the login code

**Attack:** Try all 6-digit codes (1,000,000 options) on the OTP / magic code / password reset endpoint, or brute force passwords.

**Where to look:** OTP verification, password reset, 2FA, invite codes, login routes.

**Red flags:**
- No rate limit per user, per IP, per code.
- Codes that never expire or stay valid after use.
- Short codes (4 digits) or codes made with `Math.random()`.
- The error message tells whether the email exists.

**Fix:** Limit attempts (for example 5 tries, then the code is burned) and rate limit by IP and account. Expire codes in 10-15 minutes and delete them after use. Generate codes with a crypto-secure function (`crypto.randomInt`, `secrets`). Use the auth provider's built-in limits where possible and make sure they are on.

---

## 10. Telling your AI to ignore its instructions (prompt injection)

**Attack:** Write "Ignore previous instructions and..." into the chat, a profile field, an uploaded document or a web page the AI reads. Goals: read the system prompt, get other users' data, make the AI call a tool it should not, or burn your API credits.

**Where to look:** Every LLM call, the system prompt, tools/functions the model can call, data the model reads (RAG, user content, URLs).

**Red flags:**
- The model has tools that write data, send email, or run queries with admin rights.
- Tool calls use the server's privileges instead of the current user's.
- Secrets or other users' data inside the system prompt.
- No per-user limit on AI requests, no `max_tokens`.

**Fix:** Treat model output as untrusted input. Run tools with the logged-in user's permissions and check ownership inside each tool (same rule as check 2). Keep secrets out of prompts. Ask the user to confirm destructive actions. Add per-user rate limits and spending caps on the provider dashboard.

---

## 11. A script in the username (XSS)

**Attack:** Set the username to `<img src=x onerror=alert(document.cookie)>` or `<script>...</script>`. When another user or the admin sees it, the code runs in their browser.

**Where to look:** Any place user text is rendered: names, comments, bios, chat messages, markdown, admin tables, emails.

```bash
rg -n "dangerouslySetInnerHTML|innerHTML|v-html|\{@html|html_safe|\|safe|marked\(|bypassSecurityTrust" --glob '!node_modules'
```

**Red flags:**
- `dangerouslySetInnerHTML` / `v-html` / `{@html}` with user content.
- Markdown rendered to HTML without a sanitizer.
- User-provided URLs used in `href` without blocking `javascript:`.

**Fix:** Let the framework escape text (plain `{value}` in React). When HTML is really needed, sanitize it with DOMPurify (or the server-side equivalent). Allow only `http(s)` links. Add a Content Security Policy header. Keep auth cookies `HttpOnly`.

---

## 12. Uploading something that is not a photo

**Attack:** Upload an `.html`, `.svg` with a script, `.php`, or a 2 GB file to the "profile photo" field. Then open its URL.

**Where to look:** Upload handlers, storage bucket config (S3, Supabase Storage, Firebase Storage, Cloudinary), signed URL generation.

**Red flags:**
- File type checked only by the extension or the browser's `accept` attribute.
- SVG and HTML allowed in a public bucket served from the app's own domain.
- No size limit.
- Public buckets with listing enabled, or uploads where users can overwrite others' files.

**Fix:** On the server, check the real file type from its content (magic bytes), allow a short list (jpg, png, webp), and set a size limit. Re-encode images or strip metadata if possible. Store uploads on a separate domain or bucket, never in a folder the server executes. Name files with random IDs and scope storage rules to the owner.

---

## 13. Finding your .env in Git

**Attack:** Clone the public repo (or a leaked one) and read `.env`, or look through Git history where it was committed once and deleted later.

**Where to look:** Run `scripts/find_secrets.sh`. Also check `.gitignore`, `docker-compose.yml`, CI config, `config/*.json`, mobile config files.

**Red flags:**
- `.env`, `.env.local`, `.env.production` tracked by Git.
- `.env` appears in history even if it is gone now.
- `.gitignore` does not list `.env*`.
- Real keys inside `.env.example`.

**Fix:** Add `.env*` (except `.env.example`) to `.gitignore` and run `git rm --cached` on tracked env files. Any key that was ever committed is compromised: rotate it at the provider. Cleaning history (`git filter-repo`, BFG) is optional after rotation, rotation is not.

---

## 14. Typing a query into your database

**Attack:** Two versions. (a) SQL injection: put `' OR 1=1 --` into a search box or filter. (b) Open database: use the public Supabase/Firebase config from the browser to query tables directly, because no rules block it.

**Where to look:** Raw SQL, string-built queries, ORM raw methods, Supabase/Firebase client usage, RLS policies and security rules in migrations or config.

```bash
rg -n "\$queryRawUnsafe|\$executeRawUnsafe|\.raw\(|query\(\`|execute\(f\"|\" \+ |sql\`" --glob '!node_modules'
rg -n -i "enable row level security|create policy|allow read, write: if true" --glob '!node_modules'
```

**Red flags:**
- Queries built with string concatenation or template strings that include user input.
- `$queryRawUnsafe` / `.raw()` with user input.
- Supabase tables without `ENABLE ROW LEVEL SECURITY`, or policies like `USING (true)`.
- Firebase rules `allow read, write: if true;` or test-mode rules left on.
- Database port open to the internet with a default password.

**Fix:** Use parameterized queries or the ORM's safe methods everywhere. Turn on RLS for every table in Supabase and write owner-based policies. Replace Firebase test rules with auth-based rules. Keep the database off the public internet and use strong credentials.
