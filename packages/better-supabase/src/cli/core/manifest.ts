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
      "Adds blocks with what they require, or glue for an integration with --framework",
    group: "setup",
    docs: "/docs/cli/init#add",
    examples: [
      {
        command: "better-supabase add organizations billing",
        description: "Installs two blocks and the modules they require",
      },
      {
        command: "better-supabase add --framework hono",
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
  },
  {
    name: "blocks",
    description: "Lists, shows and searches the blocks you can add",
    group: "setup",
    docs: "/docs/cli/presets#blocks",
    effects: [],
  },
  {
    name: "skills",
    description:
      "Installs the Agent Skills that ship with this version of better-supabase",
    group: "setup",
    docs: "/docs/for-ai-agents",
    effects: [FILES],
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
  },
  {
    name: "openapi",
    description:
      "Writes the document your createOpenApi() module exports, so CI can check it for drift",
    group: "generate",
    docs: "/docs/cli/local#openapi-emit",
    effects: [FILES],
  },
  {
    name: "scaffold",
    description:
      "Writes an API module, its resource routes and an OpenAPI route for Hono or Next.js",
    group: "generate",
    docs: "/docs/cli/scaffold",
    effects: [FILES],
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
    name: "doctor",
    description:
      "Checks RLS, indexes, drift, auth config and env files; exits 1 on errors, or on warnings with --strict",
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
    name: "sql",
    description:
      "Low-level SQL module commands: lists, adds, syncs, upgrades and prints module files without touching app code, and writes their data migration",
    group: "maintain",
    docs: "/docs/blocks/sql",
    effects: [FILES],
  },
  {
    name: "codemod",
    description:
      "Rewrites imports, calls and config keys for renamed better-supabase APIs",
    group: "maintain",
    docs: "/docs/cli/codemod",
    effects: [FILES],
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
