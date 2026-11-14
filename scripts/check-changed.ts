// Narrow check for the files you changed: format, lint, typecheck and the tests that cover them.
// `pnpm verify` runs everything in CI; this finishes in seconds on a leaf file.
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { argv, cwd, exit } from "node:process";

/** `vitest related` is only worth running for a file this few modules import. */
export const RELATED_IMPORTER_CAP = 3;

const SOURCE = /\.(?:ts|tsx|mts|cts|js|jsx|mjs|cjs)$/;

const FORMATTED =
  /\.(?:ts|tsx|mts|cts|js|jsx|mjs|cjs|json|jsonc|md|mdx|css|yml|yaml)$/;

const GENERATED =
  /(?:\.generated\.|\/generated\.|database\.types\.ts$|snapshot\.json$)/;

const repoRoot = (() => {
  let dir = cwd();

  while (!existsSync(join(dir, "pnpm-workspace.yaml"))) {
    const parent = dirname(dir);

    if (parent === dir) {
      return cwd();
    }

    dir = parent;
  }

  return dir;
})();

const lines = (command: string, args: string[]): string[] => {
  const result = spawnSync(command, args, { cwd: repoRoot, encoding: "utf-8" });

  return result.stdout.split("\n").filter((line) => line.length > 0);
};

/** Files changed against `origin/main`, plus uncommitted and untracked ones. */
export const changedFiles = (): string[] => {
  const base = "origin/main";

  const files = new Set([
    ...lines("git", [
      "diff",
      "--name-only",
      "--diff-filter=d",
      `${base}...HEAD`,
    ]),
    ...lines("git", ["diff", "--name-only", "--diff-filter=d", "HEAD"]),
    ...lines("git", ["ls-files", "--others", "--exclude-standard"]),
  ]);

  return [...files].filter((file) => existsSync(join(repoRoot, file)));
};

/**
 * The nearest folder with a package.json, relative to the repo root ("" for the
 * root).
 */
export const workspaceOf = (file: string): string => {
  let dir = dirname(file);

  while (dir !== "." && dir !== "/") {
    if (existsSync(join(repoRoot, dir, "package.json"))) {
      return dir;
    }

    dir = dirname(dir);
  }

  return "";
};

/** The unit test that mirrors a source path, when it exists. */
export const mirrorTest = (file: string): string | undefined => {
  const match = /^(.*?)\/src\/(.+)\.(?:ts|tsx)$/.exec(file);

  if (match === null) {
    return undefined;
  }

  const candidate = `${match[1]}/tests/${match[2]}.test.ts`;

  return existsSync(join(repoRoot, candidate)) ? candidate : undefined;
};

const directImporters = (workspace: string, file: string): string[] => {
  const name = file
    .slice(file.lastIndexOf("/") + 1)
    .replace(/\.(?:ts|tsx)$/, "");

  return lines("rg", [
    "--files-with-matches",
    "--glob",
    "*.{ts,tsx}",
    `from ["'][^"']*/${name}(?:\\.[jt]sx?)?["']`,
    join(workspace, "src"),
  ]);
};

/**
 * Source files that import `file` directly or through other source files. It
 * stops counting past the cap: a file two hops from `render.ts` has two direct
 * importers, but `vitest related` would run most of the suite for it.
 */
export const importerCount = (workspace: string, file: string): number => {
  const seen = new Set<string>([file]);
  const pending = [file];

  while (pending.length > 0 && seen.size <= RELATED_IMPORTER_CAP + 1) {
    const current = pending.shift();

    if (current === undefined) {
      break;
    }

    for (const importer of directImporters(workspace, current)) {
      if (!seen.has(importer)) {
        seen.add(importer);
        pending.push(importer);
      }
    }
  }

  return seen.size - 1;
};

interface Step {
  readonly name: string;
  readonly command: string;
  readonly args: string[];
  readonly cwd: string;
}

const run = (step: Step): boolean => {
  const started = Date.now();

  const result = spawnSync(step.command, step.args, {
    cwd: step.cwd,
    encoding: "utf-8",
    env: { ...process.env, FORCE_COLOR: "0" },
  });

  const seconds = ((Date.now() - started) / 1000).toFixed(1);

  if (result.status === 0) {
    console.log(`ok   ${step.name} (${seconds} s)`);

    return true;
  }

  console.log(`FAIL ${step.name} (${seconds} s)`);
  console.log(
    (result.stdout + result.stderr).trim().split("\n").slice(-40).join("\n"),
  );

  return false;
};

const hasScript = (workspace: string, script: string): boolean => {
  // SAFETY: the file is a package.json; only `scripts` is read.
  const manifest = JSON.parse(
    readFileSync(join(repoRoot, workspace, "package.json"), "utf-8"),
  ) as { scripts?: Record<string, string> };

  return manifest.scripts?.[script] !== undefined;
};

