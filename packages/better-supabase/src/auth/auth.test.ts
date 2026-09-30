import { createServerClient } from '@supabase/ssr';
import { describe, expect, it, vi } from 'vitest';
import { z } from 'zod';

import { dbError } from '../core/errors.ts';
import { fromProblem, problemResponse, toProblem } from '../core/problem.ts';
import { envSchema, parseEnv, toServerEnv } from '../env/index.ts';
import { createTestSigner } from '../testing/jwt.ts';
import {
  authContext,
  clientIp,
  resolveAuth,
  type ResolveAuthOptions,
} from './resolve.ts';
import {
  parseCookies,
  readSession,
  serializeCookie,
  sessionCookieName,
  type StoredSession,
  writeSession,
} from './session.ts';
import { toSession } from './view.ts';

const PROJECT_URL = 'https://abcdefghijklmnopqrst.supabase.co';
const env = {
  url: PROJECT_URL,
  publishableKey: 'sb_publishable_test',
  secretKey: 'sb_secret_test',
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const NAME = 'sb-abcdefghijklmnopqrst-auth-token';
const USER = '11111111-1111-4111-8111-111111111111';

function sessionFor(
  token: string,
  refresh = 'refresh-1',
  extra: Partial<StoredSession> = {},
): StoredSession {
  const exp = JSON.parse(
    atob(token.split('.')[1]!.replace(/-/g, '+').replace(/_/g, '/')),
  ).exp as number;
  return {
    access_token: token,
    refresh_token: refresh,
    expires_at: exp,
    token_type: 'bearer',
    user: { id: USER },
    ...extra,
  };
}

function cookieRequest(
  session: StoredSession | null,
  extra: Record<string, string> = {},
): Request {
  const writes = session ? writeSession([], NAME, session) : [];
  const cookie = writes
    .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
    .join('; ');
  return new Request('https://app.test/', {
    headers: { ...(cookie ? { cookie } : {}), ...extra },
  });
}

describe('session cookies', () => {
  it('derives the supabase-js cookie name', () => {
    expect(sessionCookieName(PROJECT_URL)).toBe(NAME);
    expect(sessionCookieName('http://127.0.0.1:54321')).toBe(
      'sb-127-auth-token',
    );
  });

  it('round-trips with @supabase/ssr, including chunked sessions', async () => {
    const big: StoredSession = {
      access_token: 'a'.repeat(2000),
      refresh_token: 'r',
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      expires_in: 3600,
      token_type: 'bearer',
      user: { id: USER, user_metadata: { bio: 'é'.repeat(2500) } },
    };
    const writes = writeSession([], NAME, big);
    expect(writes.length).toBeGreaterThan(1);
    expect(writes.map((write) => write.name)).toEqual(
      writes.map((_, index) => `${NAME}.${index}`),
    );
    expect(
      writes.every((write) => encodeURIComponent(write.value).length <= 3180),
    ).toBe(true);
    expect(writes[0]!.options).toMatchObject({
      path: '/',
      sameSite: 'lax',
      httpOnly: false,
    });

    const client = createServerClient(PROJECT_URL, 'sb_publishable_test', {
      cookies: {
        getAll: () => writes.map(({ name, value }) => ({ name, value })),
        setAll: () => undefined,
      },
    });
    const { data } = await client.auth.getSession();
    expect(data.session?.access_token).toBe(big.access_token);
  });

  it('expires chunks a smaller session no longer uses, and reads mismatched chunks as none', () => {
    const existing = [
      { name: `${NAME}.0`, value: 'x' },
      { name: `${NAME}.1`, value: 'y' },
      { name: 'other', value: 'z' },
    ];
    const writes = writeSession(existing, NAME, {
      access_token: 't',
      refresh_token: 'r',
    });
    expect(writes.map((write) => [write.name, write.options.maxAge])).toEqual([
      [`${NAME}.0`, 0],
      [`${NAME}.1`, 0],
      [NAME, 400 * 24 * 60 * 60],
    ]);
    expect(readSession(existing, NAME)).toBeNull();
    expect(serializeCookie(writes[2]!)).toMatch(
      /^sb-abcdefghijklmnopqrst-auth-token=base64-/,
    );
    expect(parseCookies('a=1; b=2')).toEqual([
      { name: 'a', value: '1' },
      { name: 'b', value: '2' },
    ]);
  });
});

describe('resolveAuth', async () => {
  const signer = await createTestSigner();
  const options: ResolveAuthOptions = { env, jwks: signer.jwks as never };

  it('verifies a Bearer token locally', async () => {
    const token = await signer.sign({ sub: USER, email: 'a@b.c' });
    const fetchSpy = vi.fn<typeof fetch>();
    const { auth, cookies } = await resolveAuth(
      new Request('https://api.test/', {
        headers: { authorization: `Bearer ${token}` },
      }),
      { ...options, fetch: fetchSpy },
    );
    expect(auth).toMatchObject({
      kind: 'user',
      source: 'bearer',
      user: { id: USER, email: 'a@b.c' },
    });
    expect(cookies).toEqual([]);
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(authContext(auth)).toMatchObject({
      actor: { id: USER, kind: 'user', email: 'a@b.c' },
    });
  });

  it('rejects an invalid Bearer token instead of downgrading to anon', async () => {
    const other = await createTestSigner();
    const token = await other.sign({ sub: USER });
    const { auth } = await resolveAuth(
      new Request('https://api.test/', {
        headers: { authorization: `Bearer ${token}` },
      }),
      options,
    );
    expect(auth).toMatchObject({
      kind: 'invalid',
      error: { kind: 'unauthorized', status: 401 },
    });
  });

  it('accepts secret keys only when enabled', async () => {
    const request = () =>
      new Request('https://api.test/', {
        headers: { apikey: 'sb_secret_test' },
      });
    expect((await resolveAuth(request(), options)).auth).toEqual({
      kind: 'anon',
      reason: 'none',
    });
    expect(
      (await resolveAuth(request(), { ...options, secret: true })).auth,
    ).toEqual({ kind: 'service', keyName: 'default' });
  });

  it('restricts secret keys to the allowed names', async () => {
    const named = {
      ...options,
      env: {
        ...options.env,
        secretKeys: { default: 'sb_secret_test', cron: 'sb_secret_cron' },
      },
      secret: ['cron'],
    };
    const call = (apikey: string) =>
      resolveAuth(
        new Request('https://api.test/', { headers: { apikey } }),
        named,
      );
    expect((await call('sb_secret_cron')).auth).toEqual({
      kind: 'service',
      keyName: 'cron',
    });
    expect((await call('sb_secret_test')).auth).toMatchObject({
      kind: 'invalid',
      error: { kind: 'unauthorized' },
    });
  });

  it('uses a fresh cookie session without network or cookie writes', async () => {
    const token = await signer.sign({ sub: USER });
    const resolution = await resolveAuth(cookieRequest(sessionFor(token)), {
      ...options,
      refresh: true,
    });
    expect(resolution.auth).toMatchObject({ kind: 'user', source: 'cookie' });
    expect(resolution.cookies).toEqual([]);
    expect(resolution.headers).toEqual({});
  });

  it('reports expired sessions where refreshing is not allowed', async () => {
    const token = await signer.sign({ sub: USER, expiresIn: 30 });
    const { auth } = await resolveAuth(
      cookieRequest(sessionFor(token)),
      options,
    );
    expect(auth).toEqual({ kind: 'anon', reason: 'expired' });
  });

  it('refreshes once for concurrent requests and writes cookies with no-store headers', async () => {
    const stale = await signer.sign({ sub: USER, expiresIn: 30 });
    const fresh = await signer.sign({ sub: USER });
    const fetchSpy = vi.fn<typeof fetch>(async () => {
      await new Promise((resolve) => setTimeout(resolve, 10));
      return Response.json({
        access_token: fresh,
        refresh_token: 'refresh-2',
        expires_in: 3600,
        token_type: 'bearer',
        user: { id: USER },
      });
    });
    const session = sessionFor(stale, 'refresh-concurrent');
    const [a, b] = await Promise.all([
      resolveAuth(cookieRequest(session), {
        ...options,
        refresh: true,
        fetch: fetchSpy,
      }),
      resolveAuth(cookieRequest(session), {
        ...options,
        refresh: true,
        fetch: fetchSpy,
      }),
    ]);
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const [url, init] = fetchSpy.mock.calls[0]!;
    expect(url).toBe(`${PROJECT_URL}/auth/v1/token?grant_type=refresh_token`);
    expect(init?.headers).toMatchObject({ apikey: 'sb_publishable_test' });
    for (const resolution of [a, b]) {
      expect(resolution.auth).toMatchObject({ kind: 'user', token: fresh });
      expect(resolution.headers['Cache-Control']).toContain('no-store');
      expect(readSession(resolution.requestCookies, NAME)?.refresh_token).toBe(
        'refresh-2',
      );
    }

    const response = a.apply(new Response('ok'));
    expect(response.headers.get('cache-control')).toContain('no-store');
    expect(response.headers.getSetCookie()[0]).toMatch(
      /^sb-abcdefghijklmnopqrst-auth-token=/,
    );

    // A later request still carrying the old refresh token reuses the result.
    await resolveAuth(cookieRequest(session), {
      ...options,
      refresh: true,
      fetch: fetchSpy,
    });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it('clears the session when the refresh token is rejected, keeps it on network errors', async () => {
    const stale = await signer.sign({ sub: USER, expiresIn: 30 });
    const rejected = await resolveAuth(
      cookieRequest(sessionFor(stale, 'refresh-dead')),
      {
        ...options,
        refresh: true,
        fetch: async () =>
          Response.json({ msg: 'Invalid Refresh Token' }, { status: 400 }),
      },
    );
    expect(rejected.auth).toEqual({ kind: 'anon', reason: 'signed_out' });
    expect(rejected.cookies.every((write) => write.options.maxAge === 0)).toBe(
      true,
    );

    const offline = await resolveAuth(
      cookieRequest(sessionFor(stale, 'refresh-offline')),
      {
        ...options,
        refresh: true,
        fetch: () => Promise.reject(new TypeError('fetch failed')),
      },
    );
    expect(offline.auth).toEqual({ kind: 'anon', reason: 'refresh_failed' });
    expect(offline.cookies).toEqual([]);
  });

  it('forwards the client IP on refresh only with a secret key', async () => {
    const stale = await signer.sign({ sub: USER, expiresIn: 30 });
    const fetchSpy = vi.fn<typeof fetch>(async () =>
      Response.json({ msg: 'Invalid Refresh Token' }, { status: 400 }),
    );
    const request = (refresh: string) =>
      cookieRequest(sessionFor(stale, refresh), {
        'x-forwarded-for': '2001:db8::1, 10.0.0.1',
      });
    const secretEnv = { ...options, env, refresh: true, fetch: fetchSpy };
    await resolveAuth(request('ip-a'), secretEnv);
    expect(fetchSpy.mock.calls[0]![1]!.headers).toMatchObject({
      apikey: 'sb_secret_test',
      'sb-forwarded-for': '2001:db8::1',
    });
    await resolveAuth(request('ip-b'), { ...secretEnv, clientIp: false });
    expect(fetchSpy.mock.calls[1]![1]!.headers).toEqual({
      apikey: 'sb_publishable_test',
      'content-type': 'application/json',
    });
    await resolveAuth(request('ip-c'), {
      ...secretEnv,
      clientIp: (req) => req.headers.get('x-real-ip') ?? undefined,
    });
    expect(fetchSpy.mock.calls[2]![1]!.headers).not.toHaveProperty(
      'sb-forwarded-for',
    );
  });

  it('reads the first x-forwarded-for hop and ignores junk', () => {
    const ip = (value: string) =>
      clientIp(
        new Request('https://a.test/', {
          headers: { 'x-forwarded-for': value },
        }),
      );
    expect(ip(' 203.0.113.7 , 10.0.0.1')).toBe('203.0.113.7');
    expect(ip('unknown')).toBeUndefined();
    expect(clientIp(new Request('https://a.test/'))).toBeUndefined();
  });

  it('runs custom resolvers first', async () => {
    const { auth } = await resolveAuth(
      new Request('https://api.test/', { headers: { 'x-api-key': 'k' } }),
      {
        ...options,
        resolvers: [
          {
            name: 'api-key',
            resolve: (request) =>
              request.headers.get('x-api-key')
                ? { kind: 'service', keyName: 'partner' }
                : undefined,
          },
        ],
      },
    );
    expect(auth).toEqual({ kind: 'service', keyName: 'partner' });
  });

  it('marks resolver failures as token failures', async () => {
    const { auth } = await resolveAuth(new Request('https://api.test/'), {
      ...options,
      resolvers: [
        {
          name: 'api-key',
          resolve: () => ({
            kind: 'invalid',
            error: dbError('unauthorized', 'bad key'),
          }),
        },
      ],
    });
    expect(auth).toMatchObject({ kind: 'invalid', reason: 'token' });
  });

  describe('claims', () => {
    const claims = z.object({
      tenant_id: z.uuid(),
      roles: z.array(z.string()).default([]),
    });
    const TENANT = '22222222-2222-4222-8222-222222222222';
    const bearer = (token: string) =>
      new Request('https://api.test/', {
        headers: { authorization: `Bearer ${token}` },
      });

    it('validates verified claims and merges the output over the payload', async () => {
      const token = await signer.sign({ sub: USER, tenant_id: TENANT });
      const { auth } = await resolveAuth(bearer(token), {
        ...options,
        claims,
      });
      expect(auth).toMatchObject({
        kind: 'user',
        claims: { sub: USER, tenant_id: TENANT, roles: [] },
      });
    });

    it('resolves claims the schema rejects to invalid, also on memo hits', async () => {
      const token = await signer.sign({ sub: USER, tenant_id: 'nope' });
      for (let i = 0; i < 2; i++) {
        const { auth } = await resolveAuth(bearer(token), {
          ...options,
          claims,
        });
        expect(auth).toMatchObject({
          kind: 'invalid',
          reason: 'claims',
          error: {
            kind: 'unauthorized',
            status: 401,
            code: 'CLAIMS_INVALID',
            message: expect.stringContaining('tenant_id:'),
          },
        });
      }
    });

    it('never refreshes a cookie session whose claims fail', async () => {
      const token = await signer.sign({ sub: USER });
      const fetchSpy = vi.fn<typeof fetch>();
      const { auth, cookies } = await resolveAuth(
        cookieRequest(sessionFor(token, 'refresh-claims')),
        { ...options, claims, refresh: true, fetch: fetchSpy },
      );
      expect(auth).toMatchObject({ kind: 'invalid', reason: 'claims' });
      expect(fetchSpy).not.toHaveBeenCalled();
      expect(cookies).toEqual([]);
    });

    it('validates users from custom resolvers', async () => {
      const token = await signer.sign({ sub: USER });
      const verified = await resolveAuth(bearer(token), options);
      const { auth } = await resolveAuth(new Request('https://api.test/'), {
        ...options,
        claims,
        resolvers: [{ name: 'fixed', resolve: () => verified.auth }],
      });
      expect(auth).toMatchObject({ kind: 'invalid', reason: 'claims' });
    });
  });

  describe('userMetadata', () => {
    const profile = z.object({
      display_name: z.string(),
      avatar_url: z.url().optional(),
    });
    const bearer = (token: string) =>
      new Request('https://api.test/', {
        headers: { authorization: `Bearer ${token}` },
      });
    const logger = () => ({
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    });

    it('parses user_metadata into the profile', async () => {
      const token = await signer.sign({
        sub: USER,
        user_metadata: { display_name: 'Ada', role: 'admin' },
      });
      const { auth } = await resolveAuth(bearer(token), {
        ...options,
        userMetadata: profile,
      });
      expect(auth).toMatchObject({
        kind: 'user',
        profile: { display_name: 'Ada' },
      });
      expect(toSession(auth)).toMatchObject({
        profile: { display_name: 'Ada' },
      });
    });

    it('leaves the profile undefined and warns once with issue paths only', async () => {
      const schema = profile.extend({});
      const log = logger();
      const token = await signer.sign({
        sub: USER,
        user_metadata: { display_name: 42, secret: 'do-not-log' },
      });
      for (let i = 0; i < 2; i++) {
        const { auth } = await resolveAuth(bearer(token), {
          ...options,
          userMetadata: schema,
          logger: log,
        });
        expect(auth).toMatchObject({ kind: 'user', user: { id: USER } });
        expect(auth).not.toHaveProperty('profile');
        expect(toSession(auth)).not.toHaveProperty('profile');
      }
      expect(log.warn).toHaveBeenCalledTimes(1);
      expect(log.warn).toHaveBeenCalledWith(expect.any(String), {
        paths: ['display_name'],
      });
      expect(JSON.stringify(log.warn.mock.calls)).not.toContain('do-not-log');
    });

    it('validates an empty object when the token has no user_metadata', async () => {
      const token = await signer.sign({ sub: USER });
      const { auth } = await resolveAuth(bearer(token), {
        ...options,
        userMetadata: z.object({ theme: z.string().default('light') }),
        logger: logger(),
      });
      expect(auth).toMatchObject({ kind: 'user', profile: { theme: 'light' } });
    });

    it('replaces a profile set by a custom resolver', async () => {
      const token = await signer.sign({
        sub: USER,
        user_metadata: { display_name: 'Ada' },
      });
      const verified = await resolveAuth(bearer(token), options);
      const forged = { ...verified.auth, profile: { display_name: 'Eve' } };
      const { auth } = await resolveAuth(new Request('https://api.test/'), {
        ...options,
        userMetadata: profile,
        resolvers: [{ name: 'fixed', resolve: () => forged }],
      });
      expect(auth).toMatchObject({ profile: { display_name: 'Ada' } });
    });

    it('never affects the claims or the authorization result', async () => {
      const token = await signer.sign({
        sub: USER,
        user_metadata: { display_name: 42, tenant_id: 'from-user' },
      });
      const { auth } = await resolveAuth(bearer(token), {
        ...options,
        userMetadata: profile,
        logger: logger(),
      });
      expect(auth.kind).toBe('user');
      expect(auth).not.toHaveProperty('claims.tenant_id');
    });
  });
});

describe('env', () => {
  it('accepts framework prefixes and derives JWKS and project ref', () => {
    const result = parseEnv({
      NEXT_PUBLIC_SUPABASE_URL: `${PROJECT_URL}/`,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_x',
    });
    expect(result.env).toEqual({
      url: PROJECT_URL,
      publishableKey: 'sb_publishable_x',
      jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
      projectRef: 'abcdefghijklmnopqrst',
    });
    expect(toServerEnv(result.env!)).toMatchObject({
      publishableKeys: { default: 'sb_publishable_x' },
      secretKeys: {},
    });
  });

  it('reads named key maps and rejects malformed ones', () => {
    const base = { SUPABASE_URL: PROJECT_URL };
    const result = parseEnv({
      ...base,
      SUPABASE_PUBLISHABLE_KEYS: '{"default":"sb_publishable_x"}',
      SUPABASE_SECRET_KEYS: '{"default":"sb_secret_a","cron":"sb_secret_b"}',
    });
    expect(result.env).toMatchObject({
      publishableKey: 'sb_publishable_x',
      secretKey: 'sb_secret_a',
      secretKeys: { default: 'sb_secret_a', cron: 'sb_secret_b' },
    });
    expect(toServerEnv(result.env!).secretKeys).toEqual({
      default: 'sb_secret_a',
      cron: 'sb_secret_b',
    });

    for (const value of ['not json', '[]', '{}', '{"cron":1}']) {
      const bad = parseEnv({
        ...base,
        SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_x',
        SUPABASE_SECRET_KEYS: value,
      });
      expect(bad.issues).toEqual([
        {
          variables: ['SUPABASE_SECRET_KEYS'],
          message: 'must be a JSON object of key names to keys',
        },
      ]);
    }
    expect(
      parseEnv({
        ...base,
        SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_x',
        SUPABASE_SECRET_KEYS: '{"cron":"sb_publishable_x"}',
      }).issues,
    ).toEqual([
      {
        variables: ['SUPABASE_SECRET_KEYS'],
        message: 'holds a publishable key, not a secret key',
      },
    ]);
  });

  it('names problems without leaking values', () => {
    const result = parseEnv(
      {
        SUPABASE_URL: 'http://db.example.com',
        SUPABASE_PUBLISHABLE_KEY: 'sb_secret_leaked',
        SUPABASE_SECRET_KEY: 'eyJhbGciOi',
      },
      { require: ['dbUrl'] },
    );
    expect(result.ok).toBe(false);
    const messages = result.issues!.map(
      (issue) => `${issue.variables[0]} ${issue.message}`,
    );
    expect(messages).toEqual([
      expect.stringMatching(/^SUPABASE_URL must use https/),
      expect.stringMatching(/^SUPABASE_PUBLISHABLE_KEY holds a secret key/),
      expect.stringMatching(/^SUPABASE_SECRET_KEY is a legacy JWT key/),
      'SUPABASE_DB_URL is not set',
    ]);
    expect(messages.join()).not.toContain('sb_secret_leaked');
  });

  it('is a Standard Schema', async () => {
    const outcome = await envSchema()['~standard'].validate({
      SUPABASE_URL: 'http://127.0.0.1:54321',
      SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_x',
    });
    expect(outcome).toMatchObject({ value: { url: 'http://127.0.0.1:54321' } });
  });
});

describe('problem details', () => {
  it('maps DbError to RFC 9457 and back', async () => {
    const error = dbError('conflict', 'duplicate key', {
      constraint: 'customers_kvk_key',
      columns: ['kvk'],
      code: '23505',
    });
    const response = problemResponse(error, { instance: '/customers' });
    expect(response.status).toBe(409);
    expect(response.headers.get('content-type')).toBe(
      'application/problem+json',
    );
    const body = await response.json();
    expect(body).toEqual({
      type: 'https://bettersupabase.com/problems/conflict',
      title: 'Conflict',
      status: 409,
      kind: 'conflict',
      detail: 'duplicate key',
      instance: '/customers',
      code: '23505',
      constraint: 'customers_kvk_key',
      columns: ['kvk'],
    });
    expect(fromProblem(body)).toEqual(error);
  });

  it('hides internal messages and challenges 401s', () => {
    expect(
      toProblem(dbError('unexpected', 'relation "secret" does not exist')),
    ).not.toHaveProperty('detail');
    const response = problemResponse(dbError('unauthorized', 'bad token'));
    expect(response.headers.get('www-authenticate')).toBe(
      'Bearer realm="supabase", error="invalid_token"',
    );
  });
});
