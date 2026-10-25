import type { AnyBlocksConfig } from "../config/blocks.ts";
import type { BlockSqlNames } from "./context.ts";
import type { BlockSqlLayout } from "./module-types.ts";

import { createModuleContext } from "./context.ts";

/** A column a block needs that the app's view at its table's name lacks. */
export interface MissingViewColumn {
  readonly block: string;
  /** The view, as `schema.view`. */
  readonly view: string;
  /** The column the block reads, as the view would name it. */
  readonly column: string;
}

export interface ViewColumns {
  /** `modules` with the optional columns the views lack mapped to `null`. */
  readonly modules: AnyBlocksConfig | undefined;
  /** The required columns the views lack. */
  readonly missing: readonly MissingViewColumn[];
}

type ColumnMap = Readonly<
  Record<string, Readonly<Record<string, string | null>>>
>;

const cache = new WeakMap<BlockSqlLayout, WeakMap<object, ViewColumns>>();

/**
 * The columns of the app's views that a block reads. A view can't take the
 * columns a block would add to a table, so each optional column (`optional` in
 * the table's spec) a view lacks counts as mapped to `null`, unless the config
 * maps it; any other column a view lacks is in `missing`. Views whose columns
 * aren't known are left alone.
 */
export function viewColumns(
  layout: BlockSqlLayout,
  modules: AnyBlocksConfig | undefined,
  namesOf: (module: string) => BlockSqlNames | undefined,
): ViewColumns {
  const views = layout.ownViews;

  if (
    modules === undefined ||
    views === undefined ||
    Object.keys(views).length === 0
  ) {
    return { modules, missing: [] };
  }

  const known = cache.get(layout)?.get(modules);

  if (known !== undefined) {
    return known;
  }

  const out: Record<string, AnyBlocksConfig[string]> = { ...modules };
  const missing: MissingViewColumn[] = [];

  for (const [block, config] of Object.entries(modules)) {
    const names = namesOf(block);

    if (
      config === undefined ||
      names === undefined ||
      !Object.values(names.tables).some((spec) => spec.app !== undefined)
    ) {
      continue;
    }

    const ctx = createModuleContext(block, namesOf, {
      modules,
      ...(layout.ownTables ? { ownTables: layout.ownTables } : {}),
      ownViews: views,
    });

    // SAFETY: a block config's `columns` maps logical tables to logical columns.
    const configured = (config.columns ?? {}) as ColumnMap;
    const columns: Record<string, Record<string, string | null>> = {};

    for (const logical of ctx.appViews) {
      const parts = ctx.tableName(logical);
      const view = `${parts.schema}.${parts.name}`;
      const has = layout.ownColumns?.[view];
      const spec = names.tables[logical]!;

      if (has === undefined || spec.app === undefined) {
        continue;
      }

      const unused = new Set(spec.app.unused?.(ctx));

      for (const column of Object.keys(spec.columns)) {
        if (unused.has(column) || !ctx.has(logical, column)) {
          continue;
        }

        const physical = ctx.colName(logical, column);

        if (has.includes(physical)) {
          continue;
        }

        if (
          spec.optional?.includes(column) === true &&
          configured[logical]?.[column] === undefined
        ) {
          columns[logical] = { ...columns[logical], [column]: null };
        } else {
          missing.push({ block, view, column: physical });
        }
      }
    }

    if (Object.keys(columns).length > 0) {
      out[block] = {
        ...config,
        columns: Object.fromEntries(
          [
            ...new Set([...Object.keys(configured), ...Object.keys(columns)]),
          ].map((logical) => [
            logical,
            { ...configured[logical], ...columns[logical] },
          ]),
        ),
      };
    }
  }

  const result = {
    modules: Object.keys(out).some((block) => out[block] !== modules[block])
      ? out
      : modules,
    missing,
  };

  const byModules = cache.get(layout) ?? new WeakMap<object, ViewColumns>();

  byModules.set(modules, result);
  cache.set(layout, byModules);

  return result;
}

/**
 * Throws when a view of the app's at a block table's name lacks a column the
 * block needs, naming the view and the column.
 */
export function assertViewColumns(missing: readonly MissingViewColumn[]): void {
  const first = missing[0];

  if (first === undefined) {
    return;
  }

  throw new TypeError(
    [
      ...missing.map(
        (each) =>
          `blocks.${each.block} reads ${each.view}.${each.column}, which the view doesn't have.`,
      ),
      "Add the column to the view, or map it in blocks.<name>.columns to one the view has.",
    ].join("\n"),
  );
}
