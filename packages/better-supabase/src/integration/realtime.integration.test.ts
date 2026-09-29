import type { StandardSchemaV1 } from '@standard-schema/spec';

import { createClient } from '@supabase/supabase-js';
import { Pool } from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { defineSupabase } from '../core/define.ts';
import { schema } from '../fixtures/generated-camel.ts';
import {
  defineTopic,
  rowChange,
  type TopicMessage,
} from '../realtime/index.ts';
import { signTestJwt } from '../testing/jwt.ts';

const url = process.env['SUPABASE_URL'] ?? 'http://127.0.0.1:55421';
const dbUrl =
  process.env['SUPABASE_DB_URL'] ??
  'postgresql://postgres:postgres@127.0.0.1:55422/postgres';
const publishableKey =
  process.env['SUPABASE_PUBLISHABLE_KEY'] ??
  'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
const jwtSecret =
  process.env['SUPABASE_JWT_SECRET'] ??
  'super-secret-jwt-token-with-at-least-32-characters-long';

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

const title: StandardSchemaV1<unknown, { title: string }> = {
  '~standard': {
    version: 1,
    vendor: 'test',
    validate: (value) =>
      typeof value === 'object' &&
      value !== null &&
      typeof (value as { title?: unknown }).title === 'string'
        ? { value: { title: (value as { title: string }).title } }
        : { issues: [{ message: 'title is required', path: ['title'] }] },
  },
};

const sb = defineSupabase(schema);
const customers = defineTopic('org:{orgId}:customers');
const notifications = defineTopic('org:{orgId}:notifications:{userId}', {
  events: { created: title },
  send: true,
});

function waitFor<T>(
  register: (resolve: (value: T) => void) => void,
  ms = 8000,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error('timed out waiting for a message')),
      ms,
    );
    register((value) => {
      clearTimeout(timer);
      resolve(value);
    });
  });
}

describe.skipIf(!live)('Realtime kit', async () => {
  const clientFor = async (orgId: string) => {
    const token = await signTestJwt(jwtSecret, {
      sub: USER,
      role: 'authenticated',
      org_id: orgId,
    });
    return createClient(url, publishableKey, {
      accessToken: async () => token,
    });
  };
  const acme = await clientFor(ACME);
  const other = await clientFor(OTHER);
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  const kvk = `rt-${String(Date.now())}`;

  beforeAll(async () => {
    await pool.query(customers.sql());
    await pool.query(notifications.sql());
    await pool.query(
      customers.triggerSql(sb, 'customers', {
        values: { orgId: 'organizationId' },
      }),
    );
  });
  afterAll(async () => {
    await pool.query('delete from public.customers where kvk = $1', [kvk]);
    acme.removeAllChannels();
    other.removeAllChannels();
    await pool.end();
  });

  it('broadcasts row changes to the tenant topic', async () => {
    let received: TopicMessage | undefined;
    const got = waitFor<TopicMessage>((resolve) => {
      received = undefined;
      const sub = customers.subscribe(
        acme,
        { orgId: ACME },
        { INSERT: (_payload, message) => resolve(message) },
      );
      void sub.ready.then(async () => {
        await sb
          .connect(acme, { claims: { org_id: ACME } })
          .customers.create({ organizationId: ACME, name: 'Realtime Co', kvk })
          .orThrow();
      });
    }, 15_000);
    received = await got;
    const change = rowChange(sb, 'customers', received);
    expect(change).toMatchObject({
      operation: 'INSERT',
      table: 'customers',
      record: { name: 'Realtime Co', organizationId: ACME, kvk },
    });
    expect(rowChange(sb, 'notes', received)).toBeNull();
  }, 20_000);

  it('refuses private topics of another tenant', async () => {
    const sub = customers.subscribe(other, { orgId: ACME }, {});
    await expect(sub.ready).rejects.toThrow(/./);
    await sub.unsubscribe();
  }, 20_000);

  it('sends validated events over HTTP', async () => {
    const values = { orgId: ACME, userId: USER };
    const invalid = await notifications.send(acme, values, 'created', {
      nope: true,
    } as never);
    expect(invalid.error).toMatchObject({
      kind: 'validation',
      issues: [{ path: ['title'] }],
    });

    const message = await waitFor<{ title: string }>((resolve) => {
      const sub = notifications.subscribe(acme, values, {
        created: (payload) => resolve(payload),
      });
      void sub.ready.then(() =>
        notifications
          .send(acme, values, 'created', { title: 'Hello' })
          .orThrow(),
      );
    });
    expect(message).toEqual({ title: 'Hello' });

    const denied = await notifications.send(other, values, 'created', {
      title: 'Hi',
    });
    expect(denied.ok).toBe(false);
  });
});
