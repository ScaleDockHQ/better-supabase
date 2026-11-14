import { createEnv } from "@t3-oss/env-nextjs";
import * as v from "valibot";

import { publicEnv } from "./env-public";

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
  SUPABASE_JWKS,
  FLAGS_SECRET,
  CRON_SECRET,
  VERCEL_MARKETPLACE_CLIENT_ID,
  VERCEL_MARKETPLACE_CLIENT_SECRET,
  AI_GATEWAY_API_KEY,
  WORKFLOW_POSTGRES_URL,
  PDL_API_KEY,
  JOBS_BACKEND,
  JOBS_SCHEDULER,
  ASSISTANT_SANDBOX,
  CONNECT_GMAIL_CONNECTOR,
  CONNECT_OUTLOOK_CONNECTOR,
  BSB_REMOTE_CACHE_DIR,
  STRIPE_SECRET_KEY,
  STRIPE_WEBHOOK_SECRET,
  STRIPE_PRICE_PRO,
  STRIPE_PRICE_ENTERPRISE,
  DATABASE_URL,
  WHATSAPP_APP_SECRET,
  WHATSAPP_VERIFY_TOKEN,
  SLACK_SIGNING_SECRET,
} = process.env;

export const env = createEnv({
  extends: [publicEnv],
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
    // The signing keys inline; createServer reads it through loadEnv, which
    // checks the shape.
    SUPABASE_JWKS: v.optional(v.string()),
    // Signs the precomputed pricing flags and guards Flags Explorer.
    FLAGS_SECRET: v.optional(v.string()),
    // The bearer token the cron routes check.
    CRON_SECRET: v.optional(v.string()),
    // The Vercel Marketplace integration the `vercel-marketplace` block serves; server-only.
    VERCEL_MARKETPLACE_CLIENT_ID: v.optional(v.string()),
    VERCEL_MARKETPLACE_CLIENT_SECRET: v.optional(v.string()),
    // The assistant and chat summaries answer with a scripted model without it.
    AI_GATEWAY_API_KEY: v.optional(v.string()),
    WORKFLOW_POSTGRES_URL: v.optional(v.string()),
    // The People Data Labs key the enrichment provider uses.
    PDL_API_KEY: v.optional(v.string()),
    // `vercel` sends the settings page's test jobs to Vercel Queues.
    JOBS_BACKEND: v.optional(v.picklist(["sql", "vercel"]), "sql"),
    // `vercel` runs the block timers from the schedules in `vercel.json`
    // through the bridge route, on Supabase Queues.
    JOBS_SCHEDULER: v.optional(v.picklist(["supabase", "vercel"]), "supabase"),
    // `vercel` gives the assistant a Vercel sandbox per chat to run code in.
    ASSISTANT_SANDBOX: v.optional(v.picklist(["off", "vercel"]), "off"),
    // Vercel Connect connector UIDs; the Integrations tab lists each one set.
    CONNECT_GMAIL_CONNECTOR: v.optional(v.string()),
    CONNECT_OUTLOOK_CONNECTOR: v.optional(v.string()),
    // The directory cache-handlers/shared-remote.ts keeps remote entries in;
    // next.config.ts reads it directly, since the handler is set at build.
    BSB_REMOTE_CACHE_DIR: v.optional(v.string()),
    // The billing block's Stripe calls and webhook; the billing screens read
    // without them, Checkout, the portal and seat sync need them.
    STRIPE_SECRET_KEY: v.optional(v.string()),
    STRIPE_WEBHOOK_SECRET: v.optional(v.string()),
    // The test-mode Stripe price ids of the paid plans in `public.plans`; the plan picker
    // starts Checkout for a plan whose price is set.
    STRIPE_PRICE_PRO: v.optional(v.string()),
    STRIPE_PRICE_ENTERPRISE: v.optional(v.string()),
    // The Postgres connection the queue drain and Stripe processing routes use.
    DATABASE_URL: v.optional(v.string()),
    // The channel webhooks (`/api/webhooks/channels/<adapter>`) answer 503
    // without the platform's secret: Meta's app secret and the verify token
    // for the GET handshake, and Slack's signing secret.
    WHATSAPP_APP_SECRET: v.optional(v.string()),
    WHATSAPP_VERIFY_TOKEN: v.optional(v.string()),
    SLACK_SIGNING_SECRET: v.optional(v.string()),
  },
  runtimeEnv: {
    NODE_ENV: process.env.NODE_ENV,
    EXPOSE_TESTING_API,
    SUPABASE_SECRET_KEY,
    SUPABASE_JWKS,
    FLAGS_SECRET,
    CRON_SECRET,
    VERCEL_MARKETPLACE_CLIENT_ID,
    VERCEL_MARKETPLACE_CLIENT_SECRET,
    AI_GATEWAY_API_KEY,
    WORKFLOW_POSTGRES_URL,
    PDL_API_KEY,
    JOBS_BACKEND,
    JOBS_SCHEDULER,
    ASSISTANT_SANDBOX,
    CONNECT_GMAIL_CONNECTOR,
    CONNECT_OUTLOOK_CONNECTOR,
    BSB_REMOTE_CACHE_DIR,
    STRIPE_SECRET_KEY,
    STRIPE_WEBHOOK_SECRET,
    STRIPE_PRICE_PRO,
    STRIPE_PRICE_ENTERPRISE,
    DATABASE_URL,
    WHATSAPP_APP_SECRET,
    WHATSAPP_VERIFY_TOKEN,
    SLACK_SIGNING_SECRET,
  },
  emptyStringAsUndefined: true,
});
