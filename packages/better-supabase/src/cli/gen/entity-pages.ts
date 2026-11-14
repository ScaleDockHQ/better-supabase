import { existsSync } from "node:fs";
import { posix } from "node:path";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";
import type { EntityPage } from "../../list/index.ts";
import type { PresetCatalogManifest } from "../../preset/index.ts";

import { blockEntities } from "../../config/index.ts";
import { PRESET_CATALOG } from "../../preset/index.ts";
import { resolveBlock } from "../../sql/index.ts";
import { CliError } from "../core/errors.ts";
import { GENERATED_HEADER } from "./emit.ts";
import {
  MANIFEST_OUTPUT,
  NAVIGATION_OUTPUT,
  SEED_OUTPUT,
} from "./entity-page-meta.ts";
import {
  COLUMNS_OUTPUT,
  DETAIL_OUTPUT,
  FORM_OUTPUT,
} from "./entity-page-ui.ts";
import { camelOf } from "./renamed-blocks.ts";
import { q, runtimeSubpath } from "./shared.ts";

/** The suffix of the migration that holds the indexes of the entity pages. */
export const ENTITY_PAGE_INDEXES_SUFFIX =
  "_better_supabase_entity_page_indexes.sql";

/** The schema file that declares the generated indexes, next to the block files. */
const ENTITY_PAGE_INDEXES_SCHEMA_FILE = "entity_page_indexes.sql";

type PagesConfig = Pick<
  ResolvedConfig,
  "blocks" | "blockNames" | "output" | "gen" | "root" | "sql"
>;

/** The list surface of an entity, as its block manifest declares it. */
export interface EntityListSurfaceDecl {
  readonly sorts: readonly string[];
  readonly facets: readonly string[];
  readonly filters: readonly string[];
  readonly search: boolean | readonly string[];
}

/** The table behind an entity, with the logical columns the page reads. */
export interface EntityPageTable {
  readonly schema: string;
  readonly name: string;
  /** The tenant column, when the table has one. */
  readonly tenant: string | undefined;
  /** Logical column to the column name in the table. */
  readonly columns: Readonly<Record<string, string>>;
}

/** An entity page with everything the outputs read, resolved once. */
export interface ResolvedEntityPage {
  readonly page: EntityPage;
  /** The file stem of the output (`risks`). */
  readonly name: string;
  readonly block: string;
  readonly entityKey: string;
  readonly surface: EntityListSurfaceDecl;
  readonly table: EntityPageTable | undefined;
  /** The input schemas of the entity's block, which the form output reads. */
  readonly schemas:
    | NonNullable<PresetCatalogManifest["entitySchemas"]>[string]
    | undefined;
  /** The expression under `db` that holds the entity's reads. */
  readonly reads: string;
}

/** One index the list of an entity page needs. */
export interface EntityPageIndex {
  readonly name: string;
  readonly table: EntityPageTable;
  /** The column of the sort, facet or search entry. */
  readonly column: string;
  /** The columns the index covers, in order. */
  readonly columns: readonly string[];
  readonly method: "btree" | "gin";
  /** The sort, facet or search entry the index serves. */
  readonly serves: string;
  readonly kind: "sort" | "facet" | "search";
}

const lastSegment = (route: string): string =>
  route.split("/").findLast((part) => part !== "") ?? "index";

/** The file stem of a page's generated files. */
export const entityPageName = (page: EntityPage): string =>
  page.name ?? lastSegment(page.route).replaceAll(/[^a-z0-9-]/g, "-");

const invalid = (message: string): CliError =>
  new CliError("config_invalid", `gen.entityPages: ${message}`);

function manifestOf(
  config: PagesConfig,
  block: string,
): PresetCatalogManifest | undefined {
  return PRESET_CATALOG.manifests.find(
    (manifest) =>
      (manifest.name === block || manifest.sql.includes(block)) &&
      manifest.sql.some((module) => config.blockNames.includes(module)),
  );
}

