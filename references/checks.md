# The 18 checks

Each check has four parts: the attack, where to look, red flags, and the fix. Code search hints use `rg` (ripgrep); fall back to `grep -rn` if it is missing.

Checks 1-14 are about the app's own logic and data. Checks 15-18 are about how it is deployed, what it depends on, and the mobile client.

---

## 1. Open admin routes and unprotected endpoints

**Attack:** Type `/admin`, `/dashboard`, `/api/admin/...` into the address bar without logging in, or as a normal user. Call API routes and Server Actions directly with `curl`, skipping the UI. Send a forged or unsigned JWT.

**Where to look:** Route folders (`app/admin`, `pages/admin`, `src/routes/admin`), API handlers under `admin`, `middleware.ts`, route guards, layout files, every file with `"use server"`, JWT helpers.

```bash
rg -n -i "admin" --glob '!node_modules' -l
rg -n "\"use server\"|'use server'" --glob '!node_modules' -l
rg -n "jwt\.decode|jwtDecode|jose\.decodeJwt|algorithms.*none|verify:\s*false" --glob '!node_modules'
rg -n "localStorage\.(setItem|getItem)\(.*(token|jwt|session)" -i --glob '!node_modules'
```

**Red flags:**
- The admin page hides its content with a client-side check only (`if (!user.isAdmin) return null`, `useEffect` redirect) while the data comes from an API that does not check the role.
- Middleware matcher does not cover the admin API routes.
- Auth is checked only in `middleware.ts` and nowhere in the route handler or page. Middleware can be skipped by a matcher gap or a framework bug (Next.js CVE-2025-29927 let attackers bypass middleware with one header on unpatched versions), so it must not be the only gate.
- A Server Action (`"use server"`) does not check the session itself. Every Server Action is a public POST endpoint, even if no button in the UI calls it.
- The JWT is decoded (`jwt.decode`, `jwtDecode`) instead of verified, or `alg: none` is accepted.
- The role is read from `localStorage`, a cookie the client can edit, or a query param.
- Session tokens are kept in `localStorage`, where any XSS can read them.

**Fix:** Check the session and the role on the server for every admin page, every admin API route and every Server Action, inside the handler itself. Keep middleware as an extra layer only, and keep the framework updated. Verify JWTs with the secret or public key and a fixed algorithm list. Return 401/403 from the API itself. Read the role from the database or a signed token, never from client input. Keep session tokens in `HttpOnly`, `Secure`, `SameSite` cookies.

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
- Webhook handler does not verify the signature with the raw body and the webhook secret: `stripe.webhooks.constructEvent` (Stripe), `validateEvent` from `@polar-sh/sdk/webhooks` (Polar), the `X-Signature` HMAC (Lemon Squeezy), or the provider's equivalent. For callback-style providers like iyzico, the server does not fetch the payment result from the provider's API with the token before marking the order paid.
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
- The model can fetch URLs or browse. Then check 17 (SSRF) applies to its tool too.

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

---

## 15. Deployment and config leaks

**Attack:** Open `https://app.com/.git/config`, `/.env`, `/_next/static/**/*.js.map`, `/api/docs`, `/graphql` with introspection, `/debug`, or trigger an error and read the stack trace. Call the API from another site and see whether the browser lets the response through (CORS). Make a logged-in user's browser send a request from a page you control (CSRF).

**Where to look:** Framework and build config (`next.config.*`, `vite.config.*`, `webpack.config.*`), server entry (`server.ts`, `app.py`, `main.go`), CORS setup, error handlers, `public/` and `static/` folders, `Dockerfile`, hosting config (`vercel.json`, `netlify.toml`, `railway.json`, `nginx.conf`), header setup.

```bash
rg -n "productionBrowserSourceMaps|sourcemap:\s*true|devtool:\s*['\"]source-map" --glob '!node_modules'
rg -n -i "access-control-allow-origin|cors\(|origin:\s*['\"]\*|origin:\s*true|allow_origins=\[\"\*\"\]|credentials:\s*true" --glob '!node_modules'
rg -n -i "debug\s*=\s*true|DEBUG=True|NODE_ENV.*development|swagger|graphiql|introspection:\s*true|err\.stack|traceback" --glob '!node_modules'
rg -n -i "content-security-policy|strict-transport-security|x-frame-options|frame-ancestors|helmet\(" --glob '!node_modules'
rg -n -i "sameSite|csrf|csurf" --glob '!node_modules'
```

**Red flags:**
- Source maps are uploaded to production (`productionBrowserSourceMaps: true`, `build.sourcemap: true`). Anyone can read the original source, including comments and internal endpoints.
- The whole project folder is served as static files (for example `express.static(".")` or a `COPY . /usr/share/nginx/html`), so `.git/` or `.env` can be downloaded.
- CORS allows any origin (`*`, `origin: true`, or reflecting the `Origin` header) together with `credentials: true`.
- Cookie-based auth with `SameSite=None` (or no SameSite) and state-changing `GET` requests or forms without a CSRF token.
- Debug mode, Swagger UI, GraphiQL or GraphQL introspection turned on in production.
- Error responses return stack traces, SQL errors or internal paths.
- No security headers: no Content Security Policy, no `Strict-Transport-Security`, no `frame-ancestors` / `X-Frame-Options` (clickjacking).

