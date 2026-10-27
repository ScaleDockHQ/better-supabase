// Checks the docs against the code: every doctor code has a heading on the
// doctor page, every subpath is in the README table and on a docs page, and
// every `meta.json` lists exactly the pages in its folder, every titled
// `lib/supabase/*` code block in the docs and skills follows the Naming page,
// no doc, skill, example or rule uses a name the Naming page retired, and the
// adoptable tables on the own-schemas page match the table specs.
// The CLI commands
// and flags are checked by `packages/better-supabase/tests/cli/docs-drift.test.ts`, and the
// `tables.*` and `columns.*` keys on the blocks pages by
// `packages/better-supabase/tests/sql/docs-drift.test.ts`; both run with the package's unit
// tests. Run with `node scripts/docs-drift.ts`.
import {
  existsSync,
  globSync,
  readFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import { join, relative } from "node:path";
import { cwd, exit } from "node:process";
import * as v from "valibot";

import {
  adoptableTablesCurrent,
  OWN_SCHEMAS_PAGE,
} from "./adoptable-tables.ts";

const root = cwd();
const docs = join(root, "apps/docs/content/docs");
const library = join(root, "packages/better-supabase");

const DoctorReport = v.object({
  properties: v.object({
    findings: v.object({
      items: v.object({
        properties: v.object({ code: v.object({ enum: v.array(v.string()) }) }),
      }),
    }),
  }),
});

const PackageExports = v.object({ exports: v.record(v.string(), v.unknown()) });
const Meta = v.object({ pages: v.optional(v.array(v.string()), []) });

function readJson<const Schema extends v.GenericSchema>(
  schema: Schema,
  path: string,
): v.InferOutput<Schema> {
  return v.parse(schema, JSON.parse(readFileSync(path, "utf-8")));
}

function doctorCodes(): string[] {
  const codes = readJson(
    DoctorReport,
    join(library, "schemas/doctor-report-v1.json"),
  ).properties.findings.items.properties.code.enum;

  const page = readFileSync(join(docs, "(reference)/cli/doctor.mdx"), "utf-8");

  const headings = new Set(
    [...page.matchAll(/^### (BS\d{3})$/gmu)].map((match) => match[1]),
  );

  return [
    ...codes
      .filter((code) => !headings.has(code))
      .map((code) => `cli/doctor.mdx has no "### ${code}" heading`),
    ...[...headings]
      .filter((code) => code !== undefined && !codes.includes(code))
      .map(
        (code) =>
          `cli/doctor.mdx documents ${code ?? ""}, which the report schema does not list`,
      ),
  ];
}

function markdownFiles(dir: string, extension: string): string[] {
  return globSync(`**/*${extension}`, { cwd: dir }).map((file) =>
    join(dir, file),
  );
}

/** The repo README is the npm README plus the repository sections. */
function readmeBody(): string[] {
  const npm = readFileSync(join(library, "README.md"), "utf-8").trim();
  const repo = readFileSync(join(root, "README.md"), "utf-8");

  return repo.startsWith(npm)
    ? []
    : ["README.md does not start with packages/better-supabase/README.md"];
}

function subpaths(): string[] {
  const { exports: exportsMap } = readJson(
    PackageExports,
    join(library, "package.json"),
  );

  const pages = markdownFiles(docs, ".mdx").map((file) =>
    readFileSync(file, "utf-8"),
  );

  const entries = Object.keys(exportsMap)
    .filter((key) => !key.includes("*") && !key.endsWith(".json"))
    .map((key) =>
      key === "." ? "better-supabase" : `better-supabase/${key.slice(2)}`,
    );

  return entries.flatMap((entry) => {
    const quoted = `"${entry}"`;
    const problems: string[] = [];

    if (!pages.some((page) => page.includes(quoted))) {
      problems.push(`no docs page imports from ${quoted}`);
    }

    return problems;
  });
}

function isPageEntry(entry: string): boolean {
  return !(
    entry.startsWith("---") ||
    entry.startsWith("...") ||
    entry.startsWith("!") ||
    entry.startsWith("[")
  );
}

function metaFiles(dir: string): string[] {
  const problems: string[] = [];
  const names = readdirSync(dir);

  const children = names.flatMap((name) => {
    if (statSync(join(dir, name)).isDirectory()) {
      problems.push(...metaFiles(join(dir, name)));

      return [name];
    }

    return name.endsWith(".mdx") ? [name.slice(0, -".mdx".length)] : [];
  });

  const where = relative(docs, dir) || ".";
  const metaPath = join(dir, "meta.json");

  if (!existsSync(metaPath)) {
    return [...problems, `${where} has no meta.json`];
  }

  const listed = readJson(Meta, metaPath).pages.filter(isPageEntry);

  if (listed.length === 0) {
    return [...problems, `${where}/meta.json has no explicit pages order`];
  }

  return [
    ...problems,
    ...listed
      .filter((entry) => !children.includes(entry))
      .map(
        (entry) => `${where}/meta.json lists "${entry}", which does not exist`,
      ),
    ...children
      .filter((child) => !listed.includes(child))
      .map((child) => `${where}/meta.json does not list "${child}"`),
  ];
}

interface CodeBlock {
  readonly title: string;
  readonly body: string;
  readonly line: number;
}

/** Fenced code blocks with a `title="..."`, also when a list indents them. */
function titledBlocks(text: string): CodeBlock[] {
  const lines = text.split("\n");
  const blocks: CodeBlock[] = [];

  for (let index = 0; index < lines.length; index += 1) {
    const open = /^(\s*)```\w*.*\btitle="([^"]+)"/u.exec(lines[index] ?? "");

    if (!open) {
      continue;
    }

    const indent = open[1] ?? "";
    const body: string[] = [];
    let end = index + 1;

    while (end < lines.length && lines[end]?.trim() !== "```") {
      body.push((lines[end] ?? "").slice(indent.length));
      end += 1;
    }

    blocks.push({
      title: open[2] ?? "",
      body: body.join("\n"),
      line: index + 1,
    });
    index = end;
  }

  return blocks;
}

/**
 * The Naming page's file layout: the definition from `defineSupabase` lives in
 * `lib/supabase/index.ts`, never in the `server.ts` or `client.ts` that create
 * `bsb`, and a Next.js `server.ts` starts with `import "server-only"`.
 */
function naming(): string[] {
  const files = [
    ...markdownFiles(docs, ".mdx"),
    ...markdownFiles(join(library, "skills"), ".md"),
  ];

  return files.flatMap((file) =>
    titledBlocks(readFileSync(file, "utf-8")).flatMap((block) => {
      const where = `${relative(root, file)}:${String(block.line)}`;
      const problems: string[] = [];

      if (
        /lib\/supabase\/(?:server|client)\.ts$/u.test(block.title) &&
        block.body.includes("defineSupabase(")
      ) {
        problems.push(
          `${where} defines betterSupabase in ${block.title}; it belongs in src/lib/supabase/index.ts (concepts/naming.mdx)`,
        );
      }

      if (
        block.title.endsWith("lib/supabase/server.ts") &&
        block.body.includes("createNext(") &&
        !block.body.trimStart().startsWith('import "server-only";')
      ) {
        problems.push(
          `${where} creates bsb with createNext in ${block.title} without starting with import "server-only" (concepts/naming.mdx)`,
        );
      }

      return problems;
    }),
  );
}

/**
 * Terms the 0.15 docs retired. Migration guides and the changelog may still
 * name them, because those pages describe the old API.
 */
const REMOVED_TERMS: readonly (readonly [RegExp, string])[] = [
  [/foundation modules?/giu, '"foundation module" (now a core block)'],
  [/blockRouter/gu, "`blockRouter` (now `defineApi`)"],
  [/scaffold screens/giu, '"scaffold screens" (now registry items)'],
];

const TERM_HISTORY = ["migration/", "changelog.mdx"];

function removedTerms(): string[] {
  return globSync("apps/docs/content/docs/**/*.mdx", { cwd: root })
    .filter(
      (file) => !TERM_HISTORY.some((page) => docsPath(file).includes(page)),
    )
    .flatMap((file) =>
      readFileSync(join(root, file), "utf-8")
        .split("\n")
        .flatMap((text, index) =>
          REMOVED_TERMS.filter(([pattern]) => pattern.test(text)).map(
            ([, name]) =>
              `${file}:${String(index + 1)} uses the removed term ${name}`,
          ),
        ),
    );
}

/** Names and paths the Naming page retired, with what replaced them. */
const RETIRED: readonly (readonly [RegExp, string])[] = [
  [
    /(?<![\w.$])sb\.\w/u,
    "`sb.` (the instance is `bsb`, the definition `betterSupabase`)",
  ],
  [/lib\/supabase\.ts\b/u, "`lib/supabase.ts` (now `lib/supabase/index.ts`)"],
  [
    /supabase\.server\.ts\b/u,
    "`supabase.server.ts` (now `lib/supabase/server.ts`)",
  ],
  [/\bcreateBrowser\b/u, "`createBrowser` (now `createClient`)"],
  [/\brequireOrganization\b/u, "`requireOrganization` (now `requireTenant`)"],
  [/\bauth\.organization\b/u, "`auth.organization` (now `auth.tenant`)"],
];

/** The pages whose job is to name the retired forms. */
const RENAMES = ["concepts/naming.mdx", "migration/", "cli/codemod.mdx"];

const IGNORED = [
  "**/node_modules/**",
  "**/.next/**",
  "**/.expo/**",
  "**/dist/**",
];

/** A docs path with the tab and group folders removed, so it matches the URL. */
function docsPath(file: string): string {
  return relative(docs, join(root, file))
    .split("/")
    .filter((part) => !/^\(.+\)$/u.test(part))
    .join("/");
}

function retiredNames(): string[] {
  const files = [
    ...globSync("apps/docs/content/docs/**/*.mdx", { cwd: root }).filter(
      (file) => !RENAMES.some((page) => docsPath(file).startsWith(page)),
    ),
    ...globSync("packages/better-supabase/skills/**/*.md", { cwd: root }),
    ...globSync(".agents/rules/*.mdc", { cwd: root }),
    ...globSync("apps/examples/**/*.{ts,tsx,md}", {
      cwd: root,
      exclude: IGNORED,
    }),
  ];

  return files.flatMap((file) =>
    readFileSync(join(root, file), "utf-8")
      .split("\n")
      .flatMap((text, index) =>
        RETIRED.filter(([pattern]) => pattern.test(text)).map(
          ([, name]) =>
            `${file}:${String(index + 1)} uses the retired ${name} (concepts/naming.mdx)`,
        ),
      ),
  );
}

const BLOCK_GROUPS = {
  organizations: ["tenancy", "identity", "admin"],
  database: ["database"],
  collaboration: ["collaboration", "messaging"],
  work: ["work"],
  crm: ["crm"],
  commerce: ["commerce"],
  content: ["content"],
  ai: ["ai"],
  automation: ["automation"],
  developer: ["developer"],
  growth: ["growth"],
  people: ["people", "scheduling"],
} as const satisfies Readonly<Record<string, readonly string[]>>;

const GROUP_OF = new Map<string, string>(
  Object.entries(BLOCK_GROUPS).flatMap(([group, categories]) =>
    categories.map((category) => [category, group] as const),
  ),
);

interface BlockDoc {
  readonly category: string;
  readonly names: readonly string[];
}

/** One `defineBlock` call: its name, category and SQL module names. */
function blockDocs(): BlockDoc[] {
  const docsForBlocks: BlockDoc[] = [];

  for (const name of readdirSync(join(library, "src/blocks"))) {
    const path = join(library, "src/blocks", name, "manifest.ts");

    if (!existsSync(path)) {
      continue;
    }

    for (const part of readFileSync(path, "utf-8")
      .split("defineBlock(")
      .slice(1)) {
      const block = /name: "([^"]+)"/u.exec(part)?.[1];
      const category = /category: "([^"]+)"/u.exec(part)?.[1];

      const sqlBody = /sql: \[([^\]]*)\]/u.exec(part)?.[1] ?? "";

      const sql = [...sqlBody.matchAll(/"([^"]+)"/gu)].flatMap((match) =>
        match[1] === undefined ? [] : [match[1]],
      );

      if (block !== undefined && category !== undefined) {
        docsForBlocks.push({
          category,
          names: [block, ...sql.filter((item) => item !== block)],
        });
      }
    }
  }

  return docsForBlocks;
}

