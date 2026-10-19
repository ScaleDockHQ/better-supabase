import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";
import type { Snapshot } from "../introspect/types.ts";

import { stdinDatabaseUrl } from "../config.ts";
import { defineCliCommand, list } from "../core/command.ts";
import { errorText } from "../core/errors.ts";
import { display, writeIfChanged } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { connect } from "../db.ts";
import { formatReport, jsonReport } from "../doctor/format.ts";
import { hookGrantBlock, hookGrantProblems } from "../doctor/hooks.ts";
import {
  ENV_FILES,
  readText,
  sqlFiles,
  sourceFiles,
} from "../doctor/inputs.ts";
import { LIVE_CODES, type OpenLive, openLive } from "../doctor/live-source.ts";
import { locate } from "../doctor/locate.ts";
import { explainClaims, reportFormat } from "../doctor/options.ts";
import {
  type DoctorContext,
  type Finding,
  RULE_CODES,
  RULES,
  runRules,
  type TextFile,
} from "../doctor/rules.ts";
import { workflowOf } from "../doctor/shared.ts";
import { METADATA_REJECTED, readMetadataSnapshot } from "../gen/metadata.ts";
import { MetadataRejectedError } from "../introspect/typegen.ts";
import { peerVersions } from "../peers.ts";
import { withSpinner } from "../prompts.ts";
import { compiledReadSets } from "../read-sets.ts";
import { type Paint, painter } from "../style.ts";
import {
  findRepoRoot,
  readSupabaseToml,
  sqlWorkflow,
} from "../supabase-toml.ts";
import { VERSION } from "../version.ts";
import { loadSnapshot, type SnapshotSource } from "./snapshot.ts";

