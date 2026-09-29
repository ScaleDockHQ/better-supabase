import { existsSync } from 'node:fs';
import { glob, readdir, readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

import type { ResolvedConfig } from '../../config/index.ts';
import type { ParsedArgs } from '../args.ts';
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
}

type Env = Readonly<Record<string, string | undefined>>;

interface OpenAdvisors {
  readonly advisors: DoctorContext['advisors'];
  close(): Promise<void>;
}

/**
 * Advisors for the database doctor reads: the Management API for hosted
 * projects, splinter over the connection otherwise. Saved snapshots skip them.
 */
async function openAdvisors(
  config: ResolvedConfig,
  env: Env,
  source: SnapshotSource,
): Promise<OpenAdvisors> {
  const none = { close: () => Promise.resolve() };
  const file = snapshotFile(config, source);
  if (file) {
    return {
      ...none,
      advisors: {
        skipped: `reading the saved snapshot ${file}; pass --db-url or --project-ref to lint a database.`,
      },
    };
  }
  const target = managementTarget(config, env, source);
  if (target) return { ...none, advisors: managementAdvisors(target) };
  let opened: Awaited<ReturnType<typeof openSource>> | undefined;
  let splinter: Promise<AdvisorSource> | undefined;
  const cacheDir = resolve(config.root, 'node_modules/.cache/better-supabase');
  const advisors: AdvisorSource = {
    describe: 'database (splinter)',
    async lints(category) {
      splinter ??= openSource(config, env, source).then((db) => {
        opened = db;
        return splinterAdvisors(db.queryable, db.describe, { cacheDir });
      });
      return (await splinter).lints(category);
    },
  };
  return { advisors, close: async () => opened?.close() };
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
  const rules = RULES.filter(
    (rule) =>
      (only.length === 0 || only.includes(rule.code)) && !ignore.has(rule.code),
  );

  const snapshotPath = flagString(args.flags, 'snapshot');
  const dbUrl = flagString(args.flags, 'db-url');
  const projectRef = flagString(args.flags, 'project-ref');
  const source: SnapshotSource = {
    ...(snapshotPath ? { snapshotPath } : {}),
    ...(dbUrl ? { dbUrl } : {}),
    ...(projectRef ? { projectRef } : {}),
  };
  const snapshot =
    options.snapshot ?? (await loadSnapshot(config, env, source));
  const wantsAdvisors = rules.some(
    (rule) => rule.code === 'BS100' || rule.code === 'BS200',
  );
  const opened =
    options.advisors !== undefined || options.snapshot || !wantsAdvisors
      ? { advisors: options.advisors, close: () => Promise.resolve() }
      : await openAdvisors(config, env, source);
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
    ...(opened.advisors ? { advisors: opened.advisors } : {}),
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
