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
    // Ask AI calls the Vercel AI Gateway. On Vercel the OIDC token
    // authenticates it; elsewhere the route answers 503 without this key.
    AI_GATEWAY_API_KEY: v.optional(v.string()),
    VERCEL_OIDC_TOKEN: v.optional(v.string()),
  },
  client: {
    NEXT_PUBLIC_SITE_URL: v.optional(
      v.pipe(v.string(), v.url()),
      "https://bettersupabase.com",
    ),
  },
  runtimeEnv: {
    NODE_ENV: process.env.NODE_ENV,
    AI_GATEWAY_API_KEY: process.env["AI_GATEWAY_API_KEY"],
    VERCEL_OIDC_TOKEN: process.env["VERCEL_OIDC_TOKEN"],
    NEXT_PUBLIC_SITE_URL: process.env["NEXT_PUBLIC_SITE_URL"],
  },
  emptyStringAsUndefined: true,
});
