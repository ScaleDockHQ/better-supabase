import { readdir, readFile, stat } from "node:fs/promises";
import { extname, join, relative, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import { CLI_CALL_FILE, SHELL_FILE } from "../codemod-calls.ts";
import { applyCodemod, CODEMODS, CONFIG_FILE } from "../codemod.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import {
  applyPlan,
  changedFiles,
  changeLines,
  type FilePlan,
  type PlannedFile,
  planResult,
} from "../core/files.ts";
import { commandMeta } from "../core/manifest.ts";
import { type Paint, plain } from "../style.ts";

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
export type CodemodArgs = CliOptions<typeof CODEMOD_ARGS>;

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

/**
 * Source, config and script files under `path`, skipping dependencies, build
 * output and `.d.ts` files.
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
      CONFIG_FILE.test(entry.name) ||
      CLI_CALL_FILE.test(full) ||
      SHELL_FILE.test(entry.name)
    ) {
      files.push(full);
    }
  }

  return files.sort();
}

export async function runCodemod(
  config: ResolvedConfig,
  args: CodemodArgs,
  paint: Paint = plain,
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
    ...new Set((await Promise.all(roots.map(sourceFiles))).flat()),
  ];

  const dryRun = args["dry-run"] === true;
  const edits: PlannedFile[] = [];
  const review: { file: string; line: number; message: string }[] = [];

  for (const file of files) {
    const source = await readFile(file, "utf-8");
    const result = applyCodemod(codemod, source, file);
    const path = relative(config.root, file);
    review.push(...result.review.map((hint) => ({ file: path, ...hint })));

    if (result.text !== source) {
      edits.push({ path: file, contents: result.text, policy: "edit" });
    }
  }

  const plan: FilePlan = {
    root: config.root,
    regenerate: `better-supabase codemod ${codemod.name}`,
    files: edits,
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
    run: (args, { config, paint }) =>
      runCodemod(config, { ...args, _: [name, ...args._] }, paint),
  });
}
