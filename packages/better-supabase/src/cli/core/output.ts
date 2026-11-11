import type { Paint } from "../style.ts";
import type { CliErrorCode } from "./errors.ts";
import type { CommandResult, NextStep } from "./io.ts";

import { highlight } from "../style.ts";
import { CliError, isActionRequired, isReport, isRetryable } from "./errors.ts";
import { splitCommandLine } from "./shell.ts";

/**
 * What one run writes: text, or under `--json` exactly one JSON document on
 * stdout.
 */
export interface Rendered {
  readonly stdout?: string;
  readonly stderr?: string;
  /** Written to stdout byte for byte, with no newline added. */
  readonly raw?: string;
}

export interface RenderOptions {
  readonly json: boolean;
  /** Colors for stdout. */
  readonly paint: Paint;
  /** Colors for stderr. Defaults to `paint`. */
  readonly errorPaint?: Paint;
  /** One envelope per line (NDJSON), for results streamed under `--watch`. */
  readonly compact?: boolean;
}

export const RESULT_SCHEMA_URL =
  "https://unpkg.com/better-supabase/schemas/cli-result-v2.json";

/**
 * `action_required` when a person has to act: give an input, confirm, or log
 * in. `next` then names the command to run.
 */
export type ResultStatus = "success" | "error" | "action_required";

/**
 * The one document `--json` prints on stdout, described by
 * `schemas/cli-result-v2.json`.
 */
export interface ResultEnvelope {
  readonly $schema: string;
  readonly status: ResultStatus;
  readonly data?: unknown;
  readonly warnings?: readonly string[];
  readonly next?: readonly NextStep[];
}

/**
 * The single-line document `--json` prints on stderr when a run fails. Stdout
 * stays empty, so a caller that parses stdout never reads half an answer.
 */
export interface ErrorDocument {
  readonly $schema: string;
  readonly status: Exclude<ResultStatus, "success">;
  readonly reason: CliErrorCode;
  readonly message: string;
  /** Links to the reason on the CLI errors page. */
  readonly type: string;
  readonly next: readonly NextStep[];
  readonly data: Readonly<Record<string, unknown>>;
  readonly userActionRequired: boolean;
  readonly retryable: boolean;
}

const statusOf = (exitCode: number): ResultStatus =>
  exitCode === 0 ? "success" : "error";

function defaultErrorCode(exitCode: number): CliErrorCode {
  switch (exitCode) {
    case 2: {
      return "usage";
    }

    case 130: {
      return "cancelled";
    }

    default: {
      return "failed";
    }
  }
}

/** `step` with its `argv` filled in from `command`. */
const withArgv = (step: NextStep): NextStep =>
  step.argv ? step : { ...step, argv: splitCommandLine(step.command) };

/** The `--json` envelope for a run that ended with `exitCode`. */
export function envelope(
  exitCode: number,
  parts: Omit<ResultEnvelope, "$schema" | "status"> = {},
): ResultEnvelope {
  return {
    $schema: RESULT_SCHEMA_URL,
    status: statusOf(exitCode),
    ...(parts.data === undefined ? {} : { data: parts.data }),
    ...(parts.warnings && parts.warnings.length > 0
      ? { warnings: parts.warnings }
      : {}),
    ...(parts.next && parts.next.length > 0
      ? { next: parts.next.map(withArgv) }
      : {}),
  };
}

/** The error document for `error`, with `data` merged into its details. */
export function errorDocument(
  error: CliError,
  data: Readonly<Record<string, unknown>> = {},
): ErrorDocument {
  const { suggestion, flag, issues, missing, choices, digest, effects } =
    error.problem;

  const details = {
    ...(suggestion === undefined ? {} : { suggestion }),
    ...(flag === undefined ? {} : { flag }),
    ...(issues === undefined ? {} : { issues }),
    ...(missing === undefined ? {} : { missing }),
    ...(choices === undefined ? {} : { choices }),
    ...(digest === undefined ? {} : { digest }),
    ...(effects === undefined ? {} : { effects }),
    ...data,
  };

  return {
    $schema: RESULT_SCHEMA_URL,
    status: isActionRequired(error.code) ? "action_required" : "error",
    reason: error.code,
    message: error.message,
    type: error.problem.type,
    next: error.next.map(withArgv),
    data: details,
    userActionRequired: isActionRequired(error.code),
    retryable: isRetryable(error.code),
  };
}