/** Resolves a page against its installed block, or says what is missing. */
export function resolveEntityPage(
  config: PagesConfig,
  page: EntityPage,
): ResolvedEntityPage {
  const [block = "", entityKey = ""] = page.entity.split(".");
  const manifest = manifestOf(config, block);

  if (manifest === undefined) {
    throw invalid(
      `${page.entity}: the block "${block}" is not installed. Add it to \`blocks\`.`,
    );
  }

  const declared = manifest.entityLists?.[entityKey];

  if (declared === undefined) {
    throw invalid(
      `${page.entity}: the block "${block}" declares no list for "${entityKey}" (its manifest has no sorts, facets, filters or search for it).`,
    );
  }

  const surface: EntityListSurfaceDecl = {
    sorts: declared.sorts ?? [],
    facets: declared.facets ?? [],
    filters: declared.filters ?? declared.facets ?? [],
    search: declared.search ?? false,
  };

  const module = PRESET_CATALOG.blocks.find(
    (entry) =>
      manifest.sql.includes(entry.name) &&
      entry.entities?.specs[entityKey] !== undefined,
  );

  const entity = blockEntities(module?.name ?? block, config.blocks).find(
    (each) => each.key === entityKey,
  );

  const logical = module?.entities?.specs[entityKey]?.table;

  const spec =
    logical === undefined ? undefined : module?.entities?.tables[logical];

  let table: EntityPageTable | undefined;

  if (
    module !== undefined &&
    entity?.table !== undefined &&
    spec !== undefined
  ) {
    const defaultSchema = resolveBlock(config.blocks[module.name]).schema;
    const dot = entity.table.indexOf(".");

    table = {
      schema: dot === -1 ? defaultSchema : entity.table.slice(0, dot),
      name: dot === -1 ? entity.table : entity.table.slice(dot + 1),
      tenant: spec.columns["tenant"],
      columns: spec.columns,
    };
  }

  return {
    page,
    name: entityPageName(page),
    block,
    entityKey,
    surface,
    table,
    schemas: manifest.entitySchemas?.[entityKey],
    reads: page.reads ?? camelOf(block),
  };
}

/** Every page of `gen.entityPages`, resolved; the names must be distinct. */
export function resolveEntityPages(
  config: PagesConfig,
): readonly ResolvedEntityPage[] {
  const pages = config.gen.entityPages?.pages ?? [];
  const resolved = pages.map((page) => resolveEntityPage(config, page));
  const seen = new Set<string>();

  for (const entry of resolved) {
    if (seen.has(entry.name)) {
      throw invalid(
        `two pages are named "${entry.name}"; set \`name\` on one of them.`,
      );
    }

    seen.add(entry.name);
  }

  return resolved;
}

const camel = (name: string): string =>
  name.replaceAll(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase());

/**
 * The indexes a page's list needs: a btree on `(tenant, column, id)` for each
 * sort and `(tenant, column)` for each facet that is a column of the table, and
 * a trigram index for each searched column. A name that is not a column of the
 * table (a derived sort, a facet over a join) has no index here.
 */
export function entityPageIndexes(
  resolved: ResolvedEntityPage,
): readonly EntityPageIndex[] {
  const { table, surface } = resolved;

  if (table === undefined) {
    return [];
  }

  const columnOf = (key: string): string | undefined =>
    table.columns[key] ?? table.columns[camel(key)];

  const lead = table.tenant === undefined ? [] : [table.tenant];
  const indexes = new Map<string, EntityPageIndex>();

  const nameOf = (columns: readonly string[], suffix: string): string =>
    `${table.name}_${columns.join("_")}_${suffix}`.slice(0, 63);

  const add = (
    kind: EntityPageIndex["kind"],
    serves: string,
    column: string,
    columns: readonly string[],
    method: EntityPageIndex["method"],
  ): void => {
    const name = nameOf(columns, method === "gin" ? "trgm_idx" : "page_idx");

    if (!indexes.has(name)) {
      indexes.set(name, { name, table, column, columns, method, serves, kind });
    }
  };

  for (const sort of surface.sorts) {
    const column = columnOf(sort);

    if (column !== undefined) {
      add("sort", sort, column, [...lead, column, "id"], "btree");
    }
  }

  for (const facet of surface.facets) {
    const column = columnOf(facet);

    if (column !== undefined) {
      add("facet", facet, column, [...lead, column], "btree");
    }
  }

  if (typeof surface.search === "object") {
    for (const key of surface.search) {
      const column = columnOf(key);

      if (column !== undefined) {
        add("search", key, column, [column], "gin");
      }
    }
  }

  return [...indexes.values()];
}

const quote = (name: string): string => `"${name.replaceAll('"', '""')}"`;

/**
 * The SQL of the indexes of every page: one statement per index. The
 * migration's statements are re-runnable; the schema file's declare the index
 * (`idempotent` false), because doctor flags `if not exists` in a schema file.
 */
export function entityPageIndexSql(
  config: PagesConfig,
  idempotent = true,
): string | undefined {
  const indexes = resolveEntityPages(config).flatMap((entry) =>
    entityPageIndexes(entry),
  );

  const unique = [
    ...new Map(indexes.map((index) => [index.name, index])).values(),
  ];

  if (unique.length === 0) {
    return undefined;
  }

  return [
    "-- The indexes the entity page lists need, one per declared sort, facet and",
    "-- searched column. Managed by `better-supabase gen` (gen.entityPages): it",
    "-- writes a new migration when a page or its block's list surface changes.",
    ...unique.map((index) => {
      const target = `${quote(index.table.schema)}.${quote(index.table.name)}`;

      const columns = index.columns
        .map((column) =>
          index.method === "gin"
            ? `${quote(column)} extensions.gin_trgm_ops`
            : quote(column),
        )
        .join(", ");

      return `create index ${idempotent ? "if not exists " : ""}${quote(index.name)} on ${target}${index.method === "gin" ? " using gin" : ""} (${columns});`;
    }),
    "",
  ].join("\n");
}

