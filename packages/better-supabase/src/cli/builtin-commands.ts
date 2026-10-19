import type { AnyCommand } from "./core/command.ts";

export type Loader = () => Promise<AnyCommand>;

export type CliEntry =
  | {
      readonly load: Loader;
      /** Shown in the root usage without loading the command. */
      readonly description: string;
    }
  | { readonly load: Loader; readonly command: AnyCommand };

const BUILTIN: readonly (readonly [string, CliEntry])[] = [
  [
    "init",
    {
      load: () => import("./commands/init.ts").then((m) => m.initCommand),
      description:
        "Writes better-supabase.config.ts, src/lib/supabase/index.ts and glue for the frameworks in package.json",
    },
  ],
  [
    "add",
    {
      load: () => import("./commands/add.ts").then((m) => m.addCommand),
      description:
        "Adds blocks with what they require, or glue for an integration with --framework",
    },
  ],
  [
    "apply",
    {
      load: () => import("./commands/apply.ts").then((m) => m.applyCommand),
      description:
        "Applies a preset to an existing project: edits the config, shows the diff and writes the blocks' modules",
    },
  ],
  [
    "adopt",
    {
      load: () => import("./commands/adopt.ts").then((m) => m.adoptCommand),
      description:
        "Maps a block onto tables the app already has: proposes blocks.<block> in adopt mode and reports what can't map",
    },
  ],
  [
    "preset",
    {
      load: () => import("./commands/preset.ts").then((m) => m.presetCommand),
      description:
        "Decodes a preset code, or shows the config's preset and how the config differs from it",
    },
  ],
  [
    "blocks",
    {
      load: () => import("./commands/blocks.ts").then((m) => m.blocksCommand),
      description: "Lists, shows and searches the blocks you can add",
    },
  ],
  [
    "env",
    {
      load: () => import("./commands/env.ts").then((m) => m.envCommand),
      description:
        "Writes the local stack's URL and keys from `supabase status` to an env file, keeping its other lines",
    },
  ],
  [
    "keys",
    {
      load: () => import("./commands/keys.ts").then((m) => m.keysCommand),
      description:
        "Creates an ES256 signing key for the local stack, so local tokens verify through JWKS like hosted ones",
    },
  ],
  [
    "skills",
    {
      load: () => import("./commands/skills.ts").then((m) => m.skillsCommand),
      description:
        "Installs the Agent Skills that ship with this version of better-supabase",
    },
  ],
  [
    "gen",
    {
      load: () => import("./commands/gen.ts").then((m) => m.genCommand),
      description:
        "Writes the typed client from the database, then every other generated file the config sets up",
    },
  ],
  [
    "introspect",
    {
      load: () =>
        import("./commands/introspect.ts").then((m) => m.introspectCommand),
      description: "Saves the database schema as a snapshot for offline gen",
    },
  ],
  [
    "openapi",
    {
      load: () => import("./commands/openapi.ts").then((m) => m.openapiCommand),
      description:
        "Writes the document your createOpenApi() module exports, so CI can check it for drift",
    },
  ],
  [
    "spec",
    {
      load: () => import("./commands/spec.ts").then((m) => m.specCommand),
      description:
        "Writes, checks or validates the OpenAPI and other spec documents your defineApi() module renders",
    },
  ],
  [
    "scaffold",
    {
      load: () =>
        import("./commands/scaffold.ts").then((m) => m.scaffoldCommand),
      description:
        "Writes an API module and its routes for Hono or Next.js, or list, create and detail pages for an app table",
    },
  ],
  [
    "seed",
    {
      load: () => import("./commands/seed.ts").then((m) => m.seedCommand),
      description:
        "Renders the fixtures from defineSeed() (better-supabase/testing) to SQL",
    },
  ],
  [
    "doctor",
    {
      load: () => import("./commands/doctor.ts").then((m) => m.doctorCommand),
      description:
        "Checks RLS, indexes, drift, auth config and env files; exits 1 on errors, or on warnings with --strict",
    },
  ],
  [
    "sql",
    {
      load: () => import("./commands/sql.ts").then((m) => m.sqlCommand),
      description:
        "Low-level SQL module commands: lists, adds, syncs, upgrades and prints module files",
    },
  ],
  [
    "config",
    {
      load: () => import("./commands/config.ts").then((m) => m.configCommand),
      description:
        "Prints the resolved config: the file it came from, the active environment and every option with its default",
    },
  ],
  [
    "codemod",
    {
      load: () => import("./commands/codemod.ts").then((m) => m.codemodCommand),
      description:
        "Rewrites imports, calls and config keys for renamed better-supabase APIs",
    },
  ],
];

/** A fresh registry of the built-in commands, for `createCli`. */
export function builtinCommands(): Map<string, CliEntry> {
  return new Map(BUILTIN);
}
