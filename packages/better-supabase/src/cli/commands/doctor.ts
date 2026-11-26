import { existsSync, statSync } from "node:fs";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { ConsentRequest } from "../core/agent.ts";
import type { AnyCommand, CliValues } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { DoctorPhase } from "../doctor/format.ts";
import type { OpenLive } from "../doctor/live-source.ts";
import type { DoctorContext, Finding, TextFile } from "../doctor/rules.ts";
import type { CliEnv } from "../env.ts";
import type { Snapshot } from "../introspect/types.ts";
import type { Paint } from "../style.ts";
import type { SnapshotSource } from "./snapshot.ts";

import { databaseUrl, isNoDatabase, stdinDatabaseUrl } from "../config.ts";
import { contentMapperSetup } from "../content-mapper.ts";
import { databaseHost, isLocalDatabaseUrl } from "../core/agent.ts";
import { defineCliCommand, list } from "../core/command.ts";
import { errorText, CliError } from "../core/errors.ts";
import { applyPlan, changeLines, insideRoot } from "../core/files.ts";
import { display } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { connect } from "../db.ts";
import {
  applyBaseline,
  groupBaseline,
  isGroupedBaseline,
  parseBaseline,
  updatedBaseline,
} from "../doctor/baseline.ts";
import { loadStackEnvCheck } from "../doctor/env.ts";
import { formatReport, jsonReport } from "../doctor/format.ts";
import { gitIgnored } from "../doctor/git-ignored.ts";
import { hookGrantBlock, hookGrantProblems } from "../doctor/hooks.ts";
import {
  ENV_FILES,
  readGitignores,
  readText,
  dataFiles,
  functionFiles,
  seedFiles,
  sqlFiles,
  sourceFiles,
} from "../doctor/inputs.ts";
import { LIVE_CODES, openLive } from "../doctor/live-source.ts";
import { locate } from "../doctor/locate.ts";
import { NO_SNAPSHOT, SOURCE_ONLY_CODES } from "../doctor/n-plus-one.ts";
import { NEXT_CONFIG_FILES, VERCEL_FILES } from "../doctor/next-cache.ts";
import {
  explainClaims,
  FLAG_FORMATS,
  reportFormat,
} from "../doctor/options.ts";
import { readProxyTrace } from "../doctor/proxy-size.ts";
import { RECEIVER_RULES } from "../doctor/receiver-types.ts";
import { DOCS_URL, RULE_CODES, RULES, runRules } from "../doctor/rules.ts";
import { workflowOf } from "../doctor/shared.ts";
import { loadLocalStackCheck } from "../doctor/stacks.ts";
import { loadSupabaseCliCheck } from "../doctor/supabase-cli.ts";
import {
  VERCEL_CODES,
  VERCEL_ENVIRONMENTS,
  vercelEnvPath,
} from "../doctor/vercel-env.ts";
import { PROCESS_ENV } from "../env.ts";
import {
  METADATA_REJECTED,
  readMetadataSnapshot,
  refuseWithMetadata,
} from "../gen/metadata.ts";
import { MetadataRejectedError } from "../introspect/typegen.ts";
import { betterSupabaseInstall } from "../lockfile.ts";
import { listedDependencies, peerVersions } from "../peers.ts";
import { compiledReadSets } from "../read-sets.ts";
import {
  findRepoRoot,
  readSupabaseConfig,
  sqlWorkflow,
} from "../supabase-config.ts";
import { openSymbolTier } from "../typescript-symbols/index.ts";
import { VERSION } from "../version.ts";
import { DEFAULT_SNAPSHOT_PATH, loadSnapshot } from "./snapshot.ts";
import { SOURCE_ARGS, sourceFlags } from "./source-args.ts";

