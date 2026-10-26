/**
 * Prepares a new git worktree: installs from the shared pnpm store, copies the
 * main checkout's env files without the keys that point at its Supabase stack
 * or its hosts, and with `--db` starts this worktree's own stack. Cursor runs
 * it from `.cursor/worktrees.json`; run it by hand in any other worktree.
 */
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import process from "node:process";

// Runs before `pnpm install`, so it imports only Node built-ins.

const ENV_FILES = [".env.local", ".env.development.local"];

const STACK_KEY =
  /^(?:export\s+)?(?:(?:NEXT_PUBLIC_)?SUPABASE_\w*|WORKFLOW_POSTGRES_URL|DATABASE_URL|NEXT_PUBLIC_SITE_URL|DOCS_ORIGIN)\s*=/;

/**
 * The env file without the keys that belong to another checkout's stack or
 * hosts.
 */
export const stripStackKeys = (text: string): string =>
  text
    .split("\n")
    .filter((line) => !STACK_KEY.test(line.trimStart()))
    .join("\n");

/** The main checkout: the first entry `git worktree list --porcelain` prints. */
export const mainWorktree = (porcelain: string): string | undefined =>
  porcelain
    .split("\n")
    .find((line) => line.startsWith("worktree "))
    ?.slice("worktree ".length);

const run = (command: string, args: string[]): void => {
  execFileSync(command, args, { stdio: "inherit" });
};

function install(): void {
  try {
    run("pnpm", ["install", "--offline", "--frozen-lockfile"]);
  } catch {
    console.log(
      "The store misses a package; installing with --prefer-offline.",
    );
    run("pnpm", ["install", "--prefer-offline", "--frozen-lockfile"]);
  }
}

async function copyEnvFiles(cwd: string): Promise<void> {
  const root = mainWorktree(
    execFileSync("git", ["worktree", "list", "--porcelain"], {
      encoding: "utf-8",
    }),
  );

  if (root === undefined || resolve(root) === cwd) {
    return;
  }

  for (const file of ENV_FILES) {
    const source = join(root, file);
    const target = join(cwd, file);

    if (!existsSync(source) || existsSync(target)) {
      continue;
    }

    const kept = stripStackKeys(await readFile(source, "utf-8"));

    if (!/^\s*[^#\s]/m.test(kept)) {
      continue;
    }

    await writeFile(target, kept);

    console.log(`Copied ${file} without the main stack's keys`);
  }
}

function startDatabase(cwd: string): void {
  if (!existsSync(join(cwd, "supabase/signing_keys.json"))) {
    run("node", [
      "packages/better-supabase/src/cli/bin.ts",
      "dev",
      "keys",
      "--cwd",
      ".",
    ]);
  }

  run("pnpm", ["supabase:start"]);
}

async function main(): Promise<void> {
  const cwd = process.cwd();

  install();
  await copyEnvFiles(cwd);

  if (process.argv.includes("--db")) {
    startDatabase(cwd);
  } else {
    console.log("Run `node scripts/worktree-setup.ts --db` for a local stack.");
  }
}

if (import.meta.main) {
  await main();
}
