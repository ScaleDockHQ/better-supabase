import { cp, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import type { BetterSupabaseConfig } from '../config/index.ts';

import { renderFixtures } from '../fixtures/render.ts';
import { parseCheckUnion } from './gen/shared.ts';
import { run } from './run.ts';

const fixtures = fileURLToPath(new URL('../fixtures/', import.meta.url));

describe('parseCheckUnion', () => {
  it('reads ANY(ARRAY[...]) constraints', () => {
    expect(
      parseCheckUnion(
        "CHECK ((status = ANY (ARRAY['lead'::text, 'active'::text, 'archived'::text])))",
      ),
    ).toEqual({ column: 'status', values: ['lead', 'active', 'archived'] });
  });

  it('reads OR chains and unescapes quotes', () => {
    expect(
      parseCheckUnion("CHECK (((kind = 'it''s'::text) OR (kind = 'b'::text)))"),
    ).toEqual({ column: 'kind', values: ["it's", 'b'] });
  });

  it('ignores constraints that are not unions', () => {
    expect(parseCheckUnion('CHECK ((length(name) > 2))')).toBeUndefined();
    expect(
      parseCheckUnion("CHECK (((a = 'x'::text) OR (b = 'y'::text)))"),
    ).toBeUndefined();
  });
});

describe('fixtures', () => {
  it('are in sync with the generator', async () => {
    for (const file of await renderFixtures()) {
      expect({
        path: file.path,
        contents: await readFile(file.path, 'utf8'),
      }).toEqual(file);
    }
  });
});

describe('config JSON Schema', () => {
  it('describes every config key', async () => {
    const schema = JSON.parse(
      await readFile(
        new URL('../../schemas/config-v1.json', import.meta.url),
        'utf8',
      ),
    ) as { properties: Record<string, unknown> };
    const keys: Record<keyof BetterSupabaseConfig, true> = {
      $schema: true,
      source: true,
      schemas: true,
      casing: true,
      tables: true,
      output: true,
      postgrestVersion: true,
      json: true,
      codecs: true,
      generators: true,
      plugins: true,
      buckets: true,
      topics: true,
      realtime: true,
      sensitive: true,
      expose: true,
      sql: true,
      seed: true,
      openapi: true,
      doctor: true,
    };
    expect(Object.keys(schema.properties).sort()).toEqual(
      Object.keys(keys).sort(),
    );
  });
});

describe('gen', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'better-supabase-'));
    await cp(join(fixtures, 'snapshot.json'), join(dir, 'snapshot.json'));
    await writeFile(
      join(dir, 'better-supabase.config.json'),
      JSON.stringify({
        casing: 'camel',
        output: 'src/db/generated.ts',
      }),
    );
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('writes, reports no changes, then detects drift with --check', async () => {
    const first = await run([
      'gen',
      '--snapshot',
      'snapshot.json',
      '--cwd',
      dir,
    ]);
    expect(first.code).toBe(0);
    expect(first.stdout).toContain('src/db/generated.ts');
    const generated = await readFile(join(dir, 'src/db/generated.ts'), 'utf8');
    expect(generated).toContain('from "better-supabase"');
    expect(generated).toContain('customerTags');

    const again = await run([
      'gen',
      '--snapshot',
      'snapshot.json',
      '--cwd',
      dir,
    ]);
    expect(again.stdout).toContain('No changes');

    const check = await run([
      'gen',
      '--check',
      '--snapshot',
      'snapshot.json',
      '--cwd',
      dir,
    ]);
    expect(check.code).toBe(0);

    await writeFile(
      join(dir, 'src/db/generated.ts'),
      `${generated}// edited\n`,
    );
    const drift = await run([
      'gen',
      '--check',
      '--snapshot',
      'snapshot.json',
      '--cwd',
      dir,
    ]);
    expect(drift.code).toBe(1);
    expect(drift.stderr).toContain('out of date');
  });

  it('writes database.types.ts next to the main module', async () => {
    await run(['gen', '--snapshot', 'snapshot.json', '--cwd', dir]);
    const types = await readFile(join(dir, 'src/db/database.types.ts'), 'utf8');
    expect(types).toContain('export type Database = {');
    expect(types).toContain('PostgrestVersion: "13"');
  });

  it('emits realtime table metadata and rejects unknown tables', async () => {
    await writeFile(
      join(dir, 'better-supabase.config.json'),
      JSON.stringify({
        casing: 'camel',
        output: 'src/db/generated.ts',
        plugins: { tenant: true },
        realtime: { tables: ['customers', 'public.tags', 'organizations'] },
      }),
    );
    expect(
      (await run(['gen', '--snapshot', 'snapshot.json', '--cwd', dir])).code,
    ).toBe(0);
    const generated = await readFile(join(dir, 'src/db/generated.ts'), 'utf8');
    expect(generated).toMatch(
      /"realtime": \{\s+"customers": \{\s+"tenant": "organizationId"\s+\},\s+"tags": \{\s+"tenant": "organizationId"\s+\},\s+"organizations": \{\}/,
    );

    await writeFile(
      join(dir, 'better-supabase.config.json'),
      JSON.stringify({ realtime: { tables: ['nope'] } }),
    );
    const failed = await run([
      'gen',
      '--snapshot',
      'snapshot.json',
      '--cwd',
      dir,
    ]);
    expect(failed.code).not.toBe(0);
    expect(failed.stderr).toContain('realtime.tables: unknown table "nope"');
  });

  it('rejects an unknown introspect --format', async () => {
    const result = await run(['introspect', '--format', 'nope', '--cwd', dir]);
    expect(result.code).toBe(2);
  });

  it('prints help and version', async () => {
    expect((await run(['--help'])).stdout).toContain('Usage: better-supabase');
    expect((await run(['--version'])).stdout).toMatch(/\d+\.\d+\.\d+/);
  });
});