const ARGS = {
  format: {
    type: "string",
    description:
      "text, sarif (code scanning) or github (workflow annotations); also tooling.doctor.format, default text. --json for the JSON report",
    valueHint: "format",
  },
  out: {
    type: "string",
    description: "Write the report to a file; also tooling.doctor.output",
    valueHint: "file",
  },
  only: {
    type: "string",
    description:
      "Run only these checks, e.g. --only BS100,BS304; also tooling.doctor.only",
    valueHint: "codes",
  },
  ignore: {
    type: "string",
    description: "Skip checks; also tooling.doctor.ignore in the config",
    valueHint: "codes",
  },
  "fail-on": {
    type: "string",
    description:
      "Exit 1 on findings at this level: error (the default), warning (the default with tooling.doctor.strict) or never",
    valueHint: "level",
  },
  metadata: {
    type: "string",
    description:
      "Check a GeneratorMetadata document (- for stdin); checks it lacks data for are skipped",
    valueHint: "path|-",
  },
  stats: {
    type: "boolean",
    description:
      "Report slow frequent statements from pg_stat_statements (BS209)",
  },
  explain: {
    type: "string",
    description:
      "EXPLAIN ANALYZE these tables or functions (rs_*, *_payload) under RLS, rolled back (BS212)",
    valueHint: "tables",
  },
  "explain-write": {
    type: "string",
    description:
      "EXPLAIN ANALYZE an insert (a copy of one row with fresh keys) and an update on these tables, with trigger times, rolled back (BS212)",
    valueHint: "tables",
  },
  args: {
    type: "string",
    description:
      "Arguments for a function passed to --explain: a JSON array (positional) or object (named)",
    valueHint: "json",
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
      "Print the grant and revoke SQL BS404 asks for, to add to your schema or migration",
  },
  vercel: {
    type: "boolean",
    description:
      "Check the variables of each Vercel environment from `vercel pull` (.vercel/.env.<name>.local): missing names, a secret under a browser prefix, preview and production on one project (BS513 to BS515)",
  },
  "update-baseline": {
    type: "boolean",
    alias: "update",
    description:
      "Rewrite tooling.doctor.baseline to accept this run's errors and warnings, keeping each entry's reason",
  },
} as const;

export type DoctorValues = CliValues<typeof ARGS & typeof SOURCE_ARGS>;

export interface DoctorOptions {
  /** Pre-loaded snapshot (tests). */
  readonly snapshot?: Snapshot;
  /** Advisor results (tests); otherwise read from the database being checked. */
  readonly advisors?: DoctorContext["advisors"];
  /** The live database (tests); otherwise the database being checked. */
  readonly database?: DoctorContext["database"];
  /** Peers and installed versions (tests); otherwise read from `node_modules`. */
  readonly peers?: DoctorContext["peers"];
  /**
   * The installed and locked better-supabase (tests); otherwise read from
   * `node_modules` and the lockfile (BS607).
   */
  readonly install?: DoctorContext["install"];
  /** The content mapper setup (tests); otherwise read from the project (BS602). */
  readonly contentMapper?: DoctorContext["contentMapper"];
  /**
   * The shell and stack variables (tests); otherwise read from `supabase
   * status` (BS503).
   */
  readonly stackEnv?: DoctorContext["stackEnv"];
  /**
   * Segment use and managed stacks (tests); otherwise read with `ipcs` (BS700,
   * BS701).
   */
  readonly localStacks?: DoctorContext["localStacks"];
  /**
   * The installed Supabase CLI and its config validation (tests); otherwise
   * read by running the CLI (BS710, BS711).
   */
  readonly supabaseCli?: DoctorContext["supabaseCli"];
  /** Opens `pg` connections (tests); defaults to `connect`. */
  readonly connect?: typeof connect;
  /** Colors the text report. */
  readonly paint?: Paint;
  /** The connection string `--db-url-stdin` read. */
  readonly dbUrl?: string;
  /** Ends the database connection (Ctrl-C). */
  readonly signal?: AbortSignal;
  /** Asks before `--yes` writes to a database that is not local. */
  readonly requireConsent?: (request: ConsentRequest) => void;
  /** Reports each statement `--yes` ran, on stderr. */
  readonly log?: (line: string) => void;
}

/** Where `--yes` writes, for the consent detail: a host, or the project. */
async function fixTarget(
  config: ResolvedConfig,
  env: CliEnv,
  options: DoctorOptions,
  projectRef: string | undefined,
): Promise<{ readonly local: boolean; readonly where: string }> {
  if (projectRef !== undefined) {
    return { local: false, where: `project ${projectRef}` };
  }

  const url = await databaseUrl(config, env, options.dbUrl).catch(
    () => undefined,
  );

  return url === undefined
    ? { local: false, where: "the database" }
    : { local: isLocalDatabaseUrl(url), where: databaseHost(url) };
}

/**
 * Runs the fix of each finding that has one, and returns the findings left: the
 * ones without a fix, and the ones whose fix failed, with the error.
 */
