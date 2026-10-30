import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { blockFileState } from "../../src/sql/markers.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { ownTablesOf } from "../fixtures/own-tables.ts";

// Refactors of the module builders keep every file here byte-identical; an
// intended change to the SQL goes in its own commit with the golden diff.

const NAMES = Object.keys(SQL_MODULES);

interface Variant {
  readonly name: string;
  readonly applies: (module: string) => boolean;
  readonly modules: (module: string) => readonly string[];
  readonly layout: (module: string) => BlockSqlLayout;
  /** `modules` and `layout` ignore the module, so one render serves them all. */
  readonly shared?: true;
}

const VARIANTS: readonly Variant[] = [
  {
    name: "alone",
    applies: () => true,
    modules: (module) => [module],
    layout: () => ({}),
  },
  {
    name: "with every module",
    applies: (module) => module !== "pgtap",
    modules: () => NAMES.filter((name) => name !== "pgtap"),
    layout: () => ({ modules: { usage: { options: { history: true } } } }),
    shared: true,
  },
  {
    name: "schema app_private",
    applies: () => true,
    modules: (module) => [module],
    layout: (module) => ({ modules: { [module]: { schema: "app_private" } } }),
  },
  {
    name: "api schema",
    applies: () => true,
    modules: (module) => [module],
    layout: (module) => ({ modules: { [module]: { api: "api" } } }),
  },
  {
    name: "over the app's tables",
    applies: (module) =>
      Object.values(SQL_MODULES[module]?.names?.tables ?? {}).some(
        (table) => table.app !== undefined,
      ),
    modules: (module) => [module],
    layout: (module) => {
      const modules = { [module]: { ...OVER_APP_OPTIONS[module] } };

      return { modules, ownTables: ownTablesOf(modules, [module]) };
    },
  },
  {
    name: "tenant column renamed",
    applies: (module) =>
      !KEEPS_TENANT.has(module) &&
      Object.keys(tenantColumns(module)).length > 0,
    modules: (module) => [module],
    layout: () => ({
      modules: Object.fromEntries(
        NAMES.filter((name) => !KEEPS_TENANT.has(name)).map((name) => [
          name,
          { columns: tenantColumns(name) },
        ]),
      ),
    }),
  },
];

/** Modules that refuse a renamed column on a table they create or keep in Vault. */
const KEEPS_TENANT: ReadonlySet<string> = new Set([
  "credentials",
  "webhook-inbox",
  "webhooks-in",
]);

/**
 * `columns` renaming the tenant column of each of the module's tables to
 * `org_id`.
 */
function tenantColumns(module: string): Record<string, { tenant: string }> {
  return Object.fromEntries(
    Object.entries(SQL_MODULES[module]?.names?.tables ?? {})
      .filter(([, table]) => "tenant" in table.columns)
      .map(([name]) => [name, { tenant: "org_id" }]),
  );
}

/** Options a module refuses to render over the app's tables without. */
const OVER_APP_OPTIONS: Record<string, { options: Record<string, unknown> }> = {
  "webhooks-out": { options: { defaultFormat: "standard" } },
};

type Rendered = ReturnType<typeof renderBlocks> | { readonly error: unknown };

const RENDERS = new Map<string, Rendered>();

function filesOf(variant: Variant, module: string): Rendered {
  const key = variant.shared ? variant.name : `${variant.name}\u0000${module}`;

  let rendered = RENDERS.get(key);

  if (rendered === undefined) {
    try {
      rendered = renderBlocks(variant.modules(module), variant.layout(module));
    } catch (error) {
      rendered = { error };
    }

    RENDERS.set(key, rendered);
  }

  return rendered;
}

const EVERY_MODULE = NAMES.filter((name) => name !== "pgtap");

let everyModule: ReturnType<typeof renderBlocks> | undefined;

function renderEveryModule(): ReturnType<typeof renderBlocks> {
  everyModule ??= renderBlocks(EVERY_MODULE, {});

  return everyModule;
}

