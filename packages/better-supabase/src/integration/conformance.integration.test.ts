import { createClient } from '@supabase/supabase-js';
import { afterAll, describe, it } from 'vitest';

import { defineSupabase } from '../core/define.ts';
import { postgrestExecutor } from '../core/postgrest-executor.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { createPostgres, postgresExecutor } from '../postgres/index.ts';
import { testExecutor } from '../testing/conformance.ts';

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

describe.skipIf(!live)('built-in executors conform', () => {
  const sb = defineSupabase(schema);
  const postgres = createPostgres({ connectionString: dbUrl, max: 2 });
  afterAll(() => postgres.end());
  const create = (name: string) => ({
    organizationId: ACME,
    name: `conformance-${name}-${Date.now()}`,
    color: 'gray',
  });

  it('postgrest', () =>
    testExecutor(
      postgrestExecutor(
        createClient(url, secretKey, { auth: { persistSession: false } }),
      ),
      {
        sb,
        table: 'tags',
        create: create('postgrest'),
      },
    ));

  it('postgres', () =>
    testExecutor(postgresExecutor(postgres.admin), {
      sb,
      table: 'tags',
      create: create('postgres'),
    }));
});
