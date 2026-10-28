/**
 * Proposes a block entry over tables the app already has: each logical table
 * the app's table can stand in for gets an existing table, and each logical
 * column the column that most likely holds it. The proposal is checked the way
 * `upgrade` and doctor check a config, so what can't map is reported before
 * anything is written.
 */

import type {
  AnyBlocksConfig,
  BlockConfig,
  SubjectsConfig,
} from "../../config/index.ts";
import type { BlockSqlLayout } from "../../sql/index.ts";
import type { CatalogTable } from "../introspect/types.ts";

import { toSnake } from "../../index.ts";
import {
  adoptedColumnProblems,
  migrationOptionUses,
  moduleBody,
  moduleIdType,
  moduleWritesText,
  SQL_MODULES,
} from "../../sql/index.ts";

/** The part of an introspected table a proposal reads. */
export interface ExistingTable {
  readonly schema: string;
  readonly name: string;
  /** A view or materialized view takes no columns from the block. */
  readonly kind?: "table" | "view";
  /** Whether Postgres writes through the view to its table. */
  readonly updatable?: boolean;
  readonly columns: readonly {
    readonly name: string;
    readonly udt: string;
    readonly isEnum?: boolean;
    readonly typeSchema?: string;
  }[];
  readonly policies?: readonly {
    readonly name: string;
    readonly permissive: boolean;
  }[];
}

/** How a logical column found its physical column. */
export type ColumnMatch =
  | {
      readonly logical: string;
      readonly column: string;
      readonly by: "name" | "alias";
    }
  | { readonly logical: string; readonly column: null; readonly by: "missing" }
  | {
      readonly logical: string;
      readonly column: null;
      readonly by: "added";
      /** The column the block's migration adds. */
      readonly adds: string;
    };

/** One logical table of the module and the existing table it maps to. */
export interface TableMatch {
  readonly logical: string;
  /** `schema.table`, or `null` for an optional table the app doesn't have. */
  readonly table: string | null;
  readonly columns: readonly ColumnMatch[];
}

export interface AdoptProposal {
  readonly block: string;
  /** The `blocks.<block>` entry to write. */
  readonly entry: BlockConfig;
  readonly tables: readonly TableMatch[];
  /** What keeps the entry from working; nothing is written while there are any. */
  readonly errors: readonly string[];
  /** What works but departs from the managed block, as doctor reports it. */
  readonly warnings: readonly string[];
}

/**
 * Other names apps give a logical column. They are tried after the module's
 * default name and the logical name in snake case.
 */
const ALIASES: Readonly<Record<string, readonly string[]>> = {
  tenant: [
    "organization_id",
    "org_id",
    "tenant_id",
    "workspace_id",
    "account_id",
    "company_id",
  ],
  user: ["user_id", "profile_id", "owner_id", "member_id"],
  createdBy: ["created_by", "author_id", "creator_id", "owner_id"],
  rank: ["position", "sort_order", "sort_key", "order_index"],
  key: ["id", "user_id"],
  note: ["notes", "note"],
};

/** Whether the app's table can stand in for one of the block's tables. */
const overAppTables = (block: string): boolean =>
  Object.values(SQL_MODULES[block]?.names?.tables ?? {}).some(
    (table) => table.app !== undefined,
  );

/** The blocks with a table the app's table can stand in for, in registry order. */
export function adoptableBlocks(): readonly string[] {
  return Object.values(SQL_MODULES)
    .filter((module) => overAppTables(module.name))
    .map((module) => module.name);
}

/**
 * `schema.table` from `table` or `schema.table`; an unqualified name is in
 * `public`.
 */
export function qualifiedName(name: string): string {
  return name.includes(".") ? name : `public.${name}`;
}

/** The introspected tables in the shape a proposal reads. */
export function existingTables(
  tables: readonly CatalogTable[],
): readonly ExistingTable[] {
  return tables;
}

function candidates(logical: string, physical: string): readonly string[] {
  const snake = toSnake(logical);
  const singular = physical.endsWith("s") ? physical.slice(0, -1) : undefined;

  return [
    physical,
    snake,
    `${snake}_id`,
    `${physical}s`,
    ...(singular === undefined ? [] : [singular]),
    ...(ALIASES[logical] ?? []),
  ];
}

