/**
 * Writes the blocks catalog the marketing site renders (`/blocks`) from
 * `SQL_MODULES`, so the pages never drift from the registry. The marketing
 * `build`, `dev`, `typecheck`, `lint` and `test` tasks depend on it. It also
 * writes the preset catalog (`src/preset/catalog.generated.ts`), which
 * `better-supabase/preset` resolves against without importing the SQL
 * renderers. That file is committed, and `pnpm catalog:check` (`--check`,
 * part of `pnpm verify`) fails when it is stale.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { argv, exit } from "node:process";
import * as v from "valibot";

// A relative import, not `better-supabase/sql`: Vercel installs only the
// marketing app's dependencies, so the root has no link to the package.
import type {
  AnyBlock,
  BlockCategory,
} from "../packages/better-supabase/src/blocks/define-block.ts";
import type { PortName } from "../packages/better-supabase/src/blocks/ports.ts";
import type {
  PresetCatalog,
  PresetCatalogBlock,
  PresetCatalogManifest,
  PresetGlueItem,
} from "../packages/better-supabase/src/preset/catalog-types.ts";
import type { PresetAccess } from "../packages/better-supabase/src/preset/fields.ts";
import type { ModuleContext } from "../packages/better-supabase/src/sql/context.ts";
import type { ModuleLayout } from "../packages/better-supabase/src/sql/module-types.ts";

import { BLOCK_MANIFESTS } from "../packages/better-supabase/src/blocks/registry.ts";
import { PRESET_TENANT_NAMES } from "../packages/better-supabase/src/preset/fields.ts";
import {
  renderModules,
  SQL_MODULES,
  type SqlModule,
} from "../packages/better-supabase/src/sql/index.ts";
import { moduleContext } from "../packages/better-supabase/src/sql/module-context.ts";
import { resolveModules } from "../packages/better-supabase/src/sql/registry.ts";
import { tenantNameClashes } from "../packages/better-supabase/src/sql/tenant-clashes.ts";

const ROOT = join(import.meta.dirname, "..");
const PACKAGE_JSON = join(ROOT, "packages/better-supabase/package.json");
const DOCS_BLOCKS = join(ROOT, "apps/docs/content/docs/blocks");

export const CATALOG_FILE: string = join(
  ROOT,
  "apps/marketing/lib/catalog.json",
);

export const PRESET_CATALOG_FILE: string = join(
  ROOT,
  "packages/better-supabase/src/preset/catalog.generated.ts",
);

const BLOCKS_SRC = join(ROOT, "packages/better-supabase/src/blocks");

export const CATEGORIES = [
  "Identity & access",
  "Tenancy & accounts",
  "Collaboration",
  "Notifications & messaging",
  "Growth & engagement",
  "CRM & sales",
  "Work management",
  "People",
  "Billing & commerce",
  "Scheduling",
  "Content & files",
  "AI",
  "Automation",
  "Developer platform",
  "Admin & compliance",
  "Database primitives",
] as const;

export type Category = (typeof CATEGORIES)[number];

/** The catalog heading for each manifest category. */
const CATEGORY_TITLES = {
  identity: "Identity & access",
  tenancy: "Tenancy & accounts",
  collaboration: "Collaboration",
  messaging: "Notifications & messaging",
  growth: "Growth & engagement",
  crm: "CRM & sales",
  work: "Work management",
  people: "People",
  commerce: "Billing & commerce",
  scheduling: "Scheduling",
  content: "Content & files",
  ai: "AI",
  automation: "Automation",
  developer: "Developer platform",
  admin: "Admin & compliance",
  database: "Database primitives",
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
  const index = readFileSync(join(DOCS_BLOCKS, "index.mdx"), "utf-8");
  const pages = new Map<string, string>();

  for (const line of index.split("\n")) {
    const row = /^\| \[[^\]]+\]\((\/docs\/[^)]+)\)\s*\|[^|]*\|([^|]*)\|/.exec(
      line,
    );

    if (!row?.[1] || row[2] === undefined) {
      continue;
    }

    for (const match of row[2].matchAll(/`([a-z0-9-]+)`/g)) {
      if (match[1] && !pages.has(match[1])) {
        pages.set(match[1], row[1]);
      }
    }
  }

  return pages;
}