/** What an output of the entity page generator is given. */
export interface EntityPageContext {
  readonly config: PagesConfig;
  readonly pages: readonly ResolvedEntityPage[];
  /**
   * The `import` path of `better-supabase`, or its source when generating
   * there.
   */
  readonly runtime: string;
  /** The folder of the generated page modules, relative to the project root. */
  readonly pagesDir: string;
}

/**
 * One output of the entity page generator. Later lanes add theirs to
 * `ENTITY_PAGE_OUTPUTS` (columns, detail and forms in M2; seed, navigation,
 * route manifest, coverage and messages in M3) and read the same resolved
 * pages. A new breaking contract needs a new `apiVersion`.
 */
export interface EntityPageOutput {
  readonly apiVersion: 1;
  readonly id: string;
  render(context: EntityPageContext): readonly GeneratedFile[];
}

const listModulePath = (context: EntityPageContext, name: string): string =>
  posix.join(context.pagesDir, `${name}.list.ts`);

/** `pages/<name>.list.ts`: the list query over the entity's declared surface. */
const LIST_QUERY: EntityPageOutput = {
  apiVersion: 1,
  id: "list-query",
  render: (context) =>
    context.pages.map((entry) => {
      const { surface, page } = entry;

      const names = (list: readonly string[]): string =>
        `[${list.map(q).join(", ")}]`;

      const search =
        typeof surface.search === "boolean"
          ? String(surface.search)
          : names(surface.search);

      const options = [
        `entity: ${q(page.entity)}`,
        ...(page.list?.pageSize === undefined
          ? []
          : [`pageSize: ${String(page.list.pageSize)}`]),
        ...(page.list?.maxPageSize === undefined
          ? []
          : [`maxPageSize: ${String(page.list.maxPageSize)}`]),
      ];

      return {
        path: listModulePath(context, entry.name),
        contents: [
          GENERATED_HEADER,
          `import { defineEntityListQuery } from ${q(runtimeSubpath(context.runtime, "list"))};`,
          "",
          `/** The list query of \`${page.entity}\` (${page.route}). */`,
          `export const ${camelOf(entry.name)}List = defineEntityListQuery(`,
          "  {",
          `    sorts: ${names(surface.sorts)},`,
          `    facets: ${names(surface.facets)},`,
          `    filters: ${names(surface.filters)},`,
          `    search: ${search},`,
          "  },",
          `  { ${options.join(", ")} },`,
          ");",
          "",
        ].join("\n"),
      };
    }),
};

/** `<appDir>/api/<name>/list/route.ts`: the handler of the list query. */
const LIST_ROUTE: EntityPageOutput = {
  apiVersion: 1,
  id: "list-route",
  render(context) {
    const settings = context.config.gen.entityPages;

    const server = settings?.server ?? {
      module: "@/lib/supabase/server-core",
      export: "bsbCore",
    };

    const appDir =
      settings?.appDir ??
      (existsSync(posix.join(context.config.root, "src")) ? "src/app" : "app");

    return context.pages.map((entry) => {
      const path = posix.join(appDir, "api", entry.name, "list", "route.ts");

      const list = `${camelOf(entry.name)}List`;

      const module = posix
        .relative(posix.dirname(path), listModulePath(context, entry.name))
        .replace(/\.ts$/, "");

      return {
        path,
        contents: [
          GENERATED_HEADER,
          `import { ${list} } from ${q(module)};`,
          server.export === "bsb"
            ? `import { bsb } from ${q(server.module)};`
            : `import { ${server.export} as bsb } from ${q(server.module)};`,
          "",
          `/** \`GET /api/${entry.name}/list\`: one page of \`${entry.page.entity}\` and the count of every facet. */`,
          "export const GET = bsb.route((request, { db }) => {",
          `  const query = ${list}.parse(request.nextUrl.searchParams);`,
          "",
          "  if (!query.ok) {",
          "    return Response.json({ issues: query.issues }, { status: 400 });",
          "  }",
          "",
          `  return ${list}.run(`,
          "    {",
          `      page: (options) => db.${entry.reads}.${entry.page.methods?.page ?? "page"}(options),`,
          `      facets: (options) => db.${entry.reads}.${entry.page.methods?.facets ?? "facets"}(options),`,
          "    },",
          "    query.value,",
          "  );",
          "});",
          "",
        ].join("\n"),
      };
    });
  },
};

