import type {
  AppColumnAccess,
  AppTableConfig,
  AppTablesConfig,
} from "./types/app-tables.ts";

import { APP_COLUMN_ACCESS } from "./types/app-tables.ts";

const PLACEHOLDER = /\{([^}]*)\}/gu;

/** `appTables.<t>.columns.<c>.access` checked. */
export function accessOf(
  where: string,
  value: unknown,
): AppColumnAccess | undefined {
  if (value === undefined) {
    return undefined;
  }

  const access = APP_COLUMN_ACCESS.find((option) => option === value);

  if (access === undefined) {
    throw new TypeError(
      `${where} must be one of ${APP_COLUMN_ACCESS.join(", ")}`,
    );
  }

  return access;
}

/** The own columns of `table` with `access` set to `access`, in config order. */
export function columnsWithAccess(
  table: AppTableConfig,
  access: AppColumnAccess,
): readonly string[] {
  return Object.entries(table.columns ?? {}).flatMap(([name, column]) =>
    column.access === access ? [name] : [],
  );
}

/** The own columns of `table` that are `encrypted`, in config order. */
export function encryptedColumns(table: AppTableConfig): readonly string[] {
  return Object.entries(table.columns ?? {}).flatMap(([name, column]) =>
    column.encrypted === true ? [name] : [],
  );
}

/**
 * The own columns signed-in users can't select: `access: "server"` ones, and
 * encrypted ones, which they read through `<table>_reveal`.
 */
export function hiddenColumns(table: AppTableConfig): readonly string[] {
  return Object.entries(table.columns ?? {}).flatMap(([name, column]) =>
    column.access === "server" || column.encrypted === true ? [name] : [],
  );
}

/** Whether `table` grants by column: a column sets `access` or is encrypted. */
export function hasColumnAccess(table: AppTableConfig): boolean {
  return Object.values(table.columns ?? {}).some(
    (column) => column.access !== undefined || column.encrypted === true,
  );
}

interface Use {
  readonly where: string;
  readonly table: string;
  readonly column: string | undefined;
}

function urlColumns(url: string | undefined): readonly string[] {
  return url === undefined
    ? []
    : [...url.matchAll(PLACEHOLDER)].flatMap((match) =>
        match[1] === undefined ? [] : [match[1]],
      );
}

/** Every place a table's config reads a column for signed-in users. */
function readsOf(
  name: string,
  table: AppTableConfig,
  tables: AppTablesConfig,
): readonly Use[] {
  const at = `appTables.${name}`;
  const { subject } = table;
  const versions = subject?.versions;
  const rank = subject?.rank;

  const own = (where: string, column: string | undefined): Use => ({
    where: `${at}.${where}`,
    table: name,
    column,
  });

  const lookupTarget = (via: string): string | undefined => {
    const reference = table.columns?.[via]?.references;

    return reference === undefined || "block" in reference
      ? undefined
      : reference.table;
  };

  return [
    own("subject.title", subject?.title),
    own("subject.search.title", subject?.search?.title),
    ...(subject?.search?.body ?? []).map((column) =>
      own("subject.search.body", column),
    ),
    ...urlColumns(subject?.url).map((column) => own("subject.url", column)),
    own("subject.rank.group", rank === true ? undefined : rank?.group),
    ...(versions === true || versions?.columns === undefined
      ? []
      : versions.columns.map((column) =>
          own("subject.versions.columns", column),
        )),
    ...(table.events === true ? [] : (table.events?.include ?? [])).map(
      (column) => own("events.include", column),
    ),
    ...Object.entries(table.rollups ?? {}).flatMap(([key, rollup]) =>
      [rollup.via, rollup.column, rollup.where?.column].map((column) => ({
        where: `${at}.rollups.${key}`,
        table: rollup.table,
        column,
      })),
    ),
    ...Object.entries(table.lookups ?? {}).flatMap(([key, lookup]) => {
      const target = lookupTarget(lookup.via);

      return [
        own(`lookups.${key}.via`, lookup.via),
        {
          where: `${at}.lookups.${key}.column`,
          table: target ?? name,
          column: target === undefined ? undefined : lookup.column,
        },
      ];
    }),
  ].filter((use) => tables[use.table] !== undefined);
}

/**
 * Throws when a column with `access: "server"` or `encrypted` is read where
 * signed-in users see the value: a subject's title, search, url, rank group or
 * versioned columns, an event payload, or a rollup or lookup (ADR 0051). The
 * database sees an encrypted column as ciphertext, so these can't use it
 * either. Versions of every column (`versions: true`) would copy it into the
 * history, so such a table lists `subject.versions.columns`.
 */
export function checkColumnAccess(tables: AppTablesConfig): void {
  for (const [name, table] of Object.entries(tables)) {
    const hidden = hiddenColumns(table);
    const versions = table.subject?.versions;

    if (
      hidden.length > 0 &&
      (versions === true || (versions !== undefined && !versions.columns))
    ) {
      throw new TypeError(
        `appTables.${name}.subject.versions: the history would copy ${hidden.join(", ")}, which ${hidden.length === 1 ? "is" : "are"} hidden from signed-in users (access server or encrypted); list subject.versions.columns without it`,
      );
    }

    for (const use of readsOf(name, table, tables)) {
      const column =
        use.column === undefined
          ? undefined
          : tables[use.table]?.columns?.[use.column];

      if (column?.encrypted === true) {
        throw new TypeError(
          `${use.where}: ${use.table}.${String(use.column)} is encrypted, so the database only sees ciphertext here; drop it or drop encrypted`,
        );
      }

      if (column?.access === "server") {
        throw new TypeError(
          `${use.where}: ${use.table}.${String(use.column)} has access server, so signed-in users can't read it here; drop it or set access read`,
        );
      }
    }
  }
}