export const planSteps = (files: string[]): Step[] => {
  const steps: Step[] = [];

  const bin = (name: string): string =>
    join(repoRoot, "node_modules/.bin", name);

  const formatted = files.filter(
    (file) => FORMATTED.test(file) && !GENERATED.test(file),
  );

  if (formatted.length > 0) {
    steps.push({
      name: `format ${formatted.length} files`,
      command: bin("oxfmt"),
      args: ["--check", ...formatted],
      cwd: repoRoot,
    });
  }

  const byWorkspace = new Map<string, string[]>();

  for (const file of files.filter(
    (entry) => SOURCE.test(entry) && !GENERATED.test(entry),
  )) {
    const workspace = workspaceOf(file);
    byWorkspace.set(workspace, [...(byWorkspace.get(workspace) ?? []), file]);
  }

  for (const [workspace, workspaceFiles] of byWorkspace) {
    if (workspace === "") {
      steps.push(
        {
          name: "lint (root)",
          command: bin("oxlint"),
          args: [
            "-c",
            "oxlint.config.ts",
            "--no-error-on-unmatched-pattern",
            ...workspaceFiles,
          ],
          cwd: repoRoot,
        },
        {
          name: "typecheck (root tooling)",
          command: bin("tsc"),
          args: ["--noEmit", "-p", "tsconfig.json"],
          cwd: repoRoot,
        },
      );
      continue;
    }

    const inside = workspaceFiles.map((file) => relative(workspace, file));
    steps.push({
      name: `lint ${workspace}`,
      command: bin("oxlint"),
      args: ["--no-error-on-unmatched-pattern", ...inside],
      cwd: join(repoRoot, workspace),
    });

    if (hasScript(workspace, "typecheck")) {
      steps.push({
        name: `typecheck ${workspace}`,
        command: "pnpm",
        args: ["run", "typecheck"],
        cwd: join(repoRoot, workspace),
      });
    }
  }

  const tests = new Map<string, Set<string>>();

  for (const file of files) {
    const workspace = workspaceOf(file);

    if (workspace === "" || !hasScript(workspace, "test")) {
      continue;
    }

    const set = tests.get(workspace) ?? new Set<string>();

    if (/\.test\.(?:ts|tsx)$/.test(file)) {
      set.add(relative(workspace, file));
    } else if (SOURCE.test(file)) {
      const mirror = mirrorTest(file);

      if (mirror !== undefined) {
        set.add(relative(workspace, mirror));
      }

      if (importerCount(workspace, file) <= RELATED_IMPORTER_CAP) {
        set.add(`related:${relative(workspace, file)}`);
      }
    }

    tests.set(workspace, set);
  }

  for (const [workspace, entries] of tests) {
    const direct = [...entries].filter(
      (entry) => !entry.startsWith("related:"),
    );

    const related = [...entries]
      .filter((entry) => entry.startsWith("related:"))
      .map((entry) => entry.slice("related:".length));

    const root = join(repoRoot, workspace);
    const vitest = join(repoRoot, "node_modules/.bin/vitest");

    // Workspaces without a `unit` project (next-config) run their one config.
    const configPath = join(root, "vitest.config.ts");

    const project =
      existsSync(configPath) &&
      /name:\s*["']unit["']/.test(readFileSync(configPath, "utf-8"))
        ? ["--project", "unit"]
        : [];

    if (direct.length > 0) {
      steps.push({
        name: `test ${workspace} (${direct.length} files)`,
        command: vitest,
        args: ["run", ...project, ...direct],
        cwd: root,
      });
    }

    if (related.length > 0) {
      steps.push({
        name: `test ${workspace} (related to ${related.length} files)`,
        command: vitest,
        args: ["related", "--run", ...project, ...related],
        cwd: root,
      });
    }
  }

  return steps;
};

const main = (): void => {
  const given = argv.slice(2).map((file) => relative(repoRoot, resolve(file)));
  const files = given.length > 0 ? given : changedFiles();

  if (files.length === 0) {
    console.log("No changed files.");

    return;
  }

  const steps = planSteps(files);

  // Apps and tests resolve `better-supabase` through its built `dist`, so a
  // fresh checkout builds it once (a Turbo cache hit afterwards).
  const needsLibrary = steps.some(
    (step) =>
      step.cwd !== repoRoot && !step.cwd.endsWith("packages/better-supabase"),
  );

  if (
    needsLibrary &&
    !existsSync(join(repoRoot, "packages/better-supabase/dist"))
  ) {
    steps.unshift({
      name: "build better-supabase (first run)",
      command: join(repoRoot, "node_modules/.bin/turbo"),
      args: ["run", "build", "--filter=better-supabase"],
      cwd: repoRoot,
    });
  }

  const failed = steps.filter((step) => !run(step));

  if (failed.length > 0) {
    console.log(
      `\n${failed.length} step(s) failed. CI runs the rest (pnpm verify).`,
    );
    exit(1);
  }
};

if (
  process.argv[1] !== undefined &&
  resolve(process.argv[1]) === resolve(import.meta.filename)
) {
  main();
}
