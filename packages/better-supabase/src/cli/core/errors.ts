import type { CommandResult } from "./io.ts";

/**
 * `1` for a failure or a failed check, `2` for a usage error the caller can
 * fix by changing the command, `3` when the user has to act (give an input,
 * consent, log in), `130` when the run was interrupted or a prompt cancelled.
 * The bin also exits `143` on SIGTERM, and `gen --metadata` exits `65` when
 * it rejects its input.
 */
export type ExitCode = 1 | 2 | 3 | 130;

export type CliErrorCode =
  | "usage"
  | "unknown_command"
  | "command_moved"
  | "missing_value"
  | "outside_root"
  | "config_not_found"
  | "config_invalid"
  | "env_invalid"
  | "not_found"
  | "invalid_input"
  | "dependency_missing"
  | "database_unreachable"
  | "supabase_cli_missing"
  | "supabase_cli_failed"
  | "network_error"
  | "request_failed"
  | "auth_required"
  | "integrity_failed"
  | "generator_failed"
  | "check_failed"
  | "file_conflict"
  | "findings"
  | "input_required"
  | "consent_required"
  | "cancelled"
  | "failed"
  | "internal";

/** Each code has a heading on this page, so `type` links to its explanation. */
export const CLI_ERRORS_URL = "https://bettersupabase.com/docs/cli/errors";

const ERRORS: {
  readonly [K in CliErrorCode]: readonly [title: string, exitCode: ExitCode];
} = {
  usage: ["Invalid arguments", 2],
  unknown_command: ["Unknown command", 2],
  command_moved: ["Command moved", 2],
  missing_value: ["Missing value", 2],
  outside_root: ["Path outside the project", 2],
  config_not_found: ["Config file not found", 2],
  config_invalid: ["Invalid config", 2],
  env_invalid: ["Invalid environment variable", 2],
  not_found: ["File not found", 1],
  invalid_input: ["Invalid input file", 1],
  dependency_missing: ["Missing dependency", 1],
  database_unreachable: ["Database unreachable", 1],
  supabase_cli_missing: ["Supabase CLI not found", 1],
  supabase_cli_failed: ["Supabase CLI failed", 1],
  network_error: ["No response", 1],
  request_failed: ["Request failed", 1],
  auth_required: ["Authentication required", 3],
  integrity_failed: ["Integrity check failed", 1],
  generator_failed: ["Generator failed", 1],
  check_failed: ["Out of date", 1],
  file_conflict: ["File not written by better-supabase", 1],
  findings: ["Checks failed", 1],
  input_required: ["Input required", 3],
  consent_required: ["Consent required", 3],
  cancelled: ["Cancelled", 130],
  failed: ["Command failed", 1],
  internal: ["Unexpected error", 1],
};

/** Every error code, in the order the errors page lists them. */
// SAFETY: ERRORS has exactly one key per CliErrorCode.
export const CLI_ERROR_CODES = Object.keys(ERRORS) as readonly CliErrorCode[];

/** The exit code a `CliError` with `code` gets unless it sets its own. */
export const exitCodeOf = (code: CliErrorCode): ExitCode => ERRORS[code][1];

/** RFC 9457 Problem Details for a CLI error. `--json` prints it on stdout. */
export interface CliProblem {
  readonly type: string;
  readonly title: string;
  readonly detail: string;
  readonly code: CliErrorCode;
  readonly exitCode: number;
  /** The closest command, for `unknown_command`. */
  readonly suggestion?: string;
  /** The flag that supplies the value, for `missing_value`. */
  readonly flag?: string;
  /** One line per problem, for `config_invalid` and `env_invalid`. */
  readonly issues?: readonly string[];
}

export type CliProblemExtensions = Pick<
  CliProblem,
  "suggestion" | "flag" | "issues"
>;

export interface CliErrorOptions extends CliProblemExtensions {
  readonly exitCode?: number;
  readonly cause?: unknown;
}

/** An error the CLI reports as text, or as Problem Details under `--json`. */
export class CliError extends Error {
  override readonly name = "CliError";
  readonly code: CliErrorCode;
  readonly exitCode: number;
  readonly problem: CliProblem;

  constructor(
    code: CliErrorCode,
    message: string,
    options: CliErrorOptions = {},
  ) {
    super(message, options.cause === undefined ? {} : { cause: options.cause });

    const [title, defaultExit] = ERRORS[code];

    const { exitCode = defaultExit, cause: _cause, ...extensions } = options;

    this.code = code;
    this.exitCode = exitCode;
    this.problem = {
      type: `${CLI_ERRORS_URL}#${code}`,
      title,
      detail: message,
      code,
      exitCode,
      ...extensions,
    };
  }
}

/** citty's own argument errors. */
function isCittyUsageError(cause: unknown): cause is Error {
  return cause instanceof Error && cause.name === "CLIError";
}

/** Any thrown value as a `CliError`: citty's argument errors become `usage`, the rest `internal`. */
export function toCliError(cause: unknown): CliError {
  if (cause instanceof CliError) {
    return cause;
  }

  if (isCittyUsageError(cause)) {
    return new CliError("usage", cause.message);
  }

  return new CliError("internal", errorText(cause), { cause });
}

/** A thrown value as the message to print. */
export const errorText = (cause: unknown): string =>
  cause instanceof Error ? cause.message : String(cause);

/** A step that threw, as a failed command result. */
export const failedResult = (cause: unknown): CommandResult => ({
  code: 1,
  error: errorText(cause),
});

/**
 * The `values` that `isValid` accepts, or a usage message naming the ones
 * it rejects and the `available` names.
 */
export function parseNames<T extends string>(
  values: readonly string[],
  isValid: (value: string) => value is T,
  noun: string,
  available: readonly string[],
): readonly T[] | string {
  const unknown = values.filter((value) => !isValid(value));

  if (unknown.length > 0) {
    return `Unknown ${noun} ${unknown.map((value) => `"${value}"`).join(", ")}. Available: ${available.join(", ")}.`;
  }

  return values.filter(isValid);
}
