// Fails when a maintainer skill in `.agents/skills` is not backed by an entry in
// `skills-lock.json`, or when a lock entry has no folder. It also fails on a
// `.bsb` file extension in a skill: a repo-wide `bs` to `bsb` rename once
// turned `index.bs` links in the webmcp skill into 404s. The lock file's
// `computedHash` comes from the upstream folder, which the skills CLI doesn't
// let us recompute locally, so this check compares names and content patterns.
// Run with `node scripts/check-skills.ts`.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { exit } from "node:process";
import * as v from "valibot";

const SKILLS_DIR = ".agents/skills";

// The ReUI installer manages this skill, so it has no lock entry.
const UNLOCKED = new Set(["reui"]);
const BROKEN_EXTENSION = /\bindex\.bsb\b/;

const LockSchema = v.object({ skills: v.record(v.string(), v.unknown()) });

const entries = Object.keys(
  v.parse(LockSchema, JSON.parse(readFileSync("skills-lock.json", "utf-8")))
    .skills,
);

const locked = new Set(entries);

const installed = new Set(
  readdirSync(SKILLS_DIR).filter((name) =>
    statSync(join(SKILLS_DIR, name)).isDirectory(),
  ),
);

const problems: string[] = [];

for (const name of installed) {
  if (!locked.has(name) && !UNLOCKED.has(name)) {
    problems.push(`${SKILLS_DIR}/${name} has no entry in skills-lock.json`);
  }
}

for (const name of locked) {
  if (!existsSync(join(SKILLS_DIR, name, "SKILL.md"))) {
    problems.push(
      `skills-lock.json lists ${name}, but ${SKILLS_DIR}/${name}/SKILL.md is missing`,
    );
  }
}

const walk = (dir: string): string[] =>
  readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);

    return statSync(path).isDirectory() ? walk(path) : [path];
  });

for (const file of walk(SKILLS_DIR).filter((path) => path.endsWith(".md"))) {
  if (BROKEN_EXTENSION.test(readFileSync(file, "utf-8"))) {
    problems.push(`${file} mentions index.bsb; the spec source is index.bs`);
  }
}

if (problems.length > 0) {
  console.error(problems.join("\n"));
  exit(1);
}

console.log(
  `Checked ${installed.size} maintainer skills against skills-lock.json.`,
);
