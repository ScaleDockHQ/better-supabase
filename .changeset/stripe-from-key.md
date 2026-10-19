---
"better-supabase": minor
---

New `better-supabase/stripe` entry with `stripeFromKey({ secretKey, apiVersion })`. It returns a `stripe` source for `createBilling`, `reportUsageToStripe`, `stripePayments` and `stripeTax` that creates the client once, on first use, from a literal `import("stripe")`, so Next.js, Vite and worker bundlers resolve the package and file tracing ships it. `stripe` stays an optional peer.

Bundled apps that passed `stripe: { secretKey }` got an empty module, because the loader's `import(specifier)` was too dynamic for the bundler, and every Stripe call threw that the stripe package was missing even when it was installed. The optional peer loader now carries `webpackIgnore` and `@vite-ignore` comments, so bundlers leave a native import that resolves in Node, Bun, Deno and apps that keep the package external, and the error names the fix: pass `stripe: stripeFromKey({ secretKey })` from `better-supabase/stripe`, or a Stripe client. `{ secretKey }` keeps working as the plain Node shortcut.
