import type { ResolvedConfig } from "better-supabase/config";

import { existsSync } from "node:fs";
import { glob, readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { AnyCommand, CliArgs } from "../command.ts";
import type { LiveDatabase } from "../doctor/live.ts";
import type { IntrospectionSource } from "../introspect/source.ts";
import type { Snapshot } from "../introspect/types.ts";
import type { CommandResult } from "../io.ts";

import { defineCliCommand, list } from "../command.ts";
import { connect } from "../db.ts";
import {
  type AdvisorSource,
  managementAdvisors,
  splinterAdvisors,
} from "../doctor/advisors.ts";
import {
  DOCTOR_FORMATS,
  type DoctorFormat,
  formatReport,
} from "../doctor/format.ts";
import { hookGrantBlock, hookGrantProblems } from "../doctor/hooks.ts";
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
} from "../doctor/rules.ts";
import { writeIfChanged } from "../io.ts";
import { readPermdock } from "../permdock.ts";
import { withSpinner } from "../prompts.ts";
import { compiledReadSets } from "../read-sets.ts";
import { type Paint, painter } from "../style.ts";
import {
  readSupabaseToml,
  schemaPaths,
  type SupabaseToml,
} from "../supabase-toml.ts";
import { VERSION } from "../version.ts";
import {
  loadSnapshot,
  managementTarget,
  openSource,
  type SnapshotSource,
  snapshotFile,
} from "./snapshot.ts";

const ARGS = {
  format: {
    type: "string",
    description:
      "text (default), json, sarif (code scanning) or github (workflow annotations)",
    valueHint: "format",
  },
  out: {
    type: "string",
    description: "Write the report to a file",
    valueHint: "file",
  },
  only: {
    type: "string",
    description: "Run only these checks, e.g. --only BS100,BS304",
    valueHint: "codes",
  },
  ignore: {
    type: "string",
    description: "Skip checks; also doctor.ignore in the config",
    valueHint: "codes",
  },
  strict: {
    type: "boolean",
    description: "Fail on warnings; also doctor.strict",
  },
  snapshot: {
    type: "string",
    description: "Check a saved snapshot instead of the database",
    valueHint: "file",
  },
  "db-url": {
    type: "string",
    description: "Read this database",
    valueHint: "url",
  },
  "project-ref": {
    type: "string",
    description: "Read a hosted project through the Management API",
    valueHint: "ref",
  },
  stats: {
    type: "boolean",
    description:
      "Report slow frequent statements from pg_stat_statements (BS209)",
  },
  explain: {
    type: "string",
    description: "EXPLAIN ANALYZE these tables under RLS, rolled back (BS212)",
    valueHint: "tables",
  },
  as: {
    type: "string",
    description:
      "Plan as this authenticated user, and measure the claims the custom access token hook returns for them (BS405)",
    valueHint: "uuid",
  },
  claims: {
    type: "string",
    description: 'Plan with these JWT claims ({"role":"authenticated",...})',
    valueHint: "json",
  },
  "fix-grants": {
    type: "boolean",
    description:
      "Print the grant and revoke SQL BS404 asks for, to append to the migration `supabase db diff` wrote",
  },
} as const;

export type DoctorArgs = CliArgs<typeof ARGS>;

const ENV_FILES = [
  ".env",
  ".env.local",
  ".env.development",
  ".env.development.local",
  ".env.production",
  ".env.production.local",
];

async function readText(
  root: string,
  path: string,
): Promise<TextFile | undefined> {
  const absolute = resolve(root, path);
  return existsSync(absolute)
    ? { path, text: await readFile(absolute, "utf8") }
    : undefined;
}

/** The declarative schemas in `schema_paths` order, then the migrations newest first. */
async function sqlFiles(
  root: string,
  toml: SupabaseToml | undefined,
): Promise<TextFile[]> {
  const read = async (path: string): Promise<TextFile> => ({
    path,
    text: await readFile(resolve(root, path), "utf8"),
  });
  const schemas = await Promise.all(
    (await schemaPaths(root, toml)).files.map(read),
  );
  const migrationsDir = resolve(root, "supabase/migrations");
  const migrations = existsSync(migrationsDir)
    ? (await readdir(migrationsDir))
        .filter((name) => name.endsWith(".sql"))
        .sort()
        .reverse()
        .map((name) => `supabase/migrations/${name}`)
    : [];
  return [...schemas, ...(await Promise.all(migrations.map(read)))];
}

/** Files matching `doctor.sources`, skipping dependencies and build output. */
async function sourceFiles(config: ResolvedConfig): Promise<TextFile[]> {
  const files: TextFile[] = [];
  for await (const path of glob([...config.doctor.sources], {
    cwd: config.root,
    exclude: (name) => name === "node_modules" || name === ".next",
  })) {
    files.push({
      path,
      text: await readFile(resolve(config.root, path), "utf8"),
    });
  }
  return files.sort((a, b) => a.path.localeCompare(b.path));
}

