import type { CommandResult } from "./io.ts";

import { CliError } from "./errors.ts";
import { highlight, type Paint } from "./style.ts";

/** What one run writes: text, or under `--json` exactly one JSON document on stdout. */
export interface Rendered {
  readonly stdout?: string;
  readonly stderr?: string;
}

export interface RenderOptions {
  readonly json: boolean;
  readonly paint: Paint;
}

const document = (value: unknown): string => JSON.stringify(value, null, 2);

/**
 * A command's result. Under `--json`, stdout gets the command's `data`, or
 * `{ "message": output }` when it has none, or Problem Details when it failed
 * without data; the text output moves to stderr as a diagnostic.
 */
export function renderResult(
  result: CommandResult,
  options: RenderOptions,
): Rendered {
  if (!options.json) {
    return {
      ...(result.output
        ? { stdout: highlight(result.output, options.paint) }
        : {}),
      ...(result.error ? { stderr: options.paint("red", result.error) } : {}),
    };
  }
  if (result.data === undefined && result.error) {
    return {
      stdout: document(
        new CliError("failed", result.error, { exitCode: result.code }).problem,
      ),
      ...(result.output ? { stderr: result.output } : {}),
    };
  }
  const diagnostics = [
    ...(result.data !== undefined && result.output ? [result.output] : []),
    ...(result.error ? [result.error] : []),
  ];
  return {
    stdout: document(result.data ?? { message: result.output ?? "" }),
    ...(diagnostics.length > 0 ? { stderr: diagnostics.join("\n") } : {}),
  };
}

/** An error that stopped the run, with the usage text for usage errors. */
export function renderError(
  error: CliError,
  options: RenderOptions & { readonly usage?: string },
): Rendered {
  if (options.json) return { stdout: document(error.problem) };
  return {
    stderr: options.usage
      ? `${error.message}\n\n${options.usage}`
      : error.message,
  };
}
