import type { AppColumn, AppTable, Design } from "./design.ts";

import { singular } from "./design.ts";

/** One sample row: column name to the text the grid shows, or `null`. */
export type SampleRow = Readonly<Record<string, string | null>>;

export interface SampleTable {
  readonly columns: readonly string[];
  readonly rows: readonly SampleRow[];
}

export const SAMPLE_ROW_COUNT = 8;

const USERS = "auth.users";

const PEOPLE = [
  "Ada Lovelace",
  "Grace Hopper",
  "Alan Turing",
  "Katherine Johnson",
  "Edsger Dijkstra",
  "Barbara Liskov",
  "Donald Knuth",
  "Frances Allen",
];

const SENTENCES = [
  "A short note that explains the row.",
  "Longer text, such as a description or the body of a post.",
  "Written by the team and edited later.",
  "Kept for reference.",
];

const COLORS = ["#2563eb", "#16a34a", "#d97706", "#dc2626", "#7c3aed"];

const TITLE_COLUMNS = ["name", "title", "label", "subject"];

function capitalized(value: string): string {
  return `${value.charAt(0).toUpperCase()}${value.slice(1)}`.replaceAll(
    "_",
    " ",
  );
}

/** The column a table's rows are named by: its subject title, then a likely name column. */
function titleColumnOf(table: AppTable): string | undefined {
  const text = new Set(
    Object.entries(table.columns ?? {})
      .filter(
        ([, column]) => column.type === "text" && column.format === undefined,
      )
      .map(([key]) => key),
  );

  return table.subject?.title ?? TITLE_COLUMNS.find((key) => text.has(key));
}

/** The name of row `index` of `table`, so a reference shows the row it points at. */
function rowTitle(table: string, index: number): string {
  return `${capitalized(singular(table))} ${String(index + 1)}`;
}

function pad(value: number): string {
  return String(value).padStart(2, "0");
}

/** A date `days` after 5 January 2026, as `YYYY-MM-DD`. */
function dayAfter(days: number): string {
  const date = new Date(Date.UTC(2026, 0, 5 + days));

  return `${String(date.getUTCFullYear())}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

function numberIn(column: AppColumn, index: number, step: number): number {
  const min = column.min ?? 0;
  const value = min + index * step;

  return column.max === undefined ? value : Math.min(value, column.max);
}

function formatted(
  column: AppColumn,
  index: number,
  slug: string,
): string | undefined {
  switch (column.format) {
    case undefined: {
      return undefined;
    }

    case "email": {
      const person = PEOPLE[index % PEOPLE.length] ?? "user";

      return `${person.split(" ")[0]?.toLowerCase() ?? "user"}@example.com`;
    }

    case "url": {
      return `https://example.com/${slug}/${String(index + 1)}`;
    }

    case "phone": {
      return `+1 555 01${pad(index + 10)}`;
    }

    case "long_text": {
      return SENTENCES[index % SENTENCES.length] ?? "";
    }

    case "color": {
      return COLORS[index % COLORS.length] ?? "#000000";
    }

    case "rating": {
      const min = column.min ?? 1;
      const max = column.max ?? 5;

      return String(min + (index % (max - min + 1)));
    }

    case "percent": {
      return String((index * 17) % 101);
    }

    case "currency": {
      return (((index + 1) * 1250) / 100).toFixed(2);
    }

    default: {
      const unreachable: never = column.format;

      return unreachable;
    }
  }
}

function referenceValue(column: AppColumn, index: number): string | undefined {
  const reference = column.references;

  if (reference === undefined) {
    return undefined;
  }

  if (reference.block === undefined && reference.table === USERS) {
    return PEOPLE[index % PEOPLE.length] ?? "";
  }

  return rowTitle(reference.table, index % 3);
}

function typedValue(column: AppColumn, index: number, slug: string): string {
  switch (column.type) {
    case "text": {
      return `${capitalized(slug)} ${String(index + 1)}`;
    }

    case "uuid": {
      return `00000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`;
    }

    case "integer":
    case "bigint": {
      return String(
        column.identity === true ? index + 1 : numberIn(column, index, 3),
      );
    }

    case "numeric": {
      return numberIn(column, index, 2.5).toFixed(2);
    }

    case "boolean": {
      return String(index % 2 === 0);
    }

    case "timestamptz": {
      return `${dayAfter(index * 2)} ${pad(9 + (index % 8))}:00`;
    }

    case "date": {
      return dayAfter(index * 3);
    }

    case "jsonb": {
      return "{}";
    }

    case "text[]": {
      return "{}";
    }

    default: {
      const unreachable: never = column.type;

      return unreachable;
    }
  }
}

function cell(
  table: string,
  key: string,
  column: AppColumn,
  index: number,
  title: string | undefined,
): string | null {
  if (key === title) {
    return rowTitle(table, index);
  }

  if (column.nullable !== false && index % 4 === 3) {
    return null;
  }

  if (column.options !== undefined && column.options.length > 0) {
    return column.options[index % column.options.length] ?? null;
  }

  return (
    referenceValue(column, index) ??
    formatted(column, index, key) ??
    typedValue(column, index, key)
  );
}

/**
 * Deterministic sample rows for app table `name`, from its columns' types,
 * formats, options, bounds and references. A reference shows the name of the
 * row it points at, so rows of related tables line up.
 */
export function sampleRows(
  design: Design,
  name: string,
  count: number = SAMPLE_ROW_COUNT,
): SampleTable {
  const table = design.appTables?.[name];

  if (table === undefined) {
    return { columns: [], rows: [] };
  }

  const entries = Object.entries(table.columns ?? {});
  const title = titleColumnOf(table);

  return {
    columns: entries.map(([key]) => key),
    rows: Array.from({ length: count }, (_, index) =>
      Object.fromEntries(
        entries.map(([key, column]) => [
          key,
          cell(name, key, column, index, title),
        ]),
      ),
    ),
  };
}
