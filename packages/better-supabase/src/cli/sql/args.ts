import type { CliArgs, CliOptions } from "../command.ts";

export const SQL_ARGS = {
  action: {
    type: "positional",
    required: false,
    description:
      "list (modules and whether they are installed), add <module...>, sync, upgrade, data (a migration with the rows a schema diff skips) or print <module>",
  },
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
  force: {
    type: "boolean",
    description:
      "Write tenant even though the authorization provider's hook owns the memberships claim",
  },
} as const;

export type SqlArgs = CliArgs<typeof SQL_ARGS>;

export type SqlFlags = CliOptions<typeof SQL_ARGS>;

export const USAGE = "Run `better-supabase sql --help` for the actions.";
