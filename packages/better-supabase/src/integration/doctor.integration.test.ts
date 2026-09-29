import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { LiveDatabase } from '../cli/doctor/live.ts';
import type { IntrospectionSource } from '../cli/introspect/source.ts';
import type { Snapshot } from '../cli/introspect/types.ts';

import { type DoctorContext, RULES, runRules } from '../cli/doctor/rules.ts';
import { introspect } from '../cli/introspect/index.ts';
import { pgSource } from '../cli/introspect/source.ts';
import { resolveConfig } from '../config/index.ts';

const dbUrl =
  process.env['SUPABASE_DB_URL'] ??
  'postgresql://postgres:postgres@127.0.0.1:55422/postgres';
const SCHEMA = `bs_doctor_${Date.now()}`;
const ORG = '00000000-0000-4000-8000-000000000001';

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

describe.skipIf(!source)('doctor against the local stack', () => {
  const db = source!;
  let snapshot: Snapshot;
  const database: LiveDatabase = {
    describe: 'local stack',
    session: true,
    async query<R>(sql: string) {
      return (await db.queryable.query(sql)).rows as R[];
    },
  };
  const context = (extra: Partial<DoctorContext> = {}): DoctorContext => ({
    config: resolveConfig({ schemas: [SCHEMA] }, '/project'),
    snapshot,
    configToml: undefined,
    envFiles: [],
    gitignore: '',
    sources: [],
    database,
    ...extra,
  });
  const only = (...codes: string[]) =>
    RULES.filter((rule) => codes.includes(rule.code));

  beforeAll(async () => {
    await db.queryable.query(`
      create schema ${SCHEMA};
      create table ${SCHEMA}.projects (
        id uuid primary key default gen_random_uuid(),
        org_id uuid not null
      );
      alter table ${SCHEMA}.projects enable row level security;
      create function ${SCHEMA}.is_member(org uuid) returns boolean
        language plpgsql stable set search_path = ''
        as $$ begin return org = ((current_setting('request.jwt.claims', true))::jsonb->>'org_id')::uuid; end $$;
      create policy projects_member on ${SCHEMA}.projects for select to authenticated
        using (${SCHEMA}.is_member(org_id));
      create policy projects_open on ${SCHEMA}.projects for select to public
        using (false);
      grant usage on schema ${SCHEMA} to anon, authenticated;
      grant select on ${SCHEMA}.projects to authenticated;
      grant execute on function ${SCHEMA}.is_member(uuid) to authenticated;
      insert into ${SCHEMA}.projects (org_id)
        select '${ORG}'::uuid from generate_series(1, 20);
    `);
    snapshot = await introspect(db.queryable, [SCHEMA]);
  });

  afterAll(async () => {
    await db.queryable.query(`drop schema if exists ${SCHEMA} cascade`);
    await db.close();
  });

  it('reads the functions a policy calls from pg_depend', () => {
    const table = snapshot.extras.tables.find(
      (entry) => entry.name === 'projects',
    )!;
    expect(
      table.policies.map((policy) => [policy.name, policy.functions]),
    ).toEqual([
      ['projects_member', [`${SCHEMA}.is_member`]],
      ['projects_open', []],
    ]);
    expect(snapshot.extras.functions).toContainEqual({
      schema: SCHEMA,
      name: 'is_member',
      signature: 'org uuid',
      language: 'plpgsql',
      volatility: 'stable',
      securityDefiner: false,
      settings: { search_path: '""' },
    });
  });

  it('flags the per-row helper and the overlapping policies', async () => {
    const findings = await runRules(context(), only('BS205', 'BS207'));
    expect(findings).toMatchObject([
      {
        code: 'BS205',
        message: expect.stringContaining(`${SCHEMA}.is_member(org_id)`),
      },
      {
        code: 'BS207',
        message: expect.stringContaining(
          'select for authenticated: projects_member, projects_open',
        ),
      },
    ]);
  });

  it('reads statistics without failing', async () => {
    const findings = await runRules(
      context({ stats: true }),
      only('BS208', 'BS209'),
    );
    for (const finding of findings)
      expect(finding.message).not.toMatch(/^Could not read/);
  });

  it('plans a table under RLS as the given claims and rolls back', async () => {
    const [finding] = await runRules(
      context({
        explain: {
          tables: ['projects'],
          claims: { role: 'authenticated', org_id: ORG },
        },
      }),
      only('BS212'),
    );
    expect(finding).toMatchObject({
      code: 'BS212',
      target: `${SCHEMA}.projects:explain`,
      message: expect.stringMatching(
        new RegExp(
          `^${SCHEMA}\\.projects as authenticated: .* ms, .*Seq Scan on projects.*${SCHEMA}\\.is_member .* over 20 calls`,
        ),
      ),
    });
    // The role and claims were local to the rolled-back transaction.
    const [who] = (
      await db.queryable.query(
        `select current_user as role, current_setting('request.jwt.claims', true) as claims`,
      )
    ).rows as { role: string; claims: string | null }[];
    expect(who).toEqual({
      role: 'postgres',
      claims: expect.toBeOneOf(['', null]),
    });
  });
});
