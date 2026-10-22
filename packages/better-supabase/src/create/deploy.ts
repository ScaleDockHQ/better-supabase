import type { Preset } from "../preset/index.ts";
import type {
  SupabaseLint,
  SupabaseOrganization,
  SupabaseProject,
} from "./supabase/management.ts";
import type { PresetMigrationFile } from "./types.ts";

/** The name the deploy gives its migration in `supabase_migrations`. */
export const MIGRATION_NAME = "better_supabase_blocks";

/**
 * Why this preset can't be deployed, or `undefined` when it can. With `access:
 * "provider"` the preview renders a stand-in provider whose functions no real
 * project has.
 */
export function deployBlocker(preset: Preset): string | undefined {
  return preset.access === "provider"
    ? "Bring your own authorization provider: its SQL comes from the provider, so deploy it with the CLI."
    : undefined;
}

/** A new deploy id: a random UUID. */
export function newDeployId(): string {
  return crypto.randomUUID();
}

/**
 * What a host app stores for one deploy, so it can show the project's preset
 * later and match the project to the record by the `id` comment at the top of
 * the migration.
 */
export interface DeployRecord {
  readonly id: string;
  readonly ref: string;
  /** The preset code. */
  readonly preset: string;
  /** The design code, or `null` when the preset had no design. */
  readonly design: string | null;
  readonly migration: string;
  /** An ISO 8601 instant, such as `Temporal.Now.instant().toString()`. */
  readonly deployedAt: string;
}

export interface DeployQueryOptions {
  /** Written as `-- better-supabase deploy <id>` on the first line. */
  readonly id?: string | undefined;
}

const DEPLOY_ID = /^[\w-]{1,64}$/u;

/**
 * The SQL of one migration for the rendered files: every schema file, then
 * every data file, each in render order, which is the order `upgrade` and `add
 * --adopt` apply them. pgTAP tests stay out. Throws a `TypeError` when `id`
 * holds anything but letters, digits, `_` and `-`.
 */
export function deployQuery(
  files: readonly PresetMigrationFile[],
  options: DeployQueryOptions = {},
): string {
  const { id } = options;

  if (id !== undefined && !DEPLOY_ID.test(id)) {
    throw new TypeError(
      "A deploy id holds 1 to 64 letters, digits, '_' or '-'.",
    );
  }

  const schema = files.filter((file) => file.path.includes("/schemas/"));

  const data = files.filter((file) =>
    file.path.includes("/better-supabase-data/"),
  );

  const body = [...schema, ...data]
    .map((file) => `-- ${file.path}\n${file.contents.trim()}\n`)
    .join("\n");

  return id === undefined ? body : `-- better-supabase deploy ${id}\n\n${body}`;
}

/** A database password for a new project: 32 base64url characters. */
export function generatePassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCodePoint(byte);
  }

  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/[=]+$/u, "");
}

/** The project name the dialog suggests: the preset's name, or `my-app`. */
export function suggestedProjectName(named: string | undefined): string {
  return named === undefined ? "my-app" : `my-${named}-app`;
}

const DASHBOARD = "https://supabase.com/dashboard";

export function dashboardUrl(ref: string, page = ""): string {
  return `${DASHBOARD}/project/${encodeURIComponent(ref)}${page}`;
}

/** `GET /create/supabase/projects`. */
export interface ProjectsResponse {
  readonly organizations: readonly SupabaseOrganization[];
  readonly projects: readonly SupabaseProject[];
}

/** `POST /create/supabase/projects`: the new project and its one-time password. */
export interface CreatedProjectResponse {
  readonly project: SupabaseProject;
  readonly dbPassword: string;
}

/** `GET /create/supabase/projects/<ref>`. */
export interface ProjectStatusResponse {
  readonly project: SupabaseProject;
  readonly ready: boolean;
  /** Tables already in `public`, or `null` while the database is starting. */
  readonly publicTables: number | null;
}

/** `POST /create/supabase/deploy`. */
export interface DeployResponse {
  /** The id written at the top of the migration; store it in a `DeployRecord`. */
  readonly id: string;
  readonly ref: string;
  /** The preset code. */
  readonly preset: string;
  /** The design code, or `null` when the preset had no design. */
  readonly design: string | null;
  readonly migration: string;
  readonly lints: readonly SupabaseLint[];
}

/** Every error body: `connect` means the Supabase session is missing or expired. */
export interface ErrorResponse {
  readonly error: "connect" | "confirm" | "blocked" | "invalid" | "supabase";
  readonly message: string;
}