/** The logical columns of `logical` matched to the columns of `table`. */
function matchColumns(
  spec: {
    readonly columns: Readonly<Record<string, string>>;
    readonly optional?: readonly string[];
  },
  table: ExistingTable,
): readonly ColumnMatch[] {
  const names = new Set(table.columns.map((column) => column.name));
  const used = new Set<string>();
  const matches: ColumnMatch[] = [];

  // Exact names first, so an alias never takes a column another logical column names.
  for (const physical of Object.values(spec.columns)) {
    if (names.has(physical)) {
      used.add(physical);
    }
  }

  for (const [logical, physical] of Object.entries(spec.columns)) {
    if (names.has(physical)) {
      matches.push({ logical, column: physical, by: "name" });
      continue;
    }

    const found =
      candidates(logical, physical).find(
        (name) => names.has(name) && !used.has(name),
      ) ??
      unique(
        table.columns
          .map((column) => column.name)
          .filter((name) => name.endsWith(`_${physical}`) && !used.has(name)),
      );

    if (found === undefined) {
      matches.push(
        spec.optional?.includes(logical) === true
          ? { logical, column: null, by: "missing" }
          : { logical, column: null, by: "added", adds: physical },
      );
    } else {
      used.add(found);
      matches.push({ logical, column: found, by: "alias" });
    }
  }

  return matches;
}

const unique = (names: readonly string[]): string | undefined =>
  names.length === 1 ? names[0] : undefined;

/**
 * The share of logical columns a table matches, so a wide table doesn't win on
 * size.
 */
const score = (matches: readonly ColumnMatch[]): number =>
  matches.length === 0
    ? 0
    : matches.filter((match) => match.column !== null).length / matches.length;

/**
 * The table each logical table of `block` maps to: the tables in `from` go to
 * the logical tables whose columns they match best, and the rest are looked up
 * by the module's default names in `schemas`.
 */
function matchTables(
  block: string,
  tables: readonly ExistingTable[],
  from: readonly string[],
  schemas: readonly string[],
  errors: string[],
): Map<string, ExistingTable | null> {
  const spec = Object.fromEntries(
    Object.entries(SQL_MODULES[block]?.names?.tables ?? {}).filter(
      ([, table]) => table.app !== undefined,
    ),
  );

  const byName = new Map(
    tables.map((table) => [`${table.schema}.${table.name}`, table]),
  );

  const chosen = new Map<string, ExistingTable | null>();

  for (const name of from) {
    const table = byName.get(qualifiedName(name));

    if (table === undefined) {
      errors.push(
        `${qualifiedName(name)} is not a table or view in the database.`,
      );
      continue;
    }

    const open = Object.entries(spec).filter(
      ([logical]) => !chosen.has(logical),
    );

    // A table under the logical table's default name wins over any column match.
    const best = open
      .map(([logical, names]) => ({
        logical,
        score:
          score(matchColumns(names, table)) +
          (table.name === names.name ? 1 : 0),
      }))
      .toSorted((left, right) => right.score - left.score)[0];

    if (best === undefined || best.score === 0) {
      errors.push(
        `${qualifiedName(name)} matches none of the ${block} tables (${Object.keys(spec).join(", ")}).`,
      );
      continue;
    }

    chosen.set(best.logical, table);
  }

  for (const [logical, table] of Object.entries(spec)) {
    if (chosen.has(logical) || table.app?.onlyWhenMapped === true) {
      continue;
    }

    const found = schemas
      .map((schema) => byName.get(`${schema}.${table.name}`))
      .find((match) => match !== undefined);

    if (found !== undefined) {
      chosen.set(logical, found);
    } else if (table.optionalTable === true) {
      chosen.set(logical, null);
    }
  }

  if (chosen.size === 0) {
    errors.push(
      `None of the ${block} tables (${Object.values(spec)
        .map((table) => table.name)
        .join(", ")}) is in the database. Pass yours with --tables.`,
    );
  }

  return chosen;
}

const enumType = (column: ExistingTable["columns"][number]): string =>
  `"${column.typeSchema ?? "public"}"."${column.udt}"`;

/**
 * A `create table` per table of the app's, with its enum types, for
 * `adoptedColumnProblems`.
 */
