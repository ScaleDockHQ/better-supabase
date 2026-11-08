import {
  cp,
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  symlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = fileURLToPath(new URL("..", import.meta.url));

export type Workflow = "migra" | "migrations" | "pg-delta";

/**
 * The newest migration of the app: stamped far ahead so a new one must follow
 * it.
 */
export const APP_MIGRATION = "20991231235959_app.sql";

const CONFIG_TOML: Readonly<Record<Workflow, string>> = {
  "pg-delta":
    '[api]\nenabled = true\n\n[experimental.pgdelta]\nenabled = true\ndeclarative_schema_path = "./schemas"\n',
  migra:
    '[api]\nenabled = true\n\n[experimental.pgdelta]\nenabled = false\n\n[db.migrations]\nschema_paths = ["./schemas/*.sql"]\n',
  migrations: "[api]\nenabled = true\n",
};

export interface ProjectOptions {
  /** Extra blocks in the config, as `name: {}` entries. */
  readonly blocks?: readonly string[];
  /** `[db] driver`, for a Supabase Lite project. */
  readonly lite?: string;
}

/** The config text: the three blocks the app adopts and the workflow. */
export const configText = (
  workflow: Workflow,
  options: ProjectOptions = {},
): string =>
  `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  database: { sql: { workflow: "${workflow}" } },
  blocks: {
    organizations: { tables: { organizations: "public.organizations" } },
    memberships: {
      tables: { memberships: "public.memberships" },
      columns: { memberships: { tenant: "organization_id" } },
    },
    profiles: {
      tables: { profiles: "public.profiles" },
      columns: { profiles: { key: "user_id" } },
    },
${(options.blocks ?? []).map((name) => `    ${name}: {},`).join("\n")}
  },
});
`;

/**
 * An app that owns its tables the way the workflow keeps them: in a migration
 * for `migra` and `migrations`, in `supabase/schemas` for `pg-delta`. The
 * project's node_modules is linked so the config resolves
 * `better-supabase/config`.
 */
export const project = async (
  workflow: Workflow,
  options: ProjectOptions = {},
): Promise<string> => {
  const dir = await mkdtemp(
    join(tmpdir(), `validation-migrations-${workflow}-`),
  );

  const supabase = join(dir, "supabase");

  await mkdir(supabase, { recursive: true });

  await writeFile(
    join(supabase, "config.toml"),
    `project_id = "validation-migrations"\n\n${options.lite === undefined ? "" : `[db]\ndriver = "${options.lite}"\n\n`}${CONFIG_TOML[workflow]}`,
  );

  if (workflow === "pg-delta") {
    await mkdir(join(supabase, "schemas"));
    await cp(join(ROOT, "app/app.sql"), join(supabase, "schemas/010_app.sql"));
  } else {
    await mkdir(join(supabase, "migrations"));
    await cp(
      join(ROOT, "app/app.sql"),
      join(supabase, "migrations", APP_MIGRATION),
    );
  }

  await cp(join(ROOT, "app/snapshot.json"), join(dir, "snapshot.json"));
  await writeFile(
    join(dir, "package.json"),
    '{ "name": "app", "type": "module" }\n',
  );
  await writeFile(
    join(dir, "better-supabase.config.ts"),
    configText(workflow, options),
  );
  await symlink(join(ROOT, "node_modules"), join(dir, "node_modules"), "dir");

  return dir;
};

/** Every file under `dir/supabase`, by relative path. */
export const readTree = async (
  dir: string,
): Promise<ReadonlyMap<string, string>> => {
  const base = join(dir, "supabase");
  const files = new Map<string, string>();

  for (const entry of await readdir(base, {
    recursive: true,
    withFileTypes: true,
  })) {
    if (entry.isFile()) {
      const path = join(entry.parentPath, entry.name);

      files.set(relative(dir, path), await readFile(path, "utf-8"));
    }
  }

  return files;
};

/** The migrations under `dir`, oldest first. */
export const migrationsOf = async (dir: string): Promise<string[]> =>
  (await readdir(join(dir, "supabase/migrations"))).toSorted();