async function applyFixes(
  findings: readonly Finding[],
  database: DoctorContext["database"],
  consent: () => Promise<void>,
  log: (line: string) => void,
): Promise<{ readonly left: Finding[]; readonly fixed: number }> {
  const fixable = findings.filter((finding) => finding.fix !== undefined);

  if (fixable.length === 0 || !database || "skipped" in database) {
    return { left: [...findings], fixed: 0 };
  }

  await consent();

  const left: Finding[] = [];
  let fixed = 0;

  for (const finding of findings) {
    if (finding.fix === undefined) {
      left.push(finding);
      continue;
    }

    try {
      await database.query(finding.fix);
      fixed += 1;
      log(`Fixed ${finding.code} ${finding.target ?? finding.title}.`);
    } catch (cause) {
      // A fix can open a transaction, which a failed statement leaves aborted.
      await database.query("rollback").catch(() => []);
      left.push({
        ...finding,
        message: `${finding.message} doctor --yes failed: ${errorText(cause)}`,
      });
    }
  }

  return { left, fixed };
}

/** The baseline entries at `path`, none when the file doesn't exist yet. */
async function readBaseline(
  root: string,
  path: string,
): Promise<{
  readonly entries: ReturnType<typeof parseBaseline>;
  readonly grouped: boolean;
}> {
  const file = await readText(root, path);

  if (file === undefined) {
    return { entries: [], grouped: false };
  }

  try {
    return {
      entries: parseBaseline(file.text, path),
      grouped: isGroupedBaseline(file.text),
    };
  } catch (cause) {
    throw new CliError("invalid_input", errorText(cause));
  }
}

/** Errors `noDatabaseError` built, so a rethrow doesn't explain twice. */
const explained = new WeakSet<CliError>();

/** The snapshot doctor reads when no database runs. */
function savedSnapshotPath(config: ResolvedConfig): string {
  return config.source.snapshot ?? DEFAULT_SNAPSHOT_PATH;
}

/**
 * `cause` with the reason this run can't do without a database: the checks that
 * need one, the flags that read it, or the snapshot that's missing.
 */
function noDatabaseError(
  config: ResolvedConfig,
  rules: readonly { readonly code: string }[],
  cause: CliError,
  needsDatabase: boolean,
): CliError {
  if (explained.has(cause)) {
    return cause;
  }

  const live = rules
    .map((rule) => rule.code)
    .filter((code) => LIVE_CODES.has(code));

  const path = savedSnapshotPath(config);

  const reason = needsDatabase
    ? "--stats, --explain, --explain-write, --as and --yes read the database itself."
    : live.length > 0
      ? `These checks need a database: ${live.join(", ")}. The others read the schema from ${path} when no database runs, so save it with \`better-supabase gen --save-snapshot\` while the stack is up and leave these out with --ignore or --only.`
      : `None of these checks needs a database, but there is no ${path} to read the schema from. Save it with \`better-supabase gen --save-snapshot\` while the stack is up, then run doctor again without it.`;

  const error = new CliError("not_found", `${cause.message} ${reason}`, {
    ...(cause.problem.suggestion === undefined
      ? {}
      : { suggestion: cause.problem.suggestion }),
    cause,
  });

  explained.add(error);

  return error;
}

/**
 * The saved snapshot, for a run whose checks read only the schema and the
 * sources, when no database is reachable.
 */
async function savedSnapshotWithoutDatabase(
  config: ResolvedConfig,
  env: CliEnv,
  rules: readonly { readonly code: string }[],
  cause: CliError,
  needsDatabase: boolean,
): Promise<{ readonly snapshot: Snapshot; readonly path: string }> {
  const path = savedSnapshotPath(config);

  if (
    !needsDatabase &&
    !rules.some((rule) => LIVE_CODES.has(rule.code)) &&
    existsSync(resolve(config.root, path))
  ) {
    return {
      snapshot: await loadSnapshot(config, env, { snapshotPath: path }),
      path,
    };
  }

  throw noDatabaseError(config, rules, cause, needsDatabase);
}

