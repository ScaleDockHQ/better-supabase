// Fails on merge-conflict markers in docs, on two ADR files with one number,
// and on an ADR that `docs/decisions/README.md` does not index. Run with `node scripts/check-adrs.ts`.
import { readdirSync, readFileSync } from "node:fs";
import { exit } from "node:process";

const DIR = "docs/decisions";
const MARKER = /^(?:\s*)(?:\|{7}|<{7}|>{7})(?:\s|$)/m;

const files = readdirSync(DIR).filter(
  (name) => /^\d{4}-.+\.md$/.test(name) && !name.startsWith("0000-"),
);

const problems: string[] = [];

const seen = new Map<string, string>();

for (const name of files) {
  const number = name.slice(0, 4);
  const first = seen.get(number);

  if (first) {
    problems.push(`ADR ${number} is used by ${first} and ${name}`);
  }

  seen.set(number, name);
}

const readme = readFileSync(`${DIR}/README.md`, "utf-8");

for (const name of files) {
  if (!readme.includes(`](${name})`)) {
    problems.push(`${DIR}/README.md does not link ${name}`);
  }
}

const linked = new Set<string>();

for (const line of readme.split("\n")) {
  if (!line.startsWith("|")) {
    continue;
  }

  const link = /^\| \[(\d{4})\]\(/.exec(line);

  if (link?.[1]) {
    if (linked.has(link[1])) {
      problems.push(`${DIR}/README.md lists ${link[1]} twice`);
    }

    linked.add(link[1]);
  } else if (/^\|\s+\|/.test(line) || /^\| =+\s/.test(line)) {
    problems.push(
      `${DIR}/README.md has a stray row: ${line.slice(0, 40).trim()}`,
    );
  }
}

for (const path of [
  "AGENTS.md",
  `${DIR}/README.md`,
  ...files.map((name) => `${DIR}/${name}`),
]) {
  if (MARKER.test(readFileSync(path, "utf-8"))) {
    problems.push(`${path} contains a merge-conflict marker`);
  }
}

if (problems.length > 0) {
  console.error(problems.join("\n"));
  exit(1);
}

console.log(`${files.length} ADRs indexed.`);
