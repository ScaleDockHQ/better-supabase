/**
 * The built-in commands as static data: names, descriptions, groups, docs
 * links, examples and side effects. Help, `--help --json`, completion and the
 * docs drift test read it without loading a command module.
 */

export type CommandGroup =
  | "setup"
  | "generate"
  | "local"
  | "inspect"
  | "maintain"
  | "account";

/** Root help prints the groups in this order and skips empty ones; `account` is kept for login and other cloud commands. */
export const GROUPS: readonly (readonly [CommandGroup, string])[] = [
  ["setup", "Set up"],
  ["generate", "Generate"],
  ["local", "Local stack"],
  ["inspect", "Inspect"],
  ["maintain", "Maintain"],
  ["account", "Account"],
];

/** Services a command contacts over the network. */
type NetworkTarget = "supabase-api" | "github";

export type CommandEffect = (
  | { readonly kind: "files" }
  | { readonly kind: "database"; readonly access: "read" | "write" }
  | { readonly kind: "network"; readonly target: NetworkTarget }
) & {
  /** The flag that turns the effect on, when the command doesn't always have it. */
  readonly when?: string;
};

export interface CommandExample {
  readonly command: string;
  readonly description: string;
}

export interface CommandSpec {
  readonly name: string;
  readonly description: string;
  /** Root help lists commands without a group under Other commands. */
  readonly group?: CommandGroup;
  /** Path under https://bettersupabase.com, with its anchor. */
  readonly docs?: string;
  readonly examples?: readonly CommandExample[];
  /** What the command changes or contacts; unset for commands from outside the manifest. */
  readonly effects?: readonly CommandEffect[];
  readonly subcommands?: readonly CommandSpec[];
}

/** Top-level names left free for account and cloud commands. */
export const RESERVED_NAMES: readonly string[] = [
  "login",
  "logout",
  "whoami",
  "link",
  "projects",
  "deploy",
  "cloud",
];

/** The hidden command the completion scripts call. */
export const COMPLETE_COMMAND = "__complete";

export const DOCS_ORIGIN = "https://bettersupabase.com";

const FILES: CommandEffect = { kind: "files" };
const READS_DATABASE: CommandEffect = { kind: "database", access: "read" };

const MANAGEMENT_API: CommandEffect = {
  kind: "network",
  target: "supabase-api",
  when: "--project-ref",
};

