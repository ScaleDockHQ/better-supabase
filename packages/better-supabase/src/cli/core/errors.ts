import type { CommandResult, NextStep } from "./io.ts";

/**
 * `1` for a failure or a failed check, `2` for a usage error or a missing input
 * the caller fixes by changing the command (a person has to act: give an input,
 * confirm, log in), `130` when the run was interrupted or a prompt cancelled,
 * `143` when it was terminated (SIGTERM), and `65` when `gen --metadata`
 * rejects its input.
 */
export type ExitCode = 1 | 2 | 65 | 130 | 143;

export type CliErrorCode =
  | "usage"
  | "unknown_command"
  | "unknown_flag"
  | "invalid_value"
  | "command_moved"
  | "flag_renamed"
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
  | "confirmation_required"
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
  unknown_flag: ["Unknown flag", 2],
  invalid_value: ["Invalid value", 2],
  command_moved: ["Command moved", 2],
  flag_renamed: ["Flag renamed", 2],
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
  auth_required: ["Authentication required", 2],
  integrity_failed: ["Integrity check failed", 1],
  generator_failed: ["Generator failed", 1],
  check_failed: ["Out of date", 1],
  file_conflict: ["File not written by better-supabase", 1],
  findings: ["Checks failed", 1],
  input_required: ["Input required", 2],
  confirmation_required: ["Confirmation required", 2],
  cancelled: ["Cancelled", 130],
  failed: ["Command failed", 1],
  internal: ["Unexpected error", 1],
};

/** Every error code, in the order the errors page lists them. */
// SAFETY: ERRORS has exactly one key per CliErrorCode.
export const CLI_ERROR_CODES = Object.keys(ERRORS) as readonly CliErrorCode[];

const ACTION_REQUIRED: ReadonlySet<CliErrorCode> = new Set([
  "auth_required",
  "input_required",
  "confirmation_required",
]);

const RETRYABLE: ReadonlySet<CliErrorCode> = new Set([
  "database_unreachable",
  "network_error",
  "request_failed",
]);

/**
 * Whether a person has to give an input, confirm or log in before a retry
 * helps.
 */
export const isActionRequired = (code: CliErrorCode): boolean =>
  ACTION_REQUIRED.has(code);

/** Whether running the same command again later can succeed. */
export const isRetryable = (code: CliErrorCode): boolean => RETRYABLE.has(code);

/**
 * Codes for a report: the command printed its findings on stdout and exits 1,
 * so no error document is written.
 */
export const isReport = (code: CliErrorCode | undefined): boolean =>
  code === "findings" || code === "check_failed";

/** The exit code a `CliError` with `code` gets unless it sets its own. */
export const exitCodeOf = (code: CliErrorCode): ExitCode => ERRORS[code][1];

/** What a CLI error carries; `--json` prints it as the error document on stderr. */
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
  /** The flags the run needs, for `input_required`. */
  readonly missing?: readonly string[];
  /** The values each missing flag takes, the suggested one first. */
  readonly choices?: Readonly<Record<string, readonly string[]>>;
  /**
   * The value for `--effects-digest` once the user agrees, for
   * `confirmation_required`.
   */
  readonly digest?: string;
  /** What the run would change, one line each, for `confirmation_required`. */
  readonly effects?: readonly string[];
}

export type CliProblemExtensions = Pick<
  CliProblem,
  | "suggestion"
  | "flag"
  | "issues"
  | "missing"
  | "choices"
  | "digest"
  | "effects"
>;

export interface CliErrorOptions extends CliProblemExtensions {
  readonly exitCode?: number;
  readonly cause?: unknown;
  /** Commands that resolve the error, printed as the envelope's `next`. */
  readonly next?: readonly NextStep[];
}

/** An error the CLI reports as text, or as Problem Details under `--json`. */
export class CliError extends Error {
  override readonly name = "CliError";
  readonly code: CliErrorCode;
  readonly exitCode: number;
  readonly problem: CliProblem;
  readonly next: readonly NextStep[];

  constructor(
    code: CliErrorCode,
    message: string,
    options: CliErrorOptions = {},
  ) {
    super(message, options.cause === undefined ? {} : { cause: options.cause });

    const [title, defaultExit] = ERRORS[code];

    const {
      exitCode = defaultExit,
      cause: _cause,
      next = [],
      ...extensions
    } = options;

    this.code = code;
    this.exitCode = exitCode;
    this.next = next;
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

/** Citty's own argument errors. */
function isCittyUsageError(cause: unknown): cause is Error {
  return cause instanceof Error && cause.name === "CLIError";
}

const MISSING_POSITIONAL = /^Missing required positional argument: (\S+)$/;

/**
 * Any thrown value as a `CliError`: a missing required positional becomes
 * `input_required`, citty's other argument errors `usage`, the rest
 * `internal`.
 */
export function toCliError(cause: unknown): CliError {
  if (cause instanceof CliError) {
    return cause;
  }

  const positional = isCittyUsageError(cause)
    ? MISSING_POSITIONAL.exec(cause.message)?.[1]
    : undefined;

  if (positional !== undefined) {
    const name = positional.toLowerCase();

    return new CliError("input_required", `<${name}> is required.`, {
      missing: [`<${name}>`],
    });
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
 * The `values` that `isValid` accepts, or a usage message naming the ones it
 * rejects and the `available` names.
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
