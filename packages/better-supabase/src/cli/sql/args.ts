import type { CliOptions } from "../core/command.ts";

/** Every flag a `sql` subcommand takes; each subcommand declares its own subset. */
export const SQL_ARGS = {
  check: {
    type: "boolean",
    description:
      "With sync: fail when a file is stale. With upgrade: fail when a module is behind",
  },
  "tests-dir": {
    type: "string",
    description: "Where the pgtap module goes. Defaults to sql.testsDir",
    valueHint: "dir",
  },
  "dry-run": { type: "boolean", description: "Show what would be written" },
  "allow-hook-overlap": {
    type: "boolean",
    description:
      "Write modules whose claim the authorization provider's hook already writes",
  },
} as const;

export type SqlFlags = CliOptions<typeof SQL_ARGS>;
