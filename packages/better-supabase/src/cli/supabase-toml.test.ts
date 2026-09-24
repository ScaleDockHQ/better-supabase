import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { readSupabasePort } from './config.ts';
import { readSupabaseToml, tomlGet } from './supabase-toml.ts';

describe('readSupabaseToml', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'better-supabase-toml-'));
    await mkdir(join(dir, 'supabase'));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('parses with @supabase/config, including env() values', async () => {
    await writeFile(
      join(dir, 'supabase/config.toml'),
      [
        'project_id = "demo"',
        '[db]',
        'port = 55422',
        '[auth]',
        'site_url = "env(BS_TOML_SITE_URL)"',
        'jwt_expiry = 7200',
        '',
      ].join('\n'),
    );
    process.env['BS_TOML_SITE_URL'] = 'https://example.test';
    try {
      const toml = await readSupabaseToml(dir);
      expect(toml?.parser).toBe('@supabase/config');
      expect(tomlGet(toml!.document, ['auth', 'site_url'])).toBe(
        'https://example.test',
      );
      expect(tomlGet(toml!.document, ['auth', 'jwt_expiry'])).toBe(7200);
      expect(await readSupabasePort(dir, 'db')).toBe(55422);
      expect(await readSupabasePort(dir, 'api')).toBeUndefined();
    } finally {
      delete process.env['BS_TOML_SITE_URL'];
    }
  });

  it('returns undefined without a config.toml', async () => {
    expect(await readSupabaseToml(join(dir, 'missing'))).toBeUndefined();
  });
});
