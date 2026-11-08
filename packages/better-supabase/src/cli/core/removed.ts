import { CliError } from "./errors.ts";

/** A flag contract 3 removed, with the command line that replaces it. */
interface RemovedFlag {
  /** The command path the flag belonged to; empty for every command. */
  readonly path: readonly string[];
  readonly flag: string;
  readonly replacement: string;
}

/** Removed flags have no alias: they exit 2 and name what to run instead. */
const REMOVED: readonly RemovedFlag[] = [
  {
    path: [],
    flag: "--confirm",
    replacement: "--yes --effects-digest <digest>",
  },
  {
    path: ["db", "seed"],
    flag: "--apply",
    replacement: "--yes (it inserts the rows; --dry-run previews)",
  },
  {
    path: ["doctor"],
    flag: "--fix",
    replacement: "--yes (it runs the fixes against the database)",
  },
  { path: ["dev", "env"], flag: "--write", replacement: "--out <file>" },
  {
    path: ["gen"],
    flag: "--emit",
    replacement: "--only <file> with --metadata",
  },
  {
    path: ["gen"],
    flag: "--out-dir",
    replacement: "--out <dir> with --metadata",
  },
  {
    path: ["gen"],
    flag: "--watch",
    replacement: "the dev command (better-supabase dev)",
  },
  {
    path: ["gen"],
    flag: "--interval",
    replacement: "the dev command (better-supabase dev --interval <ms>)",
  },
];

const startsWith = (
  path: readonly string[],
  prefix: readonly string[],
): boolean => prefix.every((name, index) => path[index] === name);

/**
 * Throws a `flag_renamed` usage error when `rest` (the arguments after the
 * command names) passes a removed flag of the command at `path`.
 */
export function removedFlag(
  path: readonly string[],
  rest: readonly string[],
): void {
  const end = rest.indexOf("--");
  const options = end === -1 ? rest : rest.slice(0, end);

  for (const entry of REMOVED) {
    if (
      startsWith(path, entry.path) &&
      options.some(
        (arg) => arg === entry.flag || arg.startsWith(`${entry.flag}=`),
      )
    ) {
      throw new CliError(
        "flag_renamed",
        `${entry.flag} was removed. Use ${entry.replacement} instead.`,
        { flag: entry.flag, suggestion: entry.replacement },
      );
    }
  }
}
