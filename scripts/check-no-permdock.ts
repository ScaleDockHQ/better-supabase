// Fails when the library, its skills, tests, READMEs, manifests, the docs, the
// marketing site, the examples or the fixture name PermDock or use its shapes
// (the `pdk_` key prefix, `permitted_<scope>_ids` helpers, its catalog file). Authorization libraries plug in through the
// `AuthorizationProvider` interface, so better-supabase never depends on one.
// Run with `node scripts/check-no-permdock.ts`.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { exit } from "node:process";

const roots = [
  "README.md",
  "server.json",
  ".claude-plugin",
  ".cursor-plugin",
  "packages/better-supabase/README.md",
  "packages/better-supabase/api",
  "packages/better-supabase/src",
  "packages/better-supabase/skills",
  "packages/better-supabase/schemas",
  "packages/better-supabase/tests",
  "apps/docs/content",
  "apps/marketing",
  "apps/examples",
  "supabase/schemas",
  "supabase/seed.sql",
  "supabase/tests",
  "tests",
];

const pattern = /permdock|\bpdk_|permitted_|permissions\.catalog/iu;

const allowed = new Set([
  "apps/docs/content/docs/extending/authorization-providers.mdx",
  "apps/docs/content/docs/migration/0.5-to-0.6.mdx",
]);

// Tracked and new files only, so build output such as `tsbuildinfo` is skipped.
const files = execFileSync(
  "git",
  ["ls-files", "--cached", "--others", "--exclude-standard", "--", ...roots],
  { encoding: "utf8" },
)
  .split("\n")
  .filter((file) => file !== "" && existsSync(file));

const findings: string[] = [];
for (const file of files) {
  if (allowed.has(file)) continue;
  readFileSync(file, "utf8")
    .split("\n")
    .forEach((line, index) => {
      if (pattern.test(line)) findings.push(`${file}:${index + 1}`);
    });
}

for (const finding of findings)
  console.error(`${finding}: names PermDock or one of its shapes`);
if (findings.length > 0) {
  console.error(
    `\n${findings.length} finding(s). Describe the AuthorizationProvider interface instead (AGENTS.md invariant 15).`,
  );
  exit(1);
}
console.log(`Checked ${files.length} files: no PermDock references.`);