const ARGS = {
  format: {
    type: "string",
    description:
      "text, sarif (code scanning) or github (workflow annotations); also doctor.format, default text. --json for the JSON report",
    valueHint: "format",
  },
  out: {
    type: "string",
    description: "Write the report to a file; also doctor.output",
    valueHint: "file",
  },
  only: {
    type: "string",
    description:
      "Run only these checks, e.g. --only BS100,BS304; also doctor.only",
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
  metadata: {
    type: "string",
    description:
      "Check a GeneratorMetadata document (- for stdin); checks it lacks data for are skipped",
    valueHint: "path|-",
  },
  "db-url-stdin": {
    type: "boolean",
    description:
      "Read the connection string from stdin instead of the config, $DATABASE_URL or $SUPABASE_DB_URL",
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
      "Print the grant and revoke SQL BS404 asks for, to add to your schema or migration",
  },
} as const;

export type DoctorArgs = CliArgs<typeof ARGS>;

export interface DoctorOptions {
  /** Pre-loaded snapshot (tests). */
  readonly snapshot?: Snapshot;
  /** Advisor results (tests); otherwise read from the database being checked. */
  readonly advisors?: DoctorContext["advisors"];
  /** The live database (tests); otherwise the database being checked. */
  readonly database?: DoctorContext["database"];
  /** Peers and installed versions (tests); otherwise read from `node_modules`. */
  readonly peers?: DoctorContext["peers"];
  /** Opens `pg` connections (tests); defaults to `connect`. */
  readonly connect?: typeof connect;
  /** Colors the text report. */
  readonly paint?: Paint;
  /** The connection string `--db-url-stdin` read. */
  readonly dbUrl?: string;
  /** Ends the database connection (Ctrl-C). */
  readonly signal?: AbortSignal;
}

export async function runDoctor(
  config: ResolvedConfig,
  args: DoctorArgs,
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
    return {
      code: 2,
      error: `Unknown check ${unknown.join(", ")}. Checks: ${RULE_CODES.join(", ")}`,
    };
  }

  const explainTables = list(args.explain);
  const stats = args.stats === true;
  const claims = explainClaims(args);

  if ("error" in claims) {
    return { code: 2, error: String(claims.error) };
  }

  if (args.claims !== undefined && explainTables.length === 0) {
    return {
      code: 2,
      error: "--claims plans a query, so it needs --explain <table>.",
    };
  }

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
  const dbUrl = options.dbUrl;
  const projectRef = args["project-ref"];

  const source: SnapshotSource = {
    // Statistics, plans and hook calls need the database, not the saved snapshot.
    ...(stats || explainTables.length > 0 || hookUser ? { live: true } : {}),
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

  const [
    snapshot,
    envFiles,
    [configToml, sql],
    gitignore,
    sources,
    readSets,
    peers,
  ] = await Promise.all([
    options.snapshot ?? loadSnapshot(config, env, source, pg, opened.open),
    Promise.all(ENV_FILES.map((path) => readText(config.root, path))).then(
      (files) => files.filter((file): file is TextFile => file !== undefined),
    ),
    readSupabaseToml(config.root).then(
      async (toml) =>
        [
          toml,
          await sqlFiles(config.root, toml, sqlWorkflow(config, toml)),
        ] as const,
    ),
    readText(config.root, ".gitignore"),
    sourceFiles(config),
    compiledReadSets(config).catch((cause: unknown) => ({
      skipped: errorText(cause),
    })),
    options.peers ?? peerVersions(config.root).catch(() => []),
  ]).catch(async (cause: unknown) => {
    await opened.close();
    throw cause;
  });

  const replay = opened.open ? (await opened.open()).replay : undefined;

  const live = replay
    ? {
        advisors: options.advisors ?? { skipped: replay },
        database: options.database ?? { skipped: replay },
      }
    : opened;

  const context: DoctorContext = {
    config,
    snapshot,
    sqlFiles: sql,
    configToml,
    envFiles,
    gitignore: gitignore?.text ?? "",
    sources,
    readSets,
    peers,
    ...(live.advisors ? { advisors: live.advisors } : {}),
    ...(live.database ? { database: live.database } : {}),
    ...(stats ? { stats } : {}),
    ...(hookUser ? { hookUser } : {}),
    ...(explainTables.length > 0
      ? { explain: { tables: explainTables, claims } }
      : {}),
  };

  if (fixGrants) {
    await opened.close();

    return {
      code: 0,
      output: hookGrantBlock(hookGrantProblems(context), workflowOf(context)),
    };
  }

  let ran: Finding[];

  try {
    ran = await runRules(context, rules);
  } finally {
    await opened.close();
  }

  const findings: Finding[] = ran.map((finding) => {
    if (finding.location || !finding.object) {
      return finding;
    }

    const location = locate(sql, finding.object);

    return location ? { ...finding, location } : finding;
  });

  const out =
    args.out ??
    (format === config.doctor.format ? config.doctor.output : undefined);

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

  const strict = args.strict === true || config.doctor.strict;
  const code = errors > 0 || (strict && warnings > 0) ? 1 : 0;

  if (out) {
    await writeIfChanged(resolve(config.root, out), `${report}\n`);

    return {
      code,
      output: `Wrote ${out}: ${errors} errors, ${warnings} warnings.`,
      data: { out, errors, warnings },
    };
  }

  return format === "json"
    ? { code, data: jsonReport(findings, VERSION) }
    : { code, output: report };
}

export const doctorCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("doctor"),
  args: ARGS,
  lists: ["only", "ignore", "explain"],
  run: async (args, { config, cwd, env, io, signal }) => {
    if (args.metadata !== undefined) {
      const conflicting = [
        ...(args.snapshot === undefined ? [] : ["--snapshot"]),
        ...(args["db-url-stdin"] === true ? ["--db-url-stdin"] : []),
        ...(args["project-ref"] === undefined ? [] : ["--project-ref"]),
        ...(args.stats === true ? ["--stats"] : []),
        ...(args.explain === undefined ? [] : ["--explain"]),
        ...(args.as === undefined ? [] : ["--as"]),
      ];

      if (conflicting.length > 0) {
        return {
          code: 2,
          error: `--metadata checks the document, not a database, so it can't be combined with ${conflicting.join(", ")}`,
        };
      }

      let snapshot: Snapshot;

      try {
        snapshot = await readMetadataSnapshot(args.metadata, cwd, io);
      } catch (cause) {
        if (cause instanceof MetadataRejectedError) {
          return { code: METADATA_REJECTED, error: cause.message };
        }

        throw cause;
      }

      const skipped = `reading a GeneratorMetadata document; set $DATABASE_URL or $SUPABASE_DB_URL, or pass --db-url-stdin or --project-ref, to check a database.`;

      return runDoctor(config, args, env, {
        snapshot,
        advisors: { skipped },
        database: { skipped },
        paint: painter(io.color),
      });
    }

    const dbUrl = await stdinDatabaseUrl(args["db-url-stdin"], io);

    return withSpinner(
      args.snapshot === undefined ? io.prompts : undefined,
      "Checking the database",
      () =>
        runDoctor(config, args, env, {
          paint: painter(io.color),
          ...(dbUrl ? { dbUrl } : {}),
          ...(signal ? { signal } : {}),
        }),
    );
  },
});
