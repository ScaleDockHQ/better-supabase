// Enforces packages/better-supabase/api/naming.json over the library, its
// tests, the docs and the skills: finished renames stay finished, environment
// variables carry the BETTER_SUPABASE_ prefix, exported types avoid the banned
// suffixes, doctor codes are upper case, subpaths keep their shape. Violations
// the repo has not renamed yet are listed in the allowlist of naming.json, and
// the check fails when an allowlisted item stops violating, so the list only
// shrinks. Run with `node scripts/check-naming.ts [--print]`.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { argv, exit } from "node:process";

interface Rename {
  readonly from: string;
  readonly to: string;
  readonly kind:
    | "argument"
    | "column"
    | "configKey"
    | "constraint"
    | "env"
    | "event"
    | "function"
    | "hint"
    | "index"
    | "policy"
    | "sqlFunction"
    | "subpath"
    | "table"
    | "trigger"
    | "type";
  readonly since: string;
}

interface Naming {
  readonly env: {
    readonly prefix: string;
    readonly platform: readonly string[];
  };
  readonly bannedTypeSuffixes: readonly string[];
  readonly subpathPattern: string;
  readonly renames: readonly Rename[];
  readonly allowlist: {
    readonly env: readonly string[];
    readonly typeNames: readonly string[];
    readonly subpaths: readonly string[];
  };
}

const NAMING_FILE = "packages/better-supabase/api/naming.json";

// SAFETY: naming.json is this repo's own file, shaped by `Naming` above.
const naming = JSON.parse(readFileSync(NAMING_FILE, "utf-8")) as Naming;

const SKIPPED = new Set([
  "node_modules",
  "dist",
  ".next",
  ".turbo",
  ".git",
  "coverage",
  ".source",
  ".temp",
]);

const TEXT = /\.(?:ts|tsx|mts|md|mdx|json|jsonc|yml|yaml|toml|sql|example)$/;

function walk(path: string, into: string[]): void {
  let stats;

  try {
    stats = statSync(path);
  } catch {
    return;
  }

  if (stats.isFile()) {
    if (TEXT.test(path) || path.includes(".env")) {
      into.push(path);
    }

    return;
  }

  for (const entry of readdirSync(path)) {
    if (!SKIPPED.has(entry)) {
      walk(join(path, entry), into);
    }
  }
}

/** Where a finished rename must not reappear. History stays as it was. */
const ROOTS = [
  "packages/better-supabase/src",
  "packages/better-supabase/tests",
  "packages/better-supabase/skills",
  "packages/better-supabase/README.md",
  "apps",
  "scripts",
  "tests",
  "supabase",
  "turbo.json",
  "docs/agents",
];

const HISTORY = [
  "supabase/migrations/",
  NAMING_FILE,
  "packages/better-supabase/api/exports.json",
  "CHANGELOG.md",
  "packages/better-supabase/tests/cli/codemod-naming.test.ts",
  "packages/better-supabase/tests/cli/commands/codemod.test.ts",
  "apps/docs/content/docs/(docs)/migration/",
  "apps/docs/content/docs/(docs)/concepts/naming.mdx",
  "scripts/check-naming.ts",
];

const files: string[] = [];

for (const root of ROOTS) {
  walk(root, files);
}

const checked = files.filter(
  (file) => !HISTORY.some((skipped) => file.startsWith(skipped)),
);

interface Found {
  rename: string[];
  env: Set<string>;
  typeNames: Set<string>;
  subpaths: Set<string>;
  codes: string[];
}

const found: Found = {
  rename: [],
  env: new Set(),
  typeNames: new Set(),
  subpaths: new Set(),
  codes: [],
};

const escaped = (text: string): string =>
  text.replaceAll(/[.*+?^${}()|[\]\\/]/g, String.raw`\$&`);

const renameChecks = naming.renames
  .filter(
    (rename) =>
      rename.kind !== "argument" &&
      rename.kind !== "column" &&
      rename.kind !== "configKey" &&
      rename.kind !== "policy",
  )
  .map((rename) => {
    const from = escaped(rename.from);

    return [
      rename,
      rename.kind === "subpath"
        ? new RegExp(`better-supabase/${from}(?![\\w-])`)
        : new RegExp(`(?<![A-Za-z0-9_])${from}(?![A-Za-z0-9_])`),
    ] as const;
  });

// `config.<former key>` in a comment, a string or a docs page. The code
// property of the resolved config can keep its name, so a `.ts` line only
// counts when the match sits in a `//` or `*` comment or inside a quote.
const configKeyChecks = naming.renames
  .filter((rename) => rename.kind === "configKey")
  .map(
    (rename) =>
      [
        rename,
        new RegExp(`\\bconfig\\.${escaped(rename.from)}\\b`, "g"),
      ] as const,
  );