const lit = (value: string): string => `'${value.replaceAll("'", "''")}'`;

/**
 * `scale_list_<name>.test.sql`: asks the planner, with sequential scans
 * disabled, how it reads the page in each declared sort and how it counts each
 * facet. A sort must come out of an index with no sort step, and a facet count
 * must be an index-only scan. The rows come from the running stack's seed
 * (`pnpm db:seed:scale`).
 */
const SCALE_TEST: EntityPageOutput = {
  apiVersion: 1,
  id: "scale-test",
  render(context) {
    const directory =
      context.config.gen.entityPages?.scaleDir ?? "supabase/tests/scale";

    return context.pages.flatMap((entry): GeneratedFile[] => {
      const indexes = entityPageIndexes(entry).filter(
        (index) => index.kind !== "search",
      );

      const { table } = entry;

      if (table === undefined || indexes.length === 0) {
        return [];
      }

      const target = `${quote(table.schema)}.${quote(table.name)}`;

      const tenant =
        table.tenant === undefined ? undefined : quote(table.tenant);

      const where =
        tenant === undefined
          ? ""
          : ` where ${tenant} = '00000000-0000-4000-8000-000000000001'`;

      const queries = indexes.map((index) => {
        const column = quote(index.column);

        return {
          kind: index.kind,
          label: `${index.kind}_${index.serves}`,
          sql:
            index.kind === "sort"
              ? `select id from ${target}${where} order by ${column}, id limit 50`
              : `select ${column}, count(*) from ${target}${where} group by ${column}`,
        };
      });

      return [
        {
          path: posix.join(directory, `scale_list_${entry.name}.test.sql`),
          contents: [
            GENERATED_HEADER.replace("// ", "-- "),
            `-- Scale plan check of the list of ${entry.page.entity} (${entry.page.route}).`,
            "-- With sequential scans off, a sort must come out of an index with no sort",
            "-- step and a facet count must be an index-only scan. The rows are the",
            "-- running stack's seed; run `pnpm db:seed:scale --tier l` first to measure.",
            "begin;",
            `select plan(${String(queries.length)});`,
            "",
            "create function pg_temp.plan_of(text) returns jsonb language plpgsql as $$",
            "declare result jsonb;",
            "begin",
            "  execute 'explain (format json) ' || $1 into result;",
            "  return result;",
            "end $$;",
            "",
            `analyze ${target};`,
            "set local enable_seqscan = off;",
            "",
            ...queries.flatMap((query) => [
              `select ok(`,
              query.kind === "sort"
                ? `  pg_temp.plan_of(${lit(query.sql)})::text !~ '"Node Type": "(Incremental )?Sort"',`
                : `  pg_temp.plan_of(${lit(query.sql)})::text ~ '"Node Type": "Index Only Scan"',`,
              `  ${lit(`${entry.page.entity} ${query.label} ${query.kind === "sort" ? "needs no sort step" : "is an index-only scan"}`)}`,
              ");",
              "",
            ]),
            "select * from finish();",
            "rollback;",
            "",
          ].join("\n"),
        },
      ];
    });
  },
};

/**
 * The outputs the generator runs, in order. Lane M2 added columns, detail and
 * forms, M3 seed, navigation and the route manifest; M4 appends its own.
 */
export const ENTITY_PAGE_OUTPUTS: readonly EntityPageOutput[] = [
  LIST_QUERY,
  LIST_ROUTE,
  SCALE_TEST,
  COLUMNS_OUTPUT,
  DETAIL_OUTPUT,
  FORM_OUTPUT,
  SEED_OUTPUT,
  NAVIGATION_OUTPUT,
  MANIFEST_OUTPUT,
];

/** Every file the entity pages generate, or none without `gen.entityPages`. */
export function emitEntityPages(
  config: PagesConfig,
  runtime: string,
): readonly GeneratedFile[] {
  const pages = resolveEntityPages(config);

  if (pages.length === 0) {
    return [];
  }

  const context: EntityPageContext = {
    config,
    pages,
    runtime,
    pagesDir: posix.join(posix.dirname(config.output), "pages"),
  };

  const indexes = entityPageIndexSql(config, false);

  // The schema folder is the source of truth: `supabase:diff` drops an index
  // the migration creates when no schema file declares it.
  const schemaIndexes: GeneratedFile[] =
    indexes === undefined
      ? []
      : [
          {
            path: posix.join(
              config.sql.dir.replace(/\/$/, ""),
              ENTITY_PAGE_INDEXES_SCHEMA_FILE,
            ),
            contents: indexes,
          },
        ];

  return [
    ...ENTITY_PAGE_OUTPUTS.flatMap((output) => output.render(context)),
    ...schemaIndexes,
  ];
}
