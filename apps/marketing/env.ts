import { createEnv } from "@t3-oss/env-nextjs";
import * as v from "valibot";

export const env = createEnv({
  shared: {
    NODE_ENV: v.optional(
      v.picklist(["development", "test", "production"]),
      "development",
    ),
  },
  server: {
    // In development the docs app runs on its own port; in production Vercel
    // Services routes /docs to it and this is unused.
    DOCS_ORIGIN: v.optional(
      v.pipe(v.string(), v.url()),
      "http://127.0.0.1:3001",
    ),
    // The Supabase OAuth app behind "Deploy to Supabase" on /create. The
    // button hides until all three are set.
    SUPABASE_OAUTH_CLIENT_ID: v.optional(v.pipe(v.string(), v.minLength(1))),
    SUPABASE_OAUTH_CLIENT_SECRET: v.optional(
      v.pipe(v.string(), v.minLength(1)),
    ),
    // Encrypts the Supabase tokens in the session cookie.
    SUPABASE_OAUTH_COOKIE_SECRET: v.optional(
      v.pipe(v.string(), v.minLength(32)),
    ),
  },
  client: {
    NEXT_PUBLIC_SITE_URL: v.optional(
      v.pipe(v.string(), v.url()),
      "https://bettersupabase.com",
    ),
  },
  runtimeEnv: {
    NODE_ENV: process.env.NODE_ENV,
    DOCS_ORIGIN: process.env["DOCS_ORIGIN"],
    SUPABASE_OAUTH_CLIENT_ID: process.env["SUPABASE_OAUTH_CLIENT_ID"],
    SUPABASE_OAUTH_CLIENT_SECRET: process.env["SUPABASE_OAUTH_CLIENT_SECRET"],
    SUPABASE_OAUTH_COOKIE_SECRET: process.env["SUPABASE_OAUTH_COOKIE_SECRET"],
    NEXT_PUBLIC_SITE_URL: process.env["NEXT_PUBLIC_SITE_URL"],
  },
  emptyStringAsUndefined: true,
});