export const document = (value: unknown): string =>
  JSON.stringify(value, null, 2);

/** The one line `--json` prints for a failure on stderr. */
const errorLine = (value: ErrorDocument): string => JSON.stringify(value);

function nextText(next: readonly NextStep[], paint: Paint): string {
  const width = Math.max(...next.map((step) => step.command.length));

  return [
    "Next steps:",
    ...next.map(
      (step) => `  ${paint("cyan", step.command.padEnd(width))}  ${step.when}`,
    ),
  ].join("\n");
}

const failure = (message: string, paint: Paint): string =>
  paint("red", message);

const warning = (message: string, paint: Paint): string =>
  `${paint("yellow", "!")} ${message}`;

/**
 * A command's result. Under `--json`, stdout gets the envelope with the
 * command's `data` and `next` steps, and the text output moves to stderr as a
 * diagnostic. A failure prints the error document on stderr and leaves stdout
 * empty; a report (`findings`, `check_failed`) keeps its data on stdout and
 * writes no error document.
 */
export function renderResult(
  result: CommandResult,
  options: RenderOptions,
): Rendered {
  const next = result.next ?? [];
  const warnings = result.warnings ?? [];
  const errorPaint = options.errorPaint ?? options.paint;

  if (result.streamed === true) {
    return {};
  }

  if (result.raw !== undefined) {
    return { raw: result.raw };
  }

  if (!options.json) {
    const stdout = result.output ? highlight(result.output, options.paint) : "";

    const stderr = [
      ...warnings.map((message) => warning(message, errorPaint)),
      ...(result.error ? [failure(result.error, errorPaint)] : []),
      ...(next.length > 0 ? [nextText(next, errorPaint)] : []),
    ].join("\n\n");

    return { ...(stdout ? { stdout } : {}), ...(stderr ? { stderr } : {}) };
  }

  const failed = result.code !== 0;

  if (failed && !isReport(result.errorCode)) {
    const error = new CliError(
      result.errorCode ?? defaultErrorCode(result.code),
      result.error ?? result.output ?? "The command failed.",
      { exitCode: result.code, next },
    );

    const data =
      typeof result.data === "object" &&
      result.data !== null &&
      !Array.isArray(result.data)
        ? Object.fromEntries(Object.entries(result.data))
        : result.data === undefined
          ? {}
          : { result: result.data };

    return {
      stderr: [
        ...(result.output ? [result.output] : []),
        ...warnings.map((message) => warning(message, errorPaint)),
        errorLine(errorDocument(error, data)),
      ].join("\n"),
    };
  }

  const diagnostics = [
    ...(result.output ? [result.output] : []),
    ...warnings.map((message) => warning(message, errorPaint)),
    ...(result.error ? [failure(result.error, errorPaint)] : []),
  ];

  const shown = envelope(result.code, {
    ...(result.data === undefined ? {} : { data: result.data }),
    ...(warnings.length > 0 ? { warnings } : {}),
    next,
  });

  return {
    stdout: options.compact === true ? JSON.stringify(shown) : document(shown),
    ...(diagnostics.length > 0 ? { stderr: diagnostics.join("\n") } : {}),
  };
}

/** An error that stopped the run, with the usage text for usage errors. */
export function renderError(
  error: CliError,
  options: RenderOptions & { readonly usage?: string },
): Rendered {
  if (options.json) {
    return { stderr: errorLine(errorDocument(error)) };
  }

  const paint = options.errorPaint ?? options.paint;

  return {
    stderr: [
      failure(error.message, paint),
      ...(error.next.length > 0 ? [nextText(error.next, paint)] : []),
      ...(options.usage ? [options.usage] : []),
    ].join("\n\n"),
  };
}
