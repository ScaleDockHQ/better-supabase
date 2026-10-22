// Flags the writing patterns .agents/rules/writing.mdc bans in published prose: docs pages,
// READMEs, skills and changesets. Code blocks, inline code, URLs and JSX are
// skipped. Run with `node scripts/check-prose.ts [files...]`.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { argv, cwd, exit } from "node:process";

interface Finding {
  readonly file: string;
  readonly line: number;
  readonly message: string;
}

const roots = [
  "README.md",
  "AGENTS.md",
  ".agents/rules",
  "PRODUCT.md",
  "DESIGN.md",
  "docs",
  "CONTRIBUTING.md",
  "SECURITY.md",
  "SUPPORT.md",
  "packages/better-supabase/README.md",
  "packages/better-supabase/skills",
  "apps/docs/content",
  ".changeset",
];

const bannedWords: readonly (readonly [RegExp, string])[] = [
  [/\bseamless(ly)?\b/iu, "seamless"],
  [/\brobust(ly|ness)?\b/iu, "robust"],
  [/\bpowerful\b/iu, "powerful"],
  [/\bleverag(e|es|ed|ing)\b/iu, "leverage"],
  [/\beffortless(ly)?\b/iu, "effortless"],
  [/\bblazing(ly)? fast\b/iu, "blazing fast"],
  [/\bdelv(e|es|ed|ing)\b/iu, "delve"],
  [/\bsimply\b/iu, "simply"],
];

const checks: readonly (readonly [RegExp, string])[] = [
  [/\u2014/u, "em dash; use a comma, colon or new sentence"],
  [/->|\u2192|\u21D2|=>/u, "arrow chain; write the steps as a sentence"],
  [/(?![\u00A9\u00AE\u2122])\p{Extended_Pictographic}/u, "emoji"],
  [/!(?=\s|$)/u, "exclamation mark"],
  ...bannedWords.map(
    ([pattern, word]) => [pattern, `banned word "${word}"`] as const,
  ),
];

function collect(path: string, into: string[]): void {
  let stats;

  try {
    stats = statSync(path);
  } catch {
    return;
  }

  if (stats.isFile()) {
    if (
      /\.mdx?$|\.mdc$/u.test(path) &&
      !path.endsWith(".changeset/README.md")
    ) {
      into.push(path);
    }

    return;
  }

  for (const entry of readdirSync(path)) {
    if (entry === "node_modules" || entry.startsWith(".source")) {
      continue;
    }

    collect(join(path, entry), into);
  }
}

/** Removes the parts of a line that are code, links or markup. */
function prose(line: string): string {
  return line
    .replaceAll(/`[^`]*`/gu, " ")
    .replaceAll(/<[^>]*>/gu, " ")
    .replaceAll(/\{[^}]*\}/gu, " ")
    .replaceAll(/\]\([^)]*\)/gu, "] ")
    .replaceAll(/https?:\/\/\S+/gu, " ");
}

function check(file: string): Finding[] {
  const findings: Finding[] = [];
  const lines = readFileSync(file, "utf-8").split("\n");
  let fence: string | undefined;
  let jsx = false;

  for (const [index, raw] of lines.entries()) {
    const trimmed = raw.trim();
    const marker = /^(`{3,}|~{3,})/u.exec(trimmed)?.[1];

    if (marker !== undefined) {
      if (fence === undefined) {
        fence = marker;
      } else if (trimmed.startsWith(fence)) {
        fence = undefined;
      }

      continue;
    }

    if (fence !== undefined) {
      continue;
    }

    if (/^(import|export)\s/u.test(trimmed)) {
      continue;
    }

    // Multi-line JSX tags carry props, not prose.
    if (jsx) {
      if (trimmed.endsWith(">")) {
        jsx = false;
      }

      continue;
    }

    if (/^<[A-Za-z][^>]*$/u.test(trimmed)) {
      jsx = true;

      continue;
    }

    const text = prose(raw);

    for (const [pattern, message] of checks) {
      if (pattern.test(text)) {
        findings.push({ file, line: index + 1, message });
      }
    }
  }

  return findings;
}

// Retired names are checked in code too, so they count fenced blocks and
// example sources. The pages that document the rename keep the old name.
const retiredRoots = [
  "apps/docs/content",
  "packages/better-supabase/skills",
  "packages/better-supabase/README.md",
  "apps/examples",
];

const retiredExempt =
  /CHANGELOG\.md$|\/migration\/|concepts\/naming\.mdx$|cli\/codemod\.mdx$|\/src\/lib\/supabase\//u;

const retired: readonly (readonly [RegExp, string])[] = [
  [
    /(?<![\w$.:/-])bs\.(?=[a-z$])|\b(?:const|let|var)\s+bs\b|\{\s*bs\s*[,}]/u,
    "retired instance name `bs`; the runtime instance is `bsb`",
  ],
];

function collectSources(path: string, into: string[]): void {
  let stats;

  try {
    stats = statSync(path);
  } catch {
    return;
  }

  if (stats.isFile()) {
    if (/\.(mdx?|tsx?)$/u.test(path) && !retiredExempt.test(path)) {
      into.push(path);
    }

    return;
  }

  for (const entry of readdirSync(path)) {
    if (entry === "node_modules" || entry.startsWith(".") || entry === "dist") {
      continue;
    }

    collectSources(join(path, entry), into);
  }
}

function checkRetired(file: string): Finding[] {
  return readFileSync(file, "utf-8")
    .split("\n")
    .flatMap((raw, index) =>
      retired
        .filter(([pattern]) => pattern.test(raw))
        .map(([, message]) => ({ file, line: index + 1, message })),
    );
}

const files: string[] = [];
const sources: string[] = [];

if (argv.length > 2) {
  for (const root of argv.slice(2)) {
    collect(root, files);
    collectSources(root, sources);
  }
} else {
  for (const root of roots) {
    collect(root, files);
  }

  for (const root of retiredRoots) {
    collectSources(root, sources);
  }
}

const findings = [...files.flatMap(check), ...sources.flatMap(checkRetired)];

for (const { file, line, message } of findings) {
  console.error(`${relative(cwd(), file)}:${line}: ${message}`);
}

if (findings.length > 0) {
  console.error(
    `\n${findings.length} prose finding(s). See .agents/rules/writing.mdc.`,
  );
  exit(1);
}

console.log(`Checked ${files.length} files: no prose findings.`);