function docsPage(name: string, pages: ReadonlyMap<string, string>): string {
  if (existsSync(join(DOCS_BLOCKS, `${name}.mdx`))) {
    return `/docs/blocks/${name}`;
  }

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
    JSON.parse(readFileSync(PACKAGE_JSON, "utf-8")),
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

const ACCESS_MODELS: readonly PresetAccess[] = [
  "roles",
  "catalog",
  "provider",
  "custom",
];

/**
 * Each manifest's export name and folder: the registry imports every
 * manifest by name from `./<folder>/manifest.ts` and lists the names in
 * `BLOCK_MANIFESTS` in the array's order.
 */
function manifestExports(): ReadonlyMap<
  AnyBlock,
  { name: string; folder: string }
> {
  const registry = readFileSync(join(BLOCKS_SRC, "registry.ts"), "utf-8");

  const folders = new Map(
    [
      ...registry.matchAll(
        /import \{([\w\s,]+)\} from "\.\/([a-z0-9-]+)\/manifest\.ts";/g,
      ),
    ].flatMap(([, imported = "", folder = ""]) =>
      [...imported.matchAll(/\w+/g)].map(([name]) => [name, folder] as const),
    ),
  );

  const list = /BLOCK_MANIFESTS[^=]*= \[([^\]]*)\]/.exec(registry)?.[1] ?? "";

  const names = [...list.matchAll(/(\w+),/g)].flatMap((match) =>
    match[1] ? [match[1]] : [],
  );

  if (names.length !== BLOCK_MANIFESTS.length) {
    throw new Error(
      `build-catalog: read ${String(names.length)} names from BLOCK_MANIFESTS in registry.ts, but it holds ${String(BLOCK_MANIFESTS.length)} manifests.`,
    );
  }

  return new Map(
    BLOCK_MANIFESTS.flatMap((block, index) => {
      const name = names[index] ?? "";
      const folder = folders.get(name);

      return folder === undefined ? [] : [[block, { name, folder }]];
    }),
  );
}

function presetManifest(
  block: AnyBlock,
  exported: { name: string; folder: string } | undefined,
  exports: ReadonlyMap<string, string>,
): PresetCatalogManifest {
  const subpath = `./blocks/${exported?.folder ?? block.name}`;
  const source = exports.get(subpath);

  const index =
    source === undefined || source === ""
      ? ""
      : readFileSync(join(ROOT, source), "utf-8");

  const reexported =
    exported !== undefined && new RegExp(`\\b${exported.name}\\b`).test(index);

  return {
    name: block.name,
    sql: block.sql,
    category: block.category,
    client:
      block.create !== undefined && exported !== undefined && reexported
        ? {
            export: exported.name,
            subpath: `better-supabase${subpath.slice(1)}`,
          }
        : null,
    consumes: block.consumes,
    provides: Object.keys(block.provides).filter(isPortName),
  };
}

const PORT_NAMES: readonly PortName[] = [
  "notifier",
  "files",
  "attachments",
  "workflows",
  "sink",
];

const isPortName = (name: string): name is PortName =>
  PORT_NAMES.some((port) => port === name);

/**
 * The logical table `blocks.<name>.options.extraColumns` adds columns to,
 * read by rendering the module with a copy of its context (plain closures,
 * no getters) that records the table it passes to `ctx.extraColumns`.
 */
function extraColumnsTable(module: SqlModule): string | undefined {
  if (module.names?.options?.includes("extraColumns") !== true) {
    return undefined;
  }

  const layout: ModuleLayout = {
    modules: {
      [module.name]: { options: { extraColumns: { bs_probe: "text" } } },
    },
  };

  const ctx = moduleContext(
    module.name,
    layout,
    resolveModules([module.name], layout).map((each) => each.name),
  );

  const tables = new Set<string>();

  const probe: ModuleContext = {
    ...ctx,
    extraColumns: (table, reserved) => {
      tables.add(table);

      return ctx.extraColumns(table, reserved);
    },
  };

  module.build(probe, layout);
  module.data?.(probe, layout);

  if (tables.size !== 1) {
    throw new Error(
      `build-catalog: the "${module.name}" module declares options.extraColumns but adds them to ${String(tables.size)} tables (${[...tables].join(", ")}); the catalog expects one.`,
    );
  }

  return [...tables][0];
}

