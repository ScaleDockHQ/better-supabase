// Fails when the library, its skills, tests, READMEs, manifests, changesets,
// the docs, the ADRs, the agent rules, the marketing site, the examples or the
// fixture name PermDock or use its shapes (the `pdk_` key prefix,
// `permitted_<scope>_ids` helpers, its catalog file).
// Authorization libraries plug in through the `AuthorizationProvider`
// interface, so better-supabase never depends on one. The Create page may name
// PermDock as one optional auth choice (ADR 0039): only its option module, that
// module's test, the dialog that renders the setup and the create e2e spec.
// The changelogs keep their history, and the rule's own text, this script and
// ADR 0039 name what they forbid.
// Run with `node scripts/check-no-permdock.ts`.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { exit } from "node:process";

const roots = [
  "README.md",
  "AGENTS.md",
  "CLAUDE.md",
  "CHANGELOG.md",
  ".agents/rules",
  "docs",
  "scripts",
  ".changeset",
  "server.json",
  ".claude-plugin",
  ".cursor-plugin",
  "packages/better-supabase/README.md",
  "packages/better-supabase/CHANGELOG.md",
  "packages/better-supabase/scripts",
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
  "AGENTS.md",
  "CHANGELOG.md",
  ".agents/rules/architecture.mdc",
  "docs/agents/commands.md",
  "docs/decisions/0011-authorization-providers.md",
  "docs/decisions/0039-name-permdock-on-create.md",
  "docs/decisions/README.md",
  "packages/better-supabase/CHANGELOG.md",
  "scripts/check-no-permdock.ts",
  "apps/docs/content/docs/extending/authorization-providers.mdx",
  "apps/docs/content/docs/migration/0.5-to-0.6.mdx",
  "apps/marketing/e2e/create.spec.ts",
  "apps/marketing/features/create/components/get-code-dialog.tsx",
  "apps/marketing/lib/create-options.ts",
  "apps/marketing/tests/lib/create-options.test.ts",
  "apps/marketing/tests/lib/permdock-commands.json",
]);

// Tracked and new files only, so build output such as `tsbuildinfo` is skipped.
const files = execFileSync(
  "git",
  ["ls-files", "--cached", "--others", "--exclude-standard", "--", ...roots],
  { encoding: "utf-8" },
)
  .split("\n")
  .filter((file) => file !== "" && existsSync(file));

const findings: string[] = [];

for (const file of files) {
  if (allowed.has(file)) {
    continue;
  }

  readFileSync(file, "utf-8")
    .split("\n")
    .forEach((line, index) => {
      if (pattern.test(line)) {
        findings.push(`${file}:${index + 1}`);
      }
    });
}

for (const finding of findings) {
  console.error(`${finding}: names PermDock or one of its shapes`);
}

if (findings.length > 0) {
  console.error(
    `\n${findings.length} finding(s). Describe the AuthorizationProvider interface instead (AGENTS.md invariant 15).`,
  );
  exit(1);
}

console.log(`Checked ${files.length} files: no PermDock references.`);
