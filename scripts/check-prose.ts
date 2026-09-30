// Flags the writing patterns AGENTS.md bans in published prose: docs pages,
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
    if (/\.mdx?$/u.test(path) && !path.endsWith(".changeset/README.md"))
      into.push(path);
    return;
  }
  for (const entry of readdirSync(path)) {
    if (entry === "node_modules" || entry.startsWith(".source")) continue;
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
  const lines = readFileSync(file, "utf8").split("\n");
  let fence: string | undefined;
  let jsx = false;
  lines.forEach((raw, index) => {
    const trimmed = raw.trim();
    const marker = /^(`{3,}|~{3,})/u.exec(trimmed)?.[1];
    if (marker !== undefined) {
      if (fence === undefined) fence = marker;
      else if (trimmed.startsWith(fence)) fence = undefined;
      return;
    }
    if (fence !== undefined) return;
    if (/^(import|export)\s/u.test(trimmed)) return;
    // Multi-line JSX tags carry props, not prose.
    if (jsx) {
      if (trimmed.endsWith(">")) jsx = false;
      return;
    }
    if (/^<[A-Za-z][^>]*$/u.test(trimmed)) {
      jsx = true;
      return;
    }
    const text = prose(raw);
    for (const [pattern, message] of checks)
      if (pattern.test(text)) findings.push({ file, line: index + 1, message });
  });
  return findings;
}

const files: string[] = [];
for (const root of argv.length > 2 ? argv.slice(2) : roots)
  collect(root, files);

const findings = files.flatMap(check);
for (const { file, line, message } of findings)
  console.error(`${relative(cwd(), file)}:${line}: ${message}`);
if (findings.length > 0) {
  console.error(
    `\n${findings.length} prose finding(s). See "Writing" in AGENTS.md.`,
  );
  exit(1);
}
console.log(`Checked ${files.length} files: no prose findings.`);