const declaration = (table: ExistingTable): string =>
  [
    ...table.columns
      .filter((column) => column.isEnum === true)
      .map((column) => `create type ${enumType(column)} as enum ();`),
    `create table ${table.schema}.${table.name} (\n${table.columns.map((column) => `  "${column.name}" ${column.isEnum === true ? enumType(column) : column.udt}`).join(",\n")}\n);`,
  ].join("\n");

export interface ProposeOptions {
  /** Tables named with `--tables`, as `table` or `schema.table`. */
  readonly from?: readonly string[];
  /** The config's blocks, so the proposal is checked next to them. */
  readonly blocks?: AnyBlocksConfig;
  /** `config.subjects`, which a block's `on` entries inherit from. */
  readonly subjects?: SubjectsConfig;
  readonly accessProvider?: BlockSqlLayout["accessProvider"];
  /**
   * Schemas searched for the module's default table names. Defaults to
   * `public`.
   */
  readonly schemas?: readonly string[];
}

/** The entry for `block` over the app's `tables`, and what can't map. */
export function proposeAdoption(
  block: string,
  tables: readonly ExistingTable[],
  options: ProposeOptions = {},
): AdoptProposal {
  const module = SQL_MODULES[block];

  if (module === undefined || !overAppTables(block)) {
    return {
      block,
      entry: {},
      tables: [],
      errors: [
        module === undefined
          ? `${block} is not a block. See \`better-supabase blocks list\`.`
          : `${block} creates all its tables. Blocks that can run over yours: ${adoptableBlocks().join(", ")}.`,
      ],
      warnings: [],
    };
  }

  const errors: string[] = [];
  const warnings: string[] = [];
  const spec = module.names?.tables ?? {};

  const chosen = matchTables(
    block,
    tables,
    options.from ?? [],
    options.schemas ?? ["public"],
    errors,
  );

  const matched: TableMatch[] = [];
  const entryTables: Record<string, string | null> = {};
  const entryColumns: Record<string, Record<string, string | null>> = {};
  let idType: string | undefined;

  for (const [logical, table] of Object.entries(spec)) {
    if (!chosen.has(logical)) {
      continue;
    }

    const existing = chosen.get(logical) ?? null;

    if (existing === null) {
      entryTables[logical] = null;
      matched.push({ logical, table: null, columns: [] });
      continue;
    }

    const name = `${existing.schema}.${existing.name}`;
    entryTables[logical] = name;
    const columns = matchColumns(table, existing);
    matched.push({ logical, table: name, columns });
    const mapped: Record<string, string | null> = {};

    for (const match of columns) {
      if (match.column === null) {
        if (table.optional?.includes(match.logical) === true) {
          mapped[match.logical] = null;
        } else if (existing.kind === "view") {
          errors.push(
            `${name} is a view with no column for ${logical}.${match.logical}, and the block can't add one to a view. Add ${table.columns[match.logical]} to the view, or map blocks.${block}.columns.${logical}.${match.logical} to the column that holds it.`,
          );
        } else {
          warnings.push(
            `${name} has no column for ${logical}.${match.logical}, so the block's migration adds ${table.columns[match.logical]}. Map blocks.${block}.columns.${logical}.${match.logical} instead when another column holds it.`,
          );
        }

        continue;
      }

      const enumColumn =
        table.optional?.includes(match.logical) === true &&
        moduleWritesText(block, logical, match.logical)
          ? existing.columns.find(
              (column) =>
                column.name === match.column && column.isEnum === true,
            )
          : undefined;

      if (enumColumn !== undefined) {
        mapped[match.logical] = null;
        warnings.push(
          `${name}.${match.column} is an enum, and the block writes text into ${logical}.${match.logical}, so it leaves that column unmapped. Change ${match.column} to text with a check constraint, then map blocks.${block}.columns.${logical}.${match.logical} to it.`,
        );
        continue;
      }

      if (match.column !== table.columns[match.logical]) {
        mapped[match.logical] = match.column;
      }

      if (match.logical === "tenant" && idType === undefined) {
        const udt = existing.columns.find(
          (column) => column.name === match.column,
        )?.udt;

        const type = udt === undefined ? undefined : moduleIdType(udt);

        if (type !== undefined && type !== "uuid") {
          idType = type;
        }
      }
    }

    if (Object.keys(mapped).length > 0) {
      entryColumns[logical] = mapped;
    }
  }

  const current = options.blocks?.[block];

  const governed =
    current?.ownTablePolicies === undefined
      ? [...chosen.values()]
          .filter(
            (table): table is ExistingTable =>
              table !== null &&
              (table.policies ?? []).some(
                (policy) =>
                  policy.permissive && !policy.name.startsWith("bsb_"),
              ),
          )
          .map((table) => `${table.schema}.${table.name}`)
      : [];

  if (governed.length > 0) {
    warnings.push(
      `${governed.join(", ")} already ${governed.length === 1 ? "has" : "have"} permissive policies of your own. To keep the block's bsb_ policies off ${governed.length === 1 ? "it" : "them"}, set blocks.${block}.ownTablePolicies: "app"; otherwise the block adds a policy for each command yours don't cover, and doctor (BS347) reports one that is wider than yours.`,
    );
  }

  const entry: BlockConfig = {
    ...current,
    tables: entryTables,
    ...(Object.keys(entryColumns).length > 0 ? { columns: entryColumns } : {}),
    ...(idType === undefined || current?.idType !== undefined
      ? {}
      : { idType }),
  };

  if (errors.length === 0) {
    const blocks = { ...options.blocks, [block]: entry };

    const adopted = [...chosen.values()].filter(
      (table): table is ExistingTable => table !== null,
    );

    const ownTables = Object.fromEntries(
      tables.map((table) => [`${table.schema}.${table.name}`, "database"]),
    );

    const ownViews = Object.fromEntries(
      tables
        .filter((table) => table.kind === "view")
        .map((table) => [
          `${table.schema}.${table.name}`,
          { updatable: table.updatable === true },
        ]),
    );

    const ownColumns = Object.fromEntries(
      tables.map((table) => [
        `${table.schema}.${table.name}`,
        table.columns.map((column) => column.name),
      ]),
    );

    try {
      // Renders the block over these tables, which throws on what it refuses.
      moduleBody(block, {
        modules: blocks,
        ownTables,
        ownViews,
        ownColumns,
        ...(options.subjects === undefined
          ? {}
          : { subjects: options.subjects }),
        ...(options.accessProvider === undefined
          ? {}
          : { accessProvider: options.accessProvider }),
      });

      errors.push(
        ...adoptedColumnProblems(
          blocks,
          adopted.map((table) => ({ text: declaration(table) })),
          [...new Set(adopted.map((table) => table.schema))],
          ownTables,
          options.subjects,
          options.accessProvider,
        ),
      );
    } catch (error) {
      errors.push(error instanceof Error ? error.message : String(error));
    }

    warnings.push(
      ...migrationOptionUses({ [block]: entry }).map((use) => use.message),
    );
  }

  return { block, entry, tables: matched, errors, warnings };
}