const escape = (name: string): string =>
  name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** Where a table, function or policy is declared: declarative schemas first, then the newest migration. */
export function locate(
  files: readonly TextFile[],
  object: SqlObject,
): Location | undefined {
  const name = `"?${escape(object.name)}"?`;
  const qualifiedName = `(?:"?${escape(object.schema)}"?\\.)?${name}`;
  const pattern =
    object.kind === "table"
      ? new RegExp(
          `create\\s+(?:unlogged\\s+)?table\\s+(?:if\\s+not\\s+exists\\s+)?${qualifiedName}(?:\\s|\\(|$)`,
          "i",
        )
      : object.kind === "function"
        ? new RegExp(
            `create\\s+(?:or\\s+replace\\s+)?function\\s+${qualifiedName}\\s*\\(`,
            "i",
          )
        : new RegExp(`create\\s+policy\\s+${name}`, "i");
  for (const file of files) {
    const line = lineOf(file.text, pattern);
    if (line) return { file: file.path, line };
  }
  return undefined;
}

function parseFormat(value: string | undefined): DoctorFormat | undefined {
  if (value === undefined) return "text";
  // SAFETY: includes only compares values; the check makes value a DoctorFormat.
  return (DOCTOR_FORMATS as readonly string[]).includes(value)
    ? (value as DoctorFormat)
    : undefined;
}

export interface DoctorOptions {
  /** Pre-loaded snapshot (tests). */
  readonly snapshot?: Snapshot;
  /** Advisor results (tests); otherwise read from the database being checked. */
  readonly advisors?: DoctorContext["advisors"];
  /** The live database (tests); otherwise the database being checked. */
  readonly database?: DoctorContext["database"];
  /** Opens `pg` connections (tests); defaults to `connect`. */
  readonly connect?: typeof connect;
  /** Colors the text report. */
  readonly paint?: Paint;
}

/** Checks that read the database itself rather than the snapshot. */
const LIVE_CODES = new Set(["BS100", "BS200", "BS208", "BS209", "BS212"]);

type Env = Readonly<Record<string, string | undefined>>;

interface OpenLive {
  readonly advisors: DoctorContext["advisors"];
  readonly database: DoctorContext["database"];
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
  pg: typeof connect,
): OpenLive {
  const none = { close: () => Promise.resolve() };
  const file = snapshotFile(config, source);
  if (file) {
    const skipped = `reading the saved snapshot ${file}; pass --db-url or --project-ref to check a database.`;
    return { ...none, advisors: { skipped }, database: { skipped } };
  }
  let opened: Promise<IntrospectionSource> | undefined;
  const open = (): Promise<IntrospectionSource> =>
    (opened ??= openSource(config, env, source, pg));
  const target = managementTarget(config, env, source);
  const database: LiveDatabase = {
    describe: target
      ? `project ${target.projectRef} (Management API)`
      : "database",
    session: !target,
    async query<R>(sql: string) {
      const result = await (await open()).queryable.query(sql);
      // SAFETY: R is the row type the caller declares for its query.
      return result.rows as R[];
    },
  };
  const close = async (): Promise<void> => {
    if (opened) await (await opened).close();
  };
  if (target) return { advisors: managementAdvisors(target), database, close };
  let splinter: Promise<AdvisorSource> | undefined;
  const cacheDir = resolve(config.root, "node_modules/.cache/better-supabase");
  const advisors: AdvisorSource = {
    describe: "database (splinter)",
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
  args: DoctorArgs,
): Record<string, unknown> | { error: string } {
  const as = args.as;
  const claims = args.claims;
  if (as && claims) return { error: "Pass --as or --claims, not both" };
  if (as) {
    if (!UUID.test(as))
      return { error: `--as takes a user id (uuid), got "${as}"` };
    return { sub: as, role: "authenticated" };
  }
  if (!claims) return { role: "anon" };
  try {
    // SAFETY: JSON.parse returns any, and the object check below narrows it.
    const parsed = JSON.parse(claims) as unknown;
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed))
      return { error: "--claims takes a JSON object" };
    // SAFETY: the check above narrows parsed to a plain object.
    return { role: "anon", ...(parsed as Record<string, unknown>) };
  } catch (cause) {
    return {
      error: `--claims is not valid JSON: ${cause instanceof Error ? cause.message : String(cause)}`,
    };
  }
}

