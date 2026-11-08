import { readdir, readFile, stat } from "node:fs/promises";
import { extname, join, relative, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { FilePlan, PlannedFile } from "../core/files.ts";
import type { CommandResult } from "../core/io.ts";
import type { Paint } from "../style.ts";

import { applyCodemod, CODEMODS } from "../codemod.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import {
  applyPlan,
  changedFiles,
  changeLines,
  planResult,
} from "../core/files.ts";
import { commandMeta } from "../core/manifest.ts";
import { migrationsDir, writtenByBlocks } from "../sql-layout.ts";
import { migrationFile } from "../sql/migration-names.ts";
import { plain } from "../style.ts";

const CODEMOD_ARGS = {
  path: {
    type: "positional",
    required: false,
    variadic: true,
    description: "Files or directories to rewrite (default: the project)",
  },
  "dry-run": {
    type: "boolean",
    description: "Show the changes without writing them",
  },
  check: {
    type: "boolean",
    description: "Write nothing; exit 1 with a diff when a file would change",
  },
} as const;

/** `_` is the codemod name, then the paths. */
export type CodemodOptions = CliOptions<typeof CODEMOD_ARGS>;

const SOURCE_EXTENSIONS: ReadonlySet<string> = new Set([
  ".ts",
  ".tsx",
  ".mts",
  ".cts",
  ".js",
  ".jsx",
  ".mjs",
  ".cjs",
]);

const SKIPPED_DIRS: ReadonlySet<string> = new Set([
  "node_modules",
  ".git",
  ".next",
  ".turbo",
  ".vercel",
  "dist",
  "build",
  "coverage",
]);

/** `.env*` files and `turbo.json`, where environment variable names live. */
const ENV_FILE = /^(?:\.env(?:\.[\w.-]+)?|turbo\.jsonc?)$/;

/**
 * Source and env files under `path`, skipping dependencies, build output and
 * `.d.ts` files. SQL stays as it is: a rename of installed objects is one new
 * migration.
 */
async function sourceFiles(path: string): Promise<string[]> {
  const info = await stat(path).catch(() => undefined);

  if (!info) {
    return [];
  }

  if (info.isFile()) {
    return [path];
  }

  const files: string[] = [];

  for (const entry of await readdir(path, { withFileTypes: true })) {
    const full = join(path, entry.name);

    if (entry.isDirectory()) {
      if (!SKIPPED_DIRS.has(entry.name)) {
        files.push(...(await sourceFiles(full)));
      }
    } else if (
      (SOURCE_EXTENSIONS.has(extname(entry.name)) &&
        !entry.name.endsWith(".d.ts")) ||
      ENV_FILE.test(entry.name)
    ) {
      files.push(full);
    }
  }

  return files.toSorted();
}

/**
 * The text of the project's `.sql` files under `supabase/`, joined. Files the
 * blocks wrote (`@bsb-block` modules, data and tests) stay out: `upgrade`
 * rewrites them, so a codemod neither reads their names nor edits them.
 */
async function projectSqlFiles(
  root: string,
): Promise<{ path: string; text: string }[]> {
  const base = resolve(root, "supabase");

  const entries = await readdir(base, {
    recursive: true,
    withFileTypes: true,
  }).catch(() => []);

  const sources = await Promise.all(
    entries
      .filter((entry) => entry.isFile() && entry.name.endsWith(".sql"))
      .map(async (entry) => {
        const path = join(entry.parentPath, entry.name);

        return { path, text: await readFile(path, "utf-8") };
      }),
  );

  return sources.filter((source) => !writtenByBlocks(source));
}

async function projectSql(root: string): Promise<string> {
  return (await projectSqlFiles(root)).map((source) => source.text).join("\n");
}

