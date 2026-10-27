import { createEnv } from "@t3-oss/env-nextjs";
import * as v from "valibot";

const flag = v.optional(v.picklist(["0", "1"]), "0");

/**
 * Every environment key the app reads. Next inlines `NEXT_PUBLIC_*` only for
 * the literal `process.env.NAME` reads in `runtimeEnv`, and `typedEnv` checks
 * the `.env*` files against what Next loads.
 */
// Destructured: typedEnv declares only the keys in local env files, in dev, so
// neither dot nor bracket access lints the same in every checkout.
const {
  EXPOSE_TESTING_API,
  SUPABASE_SECRET_KEY,
  FLAGS_SECRET,
  CRON_SECRET,
  AI_GATEWAY_API_KEY,
  WORKFLOW_POSTGRES_URL,
  PDL_API_KEY,
  JOBS_BACKEND,
} = process.env;

export const env = createEnv({
  shared: {
    NODE_ENV: v.optional(
      v.picklist(["development", "test", "production"]),
      "development",
    ),
    // `1` in a testing build: the testing API and Server-Timing.
    EXPOSE_TESTING_API: flag,
  },
  server: {
    // Server-only: account deletion, the shared plan catalog and SSO setup.
    SUPABASE_SECRET_KEY: v.optional(v.string()),
    // Signs the precomputed pricing flags and guards Flags Explorer.
    FLAGS_SECRET: v.optional(v.string()),
    // The bearer token the cron routes check.
    CRON_SECRET: v.optional(v.string()),
    // The assistant and chat summaries answer with a scripted model without it.
    AI_GATEWAY_API_KEY: v.optional(v.string()),
    WORKFLOW_POSTGRES_URL: v.optional(v.string()),
    // The People Data Labs key the enrichment provider uses.
    PDL_API_KEY: v.optional(v.string()),
    // `vercel` sends the settings page's test jobs to Vercel Queues.
    JOBS_BACKEND: v.optional(v.picklist(["sql", "vercel"]), "sql"),
  },
  client: {
    NEXT_PUBLIC_SUPABASE_URL: v.pipe(v.string(), v.url()),
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: v.pipe(v.string(), v.minLength(1)),
    // The VAPID public key for web push; the push card hides without it.
    NEXT_PUBLIC_VAPID_PUBLIC_KEY: v.optional(v.string()),
  },
  runtimeEnv: {
    NODE_ENV: process.env.NODE_ENV,
    EXPOSE_TESTING_API,
    SUPABASE_SECRET_KEY,
    FLAGS_SECRET,
    CRON_SECRET,
    AI_GATEWAY_API_KEY,
    WORKFLOW_POSTGRES_URL,
    PDL_API_KEY,
    JOBS_BACKEND,
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
      process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    NEXT_PUBLIC_VAPID_PUBLIC_KEY: process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY,
  },
  emptyStringAsUndefined: true,
});
