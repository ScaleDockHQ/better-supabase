// Decides which optional CI jobs a change needs from its file paths alone, so the job needs no install.
// Usage: node scripts/ci-changes.ts <base-ref>   (prints `name=true|false` lines for $GITHUB_OUTPUT)
// A path that no rule names turns every output on: a missed rule costs minutes, never a skipped check.
import { spawnSync } from "node:child_process";
import { argv, exit } from "node:process";

export const OUTPUTS = ["stack", "docs", "vite"] as const;

export type Output = (typeof OUTPUTS)[number];

export type Changes = Readonly<Record<Output, boolean>>;

/** Paths that can change any app, package or test: they turn everything on. */
const GLOBAL = [
  "package.json",
  "pnpm-lock.yaml",
  "pnpm-workspace.yaml",
  "turbo.json",
  ".node-version",
  "packages/next-config/",
  "packages/typescript-config/",
  ".github/actions/setup/",
];

/** Paths that no gated job reads. */
const INERT = [
  "apps/marketing/",
  "docs/",
  ".cursor/",
  ".claude/",
  ".agents/",
  ".changeset/",
  ".vscode/",
  "README.md",
  "AGENTS.md",
  "CLAUDE.md",
  "LICENSE",
];

const RULES: readonly {
  readonly prefixes: readonly string[];
  readonly outputs: readonly Output[];
}[] = [
  {
    prefixes: ["packages/better-supabase/", "packages/registry/"],
    outputs: ["stack", "docs", "vite"],
  },
  { prefixes: ["apps/docs/"], outputs: ["docs"] },
  { prefixes: ["apps/examples/vite-react/"], outputs: ["vite"] },
  {
    prefixes: [
      "apps/examples/nextjs/",
      "tests/validation-centrakit/",
      "tests/validation-recipes/",
      "tests/validation-presets/",
      "tests/validation-request-context/",
      "supabase/",
      "scripts/",
      ".github/actions/supabase-stack/",
      ".github/workflows/ci.yml",
    ],
    outputs: ["stack"],
  },
  // Suites and examples that no gated job runs.
  {
    prefixes: [
      "apps/examples/",
      "tests/",
      ".github/workflows/",
      ".github/",
      "skills-lock.json",
    ],
    outputs: [],
  },
];

function matches(path: string, prefix: string): boolean {
  return prefix.endsWith("/") ? path.startsWith(prefix) : path === prefix;
}

export function classify(paths: readonly string[]): Changes {
  const on: Record<Output, boolean> = {
    stack: false,
    docs: false,
    vite: false,
  };

  const all = (): Changes => ({ stack: true, docs: true, vite: true });

  for (const path of paths) {
    if (GLOBAL.some((prefix) => matches(path, prefix))) {
      return all();
    }

    if (INERT.some((prefix) => matches(path, prefix))) {
      continue;
    }

    // Every matching rule counts, so the broad empty rules at the end never hide a narrow one.
    const hits = RULES.filter((rule) =>
      rule.prefixes.some((prefix) => matches(path, prefix)),
    );

    if (hits.length === 0) {
      return all();
    }

    for (const hit of hits) {
      for (const output of hit.outputs) {
        on[output] = true;
      }
    }
  }

  return on;
}

function git(args: readonly string[]): string | undefined {
  const result = spawnSync("git", args, { encoding: "utf-8" });

  return result.status === 0 ? result.stdout : undefined;
}

if (import.meta.main) {
  const base = argv[2] ?? "";
  const everything = OUTPUTS.map((name) => `${name}=true`).join("\n");

  // A new branch, a force-push or a base that is not in the clone has nothing to diff against.
  const known =
    base !== "" &&
    !/^0+$/.test(base) &&
    git(["cat-file", "-e", `${base}^{commit}`]) !== undefined;

  const diff = known ? git(["diff", "--name-only", base, "HEAD"]) : undefined;

  if (diff === undefined) {
    console.log(everything);
    exit(0);
  }

  const paths = diff.split("\n").filter((line) => line !== "");
  const changes = classify(paths);

  console.error(`${paths.length} changed paths`);

  for (const name of OUTPUTS) {
    console.log(`${name}=${changes[name]}`);
  }
}