export async function runDoctor(
  config: ResolvedConfig,
  args: DoctorValues,
  env: CliEnv,
  options: DoctorOptions = {},
): Promise<CommandResult> {
  const format = reportFormat(args, config.doctor.format);

  const only =
    args.only === undefined ? [...config.doctor.only] : list(args.only);

  const ignore = new Set([...config.doctor.ignore, ...list(args.ignore)]);

  const unknown = [...only, ...ignore].filter(
    (code) => !RULE_CODES.includes(code),
  );

  if (unknown.length > 0) {
    throw new CliError(
      "usage",
      `Unknown check ${unknown.join(", ")}. Checks: ${RULE_CODES.join(", ")}`,
    );
  }

  const explainTables = list(args.explain);
  const writeTables = list(args["explain-write"]);
  const planning = explainTables.length > 0 || writeTables.length > 0;
  const stats = args.stats === true;
  const claims = explainClaims(args);

  if ("error" in claims) {
    throw new CliError("usage", String(claims.error));
  }

  let explainArgs: unknown;

  if (args.args !== undefined) {
    if (explainTables.length === 0) {
      throw new CliError(
        "usage",
        "--args passes arguments to a function, so it needs --explain <function>.",
      );
    }

    try {
      explainArgs = JSON.parse(args.args);
    } catch (cause) {
      throw new CliError(
        "usage",
        `--args is not valid JSON: ${errorText(cause)}`,
      );
    }
  }

  if (args.claims !== undefined && !planning) {
    throw new CliError(
      "usage",
      "--claims plans a query, so it needs --explain <table> or --explain-write <table>.",
    );
  }

  // --stats and --explain ask for their checks even when --only leaves them out.
  const hookUser = args.as;

  const vercelEnv = args.vercel === true;

  const asked = new Set([
    ...(vercelEnv ? VERCEL_CODES : []),
    ...(stats ? ["BS209"] : []),
    ...(planning ? ["BS212"] : []),
    ...(hookUser ? ["BS405"] : []),
  ]);

  const fixGrants = args["fix-grants"] === true;
  const baselinePath = config.doctor.baseline;
  const updateBaseline = args["update-baseline"] === true;

  if (updateBaseline && baselinePath === undefined) {
    throw new CliError(
      "usage",
      "--update-baseline rewrites tooling.doctor.baseline; set it to a file such as doctor-baseline.json first.",
    );
  }

  // Check the output path before any work: a wrong --out used to fail after
  // minutes of reading the database.
  const out =
    args.out ??
    (format === config.doctor.format ? config.doctor.file : undefined);

  if (out !== undefined) {
    const target = insideRoot(config.root, out, "--out");

    if (existsSync(target) && statSync(target).isDirectory()) {
      throw new CliError(
        "usage",
        `--out ${out} is a directory; name the file to write.`,
      );
    }
  }

  const phases: DoctorPhase[] = [];
  let phaseAt = performance.now();

  const phase = (name: string): void => {
    const now = performance.now();
    phases.push({ name, ms: Math.round(now - phaseAt) });
    phaseAt = now;
    options.log?.(
      `doctor: ${name} took ${((phases.at(-1)?.ms ?? 0) / 1000).toFixed(1)} s`,
    );
  };

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
  const dbUrl = options.dbUrl;
  const projectRef = args["project-ref"];

  const source: SnapshotSource = {
    // Statistics, plans, hook calls and fixes need the database, not the saved snapshot.
    ...(stats || planning || hookUser || args.yes === true
      ? { live: true }
      : {}),
    ...(snapshotPath ? { snapshotPath } : {}),
    ...(dbUrl ? { dbUrl } : {}),
    ...(projectRef ? { projectRef } : {}),
    ...(options.signal ? { signal: options.signal } : {}),
  };

  const pg = options.connect ?? connect;

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
          ...(options.advisors === undefined
            ? {}
            : { advisors: options.advisors }),
          ...(options.database === undefined
            ? {}
            : { database: options.database }),
        };

  // A live check can reach the missing database before the snapshot does.
  const explain = (cause: unknown): unknown =>
    isNoDatabase(cause)
      ? noDatabaseError(config, rules, cause, source.live === true)
      : cause;

  // Closing a connection that never opened rejects with the cause it failed on.
  const closeQuietly = (): Promise<unknown> =>
    opened.close().catch(() => undefined);

  // Source-only checks run without a database: the schema only names includes.
  const sourceOnly =
    rules.length > 0 && rules.every((rule) => SOURCE_ONLY_CODES.has(rule.code));

  let noSnapshot: string | undefined;

  const vercel = VERCEL_FILES.some((path) =>
    existsSync(resolve(config.root, path)),
  );

  const [
    snapshot,
    envFiles,
    [configToml, sql],
    gitignore,
    sources,
    readSets,
    peers,
    contentMapper,
    stackEnv,
    localStacks,
    supabaseCli,
    nextConfig,
    install,
    ignoredEnvFiles,
    vercelConfig,
    vercelPulled,
    listed,
    proxyTrace,
  ] = await Promise.all([
    options.snapshot ??
      loadSnapshot(config, env, source, pg, opened.open).catch(
        async (cause: unknown) => {
          if (sourceOnly) {
            noSnapshot = errorText(cause);

            return NO_SNAPSHOT;
          }

          if (!isNoDatabase(cause)) {
            throw cause;
          }

          const saved = await savedSnapshotWithoutDatabase(
            config,
            env,
            rules,
            cause,
            source.live === true,
          );

          options.log?.(
            `No database is running, so doctor read the schema from ${saved.path}. It is as current as the last \`better-supabase gen --save-snapshot\`.`,
          );

          return saved.snapshot;
        },
      ),
    Promise.all(ENV_FILES.map((path) => readText(config.root, path))).then(
      (files) => files.filter((file): file is TextFile => file !== undefined),
    ),
    readSupabaseConfig(config.root).then(
      async (toml) =>
        [
          toml,
          await sqlFiles(config.root, toml, sqlWorkflow(config, toml)),
        ] as const,
    ),
    readGitignores(config.root),
    sourceFiles(config),
    compiledReadSets(config).catch((cause: unknown) => ({
      skipped: errorText(cause),
    })),
    options.peers ?? peerVersions(config.root).catch(() => []),
    options.contentMapper ??
      (config.gen.contentMapper === true &&
      rules.some((rule) => rule.code === "BS602")
        ? contentMapperSetup(config.root)
        : undefined),
    options.stackEnv ??
      (rules.some((rule) => rule.code === "BS503")
        ? loadStackEnvCheck(config.root, env, options.signal)
        : undefined),
    options.localStacks ??
      (rules.some((rule) => rule.code === "BS700" || rule.code === "BS701")
        ? loadLocalStackCheck(config.root, env)
        : undefined),
    options.supabaseCli ??
      (rules.some((rule) => rule.code === "BS710" || rule.code === "BS711")
        ? loadSupabaseCliCheck(config.root, env)
        : undefined),
    Promise.all(
      NEXT_CONFIG_FILES.map((path) => readText(config.root, path)),
    ).then((files) => files.find((file) => file !== undefined)),
    options.install ??
      (rules.some((rule) => rule.code === "BS607")
        ? betterSupabaseInstall(config.root).catch(() => undefined)
        : undefined),
    rules.some((rule) => rule.code === "BS502")
      ? gitIgnored(config.root, ENV_FILES, env)
      : undefined,
    readText(config.root, "vercel.json"),
    vercelEnv
      ? Promise.all(
          VERCEL_ENVIRONMENTS.map(async (environment) => {
            const file = await readText(
              config.root,
              vercelEnvPath(environment),
            );

            return file === undefined ? [] : [{ environment, file }];
          }),
        ).then((found) => found.flat())
      : undefined,
    listedDependencies(config.root).catch(() => undefined),
    rules.some((rule) => rule.code === "BS650")
      ? readProxyTrace(config.root).catch(() => undefined)
      : undefined,
  ]).catch(async (cause: unknown) => {
    await closeQuietly();
    throw explain(cause);
  });

  phase("read the project");

  const replay = opened.open ? (await opened.open()).replay : undefined;

  const live = replay
    ? {
        advisors: options.advisors ?? { skipped: replay },
        database: options.database ?? { skipped: replay },
      }
    : opened;

  const symbolTier = rules.some((rule) => RECEIVER_RULES.has(rule.code))
    ? await openSymbolTier(config.root)
    : undefined;

  const symbols =
    symbolTier === undefined
      ? undefined
      : symbolTier.ok
        ? { tier: symbolTier.tier, root: config.root }
        : { skipped: symbolTier.reason };

  const closeSymbols = (): void => {
    if (symbolTier?.ok) {
      symbolTier.tier.close();
    }
  };

  const context: DoctorContext = {
    config,
    ...(symbols ? { symbols } : {}),
    snapshot,
    sqlFiles: sql,
    seedFiles: await seedFiles(config.root, configToml),
    dataFiles: await dataFiles(config.root, configToml),
    functionFiles: await functionFiles(config.root, configToml),
    configToml,
    envFiles,
    gitignore,
    ...(ignoredEnvFiles ? { ignoredEnvFiles } : {}),
    sources,
    readSets,
    peers,
    ...(install ? { install } : {}),
    ...(contentMapper ? { contentMapper } : {}),
    ...(stackEnv ? { stackEnv } : {}),
    shellEnv: env[PROCESS_ENV] ?? {},
    ...(localStacks ? { localStacks } : {}),
    ...(supabaseCli ? { supabaseCli } : {}),
    ...(nextConfig ? { nextConfig } : {}),
    vercel,
    ...(listed ? { listedDependencies: [...listed] } : {}),
    ...(vercelConfig ? { vercelConfig } : {}),
    ...(vercelPulled ? { vercelEnv: vercelPulled } : {}),
    ...(proxyTrace ? { proxyTrace } : {}),
    ...(live.advisors ? { advisors: live.advisors } : {}),
    ...(live.database ? { database: live.database } : {}),
    ...(stats ? { stats } : {}),
    ...(hookUser ? { hookUser } : {}),
    ...(planning
      ? {
          explain: {
            tables: explainTables,
            ...(writeTables.length > 0 ? { write: writeTables } : {}),
            claims,
            ...(explainArgs === undefined ? {} : { args: explainArgs }),
          },
        }
      : {}),
  };

  if (fixGrants) {
    closeSymbols();
    await opened.close();

    return {
      code: 0,
      output: hookGrantBlock(hookGrantProblems(context), workflowOf(context)),
    };
  }

  let ran: Finding[];

  try {
    ran = await runRules(context, rules);
    phase("run the rules");

    const schemaRule =
      rules.find((rule) => rule.code === "BS635") ??
      rules.find((rule) => rule.code === "BS634");

    if (noSnapshot !== undefined && schemaRule !== undefined) {
      ran.push({
        code: schemaRule.code,
        severity: "info",
        title: schemaRule.title,
        help: `${DOCS_URL}#${schemaRule.code.toLowerCase()}`,
        message: `Ran without the schema (${noSnapshot}), so the findings name no include and BS635 finds no waterfall. Pass --snapshot, or set $DATABASE_URL, to use the foreign keys.`,
      });
    }

    const byName = ran.find((finding) => RECEIVER_RULES.has(finding.code));

    if (symbols !== undefined && "skipped" in symbols && byName !== undefined) {
      ran.push({
        code: byName.code,
        severity: "info",
        title: byName.title,
        help: `${DOCS_URL}#${byName.code.toLowerCase()}`,
        message: `Matched reads by receiver name only, so a receiver named like a client but typed as something else is still reported (${symbols.skipped}). Install typescript 7.1 or later to check receiver types.`,
      });
    }

    if (args.yes === true) {
      const count = ran.filter((finding) => finding.fix !== undefined).length;

      ({ left: ran } = await applyFixes(
        ran,
        context.database,
        async () => {
          const target = await fixTarget(config, env, options, projectRef);

          if (!target.local) {
            options.requireConsent?.({
              effect: "database-write",
              detail: `doctor --yes runs ${String(count)} fix(es) against ${target.where}`,
            });
          }
        },
        options.log ?? (() => {}),
      ));
    }
  } finally {
    closeSymbols();
    await opened.close();
  }

  const located: Finding[] = ran.map((finding) => {
    if (finding.location || !finding.object) {
      return finding;
    }

    const location = locate(sql, finding.object);

    return location ? { ...finding, location } : finding;
  });

  let findings: readonly Finding[] = located;

  if (baselinePath !== undefined) {
    const { entries, grouped } = await readBaseline(config.root, baselinePath);
    const codes = new Set(rules.map((rule) => rule.code));

    if (updateBaseline) {
      const next = updatedBaseline(located, entries, codes, context);

      const applied = await applyPlan(
        {
          root: config.root,
          regenerate: "better-supabase doctor --update-baseline",
          files: [
            {
              path: insideRoot(
                config.root,
                baselinePath,
                "tooling.doctor.baseline",
              ),
              contents: `${JSON.stringify(grouped ? groupBaseline(next) : next, null, 2)}\n`,
              note: `${String(next.length)} accepted findings`,
            },
          ],
        },
        {},
      );

      return {
        code: 0,
        output: changeLines(applied).join("\n"),
        data: { baseline: baselinePath, entries: next.length },
      };
    }

    ({ findings } = applyBaseline(
      located,
      entries,
      codes,
      context,
      baselinePath,
    ));
  }

  const fromRepo = format === "sarif" || format === "github";
  const repoRoot = findRepoRoot(config.root);

  const repoPath = (file: string): string =>
    display(repoRoot, resolve(config.root, file));

  const report = formatReport(
    fromRepo
      ? findings.map((finding) =>
          finding.location
            ? {
                ...finding,
                location: {
                  ...finding.location,
                  file: repoPath(finding.location.file),
                },
              }
            : finding,
        )
      : findings,
    {
      format,
      rules,
      version: VERSION,
      phases,
      fallbackFile: repoPath(context.configToml?.path ?? "package.json"),
      ...(options.paint && !out ? { paint: options.paint } : {}),
    },
  );

  const errors = findings.filter(
    (finding) => finding.severity === "error",
  ).length;

  const warnings = findings.filter(
    (finding) => finding.severity === "warning",
  ).length;

  const failOn =
    args["fail-on"] ?? (config.doctor.strict ? "warning" : "error");

  if (failOn !== "error" && failOn !== "warning" && failOn !== "never") {
    throw new CliError(
      "usage",
      `--fail-on takes error, warning or never, got "${failOn}".`,
    );
  }

  const code =
    failOn !== "never" && (errors > 0 || (failOn === "warning" && warnings > 0))
      ? 1
      : 0;

  const failure =
    code === 0
      ? {}
      : {
          errorCode: "findings" as const,
          error: `Doctor found ${errors} errors and ${warnings} warnings${failOn === "warning" ? " (--fail-on warning)" : ""}.`,
        };

  if (out) {
    const applied = await applyPlan(
      {
        root: config.root,
        regenerate: "better-supabase doctor",
        files: [
          {
            path: insideRoot(config.root, out, "--out"),
            contents: `${report}\n`,
            note: `${errors} errors, ${warnings} warnings`,
          },
        ],
      },
      {},
    );

    return {
      code,
      output: changeLines(applied).join("\n"),
      data: { out, errors, warnings },
      ...failure,
    };
  }

  return format === "json"
    ? { code, data: jsonReport(findings, VERSION, phases), ...failure }
    : { code, output: report, ...failure };
}

