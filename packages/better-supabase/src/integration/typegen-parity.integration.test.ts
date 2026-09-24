import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';
import { describe, expect, it } from 'vitest';

import { supabaseCli } from '../cli/exec.ts';
import { introspect } from '../cli/introspect/index.ts';
import { pgSource } from '../cli/introspect/source.ts';
import { generateDatabaseTypes } from '../cli/introspect/typegen.ts';

const dbUrl =
  process.env['SUPABASE_DB_URL'] ??
  'postgresql://postgres:postgres@127.0.0.1:55422/postgres';
const repoRoot = fileURLToPath(new URL('../../../../', import.meta.url));

async function reachable(): Promise<boolean> {
  const pool = new Pool({
    connectionString: dbUrl,
    max: 1,
    connectionTimeoutMillis: 1000,
  });
  try {
    await pool.query('select 1');
    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const live = await reachable();

/**
 * Differences that come from the CLI bundling an older postgres-meta, not
 * from better-supabase: `--local` omits `__InternalSupabase`, newer typegen
 * writes `NonNullable<Json>` for non-null json columns.
 */
function normalize(source: string): string {
  return source
    .replace(
      /\n {2}\/\/ Allows to automatically[^\n]*\n[^\n]*\n {2}__InternalSupabase: \{\n[^\n]*\n {2}\}\n/,
      '\n',
    )
    .replace(/NonNullable<Json>/g, 'Json')
    .trimEnd();
}

describe.skipIf(!live)('database.types.ts parity', () => {
  it('matches `supabase gen types --local` for the fixture database', async () => {
    const cli = await supabaseCli(
      ['gen', 'types', 'typescript', '--local', '--schema', 'public'],
      repoRoot,
      process.env,
    );
    expect({ code: cli.code, stderr: cli.stderr }).toMatchObject({ code: 0 });

    const db = await pgSource(dbUrl);
    let ours: string;
    try {
      const snapshot = await introspect(db.queryable, ['public']);
      ours = await generateDatabaseTypes(snapshot.generator, {
        schemas: ['public'],
        postgrestVersion: '13',
      });
    } finally {
      await db.close();
    }
    expect(normalize(ours)).toBe(normalize(cli.stdout));
  }, 120_000);
});
