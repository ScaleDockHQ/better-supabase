import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import type {
  Catalog,
  CatalogFunction,
  CatalogTable,
  Snapshot,
} from '../introspect/types.ts';
import type { AdvisorSource, Lint } from './advisors.ts';

import { resolveConfig } from '../../config/index.ts';
import fixture from '../../fixtures/snapshot.json' with { type: 'json' };
import { locate } from '../commands/doctor.ts';
import { parseSnapshot } from '../commands/snapshot.ts';
import { toCatalog } from '../introspect/catalog.ts';
import { fromCatalog } from '../introspect/from-catalog.ts';
import { run } from '../run.ts';
import { parseTomlSubset, type SupabaseToml } from '../supabase-toml.ts';
import { formatReport } from './format.ts';
import { type DoctorContext, RULE_CODES, RULES, runRules } from './rules.ts';

const base = parseSnapshot(fixture);

const toml = (text: string): SupabaseToml => ({
  path: 'supabase/config.toml',
  text,
  document: parseTomlSubset(text),
  parser: 'builtin',
});

function snapshot(
  change: (tables: CatalogTable[], functions: CatalogFunction[]) => void,
): Snapshot {
  const copy = structuredClone(toCatalog(base)) as {
    -readonly [K in keyof Catalog]: Catalog[K];
  };
  const tables = copy.tables as CatalogTable[];
  const functions = copy.functions as CatalogFunction[];
  change(tables, functions);
  return fromCatalog(copy);
}

const edit = <T>(value: T): { -readonly [K in keyof T]: T[K] } =>
  value as never;
const table = (tables: CatalogTable[], name: string) =>
  edit(tables.find((entry) => entry.name === name)!);

function context(
  snap: Snapshot,
  extra: Partial<DoctorContext> = {},
): DoctorContext {
  return {
    config: resolveConfig(
      { plugins: { tenant: true, softDelete: { column: 'archived_at' } } },
      '/project',
    ),
    snapshot: snap,
    configToml: undefined,
    envFiles: [],
    gitignore: '',
    ...extra,
  };
}

const codes = async (ctx: DoctorContext, only?: string): Promise<string[]> =>
  (
    await runRules(
      ctx,
      RULES.filter(
        (rule) => rule.code !== 'BS303' && (!only || rule.code === only),
      ),
    )
  ).map((finding) => finding.code);

