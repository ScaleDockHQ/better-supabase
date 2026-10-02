/** `1` for a failure, `2` for a usage error the caller can fix by changing the command. */
export type ExitCode = 1 | 2;

export type CliErrorCode =
  | "usage"
  | "unknown_command"
  | "missing_value"
  | "config_not_found"
  | "config_invalid"
  | "env_invalid"
  | "failed"
  | "internal";

/** Each code has a heading on this page, so `type` links to its explanation. */
export const CLI_ERRORS_URL = "https://bettersupabase.com/docs/cli/errors";

const TITLES: { readonly [K in CliErrorCode]: string } = {
  usage: "Invalid arguments",
  unknown_command: "Unknown command",
  missing_value: "Missing value",
  config_not_found: "Config file not found",
  config_invalid: "Invalid config",
  env_invalid: "Invalid environment variable",
  failed: "Command failed",
  internal: "Unexpected error",
};

const EXIT_CODES: { readonly [K in CliErrorCode]: ExitCode } = {
  usage: 2,
  unknown_command: 2,
  missing_value: 2,
  config_not_found: 2,
  config_invalid: 2,
  env_invalid: 2,
  failed: 1,
  internal: 1,
};

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
    const {
      exitCode = EXIT_CODES[code],
      cause: _cause,
      ...extensions
    } = options;
    this.code = code;
    this.exitCode = exitCode;
    this.problem = {
      type: `${CLI_ERRORS_URL}#${code}`,
      title: TITLES[code],
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
  if (cause instanceof CliError) return cause;
  if (isCittyUsageError(cause)) return new CliError("usage", cause.message);
  return new CliError(
    "internal",
    cause instanceof Error ? cause.message : String(cause),
    { cause },
  );
}
