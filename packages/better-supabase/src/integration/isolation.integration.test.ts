import { createClient } from '@supabase/supabase-js';
import { afterAll, describe, expect, it } from 'vitest';

import type { IntrospectionSource } from '../cli/introspect/source.ts';
import type { LocalStack } from '../testing/as-user.ts';

import { pgSource } from '../cli/introspect/source.ts';
import { defineSupabase } from '../core/define.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { tenant } from '../plugins/tenant/index.ts';
import { ConformanceError } from '../testing/conformance.ts';
import { expectTenantIsolation } from '../testing/isolation.ts';

const stack: LocalStack = {
  url: process.env['SUPABASE_URL'] ?? 'http://127.0.0.1:55421',
  publishableKey:
    process.env['SUPABASE_PUBLISHABLE_KEY'] ??
    'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  secretKey:
    process.env['SUPABASE_SECRET_KEY'] ??
    'sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz',
};
const dbUrl =
  process.env['SUPABASE_DB_URL'] ??
  'postgresql://postgres:postgres@127.0.0.1:55422/postgres';

const ACME = '00000000-0000-4000-8000-000000000001';
const GLOBEX = '00000000-0000-4000-8000-000000000002';
const RUN = Date.now();
const LEAKY = `00000000-0000-4000-8000-${String(RUN).slice(-12).padStart(12, '0')}`;
const USER = '00000000-0000-4000-8000-0000000000ff';

async function open(): Promise<IntrospectionSource | undefined> {
  try {
    const source = await pgSource(dbUrl);
    await source.queryable.query('select 1');
    return source;
  } catch {
    return undefined;
  }
}

const source = await open();
const sb = defineSupabase(schema).use(tenant());
const tags = {
  row: (owner: { id: string }, n: 0 | 1) => ({
    organizationId: owner.id,
    name: `iso-${RUN}-${n}`,
  }),
  update: { color: 'red' as const },
};

describe.skipIf(!source)(
  'expectTenantIsolation against the local stack',
  () => {
    const db = source!;
    const admin = defineSupabase(schema).connect(
      createClient(stack.url!, stack.secretKey!, {
        auth: { persistSession: false, autoRefreshToken: false },
      }),
    );

    afterAll(async () => {
      await db.queryable.query(`
      drop policy if exists tags_leak_select on public.tags;
      drop policy if exists tags_leak_delete on public.tags;
    `);
      await admin.organizations.deleteMany({ where: { id: LEAKY } });
      await db.close();
    });

    it('passes when every command is scoped to the tenant', async () => {
      const report = await expectTenantIsolation(sb, {
        stack,
        tenants: [
          { id: ACME, name: 'acme', claims: { sub: USER, org_id: ACME } },
          { id: GLOBEX, name: 'globex', claims: { sub: USER, org_id: GLOBEX } },
        ],
        tables: { tags },
      });
      expect(report.checks).toHaveLength(10);
      expect(report.checks.every((check) => check.ok)).toBe(true);
      const left = await admin.tags
        .count({ where: { name: { startsWith: `iso-${RUN}` } } })
        .orThrow();
      expect(left).toBe(0);
    });

    it('names the table and command of each leak', async () => {
      const error = await expectTenantIsolation(sb, {
        stack,
        tenants: [
          { id: GLOBEX, name: 'globex', claims: { sub: USER, org_id: GLOBEX } },
          { id: LEAKY, name: 'leaky', claims: { sub: USER, org_id: LEAKY } },
        ],
        tables: { tags },
        seed: async () => {
          await admin.organizations
            .create({ id: LEAKY, name: 'Leaky', slug: `leaky-${RUN}` })
            .orThrow();
          await db.queryable.query(`
          create policy tags_leak_select on public.tags for select to authenticated
            using (organization_id = '${LEAKY}');
          create policy tags_leak_delete on public.tags for delete to authenticated
            using (organization_id = '${LEAKY}');
        `);
        },
      }).catch((cause: unknown) => cause);
      expect(error).toBeInstanceOf(ConformanceError);
      const failed = (error as ConformanceError).report.checks
        .filter((check) => !check.ok)
        .map((check) => check.name);
      expect(failed).toEqual([
        "tags: globex can't select leaky's rows",
        "tags: globex can't delete leaky's rows",
      ]);
    });
  },
);
