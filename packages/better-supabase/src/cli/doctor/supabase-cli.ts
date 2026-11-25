import type { CliEnv } from "../env.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { errorText } from "../core/errors.ts";
import {
  supabaseCli,
  SUPABASE_CLI_FLOOR,
  SUPABASE_CLI_TESTED,
} from "../exec.ts";
import { tomlGet } from "../supabase-config.ts";
import { versionAtLeast } from "./cli-advisors.ts";

/** One problem `supabase config validate` reports. */
export interface ConfigProblem {
  readonly code: string;
  readonly severity: "error" | "warning";
  readonly path: string;
  readonly reason: string;
  readonly help?: string;
  readonly line?: number;
  readonly column?: number;
}

export interface ConfigValidation {
  readonly file: string;
  readonly problems: readonly ConfigProblem[];
}

/**
 * The installed Supabase CLI and what its `config validate` says (BS710,
 * BS711).
 */
export type SupabaseCliCheck =
  | {
      readonly version: string;
      /** Absent when the CLI is older than the floor, which has no such command. */
      readonly validation?: ConfigValidation;
    }
  | { readonly skipped: string };

const SEMVER = /\d+\.\d+\.\d+/u;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function problem(
  entry: unknown,
  severity: ConfigProblem["severity"],
): ConfigProblem | undefined {
  if (
    !isRecord(entry) ||
    typeof entry["path"] !== "string" ||
    typeof entry["reason"] !== "string"
  ) {
    return undefined;
  }

  return {
    code: typeof entry["code"] === "string" ? entry["code"] : "invalid",
    severity,
    path: entry["path"],
    reason: entry["reason"],
    ...(typeof entry["help"] === "string" ? { help: entry["help"] } : {}),
    ...(typeof entry["line"] === "number" ? { line: entry["line"] } : {}),
    ...(typeof entry["column"] === "number" ? { column: entry["column"] } : {}),
  };
}

/**
 * The problems in the JSON `supabase config validate` prints on stdout, or
 * `undefined` for any other output (a missing config file prints an error
 * object).
 */
export function parseConfigValidation(
  stdout: string,
): ConfigValidation | undefined {
  let parsed: unknown;

  try {
    parsed = JSON.parse(stdout);
  } catch {
    return undefined;
  }

  if (
    !isRecord(parsed) ||
    typeof parsed["file"] !== "string" ||
    !Array.isArray(parsed["errors"])
  ) {
    return undefined;
  }

  const warnings: unknown[] = Array.isArray(parsed["warnings"])
    ? parsed["warnings"]
    : [];

  return {
    file: parsed["file"],
    problems: [
      ...parsed["errors"].map((entry) => problem(entry, "error")),
      ...warnings.map((entry) => problem(entry, "warning")),
    ].filter((entry) => entry !== undefined),
  };
}

/** Reads the CLI version and, from the floor on, validates the config with it. */
export async function getSupabaseCliCheck(
  root: string,
  env: CliEnv,
): Promise<SupabaseCliCheck> {
  try {
    const result = await supabaseCli(["--version"], root, env);
    const version = SEMVER.exec(result.stdout)?.[0];

    if (result.code !== 0 || version === undefined) {
      return { skipped: "supabase --version printed no version." };
    }

    if (!versionAtLeast(version, SUPABASE_CLI_FLOOR)) {
      return { version };
    }

    const validated = await supabaseCli(["config", "validate"], root, env);
    const validation = parseConfigValidation(validated.stdout);

    return validation === undefined ? { version } : { version, validation };
  } catch (cause) {
    return { skipped: errorText(cause) };
  }
}

function belowFloor(context: DoctorContext): FindingInput[] {
  const check = context.supabaseCli;

  if (
    check === undefined ||
    "skipped" in check ||
    versionAtLeast(check.version, SUPABASE_CLI_FLOOR)
  ) {
    return [];
  }

  return [
    {
      message: `The project runs Supabase CLI ${check.version}. This release of better-supabase is built and tested on ${SUPABASE_CLI_FLOOR}: it reads config.json and config.jsonc, runs \`config validate\` and \`stack prune\`, selects stacks with \`--stack <id>\`, and writes migrations that the older CLI names differently. Update it: pnpm add -D supabase@${SUPABASE_CLI_TESTED}`,
      target: "supabase",
    },
  ];
}

/** `db.major_version` values the CLI reports itself. */
const MAJOR_VERSION_PATH = "db.major_version";

function configProblems(context: DoctorContext): FindingInput[] {
  const check = context.supabaseCli;

  if (check === undefined || "skipped" in check || !check.validation) {
    return [];
  }

  const { file, problems } = check.validation;

  return problems
    .filter((entry) => entry.path !== MAJOR_VERSION_PATH)
    .map((entry) => ({
      severity: entry.severity,
      message: `${file}: ${entry.path} ${entry.reason}${entry.help ? `. ${entry.help}` : ""}`,
      target: `${file}:${entry.path}`,
      location: { file, line: entry.line ?? 1 },
    }));
}

/** Postgres majors the local stack can no longer run (13) or soon will not (14). */
const MAJOR_ERROR = 13;
const MAJOR_WARNING = 14;

function majorVersion(context: DoctorContext): FindingInput[] {
  const config = context.configToml;
  const value = config && tomlGet(config.document, ["db", "major_version"]);

  if (!config || typeof value !== "number" || value > MAJOR_WARNING) {
    return [];
  }

  const at = config.locate(["db", "major_version"]);
  const old = value <= MAJOR_ERROR;

  return [
    {
      severity: old ? "error" : "warning",
      message: `${config.path}: db.major_version is ${String(value)}. ${old ? "Supabase CLI 3.2 refuses Postgres 13 and the stack fails to start." : "Postgres 14 is the next version the local stack stops accepting."} Upgrade the project to Postgres 17 and set db.major_version = 17 (https://supabase.com/docs/guides/platform/upgrading).`,
      target: `${config.path}:db.major_version`,
      location: { file: config.path, line: at?.line ?? 1 },
    },
  ];
}

export const SUPABASE_CLI_RULES: readonly Rule[] = [
  {
    code: "BS710",
    severity: "warning",
    title: "Supabase CLI older than 3.3.0",
    description: `The project's Supabase CLI (\`$SUPABASE_BIN\`, \`node_modules/.bin/supabase\` or the one on the PATH) is older than ${SUPABASE_CLI_FLOOR}. better-supabase reads \`config.json\` and \`config.jsonc\`, runs \`config validate\` and \`stack prune\`, selects stacks with \`--stack <id>\` (3.3.0 removed \`--stack-id\`), and expects the multi-file migrations of ${SUPABASE_CLI_FLOOR}. Update it with \`pnpm add -D supabase@${SUPABASE_CLI_TESTED}\`.`,
    check: belowFloor,
  },
  {
    code: "BS711",
    severity: "error",
    title: "Supabase config fails validation",
    description:
      "`supabase config validate` rejects the project's `config.toml`, `config.json` or `config.jsonc`: a value of the wrong type, an unknown key, or a removed key. A removed key names its replacement. Each problem is one finding with the file, line and column the CLI reports. The `db.major_version` check is BS712.",
    check: configProblems,
  },
  {
    code: "BS712",
    severity: "error",
    title: "Postgres major version the local stack refuses",
    description:
      "`db.major_version` is 13 (an error: Supabase CLI 3.2 refuses it) or 14 (a warning: the next version to go). Upgrade the project to Postgres 17 and set `db.major_version = 17`.",
    check: majorVersion,
  },
];