function presetBlock(module: SqlModule): PresetCatalogBlock {
  const manifest = BLOCK_MANIFESTS.find((each) =>
    each.sql.includes(module.name),
  );

  if (manifest === undefined) {
    throw new Error(
      `build-catalog: no block manifest installs the "${module.name}" module; add it to one's \`sql\`.`,
    );
  }

  const requires = module.dependencies?.({}) ?? module.requires;

  const byAccess = Object.fromEntries(
    ACCESS_MODELS.flatMap((model) => {
      const needs = module.dependencies?.({
        modules: { access: { model } },
      });

      return needs === undefined || needs.join(",") === requires.join(",")
        ? []
        : [[model, needs]];
    }),
  );

  const clashes = PRESET_TENANT_NAMES.filter(
    (tenant) => tenantNameClashes(module, tenant, SQL_MODULES).length > 0,
  );

  let block: PresetCatalogBlock = {
    name: module.name,
    title: module.title,
    category: manifest.category,
    requires,
    integrates: module.integrates ?? [],
    manifest: manifest.name,
  };

  if (module.scopes !== undefined) {
    block = { ...block, scopes: module.scopes };
  }

  if (clashes.length > 0) {
    block = { ...block, tenantNameClashes: clashes };
  }

  const extraColumns = extraColumnsTable(module);

  if (extraColumns !== undefined) {
    block = { ...block, extraColumns };
  }

  return Object.keys(byAccess).length === 0
    ? block
    : { ...block, requiresByAccess: byAccess };
}

const REGISTRY_FILE = join(ROOT, "packages/registry/registry.json");

const names = v.union([
  v.pipe(
    v.string(),
    v.transform((name) => [name]),
  ),
  v.array(v.string()),
]);

const registrySchema = v.object({
  items: v.array(
    v.looseObject({
      name: v.string(),
      title: v.string(),
      files: v.optional(
        v.array(
          v.looseObject({ path: v.string(), target: v.optional(v.string()) }),
        ),
        [],
      ),
      meta: v.object({
        block: names,
        frameworks: v.array(v.string()),
        platforms: v.array(v.picklist(["web", "native"])),
        preset: v.optional(v.string()),
      }),
    }),
  ),
});

/** The shadcn registry's glue items, by the blocks they serve. */
function glueItems(): PresetGlueItem[] {
  const { items } = v.parse(
    registrySchema,
    JSON.parse(readFileSync(REGISTRY_FILE, "utf-8")),
  );

  return items.map((item) => {
    const glue = {
      name: item.name,
      title: item.title,
      blocks: item.meta.block,
      frameworks: item.meta.frameworks,
      platforms: item.meta.platforms,
      targets: item.files.map((file) => file.target ?? file.path),
    } satisfies PresetGlueItem;

    return item.meta.preset === undefined
      ? glue
      : { ...glue, preset: item.meta.preset };
  });
}

export function buildPresetCatalog(): PresetCatalog {
  const exports = exportsOf();
  const found = manifestExports();

  return {
    blocks: Object.values(SQL_MODULES).map(presetBlock),
    manifests: BLOCK_MANIFESTS.map((block) =>
      presetManifest(block, found.get(block), exports),
    ),
    glue: glueItems(),
  };
}

export function formatPresetCatalog(catalog: PresetCatalog): string {
  return [
    "// Generated by scripts/build-catalog.ts from SQL_MODULES and the block",
    "// manifests. Do not edit; run `pnpm catalog`.",
    'import type { PresetCatalog } from "./catalog-types.ts";',
    "",
    `export const PRESET_CATALOG: PresetCatalog = ${JSON.stringify(catalog, null, 2)};`,
    "",
  ].join("\n");
}

if (import.meta.main) {
  try {
    const preset = formatPresetCatalog(buildPresetCatalog());

    if (argv.includes("--check")) {
      if (readFileSync(PRESET_CATALOG_FILE, "utf-8") !== preset) {
        console.error(
          "build-catalog: src/preset/catalog.generated.ts is stale; run `pnpm catalog`.",
        );
        exit(1);
      }
    } else {
      writeFileSync(PRESET_CATALOG_FILE, preset);
      mkdirSync(dirname(CATALOG_FILE), { recursive: true });
      writeFileSync(CATALOG_FILE, formatCatalog(buildCatalog()));
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    exit(1);
  }
}
