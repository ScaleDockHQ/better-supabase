import type { EntityColumn } from "better-supabase/list";

import type { BlockColumn } from "./block-list-view";

type ColumnKind = BlockColumn["kind"];

const KINDS: Readonly<Record<EntityColumn["kind"], ColumnKind>> = {
  text: "text",
  number: "number",
  boolean: "badge",
  date: "muted",
  datetime: "muted",
  uuid: "muted",
  enum: "badge",
  json: "text",
};

/**
 * The overview columns of an entity page, from the column descriptors `gen`
 * writes (`<name>Columns`). The descriptor gives the key and the cell kind; the
 * page gives the translated header, the link column and the cell details a
 * descriptor cannot know (tones, labels, widths). A column the page lists in
 * `extra` but the descriptor lacks (a computed value) is placed by `order`.
 */
export function generatedBlockColumns({
  columns,
  header,
  link,
  order,
  overrides = {},
  extra = [],
}: {
  columns: readonly EntityColumn[];
  /** The translated header of a generated column. */
  header: (column: EntityColumn) => string;
  /** The column that links to the record, with its path (`{id}` is the id). */
  link: { readonly key: string; readonly href: string };
  /** The keys in display order; defaults to the descriptors, then `extra`. */
  order?: readonly string[];
  overrides?: Readonly<Record<string, Partial<BlockColumn>>>;
  extra?: readonly BlockColumn[];
}): BlockColumn[] {
  const generated = columns.map((column): BlockColumn => {
    const base: BlockColumn =
      column.key === link.key
        ? { key: column.key, header: header(column), kind: "link", href: link.href }
        : { key: column.key, header: header(column), kind: KINDS[column.kind] };

    return { ...base, ...overrides[column.key] };
  });

  const all = [...generated, ...extra];

  if (order === undefined) {
    return all;
  }

  const byKey = new Map(all.map((column) => [column.key, column]));

  return order.flatMap((key) => {
    const column = byKey.get(key);

    return column === undefined ? [] : [column];
  });
}
