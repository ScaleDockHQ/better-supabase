import { existsSync } from 'node:fs';
import { glob, readdir, readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

import type { ResolvedConfig } from '../../config/index.ts';
import type { ParsedArgs } from '../args.ts';
import type { LiveDatabase } from '../doctor/live.ts';
import type { IntrospectionSource } from '../introspect/source.ts';
import type { Snapshot } from '../introspect/types.ts';
import type { CommandResult } from '../io.ts';

import { flagBool, flagList, flagString } from '../args.ts';
import {
  type AdvisorSource,
  managementAdvisors,
  splinterAdvisors,
} from '../doctor/advisors.ts';
import {
  DOCTOR_FORMATS,
  type DoctorFormat,
  formatReport,
} from '../doctor/format.ts';
import {
  type DoctorContext,
  type Finding,
  lineOf,
  type Location,
  RULE_CODES,
  RULES,
  runRules,
  type SqlObject,
  type TextFile,
} from '../doctor/rules.ts';
import { writeIfChanged } from '../io.ts';
import { compiledReadSets } from '../read-sets.ts';
import { readSupabaseToml } from '../supabase-toml.ts';
import { VERSION } from '../version.ts';
import {
  loadSnapshot,
  managementTarget,
  openSource,
  type SnapshotSource,
  snapshotFile,
} from './snapshot.ts';

export const DOCTOR_HELP: string = `Usage: better-supabase doctor [--format text|json|sarif|github] [--out <file>] [--strict]

Checks the database, supabase/config.toml and env files for security,
performance and drift problems. BS100/BS200 are Supabase's Security and
Performance Advisors (Management API for hosted projects, splinter otherwise). Exits 1 when there are errors (or warnings with --strict).

Options
  --format <f>      text (default), json, sarif (code scanning) or github (workflow annotations)
  --out <file>      Write the report to a file
  --only <codes>    Run only these checks, e.g. --only BS100,BS304
  --ignore <codes>  Skip checks; also doctor.ignore in the config
  --strict          Fail on warnings; also doctor.strict
  --snapshot <file> Check a saved snapshot instead of the database
  --db-url <url>    Read this database
  --project-ref <r> Read a hosted project through the Management API
  --stats           Report slow frequent statements from pg_stat_statements (BS209)
  --explain <t,..>  EXPLAIN ANALYZE the tables under RLS, rolled back (BS212)
  --as <uuid>       Plan as this authenticated user
  --claims <json>   Plan with these JWT claims ({"role":"authenticated",...})

Checks: ${RULE_CODES.join(', ')}`;

const ENV_FILES = [
  '.env',
  '.env.local',
  '.env.development',
  '.env.development.local',
  '.env.production',
  '.env.production.local',
];

async function readText(
  root: string,
  path: string,
): Promise<TextFile | undefined> {
  const absolute = resolve(root, path);
  return existsSync(absolute)
    ? { path, text: await readFile(absolute, 'utf8') }
    : undefined;
}

async function sqlFiles(root: string): Promise<TextFile[]> {
  const files: TextFile[] = [];
  const walk = async (dir: string): Promise<void> => {
    const absolute = resolve(root, dir);
    if (!existsSync(absolute)) return;
    for (const entry of await readdir(absolute, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) await walk(path);
      else if (entry.name.endsWith('.sql'))
        files.push({ path, text: await readFile(resolve(root, path), 'utf8') });
    }
  };
  await walk('supabase/schemas');
  const migrations: TextFile[] = [];
  const before = files.length;
  await walk('supabase/migrations');
  migrations.push(...files.splice(before).reverse());
  return [...files, ...migrations];
}

/** Files matching `doctor.sources`, skipping dependencies and build output. */
async function sourceFiles(config: ResolvedConfig): Promise<TextFile[]> {
  const files: TextFile[] = [];
  for await (const path of glob([...config.doctor.sources], {
    cwd: config.root,
    exclude: (name) => name === 'node_modules' || name === '.next',
  })) {
    files.push({
      path,
      text: await readFile(resolve(config.root, path), 'utf8'),
    });
  }
  return files.sort((a, b) => a.path.localeCompare(b.path));
}

const escape = (name: string): string =>
  name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Where a table, function or policy is declared: declarative schemas first, then the newest migration. */
export function locate(
  files: readonly TextFile[],
  object: SqlObject,
): Location | undefined {
  const name = `"?${escape(object.name)}"?`;
  const qualifiedName = `(?:"?${escape(object.schema)}"?\\.)?${name}`;
  const pattern =
    object.kind === 'table'
      ? new RegExp(
          `create\\s+(?:unlogged\\s+)?table\\s+(?:if\\s+not\\s+exists\\s+)?${qualifiedName}(?:\\s|\\(|$)`,
          'i',
        )
      : object.kind === 'function'
        ? new RegExp(
            `create\\s+(?:or\\s+replace\\s+)?function\\s+${qualifiedName}\\s*\\(`,
            'i',
          )
        : new RegExp(`create\\s+policy\\s+${name}`, 'i');
  for (const file of files) {
    const line = lineOf(file.text, pattern);
    if (line) return { file: file.path, line };
  }
  return undefined;
}

function parseFormat(value: string | undefined): DoctorFormat | undefined {
  if (value === undefined) return 'text';
  return (DOCTOR_FORMATS as readonly string[]).includes(value)
    ? (value as DoctorFormat)
    : undefined;
}

export interface DoctorOptions {
  /** Pre-loaded snapshot (tests). */
  readonly snapshot?: Snapshot;
  /** Advisor results (tests); otherwise read from the database being checked. */
  readonly advisors?: DoctorContext['advisors'];
  /** The live database (tests); otherwise the database being checked. */
  readonly database?: DoctorContext['database'];
}

/** Checks that read the database itself rather than the snapshot. */
const LIVE_CODES = new Set(['BS100', 'BS200', 'BS208', 'BS209', 'BS212']);

type Env = Readonly<Record<string, string | undefined>>;

interface OpenLive {
  readonly advisors: DoctorContext['advisors'];
  readonly database: DoctorContext['database'];
  close(): Promise<void>;
}

/**
 * The database doctor reads, for advisors and live checks: the Management
 * API for hosted projects, one lazily opened connection otherwise (splinter
 * runs over it). Saved snapshots skip both.
 */
function openLive(
  config: ResolvedConfig,
  env: Env,
  source: SnapshotSource,
): OpenLive {
  const none = { close: () => Promise.resolve() };
  const file = snapshotFile(config, source);
  if (file) {
    const skipped = `reading the saved snapshot ${file}; pass --db-url or --project-ref to check a database.`;
    return { ...none, advisors: { skipped }, database: { skipped } };
  }
  let opened: Promise<IntrospectionSource> | undefined;
  const open = (): Promise<IntrospectionSource> =>
    (opened ??= openSource(config, env, source));
  const target = managementTarget(config, env, source);
  const database: LiveDatabase = {
    describe: target
      ? `project ${target.projectRef} (Management API)`
      : 'database',
    session: !target,
    async query<R>(sql: string) {
      const result = await (await open()).queryable.query(sql);
      return result.rows as R[];
    },
  };
  const close = async (): Promise<void> => {
    if (opened) await (await opened).close();
  };
  if (target) return { advisors: managementAdvisors(target), database, close };
  let splinter: Promise<AdvisorSource> | undefined;
  const cacheDir = resolve(config.root, 'node_modules/.cache/better-supabase');
  const advisors: AdvisorSource = {
    describe: 'database (splinter)',
    async lints(category) {
      splinter ??= open().then((db) =>
        splinterAdvisors(db.queryable, db.describe, { cacheDir }),
      );
      return (await splinter).lints(category);
    },
  };
  return { advisors, database, close };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** `--as <uuid>` or `--claims <json>` as `request.jwt.claims`. */
function explainClaims(
  args: ParsedArgs,
): Record<string, unknown> | { error: string } {
  const as = flagString(args.flags, 'as');
  const claims = flagString(args.flags, 'claims');
  if (as && claims) return { error: 'Pass --as or --claims, not both' };
  if (as) {
    if (!UUID.test(as))
      return { error: `--as takes a user id (uuid), got "${as}"` };
    return { sub: as, role: 'authenticated' };
  }
  if (!claims) return { role: 'anon' };
  try {
    const parsed = JSON.parse(claims) as unknown;
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed))
      return { error: '--claims takes a JSON object' };
    return { role: 'anon', ...(parsed as Record<string, unknown>) };
  } catch (cause) {
    return {
      error: `--claims is not valid JSON: ${cause instanceof Error ? cause.message : String(cause)}`,
    };
  }
}