/**
 * Whether one of `block`'s logical tables has an existing table under its
 * default name, so `apply --adopt` proposes adopting the block.
 */
export function hasDefaultTable(
  block: string,
  tables: readonly ExistingTable[],
  schemas: readonly string[] = ["public"],
): boolean {
  const names = new Set(
    Object.values(SQL_MODULES[block]?.names?.tables ?? {}).map(
      (table) => table.name,
    ),
  );

  return tables.some(
    (table) => names.has(table.name) && schemas.includes(table.schema),
  );
}

/** The proposal as lines: each table and column, then the errors and warnings. */
export function describeProposal(proposal: AdoptProposal): string[] {
  const lines: string[] = [];

  for (const table of proposal.tables) {
    lines.push(`  ${table.logical}: ${table.table ?? "null (not in the app)"}`);
    const width = Math.max(0, ...table.columns.map((c) => c.logical.length));

    for (const column of table.columns) {
      const target =
        column.by === "added"
          ? `${column.adds} (the block adds it)`
          : column.column === null
            ? "null (not in the table)"
            : column.by === "alias"
              ? `${column.column} (guessed)`
              : column.column;

      lines.push(`    ${column.logical.padEnd(width)}  ${target}`);
    }
  }

  for (const error of proposal.errors) {
    lines.push(`  error  ${error}`);
  }

  for (const warning of proposal.warnings) {
    lines.push(`  warn   ${warning}`);
  }

  return lines;
}
