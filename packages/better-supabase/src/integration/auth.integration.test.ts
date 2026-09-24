import { pipeline } from '@supabase/middleware';
import { withSupabase } from '@supabase/server';
import { withPostgresClient } from '@supabase/server/middleware/postgres';
import { createServerClient } from '@supabase/ssr';
import { createClient } from '@supabase/supabase-js';
import { QueryClient } from '@tanstack/react-query';
import { afterAll, describe, expect, it, vi } from 'vitest';

import { resolveAuth } from '../auth/resolve.ts';
import {
  readSession,
  sessionCookieName,
  type CookieRecord,
  writeSession,
} from '../auth/session.ts';
import { createBrowser } from '../client/index.ts';
import { defineSupabase } from '../core/define.ts';
import { parseEnv } from '../env/index.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { tenant } from '../plugins/tenant/index.ts';
import { createPostgres } from '../postgres/pool.ts';
import {
  withBetterPostgres,
  withBetterSupabase,
} from '../server/middleware.ts';
import { createServer } from '../server/server.ts';

const url = process.env['SUPABASE_URL'] ?? 'http://127.0.0.1:55421';
const dbUrl =
  process.env['SUPABASE_DB_URL'] ??
  'postgresql://postgres:postgres@127.0.0.1:55422/postgres';
const publishableKey =
  process.env['SUPABASE_PUBLISHABLE_KEY'] ??
  'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
const secretKey =
  process.env['SUPABASE_SECRET_KEY'] ??
  'sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz';
