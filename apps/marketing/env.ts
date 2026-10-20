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
    // Sends the /contact form through Resend. The form shows a mailto
    // fallback until the key is set.
    RESEND_API_KEY: v.optional(v.pipe(v.string(), v.minLength(1))),
    // A sender address on a domain verified in Resend.
    CONTACT_FROM_EMAIL: v.optional(
      v.pipe(v.string(), v.minLength(3)),
      "better-supabase <contact@scaledock.com>",
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
    RESEND_API_KEY: process.env["RESEND_API_KEY"],
    CONTACT_FROM_EMAIL: process.env["CONTACT_FROM_EMAIL"],
    NEXT_PUBLIC_SITE_URL: process.env["NEXT_PUBLIC_SITE_URL"],
  },
  emptyStringAsUndefined: true,
});
