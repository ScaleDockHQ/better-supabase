import { cp, mkdtemp, readdir, readFile, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = fileURLToPath(new URL("..", import.meta.url));

/** Files the generator writes: module schema files and data files. */
export const isGenerated = (path: string): boolean =>
  /(^|\/)900_better_supabase_[^/]*\.sql$/.test(path);

/**
 * A copy of the fixture in a temp folder, with the project's node_modules
 * linked so the config file resolves `better-supabase/config`.
 */
export const copyFixture = async (): Promise<string> => {
  const dir = await mkdtemp(join(tmpdir(), "validation-declarative-"));

  for (const entry of [
    "better-supabase.config.ts",
    "package.json",
    "snapshot.json",
    "supabase",
  ]) {
    await cp(join(ROOT, entry), join(dir, entry), { recursive: true });
  }

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