describe('doctor rules', () => {
  it('passes the fixture schema', async () => {
    expect(await codes(context(base))).toEqual([]);
  });

  it('flags live query tables without broadcasts and keyless realtime deletes', async () => {
    const catalog = structuredClone(toCatalog(base)) as {
      -readonly [K in keyof Catalog]: Catalog[K];
    };
    catalog.realtime = ['public.tags', 'public.customers'];
    table(catalog.tables as CatalogTable[], 'tags').replicaIdentity = 'NOTHING';
    edit(table(catalog.tables as CatalogTable[], 'notes').triggers).push({
      name: 'bs_realtime',
      timing: 'after',
      events: ['insert', 'update', 'delete'],
      level: 'statement',
      function: 'better_supabase.broadcast_changes',
    });
    const ctx = context(fromCatalog(catalog), {
      config: resolveConfig(
        { realtime: { tables: ['customers', 'public.notes', 'missing'] } },
        '/project',
      ),
    });
    const findings = await runRules(
      ctx,
      RULES.filter((rule) => rule.code === 'BS305' || rule.code === 'BS306'),
    );
    expect(findings.map((finding) => finding.target)).toEqual([
      'public.customers',
      'missing',
      'public.tags',
    ]);
  });

  it('flags anonymous write policies', async () => {
    const snap = snapshot((tables) => {
      edit(table(tables, 'notes').policies).push({
        name: 'anyone',
        command: 'insert',
        roles: ['anon'],
        permissive: true,
        using: null,
        check: 'true',
      });
    });
    const [finding, ...rest] = await runRules(
      context(snap),
      RULES.filter((rule) => rule.code === 'BS103'),
    );
    expect(rest).toEqual([]);
    expect(finding).toMatchObject({
      target: 'public.notes.anyone',
      object: { kind: 'policy', schema: 'public', name: 'anyone' },
      help: 'https://better-supabase.dev/docs/cli/doctor#bs103',
    });
  });

  it('reports Supabase advisor lints with their own severity and links', async () => {
    const lint = (overrides: Partial<Lint>): Lint => ({
      name: 'rls_disabled_in_public',
      title: 'RLS Disabled in Public',
      level: 'ERROR',
      facing: 'EXTERNAL',
      categories: ['SECURITY'],
      description: '',
      detail:
        'Table \\`public.customers\\` is public, but RLS has not been enabled.',
      remediation:
        'https://supabase.com/docs/guides/database/database-linter?lint=0013_rls_disabled_in_public',
      metadata: { schema: 'public', name: 'customers', type: 'table' },
      cache_key: 'rls_disabled_in_public_public_customers',
      ...overrides,
    });
    const requested: string[] = [];
    const advisors: AdvisorSource = {
      describe: 'test',
      lints: (category) => {
        requested.push(category);
        return Promise.resolve(
          category === 'security'
            ? [lint({})]
            : [
                lint({
                  name: 'unindexed_foreign_keys',
                  title: 'Unindexed foreign keys',
                  level: 'INFO',
                  categories: ['PERFORMANCE'],
                  detail: 'No index.',
                  metadata: null,
                  cache_key: 'unindexed_x',
                }),
              ],
        );
      },
    };
    const advisorRules = RULES.filter((rule) =>
      ['BS100', 'BS200'].includes(rule.code),
    );
    const findings = await runRules(context(base, { advisors }), advisorRules);
    expect(requested).toEqual(['security', 'performance']);
    expect(findings).toEqual([
      {
        code: 'BS100',
        severity: 'error',
        title: 'RLS Disabled in Public',
        message:
          'Table `public.customers` is public, but RLS has not been enabled. [rls_disabled_in_public]',
        target: 'public.customers',
        object: { kind: 'table', schema: 'public', name: 'customers' },
        help: 'https://supabase.com/docs/guides/database/database-linter?lint=0013_rls_disabled_in_public',
      },
      expect.objectContaining({
        code: 'BS200',
        severity: 'info',
        target: 'unindexed_x',
      }),
    ]);

    const skipped = await runRules(
      context(base, { advisors: { skipped: 'offline' } }),
      advisorRules,
    );
    expect(skipped.map((finding) => finding.severity)).toEqual([
      'info',
      'info',
    ]);
    const failing = await runRules(
      context(base, {
        advisors: {
          describe: 'splinter',
          lints: () => Promise.reject(new Error('boom')),
        },
      }),
      advisorRules,
    );
    expect(failing[0]).toMatchObject({
      severity: 'warning',
      message: expect.stringContaining('boom'),
    });
  });

  it('flags tenant columns without an index', async () => {
    const snap = snapshot((tables) => {
      const notes = table(tables, 'notes');
      notes.indexes = notes.indexes.filter(
        (index) => index.columns[0] !== 'organization_id',
      );
    });
    expect(await codes(context(snap))).toEqual(['BS204']);
  });

  it('flags soft delete hidden by a select policy and bucket drift', async () => {
    const snap = snapshot((tables) => {
      edit(table(tables, 'customers').policies).push({
        name: 'live_only',
        command: 'select',
        roles: ['authenticated'],
        permissive: false,
        using: '(archived_at IS NULL)',
        check: null,
      });
    });
    const ctx = context(snap, {
      config: resolveConfig(
        {
          plugins: { softDelete: { column: 'archived_at' } },
          buckets: {
            customerLogos: { path: '{orgId}/logo.webp', fileSizeLimit: '1MiB' },
            avatars: { path: '{userId}.png' },
          },
        },
        '/project',
      ),
    });
    const findings = await runRules(
      ctx,
      RULES.filter((rule) => ['BS301', 'BS302'].includes(rule.code)),
    );
    expect(findings.map((finding) => finding.code)).toEqual([
      'BS301',
      'BS302',
      'BS302',
      'BS302',
    ]);
    expect(findings.map((finding) => finding.message).join('\n')).toMatch(
      /avatars/,
    );
  });

  it('reads supabase/config.toml', async () => {
    const configToml = toml(
      '[api]\nport = 1\n\n[auth]\njwt_expiry = 7200\nenable_refresh_token_rotation = true\nrefresh_token_reuse_interval = 0\n\n[db]\nport = 2\n',
    );
    const findings = await runRules(
      context(base, { configToml }),
      RULES.filter((rule) => rule.code.startsWith('BS4')),
    );
    expect(
      findings.map((finding) => [finding.code, finding.location?.line]),
    ).toEqual([
      ['BS401', 7],
      ['BS402', 5],
      ['BS403', 4],
    ]);
    const fine = toml(
      '[auth]\nsigning_keys_path = "./signing_keys.json"\nrefresh_token_reuse_interval = 10\n',
    );
    expect(await codes(context(base, { configToml: fine }))).toEqual([]);
  });

  it('compares configured buckets with config.toml', async () => {
    const ctx = context(base, {
      config: resolveConfig(
        {
          buckets: {
            customerLogos: {
              path: '{orgId}/logo.webp',
              fileSizeLimit: '1MiB',
              allowedMimeTypes: ['image/webp'],
            },
          },
        },
        '/project',
      ),
      configToml: toml(
        '[storage]\nenabled = true\n\n[storage.buckets.customer-logos]\npublic = true\nfile_size_limit = "1MiB"\nallowed_mime_types = ["image/webp"] # logos\n',
      ),
    });
    const findings = await runRules(
      ctx,
      RULES.filter((rule) => rule.code === 'BS302'),
    );
    expect(
      findings
        .filter(
          (finding) => finding.target === '[storage.buckets.customer-logos]',
        )
        .map((finding) => [finding.message, finding.location?.line]),
    ).toEqual([
      [
        'supabase/config.toml [storage.buckets.customer-logos]: public is true',
        4,
      ],
    ]);
  });

  it('parses the config.toml subset supabase init writes', () => {
    expect(
      parseTomlSubset(
        '# c\n[db]\nport = 54_322\n[auth.email]\nenable_confirmations = false\nsite_url = "http://x" # note\nredirects = ["a", \'b\']\n[storage.buckets."my-bucket"]\npublic = true\n',
      ),
    ).toEqual({
      db: { port: 54322 },
      auth: {
        email: {
          enable_confirmations: false,
          site_url: 'http://x',
          redirects: ['a', 'b'],
        },
      },
      storage: { buckets: { 'my-bucket': { public: true } } },
    });
  });

  it('checks env files without printing values', async () => {
    const envFiles = [
      {
        path: '.env.local',
        text: 'NEXT_PUBLIC_SUPABASE_URL=http://x\nNEXT_PUBLIC_SUPABASE_SECRET_KEY="sb_secret_abc"\n',
      },
      { path: '.env', text: 'SUPABASE_DB_URL=postgresql://u:p@h/db\n' },
      { path: 'apps/web/.env.example', text: 'SUPABASE_SECRET_KEY=\n' },
    ];
    const findings = await runRules(
      context(base, { envFiles, gitignore: '# env\n.env*.local\n' }),
      RULES.filter((rule) => rule.code.startsWith('BS5')),
    );
    expect(
      findings.map((finding) => [
        finding.code,
        finding.target,
        finding.location?.line,
      ]),
    ).toEqual([
      ['BS501', '.env.local:NEXT_PUBLIC_SUPABASE_SECRET_KEY', 2],
      ['BS502', '.env', 1],
    ]);
    expect(JSON.stringify(findings)).not.toContain('sb_secret_abc');
  });
});

