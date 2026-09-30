import { createClient } from '@supabase/supabase-js';
import { Hono } from 'hono';
import { afterAll, describe, expect, it } from 'vitest';

import { defineSupabase } from '../core/define.ts';
import { parseEnv } from '../env/index.ts';
import {
  type Functions,
  type Models,
  schema,
} from '../fixtures/generated-camel.ts';
import { type BetterEnv, createHono } from '../hono/index.ts';
import { defineListQuery } from '../list/index.ts';
import { signLocalJwt } from '../testing/local-key.ts';

const url = process.env['SUPABASE_URL'] ?? 'http://127.0.0.1:55421';
const publishableKey =
  process.env['SUPABASE_PUBLISHABLE_KEY'] ??
  'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
const secretKey =
  process.env['SUPABASE_SECRET_KEY'] ??
  'sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz';

const ACME = '00000000-0000-4000-8000-000000000001';
const OTHER = '00000000-0000-4000-8000-000000000002';
const USER = '00000000-0000-4000-8000-0000000000ff';

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/rest/v1/`, {
      headers: { apikey: publishableKey },
      signal: AbortSignal.timeout(1000),
    });
    return response.status < 500;
  } catch {
    return false;
  }
}

const live = await reachable();

describe.skipIf(!live)('Hono adapter against the local stack', async () => {
  const sb = defineSupabase(schema);
  const env = parseEnv({
    SUPABASE_URL: url,
    SUPABASE_PUBLISHABLE_KEY: publishableKey,
  }).env!;
  const bs = createHono(sb, {
    env,
  });
  const list = defineListQuery(sb, 'customers', {
    search: ['name'],
    sorts: { name: { name: 'asc' } },
    defaultSort: 'name',
    pageSize: 20,
  });
  const app = new Hono<BetterEnv<Models, Functions, unknown>>()
    .onError(bs.onError)
    .use('/api/*', bs.middleware())
    .route(
      '/api/customers',
      bs.resource('customers', {
        list,
        select: ['id', 'name', 'organizationId'],
      }),
    );
  const admin = sb.connect(
    createClient(url, secretKey, { auth: { persistSession: false } }),
  );
  const created: string[] = [];
  afterAll(async () => {
    if (created.length > 0) {
      await admin.customers.deleteMany({ where: { id: { in: created } } });
    }
  });

  const tokenFor = (orgId: string) =>
    signLocalJwt({ sub: USER, tenant_id: orgId });
  const call = async (
    orgId: string,
    path: string,
    init: { method?: string; body?: unknown } = {},
  ) =>
    app.request(path, {
      method: init.method ?? 'GET',
      headers: {
        authorization: `Bearer ${await tokenFor(orgId)}`,
        ...(init.body === undefined
          ? {}
          : { 'content-type': 'application/json' }),
      },
      ...(init.body === undefined ? {} : { body: JSON.stringify(init.body) }),
    });

  it('runs CRUD as the caller, under RLS', async () => {
    const name = `Hono ${String(Date.now())}`;
    const create = await call(ACME, '/api/customers', {
      method: 'POST',
      body: { name, organizationId: ACME },
    });
    expect(create.status).toBe(201);
    const row = (await create.json()) as { id: string; organizationId: string };
    created.push(row.id);
    expect(row.organizationId).toBe(ACME);

    const found = await call(
      ACME,
      `/api/customers?q=${encodeURIComponent(name)}`,
    );
    expect(await found.json()).toMatchObject({
      items: [{ id: row.id, name }],
    });

    const hidden = await call(OTHER, `/api/customers/${row.id}`);
    expect(hidden.status).toBe(404);
    const crossTenant = await call(OTHER, '/api/customers', {
      method: 'POST',
      body: { name, organizationId: ACME },
    });
    expect(crossTenant.status).toBe(403);

    const patched = await call(ACME, `/api/customers/${row.id}`, {
      method: 'PATCH',
      body: { name: `${name} (renamed)` },
    });
    expect(await patched.json()).toMatchObject({ name: `${name} (renamed)` });

    expect(
      (await call(ACME, `/api/customers/${row.id}`, { method: 'DELETE' }))
        .status,
    ).toBe(204);
    expect((await call(ACME, `/api/customers/${row.id}`)).status).toBe(404);
  });

  it('rejects anonymous callers before touching the database', async () => {
    const response = await app.request('/api/customers');
    expect(response.status).toBe(401);
  });
});
