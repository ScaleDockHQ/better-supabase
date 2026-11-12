// Fails when AGENTS.md outgrows its budget, links a file that does not exist,
// or when AGENTS.md or docs/agents/commands.md name a `pnpm <script>` that
// package.json does not define. Run with `node scripts/check-agent-docs.ts`.
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { exit } from "node:process";
import * as v from "valibot";

export const AGENTS_BUDGET_BYTES = 16_000;

/** The script names a document runs as `pnpm <name>`, minus built-in commands. */
export const pnpmScripts = (text: string): string[] => {
  const builtIn = new Set([
    "install",
    "exec",
    "dlx",
    "add",
    "remove",
    "why",
    "view",
    "changeset",
    "run",
    "test",
    "build",
    "dev",
    "audit",
  ]);

  return [
    ...new Set(
      [...text.matchAll(/`pnpm ([a-z][\w:-]*)/g)]
        .map((match) => match[1] ?? "")
        .filter((name) => !builtIn.has(name)),
    ),
  ];
};

/** The repo-relative link targets of a Markdown document, anchors removed. */
export const localLinks = (text: string): string[] =>
  [...text.matchAll(/\]\((?!https?:|#|mailto:)([^)#\s]+)/g)].map(
    (match) => match[1] ?? "",
  );

export function problemsFor(
  files: Record<string, string>,
  scripts: ReadonlySet<string>,
  exists: (path: string) => boolean,
): string[] {
  const problems: string[] = [];
  const agents = files["AGENTS.md"] ?? "";

  if (Buffer.byteLength(agents) > AGENTS_BUDGET_BYTES) {
    problems.push(
      `AGENTS.md is ${Buffer.byteLength(agents)} bytes; the budget is ${AGENTS_BUDGET_BYTES}. Move detail to docs/agents.`,
    );
  }

  for (const [path, text] of Object.entries(files)) {
    for (const link of localLinks(text)) {
      if (!exists(join(dirname(path), link))) {
        problems.push(`${path} links ${link}, which does not exist`);
      }
    }

    for (const name of pnpmScripts(text)) {
      if (!scripts.has(name)) {
        problems.push(
          `${path} names \`pnpm ${name}\`, which package.json lacks`,
        );
      }
    }
  }

  return problems;
}

function main(): void {
  const paths = ["AGENTS.md", "docs/agents/commands.md"];

  const files = Object.fromEntries(
    paths.map((path) => [path, readFileSync(path, "utf-8")]),
  );

  const manifest = v.parse(
    v.looseObject({ scripts: v.record(v.string(), v.string()) }),
    JSON.parse(readFileSync("package.json", "utf-8")),
  );

  const problems = problemsFor(
    files,
    new Set(Object.keys(manifest.scripts)),
    existsSync,
  );

  if (problems.length > 0) {
    console.error(problems.join("\n"));
    exit(1);
  }

  console.log("Agent docs are in budget and name real scripts.");
}

if (import.meta.main) {
  main();
}
