import { readdir, readFile, stat } from "node:fs/promises";
import { extname, join, relative, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../command.ts";
import type { CommandResult } from "../io.ts";

import { applyCodemod, CODEMODS } from "../codemod.ts";
import { defineCliCommand } from "../command.ts";
import { fileDiff } from "../diff.ts";
import { writeIfChanged } from "../io.ts";
import { type Paint, painter, plain } from "../style.ts";

const CODEMOD_ARGS = {
  name: {
    type: "positional",
    required: false,
    description:
      "The codemod (0.4, 0.5 or 0.6), then the files or directories to rewrite (default: the project)",
  },
  "dry-run": {
    type: "boolean",
    description: "Show the changes without writing them",
  },
} as const;

export type CodemodArgs = CliArgs<typeof CODEMOD_ARGS>;

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

/** Source files under `path`, skipping dependencies, build output and `.d.ts` files. */
async function sourceFiles(path: string): Promise<string[]> {
  const info = await stat(path).catch(() => undefined);
  if (!info) return [];
  if (info.isFile()) return [path];
  const files: string[] = [];
  for (const entry of await readdir(path, { withFileTypes: true })) {
    const full = join(path, entry.name);
    if (entry.isDirectory()) {
      if (!SKIPPED_DIRS.has(entry.name))
        files.push(...(await sourceFiles(full)));
    } else if (
      SOURCE_EXTENSIONS.has(extname(entry.name)) &&
      !entry.name.endsWith(".d.ts")
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
  const [name, ...paths] = args._;
  const names = Object.entries(CODEMODS)
    .map(([key, codemod]) => `  ${key.padEnd(5)} ${codemod.description}`)
    .join("\n");
  if (name === undefined) {
    return { code: 2, error: `Name a codemod:\n${names}` };
  }
  const codemod = CODEMODS[name];
  if (!codemod) {
    return { code: 2, error: `Unknown codemod "${name}". Codemods:\n${names}` };
  }
  const roots = (paths.length > 0 ? paths : ["."]).map((path) =>
    resolve(config.root, path),
  );
  const files = [
    ...new Set((await Promise.all(roots.map(sourceFiles))).flat()),
  ];
  const dryRun = args["dry-run"] === true;
  const changed: string[] = [];
  const diffs: string[] = [];
  const review: { file: string; line: number; message: string }[] = [];
  for (const file of files) {
    const source = await readFile(file, "utf8");
    const result = applyCodemod(codemod, source);
    const path = relative(config.root, file);
    review.push(...result.review.map((hint) => ({ file: path, ...hint })));
    if (result.text === source) continue;
    changed.push(path);
    if (dryRun) diffs.push(fileDiff(path, source, result.text, paint));
    else await writeIfChanged(file, result.text);
  }
  const lines = [
    ...diffs,
    changed.length === 0
      ? `Nothing to change in ${String(files.length)} files.`
      : `${dryRun ? "Would update" : "Updated"} ${String(changed.length)} of ${String(files.length)} files:\n${changed.map((path) => `  ${path}`).join("\n")}`,
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
    data: { codemod: codemod.name, dryRun, changed, review },
  };
}

export const codemodCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "codemod",
    description: "Rewrites imports and calls for renamed better-supabase APIs",
  },
  args: CODEMOD_ARGS,
  run: (args, { config, io }) => runCodemod(config, args, painter(io.color)),
});