**Fix:** Turn off public source maps (upload them privately to your error tracker if you need them). Serve only the build output folder. Set CORS to an explicit list of your own origins. Use `SameSite=Lax` or `Strict` cookies and never change data with `GET`; add CSRF tokens if you must use `SameSite=None`. Turn off debug, API docs and introspection in production, or put them behind admin auth. Return generic error messages and log the details on the server. Add security headers (CSP, HSTS, `frame-ancestors 'none'`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`). Only test the live URL if the user owns it and asks for it; otherwise give them the URLs to open themselves.

---

## 16. Dependencies and hallucinated packages

**Attack:** AI assistants sometimes suggest packages that do not exist. Attackers register those names on npm / PyPI with malware inside (slopsquatting). Others publish look-alike names of popular packages (typosquatting). Old packages with known CVEs are also an easy way in.

**Where to look:** `package.json`, `requirements.txt`, `pyproject.toml`, `Pipfile`, `go.mod`, `Gemfile`, `pubspec.yaml`, `Podfile`, lockfiles, `postinstall` scripts.

```bash
# Known vulnerabilities (pick the one for the stack)
npm audit --omit=dev || pnpm audit --prod || yarn npm audit
pip-audit
# Install scripts that run code on install
rg -n "\"(pre|post)?install\"" package.json
# For each unfamiliar package: does it exist, how old is it, who owns it?
npm view <package> name time.created repository.url maintainers
pip index versions <package>
```

**Red flags:**
- A dependency you (or the AI) cannot explain: very few downloads, created in the last few months, no repository link, or a name that is one letter away from a famous package.
- A package that is imported in code but missing from `package.json` (the AI may tell the user to install it later under a wrong name).
- No lockfile committed, or dependencies pinned to `*` / `latest`.
- `npm audit` / `pip-audit` reports Critical or High issues in production dependencies.
- Unknown packages with `postinstall` scripts.

**Fix:** Remove packages that are not needed. Replace suspicious ones with the well-known package that does the same job. Commit the lockfile and install with `npm ci` / `pip install -r` from it. Upgrade packages with known Critical/High issues. Turn on Dependabot or Renovate. Never install a package only because an AI suggested it: check that it exists, who publishes it, and how long it has been around.

The secret scan cannot check this; it needs network access to the registry. Run these commands on the user's machine, or mark the check "Could not verify" and give the user the commands.

---

## 17. Making your server fetch internal URLs (SSRF)

**Attack:** Give the app a URL to fetch, for example in "import from URL", link previews, webhooks the user configures, image proxies, PDF/screenshot generators, or an AI tool that "reads a web page". Use `http://169.254.169.254/latest/meta-data/` (cloud metadata and credentials), `http://localhost:5432`, `http://10.0.0.5/admin`, or a redirect that lands on one of these.

**Where to look:** Every server-side `fetch`, `axios`, `got`, `requests`, `httpx`, `urllib`, headless browser (`puppeteer`, `playwright`) call where any part of the URL comes from the user or from model output.

```bash
rg -n "fetch\(|axios\.(get|post)|got\(|requests\.(get|post)|httpx\.|urlopen|page\.goto\(" --glob '!node_modules'
```

**Red flags:**
- The URL comes from the request body, query or an AI tool argument and is fetched as is.
- Only the hostname string is checked (for example "does not contain localhost"), not the resolved IP.
- Redirects are followed automatically after the check.
- The response body is sent back to the user in full.

**Fix:** Allow only `http`/`https`. Resolve the hostname and block private, loopback, link-local and metadata ranges (`127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `::1`, `fc00::/7`), and check again after each redirect (or turn redirects off). Use an allowlist of domains when the feature allows it. Set timeouts and a response size limit. Run fetchers without cloud credentials attached where possible.

---

## 18. Mobile app trusts the device

**Attack:** Unzip the IPA / APK and read the JS bundle or config files. Read tokens from the device storage on a rooted / jailbroken phone or a backup. Open the app with a crafted deep link (`myapp://reset?token=...`, `myapp://open?url=https://evil.com`). Watch traffic with a proxy.

**Where to look:** React Native / Expo / Flutter / native source, `app.json`, `app.config.*`, `Info.plist`, `AndroidManifest.xml`, deep link and universal link handlers, token storage code, network config.

```bash
rg -n "AsyncStorage\.(setItem|getItem)|SharedPreferences|UserDefaults|MMKV" --glob '!node_modules'
rg -n "SecureStore|Keychain|EncryptedSharedPreferences|flutter_secure_storage" --glob '!node_modules'
rg -n -i "Linking\.(addEventListener|getInitialURL)|useURL|onOpenURL|intent-filter|CFBundleURLSchemes|associatedDomains" --glob '!node_modules'
rg -n -i "NSAllowsArbitraryLoads|usesCleartextTraffic|cleartextTrafficPermitted" --glob '!node_modules'
```

**Red flags:**
- Secret keys in the app bundle or `app.json` `extra` (see check 3; anything shipped in the app is public).
- Session or refresh tokens saved with `AsyncStorage`, `SharedPreferences`, `UserDefaults` or plain MMKV.
- A deep link handler that logs the user in, resets a password, opens any URL in a WebView, or performs an action without checking the parameters.
- Custom URL schemes used for login or payment callbacks instead of universal links / app links (another app can register the same scheme).
- Cleartext HTTP allowed (`NSAllowsArbitraryLoads`, `usesCleartextTraffic="true"`).
- Premium features unlocked only by a flag on the device (see check 6 for receipt validation).
- Biometric login that only checks "did Face ID succeed" on the device and then uses a stored password.

**Fix:** Keep secrets on the server. Store tokens in the Keychain / Keystore (`expo-secure-store`, `react-native-keychain`, `flutter_secure_storage`). Treat every deep link parameter as untrusted input: validate it, require the user to be logged in, ask for confirmation before actions, and open only allowlisted domains in WebViews. Use universal links / app links for auth and payment callbacks. Turn off cleartext traffic. Check entitlements on the server on every request, and tie biometric unlock to a Keychain item protected by biometrics instead of a simple yes/no check.