describe('doctor formats', () => {
  const findings = [
    {
      code: 'BS103',
      severity: 'error' as const,
      title: 'Policy allows anonymous writes',
      message: 'public.x has RLS disabled, really: 100%',
      target: 'public.x',
      location: { file: 'supabase/schemas/x.sql', line: 3 },
      help: 'https://better-supabase.dev/docs/cli/doctor#bs103',
    },
    {
      code: 'BS403',
      severity: 'info' as const,
      title: 'Local stack signs tokens with a shared secret',
      message: 'No signing keys.',
      help: 'https://better-supabase.dev/docs/cli/doctor#bs403',
    },
  ];
  const options = {
    rules: RULES,
    version: '1.0.0',
    fallbackFile: 'supabase/config.toml',
  };

  it('writes SARIF 2.1.0 with rules and locations', () => {
    const sarif = JSON.parse(
      formatReport(findings, { ...options, format: 'sarif' }),
    ) as {
      version: string;
      runs: {
        tool: { driver: { rules: { id: string; name: string }[] } };
        results: Record<string, unknown>[];
      }[];
    };
    expect(sarif.version).toBe('2.1.0');
    const [runEntry] = sarif.runs;
    expect(runEntry!.tool.driver.rules.map((rule) => rule.id)).toEqual(
      RULE_CODES,
    );
    expect(runEntry!.tool.driver.rules[0]!.name).toBe(
      'SupabaseSecurityAdvisor',
    );
    expect(runEntry!.results[0]).toMatchObject({
      ruleId: 'BS103',
      level: 'error',
      locations: [
        {
          physicalLocation: {
            artifactLocation: { uri: 'supabase/schemas/x.sql' },
            region: { startLine: 3 },
          },
        },
      ],
    });
    expect(runEntry!.results[1]).toMatchObject({
      level: 'note',
      locations: [
        {
          physicalLocation: {
            artifactLocation: { uri: 'supabase/config.toml' },
          },
        },
      ],
    });
  });

  it('writes GitHub annotations and JSON with a $schema', () => {
    const github = formatReport(findings, {
      ...options,
      format: 'github',
    }).split('\n');
    expect(github[0]).toBe(
      '::error file=supabase/schemas/x.sql,line=3,title=BS103 Policy allows anonymous writes::public.x has RLS disabled, really: 100%25 (https://better-supabase.dev/docs/cli/doctor#bs103)',
    );
    expect(github[1]).toMatch(/^::notice title=BS403/);
    const json = JSON.parse(
      formatReport(findings, { ...options, format: 'json' }),
    ) as Record<string, unknown>;
    expect(json).toMatchObject({
      $schema:
        'https://unpkg.com/better-supabase/schemas/doctor-report-v1.json',
      summary: { errors: 1, warnings: 0, infos: 1 },
    });
    expect(formatReport([], { ...options, format: 'text' })).toBe(
      'No problems found.',
    );
  });
});

