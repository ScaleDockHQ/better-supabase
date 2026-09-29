import type { ServerContext } from 'better-supabase/server';

import { createBrowserClient } from '@supabase/ssr';
import { defineSupabase } from 'better-supabase';
import { createBrowser } from 'better-supabase/client';
import { createEdge } from 'better-supabase/edge';
import {
  type BetterSupabaseEnv,
  envSchema,
  type PublicEnv,
} from 'better-supabase/env';

import { type Functions, type Models, schema } from './generated.ts';

export const sb = defineSupabase(schema);

export const supabaseServerEnv = envSchema({ require: ['secretKey'] });
export const supabaseClientEnv = envSchema();

export type Channel = 'web' | 'mobile' | 'cron' | 'worker';

/** Headers the app stamps on every outbound Supabase request, for logs and rate limits. */
export function appRequestHeaders(
  request: Request,
  channel: Channel,
): Record<string, string> {
  const headers: Record<string, string> = {
    'x-app-channel': channel,
    'x-request-id': request.headers.get('x-request-id') ?? crypto.randomUUID(),
  };
  const ip = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim();
  if (ip) headers['x-client-ip'] = ip;
  return headers;
}

export function createAppServer(env: BetterSupabaseEnv, channel: Channel) {
  return createEdge(sb, {
    env,
    headers: (request) => appRequestHeaders(request, channel),
    auth: { secret: ['cron'] },
  });
}

export type AppServer = ReturnType<typeof createAppServer>;
export type AppContext = ServerContext<Models, Functions, unknown>;

/** Signed-in users only; refreshes an expiring cookie session and sends the new cookies. */
export function withUserAuth(
  server: AppServer,
  handler: (request: Request, ctx: AppContext) => unknown,
): (request: Request) => Promise<Response> {
  return server.handler(handler, { refresh: true });
}

/** Callers holding the `cron` secret key only. */
export function withCron(
  server: AppServer,
  handler: (request: Request, ctx: AppContext) => unknown,
): (request: Request) => Promise<Response> {
  return server.handler(handler, { allow: ['service'] });
}

export function createAppBrowser(env: PublicEnv) {
  return createBrowser(sb, {
    client: createBrowserClient(env.url, env.publishableKey, {
      global: { headers: { 'x-app-channel': 'web' } },
    }),
  });
}
