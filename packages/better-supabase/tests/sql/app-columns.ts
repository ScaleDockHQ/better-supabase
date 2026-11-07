import type { BlockSqlFile, BlockSqlLayout } from "../../src/sql/index.ts";

import { resolveBlocks } from "../../src/sql/index.ts";
import {
  LEGACY_OPTION,
  legacyOptionTarget,
} from "../../src/sql/legacy-options.ts";
import { moduleContext } from "../../src/sql/module-context.ts";
import {
  moduleBody as body,
  renderBlocks as render,
} from "../../src/sql/render.ts";

/**
 * A layout where the `extraColumns` options of `modules[module].options` are
 * columns an app schema file adds to the block's table: the options leave the
 * module config and become `appColumns`, which is how the block reads them as
 * fields now.
 */
export function withAppColumns(
  module: string,
  options: Readonly<Record<string, unknown>> = {},
  layout: BlockSqlLayout = {},
  needs: readonly string[] = [],
): BlockSqlLayout {
  const rest = Object.fromEntries(
    Object.entries(options).filter(([key]) => !LEGACY_OPTION.test(key)),
  );

  const base: BlockSqlLayout = {
    ...layout,
    modules: {
      ...layout.modules,
      [module]: { ...layout.modules?.[module], options: rest },
    },
  };

  const names = resolveBlocks([...needs, module], base).map(
    (each) => each.name,
  );

  const ctx = moduleContext(module, base, names);
  const appColumns: Record<string, { name: string; type: string }[]> = {};

  for (const [key, value] of Object.entries(options)) {
    const target = LEGACY_OPTION.test(key)
      ? legacyOptionTarget(
          module,
          key,
          base.modules?.[module]?.tables,
          (logical) => ctx.tableName(logical),
        )
      : undefined;

    if (target === undefined || typeof value !== "object" || value === null) {
      continue;
    }

    const at = target.table;

    appColumns[at] = [
      ...(appColumns[at] ?? []),
      ...Object.entries(value).map(([column, type]) => ({
        name: column,
        type: String(type),
      })),
    ];
  }

  return Object.keys(appColumns).length === 0
    ? base
    : { ...base, appColumns: { ...layout.appColumns, ...appColumns } };
}

/** `text` with `statements` after the `create table` of `table`, if it has one. */
function afterCreate(
  text: string,
  table: string,
  statements: string,
): string | undefined {
  const [schema, name] = table.split(".");

  const create = new RegExp(
    String.raw`create table (?:if not exists )?"?${schema}"?\."?${name}"? \(`,
  ).exec(text);

  if (create === null) {
    return undefined;
  }

  let depth = 1;
  let at = create.index + create[0].length;

  for (; depth > 0 && at < text.length; at += 1) {
    depth += text[at] === "(" ? 1 : text[at] === ")" ? -1 : 0;
  }

  const end = text.indexOf(";", at) + 1;

  return `${text.slice(0, end)}\n${statements}${text.slice(end)}`;
}

/**
 * `renderBlocks` for a layout whose module options still carry `extraColumns`
 * entries: each becomes a column the app's files add, as in `withAppColumns`,
 * and an `alter table ... add column` after the block's `create table` stands
 * for the app file that adds it.
 */
export function renderBlocks(
  names: readonly string[],
  layout: BlockSqlLayout = {},
): BlockSqlFile[] {
  let converted = layout;

  for (const [module, block] of Object.entries(layout.modules ?? {})) {
    const options: Readonly<Record<string, unknown>> = block?.options ?? {};

    if (Object.keys(options).some((key) => LEGACY_OPTION.test(key))) {
      converted = withAppColumns(module, options, converted, names);
    }
  }

  const files = render(names, converted);

  return Object.entries(converted.appColumns ?? {}).reduce(
    (all, [table, columns]) => {
      if (layout.appColumns?.[table] !== undefined) {
        return all;
      }

      const target = table
        .split(".")
        .map((part) => `"${part}"`)
        .join(".");

      const statements = columns
        .map(
          (column) =>
            `alter table ${target} add column "${column.name}" ${column.type};\n`,
        )
        .join("");

      let placed = false;

      return all.map((file) => {
        const text = placed
          ? undefined
          : afterCreate(file.contents, table, statements);

        if (text === undefined) {
          return file;
        }

        placed = true;

        return { ...file, contents: text };
      });
    },
    files,
  );
}

/** `moduleBody` for a layout whose module options still carry `extraColumns`. */
export function moduleBody(
  name: string,
  layout: BlockSqlLayout = {},
): string | undefined {
  const options: Readonly<Record<string, unknown>> =
    layout.modules?.[name]?.options ?? {};

  if (!Object.keys(options).some((key) => LEGACY_OPTION.test(key))) {
    return body(name, layout);
  }

  const converted = withAppColumns(name, options, layout, [name]);
  let text = body(name, converted);

  for (const [table, columns] of Object.entries(converted.appColumns ?? {})) {
    const target = table
      .split(".")
      .map((part) => `"${part}"`)
      .join(".");

    const statements = columns
      .map(
        (column) =>
          `alter table ${target} add column "${column.name}" ${column.type};\n`,
      )
      .join("");

    text =
      text === undefined
        ? text
        : (afterCreate(text, table, statements) ?? text);
  }

  return text;
}
