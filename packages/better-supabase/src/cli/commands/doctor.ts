import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";
import type { Snapshot } from "../introspect/types.ts";
import type { Paint } from "../style.ts";

import { stdinDatabaseUrl } from "../config.ts";
import { defineCliCommand, list } from "../core/command.ts";
import { errorText, CliError } from "../core/errors.ts";
import { applyPlan, changeLines, insideRoot } from "../core/files.ts";
import { display } from "../core/io.ts";
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
import {
  explainClaims,
  FLAG_FORMATS,
  reportFormat,
} from "../doctor/options.ts";
import {
  type DoctorContext,
  type Finding,
  RULE_CODES,
  RULES,
  runRules,
  type TextFile,
} from "../doctor/rules.ts";
import { workflowOf } from "../doctor/shared.ts";
import {
  METADATA_REJECTED,
  readMetadataSnapshot,
  refuseWithMetadata,
} from "../gen/metadata.ts";
import { MetadataRejectedError } from "../introspect/typegen.ts";
import { peerVersions } from "../peers.ts";
import { compiledReadSets } from "../read-sets.ts";
import {
  findRepoRoot,
  readSupabaseToml,
  sqlWorkflow,
} from "../supabase-toml.ts";
import { VERSION } from "../version.ts";
import { loadSnapshot, type SnapshotSource } from "./snapshot.ts";
import { SOURCE_ARGS, sourceFlags } from "./source-args.ts";

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
  "fail-on": {
    type: "string",
    description:
      "Exit 1 on findings at this level: error (the default), warning (the default with doctor.strict) or never",
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

export type DoctorArgs = CliArgs<typeof ARGS & typeof SOURCE_ARGS>;

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
    throw new CliError(
      "usage",
      `Unknown check ${unknown.join(", ")}. Checks: ${RULE_CODES.join(", ")}`,
    );
  }

  const explainTables = list(args.explain);
  const stats = args.stats === true;
  const claims = explainClaims(args);

  if ("error" in claims) {
    throw new CliError("usage", String(claims.error));
  }

  if (args.claims !== undefined && explainTables.length === 0) {
    throw new CliError(
      "usage",
      "--claims plans a query, so it needs --explain <table>.",
    );
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
    ? { code, data: jsonReport(findings, VERSION), ...failure }
    : { code, output: report, ...failure };
}

const ruleCodes = (): string[] => [...new Set([...RULE_CODES, ...LIVE_CODES])];

export const doctorCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("doctor"),
  args: { ...SOURCE_ARGS, ...ARGS },
  lists: ["only", "ignore", "explain"],
  completions: {
    format: () => FLAG_FORMATS,
    only: ruleCodes,
    ignore: ruleCodes,
  },
  run: async (args, { config, cwd, env, io, log, paint, signal }) => {
    if (args.metadata !== undefined) {
      refuseWithMetadata([
        ...sourceFlags(args),
        ...(args.stats === true ? ["--stats"] : []),
        ...(args.explain === undefined ? [] : ["--explain"]),
        ...(args.as === undefined ? [] : ["--as"]),
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
        ...(dbUrl ? { dbUrl } : {}),
        ...(signal ? { signal } : {}),
      });

    return args.snapshot === undefined
      ? log.progress("Checking the database", check)
      : check();
  },
});
