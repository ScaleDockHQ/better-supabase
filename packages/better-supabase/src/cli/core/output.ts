import type { CommandResult, NextStep } from "./io.ts";

import { highlight, type Paint } from "../style.ts";
import { CliError, type CliErrorCode, type CliProblem } from "./errors.ts";

/** What one run writes: text, or under `--json` exactly one JSON document on stdout. */
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
  "https://unpkg.com/better-supabase/schemas/cli-result-v1.json";

/**
 * `action_required` when the user has to act (exit code 3): give an input,
 * consent, or log in. `next` then names the command to run.
 */
export type ResultStatus = "success" | "error" | "action_required";

/** The one document `--json` prints, described by `schemas/cli-result-v1.json`. */
export interface ResultEnvelope {
  readonly $schema: string;
  readonly status: ResultStatus;
  readonly data?: unknown;
  readonly error?: CliProblem;
  readonly next?: readonly NextStep[];
}

const statusOf = (exitCode: number): ResultStatus => {
  if (exitCode === 0) {
    return "success";
  }

  return exitCode === 3 ? "action_required" : "error";
};

function defaultErrorCode(exitCode: number): CliErrorCode {
  switch (exitCode) {
    case 2: {
      return "usage";
    }

    case 3: {
      return "input_required";
    }

    case 130: {
      return "cancelled";
    }

    default: {
      return "failed";
    }
  }
}

/** The `--json` envelope for a run that ended with `exitCode`. */
export function envelope(
  exitCode: number,
  parts: Omit<ResultEnvelope, "$schema" | "status"> = {},
): ResultEnvelope {
  return {
    $schema: RESULT_SCHEMA_URL,
    status: statusOf(exitCode),
    ...(parts.data === undefined ? {} : { data: parts.data }),
    ...(parts.error ? { error: parts.error } : {}),
    ...(parts.next && parts.next.length > 0 ? { next: parts.next } : {}),
  };
}

export const document = (value: unknown): string =>
  JSON.stringify(value, null, 2);

function nextText(next: readonly NextStep[], paint: Paint): string {
  const width = Math.max(...next.map((step) => step.command.length));

  return [
    "Next:",
    ...next.map(
      (step) => `  ${paint("cyan", step.command.padEnd(width))}  ${step.when}`,
    ),
  ].join("\n");
}

/**
 * A command's result. Under `--json`, stdout gets the envelope with the
 * command's `data`, its `next` steps, and Problem Details when it failed;
 * the text output moves to stderr as a diagnostic.
 */
export function renderResult(
  result: CommandResult,
  options: RenderOptions,
): Rendered {
  const next = result.next ?? [];
  const errorPaint = options.errorPaint ?? options.paint;

  if (result.streamed === true) {
    return {};
  }

  if (result.raw !== undefined) {
    return { raw: result.raw };
  }

  if (!options.json) {
    const stdout = [
      ...(result.output ? [highlight(result.output, options.paint)] : []),
      ...(next.length > 0 && result.code === 0
        ? [nextText(next, options.paint)]
        : []),
    ].join("\n\n");

    return {
      ...(stdout ? { stdout } : {}),
      ...(result.error ? { stderr: errorPaint("red", result.error) } : {}),
    };
  }

  const failed = result.code !== 0;

  const problem = failed
    ? new CliError(
        result.errorCode ?? defaultErrorCode(result.code),
        result.error ?? result.output ?? "The command failed.",
        { exitCode: result.code },
      ).problem
    : undefined;

  const diagnostics = [
    ...(result.output ? [result.output] : []),
    ...(result.error && !failed ? [result.error] : []),
  ];

  const shown = envelope(result.code, {
    ...(result.data === undefined ? {} : { data: result.data }),
    ...(problem ? { error: problem } : {}),
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
    return {
      stdout: document(
        envelope(error.exitCode, { error: error.problem, next: error.next }),
      ),
    };
  }

  return {
    stderr: [
      error.message,
      ...(error.next.length > 0
        ? [nextText(error.next, options.errorPaint ?? options.paint)]
        : []),
      ...(options.usage ? [options.usage] : []),
    ].join("\n\n"),
  };
}
