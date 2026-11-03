import type { AppColumnConfig, AppColumnGroup } from "./types/app-tables.ts";

const GROUP_NAME = /^[a-z][a-z0-9_]{0,62}$/u;
const PERMISSION_KEY = /^[a-z][a-z0-9_:.-]{0,127}$/iu;
const MAX_GROUPS = 20;

function isObject(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The groups that list `column`, as group names. */
export function groupsOfColumn(
  groups: Readonly<Record<string, AppColumnGroup>> | undefined,
  column: string,
): readonly string[] {
  return Object.entries(groups ?? {}).flatMap(([name, group]) =>
    group.columns.includes(column) ? [name] : [],
  );
}

/**
 * `tables.<t>.columnGroups` checked (ADR 0216): each group lists own columns
 * (never the id, the scope column or a timestamp) and one permission key that
 * may change them. A column belongs to one group at most, so a changed column
 * asks for one permission.
 */
export function columnGroupsOf(
  where: string,
  value: unknown,
  columns: Readonly<Record<string, AppColumnConfig>>,
): Readonly<Record<string, AppColumnGroup>> | undefined {
  if (value === undefined) {
    return undefined;
  }

  const at = `${where}.columnGroups`;

  if (!isObject(value)) {
    throw new TypeError(`${at} must be an object keyed by group name`);
  }

  const entries = Object.entries(value);

  if (entries.length === 0 || entries.length > MAX_GROUPS) {
    throw new TypeError(
      `${at} must hold 1 to ${String(MAX_GROUPS)} groups; remove it for none`,
    );
  }

  const owner = new Map<string, string>();

  const groups = entries.map(([name, group]): [string, AppColumnGroup] => {
    const here = `${at}.${name}`;

    if (!GROUP_NAME.test(name)) {
      throw new TypeError(
        `${here}: "${name}" is not a group name (lower snake, at most 63 characters)`,
      );
    }

    if (!isObject(group)) {
      throw new TypeError(`${here} must be an object with columns and update`);
    }

    for (const key of Object.keys(group)) {
      if (key !== "columns" && key !== "update") {
        throw new TypeError(
          `${here}: unknown key "${key}" (use columns, update)`,
        );
      }
    }

    const listed: unknown = group["columns"];

    if (
      !Array.isArray(listed) ||
      listed.length === 0 ||
      listed.some((column) => typeof column !== "string")
    ) {
      throw new TypeError(`${here}.columns must be a list of column names`);
    }

    const names = [...new Set(listed.map(String))];

    for (const column of names) {
      if (columns[column] === undefined) {
        throw new TypeError(
          `${here}.columns names "${column}", which is not an own column of the table (${Object.keys(columns).join(", ")})`,
        );
      }

      const other = owner.get(column);

      if (other !== undefined) {
        throw new TypeError(
          `${here}.columns: "${column}" is also in ${at}.${other}; a column belongs to one group, so it asks for one permission`,
        );
      }

      owner.set(column, name);
    }

    const update: unknown = group["update"];

    if (typeof update !== "string" || !PERMISSION_KEY.test(update)) {
      throw new TypeError(
        `${here}.update must be a permission key such as "orders.price.update"`,
      );
    }

    return [name, { columns: names, update }];
  });

  return Object.fromEntries(groups);
}