export async function runDoctor(
  config: ResolvedConfig,
  args: DoctorArgs,
  env: Readonly<Record<string, string | undefined>>,
  options: DoctorOptions = {},
): Promise<CommandResult> {
  const format = parseFormat(args.format);
  if (!format)
    return {
      code: 2,
      error: `--format must be one of ${DOCTOR_FORMATS.join(", ")}`,
    };
  const only = list(args.only);
  const ignore = new Set([...config.doctor.ignore, ...list(args.ignore)]);
  const unknown = [...only, ...ignore].filter(
    (code) => !RULE_CODES.includes(code),
  );
  if (unknown.length > 0)
    return {
      code: 2,
      error: `Unknown check ${unknown.join(", ")}. Checks: ${RULE_CODES.join(", ")}`,
    };
  const explainTables = list(args.explain);
  const stats = args.stats === true;
  const claims = explainClaims(args);
  if ("error" in claims) return { code: 2, error: String(claims.error) };
  // --stats and --explain ask for their checks even when --only leaves them out.
  const hookUser = args.as;
  const asked = new Set([
    ...(stats ? ["BS209"] : []),
    ...(explainTables.length > 0 ? ["BS212"] : []),
    ...(hookUser ? ["BS405"] : []),
  ]);
  const fixGrants = args["fix-grants"] === true;
  const rules = fixGrants
    ? RULES.filter((rule) => rule.code === "BS404")
    : RULES.filter(
        (rule) =>
          (only.length === 0 ||
            only.includes(rule.code) ||
            asked.has(rule.code)) &&
          !ignore.has(rule.code),
      );

  const snapshotPath = args.snapshot;
  const dbUrl = args["db-url"];
  const projectRef = args["project-ref"];
  const source: SnapshotSource = {
    // Statistics, plans and hook calls need the database, not the saved snapshot.
    ...(stats || explainTables.length > 0 || hookUser ? { live: true } : {}),
    ...(snapshotPath ? { snapshotPath } : {}),
    ...(dbUrl ? { dbUrl } : {}),
    ...(projectRef ? { projectRef } : {}),
  };
  const pg = options.connect ?? connect;
  const snapshot =
    options.snapshot ?? (await loadSnapshot(config, env, source, pg));
  const wantsLive =
    hookUser !== undefined || rules.some((rule) => LIVE_CODES.has(rule.code));
  const opened: OpenLive =
    options.snapshot || !wantsLive
      ? {
          advisors: options.advisors,
          database: options.database,
          close: () => Promise.resolve(),
        }
      : {
          ...openLive(config, env, source, pg),
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
  const permdock = await readPermdock(config.root, config.permdock);
  const configToml = await readSupabaseToml(config.root);
  const sql = await sqlFiles(config.root, configToml);
  const context: DoctorContext = {
    config,
    snapshot,
    ...(permdock ? { permdock } : {}),
    sqlFiles: sql,
    configToml,
    envFiles,
    gitignore: (await readText(config.root, ".gitignore"))?.text ?? "",
    sources: await sourceFiles(config),
    readSets: await compiledReadSets(config).catch((cause: unknown) => ({
      skipped: cause instanceof Error ? cause.message : String(cause),
    })),
    ...(opened.advisors ? { advisors: opened.advisors } : {}),
    ...(opened.database ? { database: opened.database } : {}),
    ...(stats ? { stats } : {}),
    ...(hookUser ? { hookUser } : {}),
    ...(explainTables.length > 0
      ? { explain: { tables: explainTables, claims } }
      : {}),
  };
  if (fixGrants) {
    await opened.close();
    return { code: 0, output: hookGrantBlock(hookGrantProblems(context)) };
  }
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

  const out = args.out;
  const report = formatReport(findings, {
    format,
    rules,
    version: VERSION,
    fallbackFile: context.configToml?.path ?? "package.json",
    ...(options.paint && !out ? { paint: options.paint } : {}),
  });
  const errors = findings.filter(
    (finding) => finding.severity === "error",
  ).length;
  const warnings = findings.filter(
    (finding) => finding.severity === "warning",
  ).length;
  const strict = args.strict === true || config.doctor.strict;
  const code = errors > 0 || (strict && warnings > 0) ? 1 : 0;

  if (out) {
    await writeIfChanged(resolve(config.root, out), `${report}\n`);
    return {
      code,
      output: `Wrote ${out}: ${errors} errors, ${warnings} warnings.`,
    };
  }
  return { code, output: report };
}

export const doctorCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "doctor",
    description:
      "Checks RLS, indexes, drift, auth config and env files; exits 1 on errors, or on warnings with --strict",
  },
  args: ARGS,
  lists: ["only", "ignore", "explain"],
  run: (args, { config, env, io }) =>
    withSpinner(
      args.snapshot === undefined ? io.prompts : undefined,
      "Checking the database",
      () => runDoctor(config, args, env, { paint: painter(io.color) }),
    ),
});
