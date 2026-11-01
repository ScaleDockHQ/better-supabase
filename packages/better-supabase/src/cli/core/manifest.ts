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

/**
 * Root help prints the groups in this order and skips empty ones; `account` is
 * kept for login and other cloud commands.
 */
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
  | { readonly kind: "process" }
  | { readonly kind: "stacks"; readonly access: "read" | "write" }
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
  /**
   * What the command changes or contacts; unset for commands from outside the
   * manifest.
   */
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
      "Adds blocks with what they require, a preset with --preset, existing tables with --adopt, or glue for an integration with --integration",
    group: "setup",
    docs: "/docs/cli/init#add",
    examples: [
      {
        command: "better-supabase add organizations billing",
        description: "Installs two blocks and the blocks they require",
      },
      {
        command: "better-supabase add --preset saas",
        description:
          "Applies a preset to the config, shows the diff and writes the blocks' SQL",
      },
      {
        command: "better-supabase add teams --adopt --tables public.teams",
        description: "Maps the teams block onto a table the app already has",
      },
      {
        command: "better-supabase add --integration hono",
        description: "Adds the Hono glue",
      },
    ],
    effects: [FILES, { ...READS_DATABASE, when: "--adopt" }, MANAGEMENT_API],
  },
  {
    name: "remove",
    description:
      "Removes blocks: their config entries, their clients in lib/blocks.ts and the SQL files no other block needs",
    group: "setup",
    docs: "/docs/cli/init#remove",
    examples: [
      {
        command: "better-supabase remove comments",
        description:
          "Removes the block, then names the db diff that drops its tables",
      },
      {
        command: "better-supabase remove crm --with-parts",
        description:
          "Removes a composite and its parts, except the parts another block still needs",
      },
    ],
    effects: [FILES],
  },
  {
    name: "table",
    description:
      "Turns a per-table feature on or off with its @bsb tag in the table comment, in the schema file that creates the table",
    group: "setup",
    docs: "/docs/cli/table",
    examples: [
      {
        command: "better-supabase table invoices enable realtime",
        description: "Adds the realtime tag to the invoices table comment",
      },
      {
        command: "better-supabase table public.invoices disable audit",
        description: "Removes the audit tag and keeps the comment's text",
      },
    ],
    effects: [FILES],
  },
  {
    name: "migrate",
    description:
      "Moves a project to a newer model: schema-first turns appTables into table files you own",
    group: "maintain",
    docs: "/docs/cli/migrate",
    effects: [FILES],
    subcommands: [
      {
        name: "schema-first",
        description:
          "Writes the tables appTables renders as files under supabase/schemas, with the per-table features as @bsb tags",
        docs: "/docs/cli/migrate",
        examples: [
          {
            command: "better-supabase migrate schema-first --dry-run",
            description: "Shows the table files without writing them",
          },
        ],
        effects: [FILES],
      },
    ],
  },
  {
    name: "upgrade",
    description:
      "Brings the blocks' SQL up to the config and this release: upgrade steps for blocks behind, then every block's files",
    group: "setup",
    docs: "/docs/cli/init#upgrade",
    examples: [
      {
        command: "better-supabase upgrade",
        description: "Writes the upgrade steps and the blocks' SQL files",
      },
      {
        command: "better-supabase upgrade --check",
        description:
          "Exits 1 when a block is behind or a SQL file is out of date",
      },
    ],
    effects: [FILES],
  },
  {
    name: "blocks",
    description:
      "Lists, shows and searches the blocks you can add, and decodes presets",
    group: "setup",
    docs: "/docs/cli/presets#blocks",
    effects: [],
    subcommands: [
      {
        name: "list",
        description:
          "Lists the blocks, the ones this project installed with --installed, or a preset's with --preset",
        docs: "/docs/cli/presets#blocks",
        examples: [
          {
            command: "better-supabase blocks list --preset saas",
            description:
              "Prints the blocks, auth and settings a preset, code or Create URL holds",
          },
        ],
        effects: [],
      },
      {
        name: "view",
        description:
          "Shows a block: the blocks it requires, its modes and its client, or its SQL with --sql",
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
    name: "automations",
    description: "Lists the automations the installed blocks ship",
    group: "inspect",
    docs: "/docs/cli/automations",
    effects: [],
    subcommands: [
      {
        name: "list",
        description:
          "Lists each automation's trigger and actions, and with --explain what starts and runs it",
        docs: "/docs/cli/automations",
        examples: [
          {
            command: "better-supabase automations list --explain",
            description:
              "Says which block's event starts each automation and what each action does",
          },
        ],
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
      {
        command: "better-supabase gen --save-snapshot",
        description: "Saves the database schema as a snapshot for offline gen",
      },
    ],
    effects: [FILES, READS_DATABASE, MANAGEMENT_API],
  },
  {
    name: "powersync",
    description:
      "Writes PowerSync sync streams, the PowerSync schema and the publication migration for the blocks that sync offline",
    group: "generate",
    docs: "/docs/cli/powersync",
    effects: [FILES],
    subcommands: [
      {
        name: "streams",
        description:
          "Writes sync-streams.yaml and schema.ts for the synced block instances, and a migration that adds their tables to the powersync publication",
        docs: "/docs/cli/powersync",
        examples: [
          {
            command: "better-supabase powersync streams",
            description: "Writes the files for gen.powersync.instances",
          },
          {
            command:
              "better-supabase powersync streams --instance notifications --check",
            description: "Exits 1 when a file for notifications is out of date",
          },
        ],
        effects: [FILES],
      },
    ],
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
    name: "dev",
    description:
      "Works with the local stack: its env file, commands run against it, its signing key and the stacks on this machine",
    group: "local",
    docs: "/docs/cli/dev",
    effects: [FILES, { kind: "process" }, { kind: "stacks", access: "write" }],
    subcommands: [
      {
        name: "env",
        description:
          "Writes the local stack's URL and keys from `supabase status` to an env file, keeping its other lines",
        docs: "/docs/cli/dev#env",
        effects: [FILES],
        examples: [
          {
            command:
              "better-supabase dev env --write .env.supabase.local --prefix next",
            description:
              "Write the URL, keys and JWKS URL, plain and with NEXT_PUBLIC_",
          },
        ],
      },
      {
        name: "run",
        description:
          "Runs the command after -- with the local stack's URL and keys set, overriding the shell and .env files",
        docs: "/docs/cli/dev#run",
        effects: [{ kind: "process" }],
        examples: [
          {
            command: "better-supabase dev run -- next dev",
            description: "Start Next.js against this worktree's stack",
          },
        ],
      },
      {
        name: "keys",
        description:
          "Creates an ES256 signing key for the local stack, so local tokens verify through JWKS like hosted ones",
        docs: "/docs/cli/dev#keys",
        effects: [FILES],
      },
      {
        name: "stack",
        description:
          "Lists the Supabase CLI's managed stacks and prunes the ones whose worktree or branch is gone",
        docs: "/docs/cli/dev#stack",
        effects: [{ kind: "stacks", access: "write" }],
        subcommands: [
          {
            name: "ls",
            description:
              "Lists every managed stack with its branch, worktree, running state and shared memory segments",
            docs: "/docs/cli/dev#ls",
            effects: [{ kind: "stacks", access: "read" }],
          },
          {
            name: "prune",
            description:
              "Destroys stacks whose worktree or branch is gone; --stop-idle also stops other branches' running stacks",
            docs: "/docs/cli/dev#prune",
            examples: [
              {
                command:
                  "better-supabase dev stack prune --stop-idle --dry-run",
                description: "Print what it would destroy and stop",
              },
            ],
            effects: [{ kind: "stacks", access: "write" }],
          },
        ],
      },
    ],
  },
  {
    name: "db",
    description:
      "Runs SQL files and seeds against the database, backfills columns, prunes ended workflow runs, and diffs the declarative schema: the local stack by default, or the one in the connection string",
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
      {
        name: "diff",
        description:
          "Turns the declarative schema into a migration, diffing inside the running stack when the shadow database can't start",
        docs: "/docs/cli/db#diff",
        examples: [
          {
            command: "better-supabase db diff -f add_invoices",
            description:
              "Save the diff as a migration, falling back to the running stack",
          },
          {
            command: "better-supabase db diff --in-stack",
            description: "Print the diff without starting a shadow database",
          },
        ],
        effects: [
          { kind: "database", access: "write" },
          { kind: "files", when: "--file" },
        ],
      },
      {
        name: "seed",
        description:
          "Renders the fixtures from defineSeed() (better-supabase/testing) to SQL, and runs them with --apply",
        docs: "/docs/cli/db#seed",
        effects: [
          FILES,
          { kind: "database", access: "write", when: "--apply" },
          { kind: "database", access: "write", when: "--tenant" },
        ],
      },
      {
        name: "backfill",
        description:
          "Fills the null values of a column in batches, from the table a foreign key references or from a literal",
        docs: "/docs/cli/db#backfill",
        examples: [
          {
            command:
              "better-supabase db backfill invoices.organization_id --from projects.organization_id via project_id",
            description:
              "Copies each invoice's organization from its project, where it is still null",
          },
          {
            command:
              "better-supabase db backfill invoices.currency --value \"'EUR'\" --dry-run",
            description: "Counts the rows it would set to EUR",
          },
        ],
        effects: [{ kind: "database", access: "write" }],
      },
      {
        name: "prune-workflows",
        description:
          "Deletes ended Workflow SDK runs, with their events, steps, streams and hooks, in batches",
        docs: "/docs/cli/db#prune-workflows",
        examples: [
          {
            command: "better-supabase db prune-workflows --older-than 30d",
            description:
              "Deletes completed, failed and cancelled runs older than 30 days",
          },
          {
            command:
              "better-supabase db prune-workflows --older-than 7d --status failed --dry-run",
            description: "Counts the failed runs it would delete",
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
      { kind: "database", access: "write", when: "--fix" },
      MANAGEMENT_API,
      { kind: "network", target: "github" },
    ],
  },
  {
    name: "config",
    description:
      "Prints the resolved config: the file it came from, the active environment and every option with its default, or the preset it names with --preset",
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
          "Adds gen, upgrade, add and remove, each behind a consent token",
      },
    ],
    effects: [READS_DATABASE, { kind: "files", when: "--allow-writes" }],
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
      {
        name: "0.11",
        description:
          "Changes from 0.10 to 0.11: adopted outgoing webhooks get an explicit defaultFormat",
        docs: "/docs/cli/codemod",
        effects: [FILES],
      },
      {
        name: "0.15",
        description:
          "Changes from 0.14 to 0.15: the runtime instance bs becomes bsb, exports take their block, record and provider names, the config regroups, renamed blocks take their 0.15 names, and CLI calls use the new commands",
        docs: "/docs/cli/codemod",
        effects: [FILES],
      },
      {
        name: "0.29",
        description:
          "Changes from 0.28 to 0.29: records is renamed back to subjects in the config, and record tags in the schema files become subject tags",
        docs: "/docs/cli/codemod",
        effects: [FILES],
      },
      {
        name: "0.32",
        description:
          "Changes from 0.31 to 0.32: tenant is the public word again (auth.tenant, requireTenant), and sign-in, session, proxy and cache names follow supabase-js",
        docs: "/docs/cli/codemod",
        effects: [FILES],
      },
      {
        name: "0.35",
        description:
          "The 0.36 part of the 0.35 to 0.37 changes, as 0.36.0 shipped it: the proxy refreshes on every request, session cookies go through @supabase/ssr, and the cookie codec and prefetch predicates are gone. Prefer codemod 0.37",
        docs: "/docs/cli/codemod",
        effects: [FILES],
      },
      {
        name: "0.37",
        description:
          "Changes from 0.35 to 0.37: the proxy refreshes on every request, session cookies go through @supabase/ssr, the cookie codec and prefetch predicates are gone, and stock quantities are numeric",
        docs: "/docs/cli/codemod",
        effects: [FILES],
      },
      {
        name: "0.46",
        description:
          "Changes from 0.45 to 0.46: permission keys use the block name as their area and the read, write and manage verbs",
        docs: "/docs/cli/codemod",
        effects: [FILES],
      },
      {
        name: "0.47",
        description:
          "Changes from 0.46 to 0.47: entity keys equal the entity's singular, hint codes start with the entity's new name, the work_item, engagement and policy subject types become task, activity and compliance_policy, event types are named <entity>.<past verb>, and saved events split into created and updated",
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

/**
 * The meta a built-in command's `defineCliCommand` takes, read from the
 * manifest.
 */
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