function render(variant: Variant, module: string): string {
  const files = filesOf(variant, module);

  if ("error" in files) {
    const cause = files.error;

    return `-- ==== ${variant.name}: throws\n-- ${String(cause instanceof Error ? cause.message : cause)}\n`;
  }

  return files
    .filter((file) => file.module === module)
    .map(
      (file) =>
        `-- ==== ${variant.name}: ${file.kind} ${file.path}\n${file.contents}`,
    )
    .join("\n");
}

describe("SQL module output", () => {
  it.each(NAMES)("%s renders the golden SQL", async (module) => {
    const out = VARIANTS.filter((variant) => variant.applies(module))
      .map((variant) => render(variant, module))
      .join("\n");

    await expect(out).toMatchFileSnapshot(`__golden__/${module}.sql`);
  });

  it("renders the same files whatever order the modules come in", () => {
    const forward = renderEveryModule();

    const reversed = new Map(
      renderBlocks(EVERY_MODULE.toReversed(), {}).map((file) => [
        file.path,
        file.contents,
      ]),
    );

    expect(
      forward
        .filter((file) => reversed.get(file.path) !== file.contents)
        .map((file) => file.path),
    ).toEqual([]);
  });

  it("stamps every file with the hash of its own body", () => {
    const each = VARIANTS.filter(
      (variant) => variant.name !== "with every module",
    ).flatMap((variant) =>
      NAMES.filter((module) => variant.applies(module)).flatMap((module) => {
        const files = filesOf(variant, module);

        return "error" in files ? [] : files;
      }),
    );

    const pathsByBody = new Map<string, Set<string>>();

    for (const file of [...each, ...renderEveryModule()]) {
      const paths = pathsByBody.get(file.contents) ?? new Set<string>();

      paths.add(file.path);
      pathsByBody.set(file.contents, paths);
    }

    expect(
      [...pathsByBody]
        .filter(([body]) => blockFileState(body) !== "clean")
        .flatMap(([, paths]) => [...paths]),
    ).toEqual([]);
  });

  it("names no tenant_id column once every tenant column is renamed", () => {
    const variant = VARIANTS.find(
      (each) => each.name === "tenant column renamed",
    );

    const left = NAMES.filter((module) => variant?.applies(module)).flatMap(
      (module) => {
        const files = variant === undefined ? [] : filesOf(variant, module);

        return "error" in files
          ? [`${module}: ${String(files.error)}`]
          : files
              .filter((file) => file.module === module)
              .flatMap((file) =>
                file.contents
                  .split("\n")
                  .map((line) =>
                    line.replace(COMMENT, "").replaceAll(LITERAL, "''"),
                  )
                  .filter((line) => TENANT_ID.test(line))
                  .map((line) => `${module}: ${line.trim()}`),
              );
      },
    );

    expect(left).toEqual([]);
  });

  it("gives every table one owning module", () => {
    const owners = new Map<string, Set<string>>();

    for (const file of renderEveryModule()) {
      for (const match of file.contents.matchAll(CREATE_TABLE)) {
        const table = (match[1] ?? "").replaceAll('"', "");
        const modules = owners.get(table) ?? new Set<string>();
        modules.add(file.module);
        owners.set(table, modules);
      }
    }

    const shared = [...owners]
      .filter(([table, modules]) => modules.size > 1 && table !== REGISTRY)
      .map(([table, modules]) => `${table}: ${[...modules].join(", ")}`);

    expect(shared).toEqual([]);
  });
});

const COMMENT = /--.*$/u;
const LITERAL = /'(?:[^']|'')*'/gu;
const TENANT_ID = /\btenant_id\b/u;

const CREATE_TABLE = /create table (?:if not exists )?("?\w+"?\."?\w+"?)/giu;

/** The modules registry every module writes its row to. */
const REGISTRY = "better_supabase.blocks";