const COMMENT_LINE = /^\s*(?:\/\/|\/?\*|--)/;

function inCommentOrString(line: string, index: number): boolean {
  const before = line.slice(0, index);
  const quotes = (mark: string): number => before.split(mark).length - 1;

  return (
    COMMENT_LINE.test(line) ||
    before.includes("//") ||
    quotes("`") % 2 === 1 ||
    quotes('"') % 2 === 1 ||
    quotes("'") % 2 === 1
  );
}

const ENV_READ = /\b(?:process\.env|env)\.([A-Z][A-Z0-9_]{3,})\b/g;
const TYPE_DECLARATION = /\bexport\s+(?:interface|type)\s+(\w+)/g;
const LOWERCASE_CODE = /(?<!#)\bbs\d{3}\b/;

for (const file of checked) {
  const text = readFileSync(file, "utf-8");
  const inSource = file.startsWith("packages/better-supabase/src/");
  const lines = text.split("\n");

  for (const [index, line] of lines.entries()) {
    for (const [rename, pattern] of renameChecks) {
      if (pattern.test(line)) {
        found.rename.push(
          `${file}:${String(index + 1)} ${rename.from} is ${rename.to}`,
        );
      }
    }
  }

  const prose = /\.(?:md|mdx)$/.test(file);

  if (prose || /\.(?:ts|tsx|mts)$/.test(file)) {
    for (const [index, line] of lines.entries()) {
      for (const [rename, pattern] of configKeyChecks) {
        for (const match of line.matchAll(pattern)) {
          if (prose || inCommentOrString(line, match.index)) {
            found.rename.push(
              `${file}:${String(index + 1)} config.${rename.from} is config.${rename.to}`,
            );
          }
        }
      }
    }
  }

  if (inSource) {
    for (const match of text.matchAll(ENV_READ)) {
      const name = match[1]!;

      if (
        !name.startsWith(naming.env.prefix) &&
        !naming.env.platform.some((prefix) => name.startsWith(prefix))
      ) {
        found.env.add(name);
      }
    }

    for (const match of text.matchAll(TYPE_DECLARATION)) {
      const name = match[1]!;

      if (naming.bannedTypeSuffixes.some((suffix) => name.endsWith(suffix))) {
        found.typeNames.add(name);
      }
    }

    for (const [index, line] of lines.entries()) {
      if (
        file.includes("/doctor/") &&
        LOWERCASE_CODE.test(line) &&
        !line.includes("//")
      ) {
        found.codes.push(`${file}:${String(index + 1)} lowercase doctor code`);
      }
    }
  }
}

// The `exports` keys sit at four spaces; `publishConfig.exports` is nested deeper.
const exportKeys: readonly string[] = [
  ...readFileSync("packages/better-supabase/package.json", "utf-8").matchAll(
    /^ {4}"(\.[^"]*)":/gm,
  ),
].map((match) => match[1]!);

const subpath = new RegExp(naming.subpathPattern);

for (const key of exportKeys) {
  if (key === "." || key.endsWith("package.json")) {
    continue;
  }

  if (!subpath.test(key)) {
    found.subpaths.add(key);
  }
}

if (argv.includes("--print")) {
  console.log(
    JSON.stringify(
      {
        env: [...found.env].toSorted(),
        typeNames: [...found.typeNames].toSorted(),
        subpaths: [...found.subpaths].toSorted(),
      },
      null,
      2,
    ),
  );
  exit(0);
}

const problems = [...found.rename, ...found.codes];

const lists = ["env", "typeNames", "subpaths"] as const;

for (const list of lists) {
  const allowed = new Set(naming.allowlist[list]);

  for (const name of found[list]) {
    if (!allowed.has(name)) {
      problems.push(
        `${list}: ${name} breaks the naming rules (api/naming.json)`,
      );
    }
  }

  for (const name of allowed) {
    if (!found[list].has(name)) {
      problems.push(
        `${list}: ${name} no longer breaks a rule; remove it from the allowlist`,
      );
    }
  }
}

if (problems.length > 0) {
  console.error(problems.join("\n"));
  console.error(`\n${String(problems.length)} naming problem(s).`);
  exit(1);
}

console.log(
  `naming ok: ${String(naming.renames.length)} renames hold, ${String(
    Object.values(naming.allowlist).reduce(
      (sum, names) => sum + names.length,
      0,
    ),
  )} allowlisted.`,
);
