import type { ServerContext } from "better-supabase/server";

import { createBrowserClient } from "@supabase/ssr";
import { defineSupabase } from "better-supabase";
import { createClient } from "better-supabase/client";
import { createEdge } from "better-supabase/edge";
import {
  type BetterSupabaseEnv,
  envSchema,
  type PublicEnv,
} from "better-supabase/env";

import { type Functions, type Models, schema } from "./generated.ts";

export const betterSupabase = defineSupabase(schema);

export const supabaseServerEnv = envSchema({ require: ["secretKey"] });
export const supabaseClientEnv = envSchema();

export type Channel = "web" | "mobile" | "cron" | "worker";

/** Headers the app stamps on every outbound Supabase request, for logs and rate limits. */
export function appRequestHeaders(
  request: Request,
  channel: Channel,
): Record<string, string> {
  const headers = {
    "x-app-channel": channel,
    "x-request-id": request.headers.get("x-request-id") ?? crypto.randomUUID(),
  };
  const ip = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return ip ? { ...headers, "x-client-ip": ip } : headers;
}

export function createAppServer(env: BetterSupabaseEnv, channel: Channel) {
  return createEdge(betterSupabase, {
    env,
    headers: (request) => appRequestHeaders(request, channel),
    auth: { secret: ["cron"] },
  });
}

export type AppServer = ReturnType<typeof createAppServer>;
export type AppContext = ServerContext<Models, Functions, unknown>;
type AppHandler = Parameters<AppServer["handler"]>[0];

/** Signed-in users only; refreshes an expiring cookie session and sends the new cookies. */
export function withUserAuth(
  server: AppServer,
  handler: AppHandler,
): (request: Request) => Promise<Response> {
  return server.handler(handler, { refresh: true });
}

/** Callers holding the `cron` secret key only. */
export function withCron(
  server: AppServer,
  handler: AppHandler,
): (request: Request) => Promise<Response> {
  return server.handler(handler, { allow: ["service"] });
}

export function createAppBrowser(env: PublicEnv) {
  return createClient(betterSupabase, {
    // oxlint-disable-next-line typescript/no-unsafe-assignment -- supabase-js infers `any` for the schema name without a Database type.
    client: createBrowserClient(env.url, env.publishableKey, {
      global: { headers: { "x-app-channel": "web" } },
    }),
  });
}