describe('doctor command', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'better-supabase-doctor-'));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  async function write(path: string, contents: string): Promise<void> {
    await mkdir(dirname(join(dir, path)), { recursive: true });
    await writeFile(join(dir, path), contents);
  }

  it('locates findings in SQL files and sets the exit code', async () => {
    const snap = snapshot((tables) => {
      edit(table(tables, 'notes').policies).push({
        name: 'anyone',
        command: 'insert',
        roles: ['anon'],
        permissive: true,
        using: null,
        check: 'true',
      });
      const notes = table(tables, 'notes');
      notes.indexes = notes.indexes.filter(
        (index) => index.columns[0] !== 'organization_id',
      );
    });
    await write('snapshot.json', JSON.stringify(snap));
    await write(
      'supabase/migrations/001_init.sql',
      'create policy "anyone" on public.notes;\n',
    );
    await write(
      'supabase/migrations/002_more.sql',
      '\n\ncreate policy anyone on "public"."notes" (\n);\n',
    );
    await write(
      'better-supabase.config.json',
      JSON.stringify({
        doctor: { ignore: ['BS303'] },
        plugins: { tenant: true },
      }),
    );

    const result = await run([
      'doctor',
      '--snapshot',
      'snapshot.json',
      '--format',
      'json',
      '--cwd',
      dir,
    ]);
    expect(result.code).toBe(1);
    const report = JSON.parse(result.stdout) as {
      findings: { code: string; location?: unknown }[];
    };
    expect(
      report.findings.find((finding) => finding.code === 'BS103')?.location,
    ).toEqual({
      file: 'supabase/migrations/002_more.sql',
      line: 3,
    });

    const warnings = await run([
      'doctor',
      '--snapshot',
      'snapshot.json',
      '--only',
      'BS204',
      '--cwd',
      dir,
    ]);
    expect(warnings.code).toBe(0);
    expect(warnings.stdout).toContain('BS204');
    expect(
      (
        await run([
          'doctor',
          '--snapshot',
          'snapshot.json',
          '--only',
          'BS204',
          '--strict',
          '--cwd',
          dir,
        ])
      ).code,
    ).toBe(1);
    expect(
      (
        await run([
          'doctor',
          '--snapshot',
          'snapshot.json',
          '--only',
          'BS999',
          '--cwd',
          dir,
        ])
      ).code,
    ).toBe(2);
    expect(
      (
        await run([
          'doctor',
          '--snapshot',
          'snapshot.json',
          '--format',
          'xml',
          '--cwd',
          dir,
        ])
      ).code,
    ).toBe(2);

    const sarif = await run([
      'doctor',
      '--snapshot',
      'snapshot.json',
      '--format',
      'sarif',
      '--out',
      'doctor.sarif',
      '--cwd',
      dir,
    ]);
    expect(sarif.stdout).toContain('Wrote doctor.sarif: 1 errors');
    expect(
      JSON.parse(await readFile(join(dir, 'doctor.sarif'), 'utf8')),
    ).toMatchObject({ version: '2.1.0' });
  });

  it('locates functions and policies', () => {
    const files = [
      {
        path: 'supabase/schemas/a.sql',
        text: 'create or replace function public.do_it()\nreturns void',
      },
      {
        path: 'supabase/schemas/b.sql',
        text: '\ncreate policy "Tenant read" on public.x',
      },
    ];
    expect(
      locate(files, { kind: 'function', schema: 'public', name: 'do_it' }),
    ).toEqual({ file: 'supabase/schemas/a.sql', line: 1 });
    expect(
      locate(files, { kind: 'policy', schema: 'public', name: 'Tenant read' }),
    ).toEqual({ file: 'supabase/schemas/b.sql', line: 2 });
    expect(
      locate(files, { kind: 'table', schema: 'public', name: 'do_it' }),
    ).toBeUndefined();
  });

  it('documents every check', async () => {
    const docs = await readFile(
      new URL(
        '../../../../../apps/docs/content/docs/cli/doctor.mdx',
        import.meta.url,
      ),
      'utf8',
    );
    for (const code of RULE_CODES) expect(docs).toContain(`### ${code}`);
    const schema = JSON.parse(
      await readFile(
        new URL('../../../schemas/doctor-report-v1.json', import.meta.url),
        'utf8',
      ),
    ) as {
      properties: {
        findings: { items: { properties: { code: { enum: string[] } } } };
      };
    };
    expect(schema.properties.findings.items.properties.code.enum).toEqual(
      RULE_CODES,
    );
  });
});