describe('sql', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'better-supabase-'));
    await writeFile(
      join(dir, 'better-supabase.config.json'),
      JSON.stringify({ sql: { kit: ['invitations'] } }),
    );
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('adds modules with their dependencies and suggests tracking them', async () => {
    const added = await run(['sql', 'add', 'jobs', 'pgtap', '--cwd', dir]);
    expect(added.code).toBe(0);
    expect(added.stdout).toMatch(
      /Wrote supabase\/schemas\/900_better_supabase_\d\d_jobs\.sql/,
    );
    expect(added.stdout).toContain(
      'supabase/tests/000_better_supabase_pgtap.test.sql',
    );
    expect(added.stdout).toContain("kit: ['invitations', 'jobs', 'pgtap']");

    const list = await run(['sql', 'list', '--cwd', dir]);
    expect(list.stdout).toMatch(/○ jobs/);
    expect(list.stdout).toMatch(/^ {2}audit/m);
  });

  it('syncs sql.kit and detects stale files with --check', async () => {
    expect((await run(['sql', 'sync', '--check', '--cwd', dir])).code).toBe(1);
    const sync = await run(['sql', 'sync', '--cwd', dir]);
    expect(sync.stdout).toContain('tenant');
    expect(sync.stdout).toContain('invitations');
    expect((await run(['sql', 'sync', '--check', '--cwd', dir])).code).toBe(0);
    const list = await run(['sql', 'list', '--cwd', dir]);
    expect(list.stdout).toMatch(/● invitations/);
    expect(list.stdout).toMatch(/○ tenant/);
  });

  it('prints a module and rejects unknown ones', async () => {
    const print = await run(['sql', 'print', 'audit', '--cwd', dir]);
    expect(print.stdout).toContain('better_supabase.audit_log');
    expect((await run(['sql', 'add', 'nope', '--cwd', dir])).code).toBe(2);
    expect(
      (await run(['sql', 'add', '--dry-run', 'audit', '--cwd', dir])).stdout,
    ).toContain('Would write');
  });
});