export async function runCodemod(
  config: ResolvedConfig,
  args: CodemodOptions,
  paint: Paint = plain,
  configFile?: string,
): Promise<CommandResult> {
  const [name, ...paths] = args._ ?? [];

  const names = Object.entries(CODEMODS)
    .map(([key, codemod]) => `  ${key.padEnd(5)} ${codemod.description}`)
    .join("\n");

  if (name === undefined) {
    throw new CliError("usage", `Name a codemod:\n${names}`);
  }

  const codemod = CODEMODS[name];

  if (!codemod) {
    throw new CliError(
      "usage",
      `Unknown codemod "${name}". Codemods:\n${names}`,
    );
  }

  const roots = (paths.length > 0 ? paths : ["."]).map((path) =>
    resolve(config.root, path),
  );

  const files = [
    ...new Set(
      (await Promise.all(roots.map((root) => sourceFiles(root)))).flat(),
    ),
  ];

  const dryRun = args["dry-run"] === true;
  const edits: PlannedFile[] = [];
  const review: { file: string; line: number; message: string }[] = [];

  const projectInput = {
    config,
    sql: await projectSqlFiles(config.root),
    ...(configFile === undefined
      ? {}
      : { configFile, configText: await readFile(configFile, "utf-8") }),
  };

  const rewrite = await codemod.files?.(projectInput);

  for (const file of files) {
    const source = await readFile(file, "utf-8");
    const result = applyCodemod(codemod, source, rewrite, file);
    const path = relative(config.root, file);
    review.push(...result.review.map((hint) => ({ file: path, ...hint })));

    if (result.text !== source) {
      edits.push({ path: file, contents: result.text, policy: "edit" });
    }
  }

  if (codemod.project !== undefined) {
    const project = await codemod.project(projectInput);

    for (const file of project.files) {
      const at = edits.findIndex((edit) => edit.path === file.path);

      if (at === -1) {
        edits.push(file);
      } else {
        edits[at] = file;
      }
    }

    review.push(
      ...project.review.map((hint) => ({
        file: configFile === undefined ? "" : relative(config.root, configFile),
        line: 1,
        ...hint,
      })),
    );
  }

  const sql = codemod.migration?.(await projectSql(config.root));

  if (sql !== undefined) {
    const dir = migrationsDir(config);

    const existing: string[] = await readdir(resolve(config.root, dir)).catch(
      () => [],
    );

    edits.push({
      path: resolve(
        config.root,
        dir,
        migrationFile(
          existing,
          new Date(),
          `_better_supabase_${codemod.name}.sql`,
          sql,
        ).name,
      ),
      contents: sql,
      policy: "create",
    });
  }

  // `upgrade` owns the block files, so no codemod rewrites them, whatever path
  // a rewrite or an argument names.
  const planned: PlannedFile[] = [];

  for (const edit of edits) {
    const current = await readFile(edit.path, "utf-8").catch(() => undefined);

    if (
      current !== undefined &&
      edit.path.endsWith(".sql") &&
      writtenByBlocks({ path: edit.path, text: current })
    ) {
      review.push({
        file: relative(config.root, edit.path),
        line: 1,
        message:
          "A block file, which `better-supabase upgrade` rewrites. The codemod left it alone.",
      });
    } else {
      planned.push(edit);
    }
  }

  const plan: FilePlan = {
    root: config.root,
    regenerate: `better-supabase codemod ${codemod.name}`,
    files: planned,
  };

  const applied = await applyPlan(plan, args, paint);
  const changed = changedFiles(applied);

  if (applied.mode === "check" && applied.drift) {
    return planResult(plan, applied, { data: { codemod: codemod.name } });
  }

  const lines = [
    ...(applied.mode === "write" ? [] : applied.diffs),
    changed.length === 0
      ? `Nothing to change in ${String(files.length)} files.`
      : [
          ...changeLines(applied),
          `${applied.mode === "write" ? "Updated" : "Would update"} ${String(changed.length)} of ${String(files.length)} files.`,
        ].join("\n"),
  ];

  if (review.length > 0) {
    lines.push(
      "",
      "Check these by hand:",
      ...review.map(
        (hint) => `  ${hint.file}:${String(hint.line)}: ${hint.message}`,
      ),
    );
  }

  return {
    code: 0,
    output: lines.join("\n"),
    data: {
      codemod: codemod.name,
      dryRun,
      changed,
      files: applied.changes,
      review,
    },
  };
}

/** The `codemod <name>` subcommand for one codemod in `CODEMODS`. */
export function codemodCommand(name: string): AnyCommand {
  return defineCliCommand({
    meta: commandMeta(`codemod ${name}`),
    args: CODEMOD_ARGS,
    runsWithInvalidConfig: true,
    run: (args, { config, configFile, paint }) =>
      runCodemod(config, { ...args, _: [name, ...args._] }, paint, configFile),
  });
}