/**
 * Every block page sits in the folder for its manifest category, and every
 * block has a page. A page may be named after the block or one of its SQL
 * modules (`webhooks-out`).
 */
function blockGroups(): string[] {
  const blocksDir = join(docs, "(blocks)/blocks");
  const categoryOf = new Map<string, string>();

  for (const block of blockDocs()) {
    for (const name of block.names) {
      categoryOf.set(name, block.category);
    }
  }

  const pages = globSync("**/*.mdx", { cwd: blocksDir });
  const problems: string[] = [];
  const documented = new Set<string>();

  for (const file of pages) {
    const parts = file.split("/");
    const folder = parts[0] ?? "";
    const page = (parts.at(-1) ?? "").slice(0, -".mdx".length);

    if (
      page === "index" ||
      page === "using" ||
      page.startsWith("catalog-") ||
      folder === "(using)"
    ) {
      continue;
    }

    const category = categoryOf.get(page);
    const group = folder.startsWith("(") ? folder.slice(1, -1) : folder;

    if (category === undefined) {
      problems.push(
        `blocks/${file} is not a block or one of a block's SQL modules`,
      );
      continue;
    }

    documented.add(page);

    const expected = GROUP_OF.get(category);

    if (expected !== group) {
      problems.push(
        `blocks/${file} is in (${group}), but ${page} is category ${category} (${expected ?? "unknown"})`,
      );
    }
  }

  const sqlPage = readFileSync(join(blocksDir, "(using)/sql.mdx"), "utf-8");

  const slugs = new Set(
    globSync("**/*.mdx", { cwd: docs }).map((file) => {
      const parts = file.split("/").filter((part) => !/^\(.+\)$/u.test(part));

      const last = parts.at(-1);

      return last?.replace(/\.mdx$/u, "");
    }),
  );

  for (const block of blockDocs()) {
    const covered = block.names.some(
      (name) =>
        documented.has(name) ||
        slugs.has(name) ||
        sqlPage.includes(`\`${name}\``),
    );

    if (!covered) {
      problems.push(`block ${block.names[0] ?? ""} has no docs page`);
    }
  }

  return problems;
}

function adoptableTables(): string[] {
  return adoptableTablesCurrent(readFileSync(OWN_SCHEMAS_PAGE, "utf-8"))
    ? []
    : [
        "the adoptable tables on blocks/own-schemas are stale; run `pnpm catalog`",
      ];
}

const problems = [
  ...doctorCodes(),
  ...subpaths(),
  ...metaFiles(docs),
  ...naming(),
  ...retiredNames(),
  ...removedTerms(),
  ...blockGroups(),
  ...readmeBody(),
  ...adoptableTables(),
];

for (const problem of problems) {
  console.error(`docs drift: ${problem}`);
}

if (problems.length > 0) {
  exit(1);
}

console.log(
  "docs drift: doctor codes, subpaths, meta.json, block groups, adoptable tables and lib/supabase naming match the code, with no retired names",
);
