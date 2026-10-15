/**
 * Writes the blocks catalog the marketing site renders (`/blocks`) from
 * `SQL_MODULES`, so the pages never drift from the registry. The marketing
 * `build`, `dev`, `typecheck`, `lint` and `test` tasks depend on it.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { exit } from "node:process";
import * as v from "valibot";

// A relative import, not `better-supabase/sql`: Vercel installs only the
// marketing app's dependencies, so the root has no link to the package.
import type { BlockCategory } from "../packages/better-supabase/src/blocks/define-block.ts";

import { BLOCK_MANIFESTS } from "../packages/better-supabase/src/blocks/registry.ts";
import {
  renderModules,
  SQL_MODULES,
  type SqlModule,
} from "../packages/better-supabase/src/sql/index.ts";

const ROOT = join(import.meta.dirname, "..");
const PACKAGE_JSON = join(ROOT, "packages/better-supabase/package.json");
const DOCS_BLOCKS = join(ROOT, "apps/docs/content/docs/blocks");
export const CATALOG_FILE = join(ROOT, "apps/marketing/lib/catalog.json");

export const CATEGORIES = [
  "Foundation",
  "Collaboration",
  "CRM & sales",
  "Work",
  "Billing & commerce",
  "Scheduling",
  "AI",
  "Content",
  "Operations",
  "Platform",
] as const;

export type Category = (typeof CATEGORIES)[number];

/** The catalog heading for each manifest category. */
const CATEGORY_TITLES = {
  foundation: "Foundation",
  collaboration: "Collaboration",
  crm: "CRM & sales",
  work: "Work",
  commerce: "Billing & commerce",
  scheduling: "Scheduling",
  ai: "AI",
  content: "Content",
  operations: "Operations",
  platform: "Platform",
} as const satisfies Readonly<Record<BlockCategory, Category>>;

export interface CatalogBlock {
  readonly name: string;
  readonly title: string;
  readonly category: Category;
  readonly description: string;
  readonly requires: readonly string[];
  readonly integrates: readonly string[];
  readonly modes: readonly string[];
  /** Outbox event types the module emits when the outbox is installed. */
  readonly events: readonly string[];
  /** The `better-supabase/blocks/<name>` subpath, when the block has a TypeScript side. */
  readonly subpath: string | null;
  /** The `better-supabase/blocks/<name>/react` entry and its source file, when there is one. */
  readonly react: { readonly subpath: string; readonly source: string } | null;
  /** The docs page that covers the module. */
  readonly docs: string;
}

export interface Catalog {
  readonly categories: readonly Category[];
  readonly blocks: readonly CatalogBlock[];
}

/** The category of the block whose manifest installs the module. */
function categoryOf(name: string): Category {
  const block = BLOCK_MANIFESTS.find((each) => each.sql.includes(name));
  if (block === undefined) {
    throw new Error(
      `build-catalog: no block manifest installs the "${name}" module; add it to one's \`sql\`.`,
    );
  }
  return CATEGORY_TITLES[block.category];
}

/** Module name to docs page, from the Blocks table in `blocks/index.mdx`. */
function docsPages(): ReadonlyMap<string, string> {
  const index = readFileSync(join(DOCS_BLOCKS, "index.mdx"), "utf8");
  const pages = new Map<string, string>();
  for (const line of index.split("\n")) {
    const row = /^\| \[[^\]]+\]\((\/docs\/[^)]+)\)\s*\|[^|]*\|([^|]*)\|/.exec(
      line,
    );
    if (!row?.[1] || row[2] === undefined) continue;
    for (const match of row[2].matchAll(/`([a-z0-9-]+)`/g)) {
      if (match[1] && !pages.has(match[1])) pages.set(match[1], row[1]);
    }
  }
  return pages;
}

function docsPage(name: string, pages: ReadonlyMap<string, string>): string {
  if (existsSync(join(DOCS_BLOCKS, `${name}.mdx`)))
    return `/docs/blocks/${name}`;
  return pages.get(name) ?? "/docs/blocks/sql";
}

// Each export maps to its source file, or undefined for a plain string target.
const packageJsonSchema = v.object({
  exports: v.record(
    v.string(),
    v.union([
      v.pipe(
        v.string(),
        v.transform(() => undefined),
      ),
      v.pipe(
        v.looseObject({ "@better-supabase/source": v.optional(v.string()) }),
        v.transform((target) => target["@better-supabase/source"]),
      ),
    ]),
  ),
});

/** Export subpath to its source file (the `@better-supabase/source` condition). */
function exportsOf(): ReadonlyMap<string, string> {
  const { exports } = v.parse(
    packageJsonSchema,
    JSON.parse(readFileSync(PACKAGE_JSON, "utf8")),
  );
  return new Map(
    Object.entries(exports).map(([subpath, source]) => [
      subpath,
      source === undefined
        ? ""
        : `packages/better-supabase/${source.replace(/^\.\//, "")}`,
    ]),
  );
}

/**
 * Event types from the module's file rendered next to the outbox. A module
 * that needs options to render (`entitlements` needs a customer column) gets
 * the managed organizations module, which supplies the default.
 */
function eventsOf(module: SqlModule): readonly string[] {
  const attempts = [
    [module.name, "outbox"],
    [module.name, "outbox", "organizations"],
  ];
  for (const names of attempts) {
    try {
      const sql = renderModules(names)
        .filter((file) => file.module === module.name)
        .map((file) => file.contents)
        .join("\n");
      const types = [...sql.matchAll(/emit_event\(\s*'([^']+)'/g)].flatMap(
        (match) => (match[1] ? [match[1]] : []),
      );
      return [...new Set(types)].toSorted();
    } catch {
      continue;
    }
  }
  return [];
}

export function buildCatalog(): Catalog {
  const exports = exportsOf();
  const pages = docsPages();
  const blocks = Object.values(SQL_MODULES).map((module): CatalogBlock => {
    const subpath = `./blocks/${module.name}`;
    const reactSource = exports.get(`${subpath}/react`);
    return {
      name: module.name,
      title: module.title,
      category: categoryOf(module.name),
      description: module.description,
      requires: module.requires,
      integrates: module.integrates ?? [],
      modes: module.modes ?? ["managed"],
      events: eventsOf(module),
      subpath: exports.has(subpath)
        ? `better-supabase${subpath.slice(1)}`
        : null,
      react:
        reactSource === undefined
          ? null
          : {
              subpath: `better-supabase${subpath.slice(1)}/react`,
              source: reactSource,
            },
      docs: docsPage(module.name, pages),
    };
  });
  return { categories: CATEGORIES, blocks };
}

export function formatCatalog(catalog: Catalog): string {
  return `${JSON.stringify(catalog, null, 2)}\n`;
}

if (import.meta.main) {
  try {
    mkdirSync(dirname(CATALOG_FILE), { recursive: true });
    writeFileSync(CATALOG_FILE, formatCatalog(buildCatalog()));
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    exit(1);
  }
}
