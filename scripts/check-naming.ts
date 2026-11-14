// Enforces packages/better-supabase/api/naming.json over the library, its
// tests, the docs and the skills: finished renames stay finished, environment
// variables carry the BETTER_SUPABASE_ prefix, exported types avoid the banned
// suffixes, doctor codes are upper case, subpaths keep their shape. Violations
// the repo has not renamed yet are listed in the allowlist of naming.json, and
// the check fails when an allowlisted item stops violating, so the list only
// shrinks. It also enforces the event verb vocabulary and the hint prefix rule
// of ADR 0699. Run with `node scripts/check-naming.ts [--print]`.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { argv, exit } from "node:process";

import { checkPgtapCoverage } from "./check-pgtap-coverage.ts";

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
  readonly hints: {
    readonly shared: readonly string[];
    readonly allowlist: Readonly<Record<string, readonly string[]>>;
  };
  readonly eventVerbs: {
    readonly banned: Readonly<Record<string, string>>;
    readonly bannedSuffixes: Readonly<Record<string, string>>;
    readonly bannedEnding: Readonly<Record<string, string>>;
    readonly endingExceptions: readonly string[];
  };
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

const BLOCKS_SRC = "packages/better-supabase/src/blocks";

/** The verb of every `"<entity>.<verb>": event<...>` a block declares. */
function eventTypes(): readonly { file: string; type: string }[] {
  const found: { file: string; type: string }[] = [];
  const events: string[] = [];

  walk(BLOCKS_SRC, events);

  for (const file of events.filter((each) => each.endsWith("/events.ts"))) {
    for (const match of readFileSync(file, "utf-8").matchAll(
      /^\s+"([a-z_]+\.[a-z_]+)": event</gm,
    )) {
      found.push({ file, type: match[1]! });
    }
  }

  return found;
}

const declaredTypes = eventTypes();

for (const { file, type } of declaredTypes) {
  const verb = type.slice(type.indexOf(".") + 1);
  const use = naming.eventVerbs.banned[verb];
  const ending = naming.eventVerbs.bannedEnding[verb];

  if (
    ending !== undefined &&
    !naming.eventVerbs.endingExceptions.includes(type)
  ) {
    found.codes.push(
      `${file} ${type}: "${verb}" ends a record with a verb ADR 1027 does not use, write ${ending}`,
    );
  }

  if (use !== undefined) {
    found.codes.push(
      `${file} ${type}: the verb "${verb}" is banned, use ${use}`,
    );
  }

  for (const [suffix, instead] of Object.entries(
    naming.eventVerbs.bannedSuffixes,
  )) {
    if (verb.endsWith(suffix)) {
      found.codes.push(
        `${file} ${type}: a verb ending in "${suffix}" is banned, end it in "${instead}"`,
      );
    }
  }
}

for (const type of naming.eventVerbs.endingExceptions) {
  if (!declaredTypes.some((each) => each.type === type)) {
    found.codes.push(
      `naming.json eventVerbs.endingExceptions lists ${type}, which no block declares any more: remove it`,
    );
  }
}

const singularAndPlural = (word: string): readonly string[] => {
  const lower = word.toLowerCase();
  const forms = new Set([lower]);

  if (lower.endsWith("ies")) {
    forms.add(`${lower.slice(0, -3)}y`);
  } else if (lower.endsWith("s") && !lower.endsWith("ss")) {
    forms.add(lower.slice(0, -1));
  } else {
    forms.add(`${lower}s`);
  }

  if (lower.endsWith("y")) {
    forms.add(`${lower.slice(0, -1)}ies`);
  }

  return [...forms].map((form) => form.toUpperCase());
};

/**
 * The prefixes a block's name gives: a run of its words, the last in either
 * number.
 */
function namePrefixes(block: string): readonly string[] {
  const words = block.toUpperCase().split("-");
  const prefixes: string[] = [];

  for (let from = 0; from < words.length; from += 1) {
    for (let to = from; to < words.length; to += 1) {
      for (const last of singularAndPlural(words[to]!)) {
        prefixes.push([...words.slice(from, to), last].join("_"));
      }
    }
  }

  return prefixes;
}

const usedHintPrefixes = new Set<string>();

for (const line of readFileSync(
  `${BLOCKS_SRC}/hint-codes.generated.ts`,
  "utf-8",
).matchAll(/^ {2}readonly "([^"]+)": (.+);$/gm)) {
  const block = line[1]!;
  const given = namePrefixes(block);
  const allowed = naming.hints.allowlist[block] ?? [];

  for (const code of line[2]!.matchAll(/"([A-Z0-9_]+)"/g)) {
    const hint = code[1]!;

    if (naming.hints.shared.some((prefix) => hint.startsWith(prefix))) {
      continue;
    }

    if (given.some((prefix) => hint.startsWith(`${prefix}_`))) {
      continue;
    }

    const exception = allowed.find((prefix) => hint.startsWith(prefix));

    if (exception === undefined) {
      found.codes.push(
        `${BLOCKS_SRC}/hint-codes.generated.ts ${block}: ${hint} does not start with a prefix its name gives (${given.slice(-2).join(", ")}); rename it, or allowlist the entity prefix in api/naming.json (ADR 0130 rule 8)`,
      );
    } else {
      usedHintPrefixes.add(`${block}:${exception}`);
    }
  }
}

for (const [block, prefixes] of Object.entries(naming.hints.allowlist)) {
  for (const prefix of prefixes) {
    if (!usedHintPrefixes.has(`${block}:${prefix}`)) {
      found.codes.push(
        `hints: ${block} no longer has a code starting with ${prefix}; remove it from the hints allowlist`,
      );
    }
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

const problems = [...found.rename, ...found.codes, ...checkPgtapCoverage()];

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
