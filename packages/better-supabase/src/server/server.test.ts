import { afterEach, describe, expect, it, vi } from 'vitest';

import { defineSupabase } from '../core/define.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { createTestSigner } from '../testing/jwt.ts';
import { createServer } from './server.ts';

const PROJECT_URL = 'https://abcdefghijklmnopqrst.supabase.co';
const env = {
  url: PROJECT_URL,
  publishableKey: 'sb_publishable_test',
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const signer = await createTestSigner();

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('createServer headers', () => {
  it('stamps per-request headers on the caller’s PostgREST requests', async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(() =>
      Promise.resolve(Response.json([])),
    );
    vi.stubGlobal('fetch', fetch);
    const server = createServer(defineSupabase(schema), {
      env,
      auth: { jwks: signer.jwks as never },
      headers: (request) => ({
        'x-channel': 'api',
        'x-request-id': request.headers.get('x-request-id') ?? '',
      }),
    });
    const token = await signer.sign({
      sub: '11111111-1111-4111-8111-111111111111',
    });

    for (const headers of [
      { 'x-request-id': 'r1' },
      { 'x-request-id': 'r2', authorization: `Bearer ${token}` },
    ]) {
      const ctx = await server.context(
        new Request('https://api.test/', { headers }),
      );
      await ctx.db.customers.findMany({ select: ['id'] }).orThrow();
    }

    const sent = fetch.mock.calls.map(([, init]) => new Headers(init?.headers));
    expect(
      sent.map((headers) => [
        headers.get('x-channel'),
        headers.get('x-request-id'),
      ]),
    ).toEqual([
      ['api', 'r1'],
      ['api', 'r2'],
    ]);
    expect(sent[1]!.get('authorization')).toBe(`Bearer ${token}`);
  });
});