const ruleCodes = (): string[] => [...new Set([...RULE_CODES, ...LIVE_CODES])];

export const doctorCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("doctor"),
  args: { ...SOURCE_ARGS, ...ARGS },
  lists: ["only", "ignore", "explain", "explain-write"],
  completions: {
    format: () => FLAG_FORMATS,
    only: ruleCodes,
    ignore: ruleCodes,
  },
  run: async (
    args,
    { config, cwd, env, io, log, paint, requireConsent, signal },
  ) => {
    if (args.metadata !== undefined) {
      refuseWithMetadata([
        ...sourceFlags(args),
        ...(args.stats === true ? ["--stats"] : []),
        ...(args.explain === undefined ? [] : ["--explain"]),
        ...(args["explain-write"] === undefined ? [] : ["--explain-write"]),
        ...(args.args === undefined ? [] : ["--args"]),
        ...(args.as === undefined ? [] : ["--as"]),
        ...(args.yes === true ? ["--yes"] : []),
      ]);

      let snapshot: Snapshot;

      try {
        snapshot = await readMetadataSnapshot(args.metadata, cwd, io);
      } catch (cause) {
        if (cause instanceof MetadataRejectedError) {
          return {
            code: METADATA_REJECTED,
            errorCode: "invalid_input",
            error: cause.message,
          };
        }

        throw cause;
      }

      const skipped = `reading a GeneratorMetadata document; set $DATABASE_URL or $SUPABASE_DB_URL, or pass --db-url-stdin or --project-ref, to check a database.`;

      return runDoctor(config, args, env, {
        snapshot,
        advisors: { skipped },
        database: { skipped },
        paint,
      });
    }

    const dbUrl = await stdinDatabaseUrl(args["db-url-stdin"], io);

    const check = (): Promise<CommandResult> =>
      runDoctor(config, args, env, {
        paint,
        requireConsent,
        log: log.info,
        ...(dbUrl ? { dbUrl } : {}),
        ...(signal ? { signal } : {}),
      });

    return args.snapshot === undefined
      ? log.progress("Checking the database", check)
      : check();
  },
});
