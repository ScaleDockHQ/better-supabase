import type { GEN_TASKS, INTEGRATION_NAMES, SKILLS_AGENTS } from "../names.ts";

export interface OpenApiConfig {
  /**
   * Module exporting the document (or a function returning it) as `openapi` or
   * default.
   */
  readonly entry?: string;
  /** JSON file `better-supabase spec emit openapi` writes. */
  readonly output?: string;
}

/** A docs UI `spec emit --ui` writes next to an OpenAPI document. */
export type SpecUiName =
  | "scalar"
  | "swagger"
  | "redoc"
  | "elements"
  | "rapidoc";

/** One document `better-supabase spec emit` writes. */
export interface SpecOutputConfig {
  /** A format id: `openapi`, `asyncapi` or `arazzo`. */
  readonly format: string;
  /** Defaults to the format's default version, e.g. `3.1` for OpenAPI. */
  readonly version?: string;
  /** File to write, relative to the root. Defaults to the format's file name. */
  readonly output?: string;
  /** Overlay files (JSON or YAML), applied in order. */
  readonly overlays?: readonly string[];
  /**
   * Defaults to `yaml` when `output` ends in `.yaml` or `.yml`, otherwise
   * `json`.
   */
  readonly serialize?: "json" | "yaml";
  /**
   * Also writes a reference page (`openapi.html` for `openapi.json`) next to
   * OpenAPI outputs.
   */
  readonly ui?: SpecUiName;
}

export interface SpecsConfig {
  /**
   * Module exporting a `defineApi()` result (or a function returning one) as
   * `api` or default.
   */
  readonly entry?: string;
  /** The documents to write. Defaults to one OpenAPI document. */
  readonly outputs?: readonly SpecOutputConfig[];
  /**
   * The lowest severity that fails `spec emit`, `check` and `validate`.
   * Defaults to `error`.
   */
  readonly failOn?: "error" | "warning" | "never";
  /**
   * Also write the diagnostics manifest (JSON) to this file, like `spec
   * --manifest`.
   */
  readonly manifest?: string;
}

/** A step `better-supabase gen` runs. */
export type GenTask = (typeof GEN_TASKS)[number];

export interface GenConfig {
  /**
   * The steps `better-supabase gen` runs, in this order: `types` (the generated
   * modules and `generators`), `sql` (`upgrade`), `spec` (`spec emit`), `seed`
   * and `env`. Without a list, `types` runs, plus `sql` when `blocks` or
   * `realtime.policies` is set, and `spec` and `seed` when their entry file
   * exists. `env` runs only when listed, because it needs the local stack. A
   * listed step always runs.
   */
  readonly tasks?: readonly GenTask[];
  /** Milliseconds between checks in `gen --watch` and `spec emit --watch`. */
  readonly watchInterval?: number;
  /**
   * Serves the schema types through the TypeScript 7.1 content mapper instead
   * of writing them. `gen` then writes a slim `generated.ts` with the runtime
   * values and a `schema.bsb` next to it, and no `database.types.ts`. The app
   * still imports from `./generated`. Needs a `contentMappers` entry in
   * `tsconfig.json` and `tsc --runExternalCode`. Defaults to `false`.
   */
  readonly contentMapper?: boolean;
  /**
   * Writes PowerSync sync streams for these block instances:
   * `sync-streams.yaml` and `schema.ts` in `out`, and a migration that adds
   * their tables to the `powersync` publication. Runs as the `powersync` task,
   * and as `better-supabase powersync streams`.
   */
  readonly powersync?: PowerSyncGenConfig;
}

export interface PowerSyncGenConfig {
  /**
   * The block instances to sync, by their key in `blocks`: instances of
   * `notifications` and `attachments`.
   */
  readonly instances: readonly string[];
  /**
   * The folder for `sync-streams.yaml` and `schema.ts`. Defaults to
   * `powersync`.
   */
  readonly out?: string;
  /**
   * The module `schema.ts` imports `column` and `Table` from. Defaults to
   * `@powersync/common`.
   */
  readonly import?: string;
}

/** Glue `better-supabase init` and `add` write for a framework or runtime. */
export type IntegrationName = (typeof INTEGRATION_NAMES)[number];

export interface EnvFileConfig {
  /** Env file `better-supabase dev env` writes. Defaults to `.env.local`. */
  readonly output?: string;
  /**
   * Prefix for the browser variables, such as `NEXT_PUBLIC_`; `'none'` for no
   * prefix. Detected from the framework by default.
   */
  readonly prefix?: string;
}

/** An agent folder `better-supabase skills install` writes to. */
export type SkillsAgent = (typeof SKILLS_AGENTS)[number];

export interface SkillsConfig {
  /** Defaults to the agent folders the project has, else `agents`. */
  readonly agents?: readonly SkillsAgent[];
}

export interface KeysConfig {
  /**
   * Signing key file `better-supabase dev keys` writes. Defaults to
   * `supabase/signing_keys.json`.
   */
  readonly output?: string;
}

export interface DoctorConfig {
  /** Finding codes to skip, e.g. `['BS204']`. */
  readonly ignore?: readonly string[];
  /** Run only these checks, e.g. `['BS100', 'BS304']`. */
  readonly only?: readonly string[];
  /** Treat warnings as errors. */
  readonly strict?: boolean;
  /**
   * Report format: `text` (default), `sarif` (code scanning) or `github`
   * (workflow annotations). `--json` still wins.
   */
  readonly format?: "text" | "sarif" | "github";
  /** Write the report to this file. */
  readonly output?: string;
  /**
   * App source files doctor scans for API use (BS210). Globs relative to the
   * root. Defaults to `['src/**\/*.{ts,tsx}']`, plus
   * `<package>/src/**\/*.{ts,tsx}` for each package when the root is a pnpm,
   * npm, yarn or bun workspace.
   */
  readonly sources?: readonly string[];
  /**
   * A JSON file of accepted findings, `[{ code, target, reason }]`, relative to
   * the root. Doctor leaves out a finding the file lists, fails on an entry no
   * finding matches, and `doctor --update-baseline` rewrites it.
   */
  readonly baseline?: string;
  /**
   * How many policies a security definer helper may appear in before BS206 asks
   * for an inlinable `language sql stable` function. Defaults to 5.
   */
  readonly policyHelperLimit?: number;
  /**
   * The BS405 limit in bytes. When the authorization provider's token hook has
   * a budget, it replaces that budget and the whole token keeps 2048. Otherwise
   * it limits the whole token's claims (default 2048).
   */
  readonly claimsLimit?: number;
  /** Which migrations the lock checks (BS229 to BS235) read. */
  readonly migrationSafety?: MigrationSafetyConfig;
}

export interface MigrationSafetyConfig {
  /**
   * The newest migration that is already applied everywhere, by file name
   * (`20260101000000_init.sql`) or version (`20260101000000`). Offline, doctor
   * checks only the migrations after it; with `--db-url` it checks the ones the
   * database hasn't applied. `init` and `add --adopt` set it to the latest
   * migration.
   */
  readonly since?: string;
}
