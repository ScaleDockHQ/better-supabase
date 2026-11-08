import type { ExecResult } from "../exec.ts";
import type { AdvisorSource, Lint } from "./advisors.ts";

/** The first Supabase CLI release with `supabase db advisors`. */
const ADVISORS_CLI_VERSION = "2.81.3";

export type RunSupabase = (args: readonly string[]) => Promise<ExecResult>;

const parts = (version: string): number[] =>
  version.split(".").map((part) => Math.trunc(Number(part)) || 0);

/** Whether `version` (`2.84.0`) is at least `minimum`. */
export function versionAtLeast(version: string, minimum: string): boolean {
  const have = parts(version);
  const want = parts(minimum);

  for (let index = 0; index < want.length; index += 1) {
    const difference = (have[index] ?? 0) - (want[index] ?? 0);

    if (difference !== 0) {
      return difference > 0;
    }
  }

  return true;
}

/** A database URL that points at this machine, which is safe to put on argv. */
export function isLoopbackUrl(url: string): boolean {
  try {
    return ["localhost", "127.0.0.1", "[::1]", "::1"].includes(
      new URL(url).hostname,
    );
  } catch {
    return false;
  }
}

function isLint(value: unknown): value is Lint {
  // SAFETY: every field is checked below before value counts as a Lint.
  const lint = value as Partial<Lint> | null;

  return (
    typeof lint === "object" &&
    lint !== null &&
    typeof lint.name === "string" &&
    typeof lint.level === "string" &&
    Array.isArray(lint.categories)
  );
}

/**
 * The lints of `supabase db advisors -o json`: a list, or an object with
 * `lints`.
 */
export function parseAdvisorOutput(text: string): readonly Lint[] {
  // SAFETY: JSON.parse returns any, and each entry is checked below.
  const body = JSON.parse(text) as unknown;

  // SAFETY: only `lints` is read, and the result is checked with Array.isArray.
  const wrapped = body as { lints?: unknown } | null;
  const list = Array.isArray(body) ? body : wrapped?.lints;

  if (!Array.isArray(list)) {
    throw new TypeError("supabase db advisors printed no lints");
  }

  const lints = list.filter(isLint);

  if (list.length > 0 && lints.length === 0) {
    throw new TypeError("supabase db advisors printed an unknown lint shape");
  }

  return lints;
}

export interface CliAdvisorOptions {
  readonly run: RunSupabase;
  /** A loopback database URL; the CLI reads it from argv. */
  readonly dbUrl: string;
}

/**
 * The advisors `supabase db advisors` prints for a local database. `undefined`
 * when the installed CLI is older than 2.81.3 or the URL is not local, so the
 * caller falls back to splinter at the pinned commit.
 */
export async function cliAdvisors(
  options: CliAdvisorOptions,
): Promise<AdvisorSource | undefined> {
  if (!isLoopbackUrl(options.dbUrl)) {
    return undefined;
  }

  const result = await options.run(["--version"]);
  const version = /\d+\.\d+\.\d+/u.exec(result.stdout)?.[0];

  if (
    result.code !== 0 ||
    version === undefined ||
    !versionAtLeast(version, ADVISORS_CLI_VERSION)
  ) {
    return undefined;
  }

  return {
    describe: `database (supabase db advisors ${version})`,
    async lints(category) {
      const output = await options.run([
        "db",
        "advisors",
        "--db-url",
        options.dbUrl,
        "--type",
        category,
        "--level",
        "info",
        "-o",
        "json",
      ]);

      if (output.code !== 0) {
        throw new Error(
          `supabase db advisors exited with ${String(output.code)}: ${output.stderr.trim()}`,
        );
      }

      return parseAdvisorOutput(output.stdout);
    },
  };
}

/**
 * Tries `primary` first and reads `fallback` when it is missing or fails, so a
 * CLI whose output changes never hides the advisors.
 */
export function withFallback(
  primary: () => Promise<AdvisorSource | undefined>,
  fallback: AdvisorSource,
): AdvisorSource {
  let chosen: Promise<AdvisorSource | undefined> | undefined;

  return {
    describe: fallback.describe,
    async lints(category) {
      chosen ??= primary().catch(() => undefined);
      const cli = await chosen;

      if (cli) {
        try {
          return await cli.lints(category);
        } catch {
          chosen = Promise.resolve(undefined);
        }
      }

      return fallback.lints(category);
    },
  };
}