export async function runDoctor(
  config: ResolvedConfig,
  args: ParsedArgs,
  env: Readonly<Record<string, string | undefined>>,
  options: DoctorOptions = {},
): Promise<CommandResult> {
  const format = parseFormat(flagString(args.flags, 'format'));
  if (!format)
    return {
      code: 2,
      error: `--format must be one of ${DOCTOR_FORMATS.join(', ')}`,
    };
  const only = flagList(args.flags, 'only');
  const ignore = new Set([
    ...config.doctor.ignore,
    ...flagList(args.flags, 'ignore'),
  ]);
  const unknown = [...only, ...ignore].filter(
    (code) => !RULE_CODES.includes(code),
  );
  if (unknown.length > 0)
    return {
      code: 2,
      error: `Unknown check ${unknown.join(', ')}. Checks: ${RULE_CODES.join(', ')}`,
    };
  const explainTables = flagList(args.flags, 'explain');
  const stats = flagBool(args.flags, 'stats');
  const claims = explainClaims(args);
  if ('error' in claims) return { code: 2, error: String(claims.error) };
  // --stats and --explain ask for their checks even when --only leaves them out.
  const asked = new Set([
    ...(stats ? ['BS209'] : []),
    ...(explainTables.length > 0 ? ['BS212'] : []),
  ]);
  const rules = RULES.filter(
    (rule) =>
      (only.length === 0 || only.includes(rule.code) || asked.has(rule.code)) &&
      !ignore.has(rule.code),
  );

  const snapshotPath = flagString(args.flags, 'snapshot');
  const dbUrl = flagString(args.flags, 'db-url');
  const projectRef = flagString(args.flags, 'project-ref');
  const source: SnapshotSource = {
    // Statistics and plans need the database, not the saved snapshot.
    ...(stats || explainTables.length > 0 ? { live: true } : {}),
    ...(snapshotPath ? { snapshotPath } : {}),
    ...(dbUrl ? { dbUrl } : {}),
    ...(projectRef ? { projectRef } : {}),
  };
  const snapshot =
    options.snapshot ?? (await loadSnapshot(config, env, source));
  const wantsLive = rules.some((rule) => LIVE_CODES.has(rule.code));
  const opened: OpenLive =
    options.snapshot || !wantsLive
      ? {
          advisors: options.advisors,
          database: options.database,
          close: () => Promise.resolve(),
        }
      : {
          ...openLive(config, env, source),
          ...(options.advisors !== undefined
            ? { advisors: options.advisors }
            : {}),
          ...(options.database !== undefined
            ? { database: options.database }
            : {}),
        };
  const envFiles = (
    await Promise.all(ENV_FILES.map((path) => readText(config.root, path)))
  ).filter((file): file is TextFile => file !== undefined);
  const context: DoctorContext = {
    config,
    snapshot,
    configToml: await readSupabaseToml(config.root),
    envFiles,
    gitignore: (await readText(config.root, '.gitignore'))?.text ?? '',
    sources: await sourceFiles(config),
    readSets: await compiledReadSets(config).catch((cause: unknown) => ({
      skipped: cause instanceof Error ? cause.message : String(cause),
    })),
    ...(opened.advisors ? { advisors: opened.advisors } : {}),
    ...(opened.database ? { database: opened.database } : {}),
    ...(stats ? { stats } : {}),
    ...(explainTables.length > 0
      ? { explain: { tables: explainTables, claims } }
      : {}),
  };
  const sql = await sqlFiles(config.root);
  let ran: Finding[];
  try {
    ran = await runRules(context, rules);
  } finally {
    await opened.close();
  }
  const findings: Finding[] = ran.map((finding) => {
    if (finding.location || !finding.object) return finding;
    const location = locate(sql, finding.object);
    return location ? { ...finding, location } : finding;
  });

  const report = formatReport(findings, {
    format,
    rules,
    version: VERSION,
    fallbackFile: context.configToml?.path ?? 'package.json',
  });
  const errors = findings.filter(
    (finding) => finding.severity === 'error',
  ).length;
  const warnings = findings.filter(
    (finding) => finding.severity === 'warning',
  ).length;
  const strict = flagBool(args.flags, 'strict') || config.doctor.strict;
  const code = errors > 0 || (strict && warnings > 0) ? 1 : 0;

  const out = flagString(args.flags, 'out');
  if (out) {
    await writeIfChanged(resolve(config.root, out), `${report}\n`);
    return {
      code,
      output: `Wrote ${out}: ${errors} errors, ${warnings} warnings.`,
    };
  }
  return { code, output: report };
}
