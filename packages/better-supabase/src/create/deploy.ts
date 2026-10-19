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
 * Why this preset can't be deployed, or `undefined` when it can. With
 * `access: "provider"` the preview renders a stand-in provider whose
 * functions no real project has.
 */
export function deployBlocker(preset: Preset): string | undefined {
  return preset.access === "provider"
    ? "Bring your own authorization provider: its SQL comes from the provider, so deploy it with the CLI."
    : undefined;
}

/**
 * The SQL of one migration for the rendered files: every schema file, then
 * every data file, each in render order, which is the order `sql sync` and
 * `sql data` apply them. pgTAP tests stay out.
 */
export function deployQuery(files: readonly PresetMigrationFile[]): string {
  const schema = files.filter((file) => file.path.includes("/schemas/"));

  const data = files.filter((file) =>
    file.path.includes("/better-supabase-data/"),
  );

  return [...schema, ...data]
    .map((file) => `-- ${file.path}\n${file.contents.trim()}\n`)
    .join("\n");
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
    .replace(/=+$/u, "");
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
  readonly ref: string;
  readonly migration: string;
  readonly lints: readonly SupabaseLint[];
}

/** Every error body: `connect` means the Supabase session is missing or expired. */
export interface ErrorResponse {
  readonly error: "connect" | "confirm" | "blocked" | "invalid" | "supabase";
  readonly message: string;
}
