import { handler } from '@better-supabase/example-edge/handler';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import {
  ACME,
  cleanup,
  createUser,
  reachable,
  type TestUser,
} from './stack.ts';

describe.skipIf(!(await reachable()))('edge example', () => {
  let acme: TestUser;
  const rows = cleanup('customers');

  beforeAll(async () => {
    acme = await createUser(ACME);
  });
  afterAll(async () => {
    await rows.run();
    await acme.remove();
  });

  const request = (
    path: string,
    init: {
      method?: string;
      body?: unknown;
      token?: string;
      origin?: string;
    } = {},
  ) =>
    handler(
      new Request(`http://127.0.0.1:54321${path}`, {
        method: init.method ?? 'GET',
        headers: {
          ...(init.token ? { authorization: `Bearer ${init.token}` } : {}),
          ...(init.origin ? { origin: init.origin } : {}),
          ...(init.body === undefined
            ? {}
            : { 'content-type': 'application/json' }),
        },
        ...(init.body === undefined ? {} : { body: JSON.stringify(init.body) }),
      }),
    );

  it('serves REST resources as the caller', async () => {
    const name = `Edge e2e ${crypto.randomUUID()}`;
    const created = await request('/api/customers', {
      method: 'POST',
      token: acme.accessToken,
      body: { name, organizationId: ACME },
    });
    expect(created.status).toBe(201);
    const row = (await created.json()) as { id: string; name: string };
    rows.track(row.id);
    expect(row.name).toBe(name);

    const fetched = await request(`/api/customers/${row.id}`, {
      token: acme.accessToken,
    });
    expect(await fetched.json()).toMatchObject({
      id: row.id,
      name,
      organizationId: ACME,
    });
    expect(
      (
        await request(`/api/customers/${row.id}`, {
          method: 'DELETE',
          token: acme.accessToken,
        })
      ).status,
    ).toBe(204);
  });

  it('answers /api/me and CORS preflights', async () => {
    expect(
      await (await request('/api/me', { token: acme.accessToken })).json(),
    ).toEqual({ kind: 'user' });
    const preflight = await request('/api/customers', {
      method: 'OPTIONS',
      origin: 'https://app.test',
    });
    expect(preflight.status).toBeLessThan(300);
    expect(preflight.headers.get('access-control-allow-headers')).toContain(
      'authorization',
    );
    expect((await request('/api/customers')).status).toBe(401);
  });
});
