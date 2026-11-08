import { spawnSync } from "node:child_process";
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
import { join } from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = fileURLToPath(new URL("..", import.meta.url));

export type PackageManager = "bun" | "npm" | "pnpm" | "yarn";

/** One new app: what its `package.json` and lockfile show to `init`. */
export interface NewApp {
  readonly name: string;
  readonly dependencies: Readonly<Record<string, string>>;
  readonly manager: PackageManager;
}

const LOCKFILES: Readonly<Record<PackageManager, string>> = {
  bun: "bun.lock",
  npm: "package-lock.json",
  pnpm: "pnpm-lock.yaml",
  yarn: "yarn.lock",
};

/** The app a person has before they run `init`: a manifest and a lockfile. */
export const newApp = async (app: NewApp): Promise<string> => {
  const dir = await mkdtemp(join(tmpdir(), `validation-new-app-${app.name}-`));

  await writeFile(
    join(dir, "package.json"),
    `${JSON.stringify({ name: app.name, private: true, type: "module", dependencies: app.dependencies }, null, 2)}\n`,
  );

  await writeFile(join(dir, LOCKFILES[app.manager]), "");

  return dir;
};

/** Every file under `dir` except installed packages, by relative path. */
export const readFiles = async (
  dir: string,
): Promise<ReadonlyMap<string, string>> => {
  const files = new Map<string, string>();

  for (const entry of await readdir(dir, {
    recursive: true,
    withFileTypes: true,
  })) {
    const path = join(entry.parentPath, entry.name);

    if (entry.isFile() && !path.includes("node_modules")) {
      files.set(path.slice(dir.length + 1), await readFile(path, "utf-8"));
    }
  }

  return files;
};

/**
 * What a started stack gives the app: the schema of an empty database as a
 * snapshot, so `gen` runs without one.
 */
export const startStack = async (dir: string): Promise<string> => {
  await mkdir(join(dir, "supabase"), { recursive: true });

  const snapshot = join(dir, "supabase/snapshot.json");

  await cp(join(ROOT, "src/empty-snapshot.json"), snapshot);

  return snapshot;
};

/** Type-checks `files` of the app against the workspace's packages. */
export const typecheck = async (
  dir: string,
  files: readonly string[],
): Promise<void> => {
  // `gen` keeps its cache in node_modules, so link the packages one by one.
  await mkdir(join(dir, "node_modules"), { recursive: true });

  for (const entry of await readdir(join(ROOT, "node_modules"))) {
    if (!entry.startsWith(".")) {
      await symlink(
        join(ROOT, "node_modules", entry),
        join(dir, "node_modules", entry),
      );
    }
  }

  await writeFile(
    join(dir, "tsconfig.check.json"),
    JSON.stringify({
      extends: join(
        ROOT,
        "node_modules/@better-supabase/typescript-config/base.json",
      ),
      compilerOptions: { types: ["node"] },
      files,
    }),
  );

  const result = spawnSync(
    join(ROOT, "node_modules/.bin/tsc"),
    ["-p", "tsconfig.check.json"],
    { cwd: dir, encoding: "utf-8" },
  );

  if (result.status !== 0) {
    throw new Error(`tsc failed:\n${result.stdout}${result.stderr}`);
  }
};