export const COMMANDS: readonly CommandSpec[] = [
  {
    name: "init",
    description:
      "Writes better-supabase.config.ts, src/lib/supabase/index.ts and glue for the frameworks in package.json",
    group: "setup",
    docs: "/docs/cli/init",
    examples: [
      {
        command: "better-supabase init",
        description: "Asks what to set up, then writes the files",
      },
      {
        command: "better-supabase init --preset saas --yes",
        description: "Starts from a preset without asking",
      },
    ],
    effects: [FILES],
  },
  {
    name: "add",
    description:
      "Adds blocks with what they require, or glue for an integration with --integration",
    group: "setup",
    docs: "/docs/cli/init#add",
    examples: [
      {
        command: "better-supabase add organizations billing",
        description: "Installs two blocks and the modules they require",
      },
      {
        command: "better-supabase add --integration hono",
        description: "Adds the Hono glue",
      },
    ],
    effects: [FILES],
  },
  {
    name: "apply",
    description:
      "Applies a preset to an existing project: edits the config, shows the diff and writes the blocks' modules",
    group: "setup",
    docs: "/docs/cli/presets#apply",
    effects: [FILES, { ...READS_DATABASE, when: "--adopt" }, MANAGEMENT_API],
  },
  {
    name: "adopt",
    description:
      "Maps a block onto tables the app already has: proposes blocks.<block> in adopt mode and reports what can't map",
    group: "setup",
    docs: "/docs/cli/presets#adopt",
    effects: [FILES, READS_DATABASE, MANAGEMENT_API],
  },
  {
    name: "preset",
    description:
      "Decodes a preset code, or shows the config's preset and how the config differs from it",
    group: "setup",
    docs: "/docs/cli/presets#preset",
    effects: [],
    subcommands: [
      {
        name: "decode",
        description:
          "Prints the blocks, auth and settings a preset code or Create URL holds",
        docs: "/docs/cli/presets#preset",
        effects: [],
      },
      {
        name: "info",
        description:
          "Shows the config's preset and how the config differs from it",
        docs: "/docs/cli/presets#preset",
        effects: [],
      },
    ],
  },
  {
    name: "blocks",
    description: "Lists, shows and searches the blocks you can add",
    group: "setup",
    docs: "/docs/cli/presets#blocks",
    effects: [],
    subcommands: [
      {
        name: "list",
        description: "Lists the blocks, optionally in one category",
        docs: "/docs/cli/presets#blocks",
        effects: [],
      },
      {
        name: "view",
        description:
          "Shows a block: its tables, the blocks it requires and its options",
        docs: "/docs/cli/presets#blocks",
        effects: [],
      },
      {
        name: "search",
        description: "Finds blocks by name, description or category",
        docs: "/docs/cli/presets#blocks",
        effects: [],
      },
    ],
  },
  {
    name: "skills",
    description:
      "Installs the Agent Skills that ship with this version of better-supabase",
    group: "setup",
    docs: "/docs/for-ai-agents",
    effects: [FILES],
    subcommands: [
      {
        name: "list",
        description: "Lists the skills that ship with this version",
        docs: "/docs/for-ai-agents",
        effects: [],
      },
      {
        name: "install",
        description:
          "Copies the skills into each agent's skills folder in the project, or the home folder with --global",
        docs: "/docs/for-ai-agents",
        effects: [FILES],
      },
    ],
  },
  {
    name: "completion",
    description:
      "Prints the shell completion script for bash, zsh or fish, for both better-supabase and bsb",
    group: "setup",
    docs: "/docs/cli/completion",
    examples: [
      {
        command: 'eval "$(better-supabase completion zsh)"',
        description:
          "Turns on completion in the current zsh; add it to ~/.zshrc",
      },
    ],
    effects: [],
  },
  {
    name: "gen",
    description:
      "Writes the typed client from the database, then every other generated file the config sets up",
    group: "generate",
    docs: "/docs/cli/gen",
    examples: [
      {
        command: "better-supabase gen",
        description: "Regenerates every file the config sets up",
      },
      {
        command: "better-supabase gen --check",
        description: "Exits 1 when a generated file is out of date",
      },
    ],
    effects: [FILES, READS_DATABASE, MANAGEMENT_API],
  },
  {
    name: "introspect",
    description: "Saves the database schema as a snapshot for offline gen",
    group: "generate",
    docs: "/docs/cli/introspect",
    effects: [FILES, READS_DATABASE, MANAGEMENT_API],
  },
  {
    name: "spec",
    description:
      "Writes, checks or validates the OpenAPI and other spec documents your defineApi() module renders",
    group: "generate",
    docs: "/docs/cli/spec",
    effects: [FILES],
    subcommands: [
      {
        name: "emit",
        description:
          "Writes the spec documents, or exits 1 when one is out of date with --check",
        docs: "/docs/cli/spec",
        examples: [
          {
            command: "better-supabase spec emit openapi",
            description: "Writes the OpenAPI document",
          },
          {
            command: "better-supabase spec emit --check",
            description: "Exits 1 when a written document is out of date",
          },
        ],
        effects: [FILES],
      },
      {
        name: "validate",
        description:
          "Validates the documents against their specs and lints them, writing nothing",
        docs: "/docs/cli/spec",
        effects: [],
      },
    ],
  },
  {
    name: "scaffold",
    description:
      "Writes an API module and its routes for Hono or Next.js, or list, create and detail pages for an app table",
    group: "generate",
    docs: "/docs/cli/scaffold",
    effects: [FILES],
    subcommands: [
      {
        name: "api",
        description:
          "Writes an API module, its resource routes and an OpenAPI route for Hono or Next.js",
        docs: "/docs/cli/scaffold",
        effects: [FILES],
      },
      {
        name: "screens",
        description:
          "Writes Next.js list, create and detail pages for an app table",
        docs: "/docs/cli/scaffold#screens",
        effects: [FILES],
      },
    ],
  },
  {
    name: "env",
    description:
      "Writes the local stack's URL and keys from `supabase status` to an env file, keeping its other lines",
    group: "local",
    docs: "/docs/cli/local#env",
    effects: [FILES],
  },
  {
    name: "keys",
    description:
      "Creates an ES256 signing key for the local stack, so local tokens verify through JWKS like hosted ones",
    group: "local",
    docs: "/docs/cli/local#keys",
    effects: [FILES],
  },
  {
    name: "seed",
    description:
      "Renders the fixtures from defineSeed() (better-supabase/testing) to SQL",
    group: "local",
    docs: "/docs/cli/local#seed",
    effects: [FILES, { kind: "database", access: "write", when: "--apply" }],
  },
  {
    name: "db",
    description:
      "Runs SQL files against the database: the local stack by default, or the one in the connection string",
    group: "local",
    docs: "/docs/cli/db",
    effects: [{ kind: "database", access: "write" }],
    subcommands: [
      {
        name: "query",
        description:
          "Runs each file as one multi-statement script, in order, optionally in a single transaction",
        docs: "/docs/cli/db#query",
        examples: [
          {
            command:
              "better-supabase db query --single-transaction a.sql b.sql",
            description: "Runs both files, or neither when one fails",
          },
        ],
        effects: [{ kind: "database", access: "write" }],
      },
    ],
  },
  {
    name: "doctor",
    description:
      "Checks RLS, indexes, drift, auth config and env files; exits 1 on errors, or on warnings with --fail-on warning",
    group: "inspect",
    docs: "/docs/cli/doctor",
    examples: [
      {
        command: "better-supabase doctor",
        description: "Checks the local database and the project",
      },
      {
        command: "better-supabase doctor --format sarif --out doctor.sarif",
        description: "Writes the findings for code scanning",
      },
    ],
    effects: [
      READS_DATABASE,
      MANAGEMENT_API,
      { kind: "network", target: "github" },
    ],
  },
  {
    name: "config",
    description:
      "Prints the resolved config: the file it came from, the active environment and every option with its default",
    group: "inspect",
    docs: "/docs/cli/config#print-the-resolved-config",
    effects: [],
  },
  {
    name: "mcp",
    description:
      "Serves the CLI to coding agents as an MCP server on stdio: read-only tools, and file writes with --allow-writes and the user's consent",
    group: "inspect",
    docs: "/docs/cli/mcp",
    examples: [
      {
        command: "better-supabase mcp",
        description:
          "Starts the read-only server; add it to the agent's MCP config",
      },
      {
        command: "better-supabase mcp --allow-writes",
        description:
          "Adds gen, sql_sync, apply and add, each behind a consent token",
      },
    ],
    effects: [READS_DATABASE, { kind: "files", when: "--allow-writes" }],
  },
  {
    name: "sql",
    description:
      "Low-level SQL module commands: lists, adds, syncs, upgrades and prints module files without touching app code, and writes their data migration",
    group: "maintain",
    docs: "/docs/blocks/sql",
    effects: [FILES],
    subcommands: [
      {
        name: "list",
        description: "Lists the SQL modules and which ones the project has",
        docs: "/docs/blocks/sql",
        effects: [],
      },
      {
        name: "add",
        description:
          "Writes module files and their pgTAP tests, and adds the modules to the config",
        docs: "/docs/blocks/sql",
        effects: [FILES],
      },
      {
        name: "sync",
        description:
          "Writes the files for the modules the config lists and removes the ones it no longer lists",
        docs: "/docs/blocks/sql",
        effects: [FILES],
      },
      {
        name: "upgrade",
        description:
          "Rewrites module files to this version's SQL, or exits 1 when one is behind with --check",
        docs: "/docs/blocks/sql",
        effects: [FILES],
      },
      {
        name: "data",
        description: "Writes the data migration for blocks in adopt mode",
        docs: "/docs/blocks/sql",
        effects: [FILES],
      },
      {
        name: "print",
        description: "Prints a module's SQL on stdout",
        docs: "/docs/blocks/sql",
        effects: [],
      },
    ],
  },
  {
    name: "codemod",
    description:
      "Rewrites imports, calls and config keys for renamed better-supabase APIs",
    group: "maintain",
    docs: "/docs/cli/codemod",
    effects: [FILES],
    subcommands: [
      {
        name: "0.4",
        description: "Renames from 0.3 to 0.4",
        docs: "/docs/cli/codemod",
        effects: [FILES],
      },
      {
        name: "0.5",
        description: "Renames from 0.4 to 0.5",
        docs: "/docs/cli/codemod",
        effects: [FILES],
      },
      {
        name: "0.6",
        description: "Changes from 0.5 to 0.6: kits become blocks and modules",
        docs: "/docs/cli/codemod",
        effects: [FILES],
      },
      {
        name: "0.9",
        description:
          "Changes from 0.8 to 0.9: sql.modules becomes blocks, and CLI calls use the new subcommands and flags",
        docs: "/docs/cli/codemod",
        effects: [FILES],
      },
    ],
  },
];

/** The spec at `path` (`["sql", "add"]`), or `undefined`. */
export function findSpec(
  path: readonly string[],
  commands: readonly CommandSpec[] = COMMANDS,
): CommandSpec | undefined {
  let level: readonly CommandSpec[] | undefined = commands;
  let found: CommandSpec | undefined;

  for (const name of path) {
    found = level?.find((spec) => spec.name === name);

    if (!found) {
      return undefined;
    }

    level = found.subcommands;
  }

  return found;
}

/** Every command path in the manifest, parents before their subcommands. */
export function specPaths(
  commands: readonly CommandSpec[] = COMMANDS,
  parent: readonly string[] = [],
): string[][] {
  return commands.flatMap((spec) => {
    const path = [...parent, spec.name];

    return [path, ...specPaths(spec.subcommands ?? [], path)];
  });
}

/** The meta a built-in command's `defineCliCommand` takes, read from the manifest. */
export function commandMeta(path: string): {
  readonly name: string;
  readonly description: string;
} {
  const parts = path.split(" ");
  const spec = findSpec(parts);

  if (!spec) {
    throw new TypeError(`"${path}" is not in the command manifest`);
  }

  return { name: spec.name, description: spec.description };
}