const ACME = '00000000-0000-4000-8000-000000000001';

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/auth/v1/health`, {
      headers: { apikey: publishableKey },
      signal: AbortSignal.timeout(1000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

const live = await reachable();

describe.skipIf(!live)('auth against the local stack', async () => {
  const env = parseEnv({
    SUPABASE_URL: url,
    SUPABASE_PUBLISHABLE_KEY: publishableKey,
    SUPABASE_SECRET_KEY: secretKey,
    SUPABASE_DB_URL: dbUrl,
  }).env!;
  const admin = createClient(url, secretKey, {
    auth: { persistSession: false },
  });
  const email = `auth-${crypto.randomUUID()}@example.com`;
  const password = 'correct horse battery staple';
  const { data: created, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: { org_id: ACME },
  });
  if (error) throw error;
  const userId = created.user.id;
  const postgres = createPostgres({ connectionString: dbUrl, max: 2 });

  afterAll(async () => {
    await admin.auth.admin.deleteUser(userId);
    await postgres.end();
  });

  const name = sessionCookieName(url);

  async function signInCookies(): Promise<CookieRecord[]> {
    let jar: CookieRecord[] = [];
    const client = createServerClient(url, publishableKey, {
      cookies: {
        getAll: () => jar,
        setAll: (cookies) => {
          jar = writeSessionJar(jar, cookies);
        },
      },
    });
    const { error: signInError } = await client.auth.signInWithPassword({
      email,
      password,
    });
    if (signInError) throw signInError;
    return jar;
  }

  function writeSessionJar(
    jar: CookieRecord[],
    cookies: { name: string; value: string; options: { maxAge?: number } }[],
  ): CookieRecord[] {
    const next = new Map(jar.map((cookie) => [cookie.name, cookie.value]));
    for (const cookie of cookies) {
      if (cookie.options.maxAge === 0 || cookie.value === '')
        next.delete(cookie.name);
      else next.set(cookie.name, cookie.value);
    }
    return [...next].map(([cookieName, value]) => ({
      name: cookieName,
      value,
    }));
  }

  const toRequest = (cookies: readonly CookieRecord[]) =>
    new Request('http://app.test/', {
      headers: {
        cookie: cookies
          .map((cookie) => `${cookie.name}=${encodeURIComponent(cookie.value)}`)
          .join('; '),
      },
    });

  it('reads sessions written by @supabase/ssr and verifies them against the JWKS', async () => {
    const cookies = await signInCookies();
    expect(readSession(cookies, name)?.user).toMatchObject({ email });
    const { auth, cookies: writes } = await resolveAuth(toRequest(cookies), {
      env,
    });
    expect(auth).toMatchObject({
      kind: 'user',
      source: 'cookie',
      user: { id: userId, email },
    });
    expect(writes).toEqual([]);
  });

  it('refreshes an expiring session with the real refresh token', async () => {
    const cookies = await signInCookies();
    const session = readSession(cookies, name)!;
    const expiring = writeSession(cookies, name, {
      ...session,
      expires_at: Math.floor(Date.now() / 1000) + 5,
    });
    const jar = expiring
      .map(({ name: cookieName, value }) => ({ name: cookieName, value }))
      .filter((cookie) => cookie.value);
    const resolution = await resolveAuth(toRequest(jar), {
      env,
      refresh: true,
    });
    expect(resolution.auth).toMatchObject({
      kind: 'user',
      user: { id: userId },
    });
    const refreshed = readSession(resolution.requestCookies, name)!;
    expect(refreshed.refresh_token).not.toBe(session.refresh_token);
    expect(resolution.headers['Cache-Control']).toContain('no-store');
  });

  it('binds repositories to the caller through createServer', async () => {
    const sb = defineSupabase(schema).use(tenant());
    const server = createServer(sb, { env, postgres });
    const cookies = await signInCookies();
    const ctx = await server.context(toRequest(cookies));
    expect(ctx.auth.kind).toBe('user');
    const viaRest = await ctx.db.customers
      .findMany({ select: ['name'], orderBy: { name: 'asc' } })
      .orThrow();
    const viaSql = await ctx
      .sql!.customers.findMany({ select: ['name'], orderBy: { name: 'asc' } })
      .orThrow();
    expect(viaSql).toEqual(viaRest);
    expect(viaRest.length).toBeGreaterThan(0);

    const acting = await server
      .actingAs(userId, { org_id: ACME })
      .customers.count()
      .orThrow();
    expect(acting).toBe(viaRest.length);
    const all = await server
      .admin({ tenant: ACME })
      .customers.count({ allTenants: true } as never)
      .orThrow();
    expect(all).toBeGreaterThanOrEqual(acting);
  });

  it('follows the session in the browser client', async () => {
    const sb = defineSupabase(schema).use(tenant());
    const browser = createBrowser(sb, {
      client: createClient(url, publishableKey, {
        auth: { persistSession: false },
      }),
    });
    const seen: string[] = [];
    const stop = browser.auth.subscribe(() =>
      seen.push(browser.auth.current().status),
    );
    await browser.supabase.auth.signInWithPassword({ email, password });
    await vi.waitFor(() =>
      expect(browser.auth.current().status).toBe('signed-in'),
    );
    expect(browser.db.$context.actor).toMatchObject({
      id: userId,
      kind: 'user',
      email,
    });

    const queryClient = new QueryClient();
    const customers = await queryClient.fetchQuery(
      browser.queries.customers.findMany({ select: ['name'] }),
    );
    expect(customers.length).toBeGreaterThan(0);

    await browser.supabase.auth.signOut();
    await vi.waitFor(() =>
      expect(browser.auth.current().status).toBe('signed-out'),
    );
    expect(browser.db.$context.actor).toMatchObject({ kind: 'anon' });
    expect(seen).toContain('signed-in');
    stop();
  });

  it('plugs into @supabase/server pipelines as ctx.db and ctx.sql', async () => {
    const sb = defineSupabase(schema);
    const { data: signIn } = await createClient(url, publishableKey, {
      auth: { persistSession: false },
    }).auth.signInWithPassword({ email, password });
    const serverEnv = {
      url,
      publishableKeys: { default: publishableKey },
      secretKeys: { default: secretKey },
      jwks: env.jwksUrl,
    };
    const handler = pipeline(
      [
        withSupabase({ auth: 'user', env: serverEnv }),
        withBetterSupabase(sb)(),
        withPostgresClient({ connectionString: dbUrl }),
        withBetterPostgres(sb)(),
      ],
      async (_req, ctx) => {
        const rest = await ctx.db.customers.count().orThrow();
        const sql = await ctx.sql.customers.count().orThrow();
        return Response.json({ rest, sql, actor: ctx.db.$context.actor });
      },
    );
    const response = await handler(
      new Request('http://api.test/', {
        headers: {
          authorization: `Bearer ${signIn.session!.access_token}`,
          apikey: publishableKey,
        },
      }),
    );
    const body = (await response.json()) as {
      rest: number;
      sql: number;
      actor: unknown;
    };
    expect(response.status).toBe(200);
    expect(body.rest).toBe(body.sql);
    expect(body.actor).toMatchObject({ id: userId, kind: 'user' });
  });
});
