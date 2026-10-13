import type {
  SubjectConfig,
  SubjectsConfig,
} from "../config/types/subjects.ts";

import { sqlIdent, sqlString } from "../core/template.ts";
import { splitTable } from "./shared.ts";

/** A `config.subjects` entry, checked, with its table split and quoted. */
export interface RegisteredSubject {
  readonly type: string;
  readonly config: SubjectConfig;
  readonly schema: string;
  readonly table: string;
  /** `"schema"."table"`. */
  readonly qualified: string;
  /** The id column, quoted. */
  readonly id: string;
  /** The tenant column, quoted, or `undefined` for a subject without one. */
  readonly tenant: string | undefined;
}

const TYPE = /^[a-z][a-z0-9_]{0,62}$/;
const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/;
const ID_TYPE = /^[a-z][a-z0-9_ ]{0,62}$/;
const ACTION = /^[a-z][a-z0-9_.-]{0,62}$/;
const PLACEHOLDER = /\{([^}]*)\}/g;

function column(where: string, value: unknown): string {
  if (typeof value !== "string" || !COLUMN.test(value)) {
    throw new TypeError(`${where} must be a column name`);
  }
  return value;
}

/** `config.subjects`, checked: every entry with its table split and quoted. */
export function registeredSubjects(
  subjects: SubjectsConfig,
): readonly RegisteredSubject[] {
  return Object.entries(subjects).map(([type, entry]) => {
    const where = `subjects.${type}`;
    if (!TYPE.test(type)) {
      throw new TypeError(
        `${where}: a subject type is lowercase letters, digits and underscores`,
      );
    }
    let schema: string;
    let table: string;
    try {
      [schema, table] = splitTable(entry.table);
    } catch {
      throw new TypeError(`${where}.table must be "table" or "schema.table"`);
    }
    column(`${where}.table`, schema);
    column(`${where}.table`, table);
    const id = column(`${where}.id`, entry.id ?? "id");
    if (entry.idType !== undefined && !ID_TYPE.test(entry.idType)) {
      throw new TypeError(
        `${where}.idType must be a type name such as uuid, text or bigint`,
      );
    }
    const tenant =
      entry.tenant === false
        ? undefined
        : column(`${where}.tenant`, entry.tenant ?? "organization_id");
    if (entry.title !== undefined) column(`${where}.title`, entry.title);
    if (entry.deletedAt !== undefined) {
      column(`${where}.deletedAt`, entry.deletedAt);
    }
    if (entry.url !== undefined) {
      for (const [, name] of entry.url.matchAll(PLACEHOLDER)) {
        column(`${where}.url {${name ?? ""}}`, name);
      }
    }
    for (const [action, key] of Object.entries(entry.permissions ?? {})) {
      if (!ACTION.test(action) || typeof key !== "string" || key === "") {
        throw new TypeError(
          `${where}.permissions.${action}: use an action name with a permission key`,
        );
      }
    }
    if (
      tenant === undefined &&
      entry.scope === undefined &&
      Object.keys(entry.permissions ?? {}).length > 0
    ) {
      throw new TypeError(
        `${where}.permissions need a tenant column or a scope to check them in`,
      );
    }
    if (entry.rank !== undefined) {
      column(`${where}.rank.column`, entry.rank.column);
      if (entry.rank.group !== undefined) {
        column(`${where}.rank.group`, entry.rank.group);
      }
    }
    for (const name of [entry.search?.title, ...(entry.search?.body ?? [])]) {
      if (name !== undefined) column(`${where}.search`, name);
    }
    return {
      type,
      config: entry,
      schema,
      table,
      qualified: `${sqlIdent(schema)}.${sqlIdent(table)}`,
      id: sqlIdent(id),
      tenant: tenant === undefined ? undefined : sqlIdent(tenant),
    };
  });
}

/** Every column a registry entry names, keyed by the config path that names it. */
export function subjectColumns(
  entry: SubjectConfig,
): readonly (readonly [path: string, column: string])[] {
  const columns: [string, string][] = [["id", entry.id ?? "id"]];
  if (entry.tenant !== false) {
    columns.push(["tenant", entry.tenant ?? "organization_id"]);
  }
  if (entry.title !== undefined) columns.push(["title", entry.title]);
  if (entry.deletedAt !== undefined) {
    columns.push(["deletedAt", entry.deletedAt]);
  }
  for (const [, name] of entry.url?.matchAll(PLACEHOLDER) ?? []) {
    if (name !== undefined) columns.push([`url {${name}}`, name]);
  }
  if (entry.rank !== undefined) {
    columns.push(["rank.column", entry.rank.column]);
    if (entry.rank.group !== undefined) {
      columns.push(["rank.group", entry.rank.group]);
    }
  }
  if (entry.search?.title !== undefined) {
    columns.push(["search.title", entry.search.title]);
  }
  for (const name of entry.search?.body ?? []) {
    columns.push(["search.body", name]);
  }
  return columns;
}

/** `s.<id> = <value>` on the id column's own type when the registry gives it. */
export function registeredIdMatches(
  subject: RegisteredSubject,
  value: string,
  alias = "s",
): string {
  return subject.config.idType === undefined
    ? `${alias}.${subject.id}::text = ${value}`
    : `${alias}.${subject.id} = (${value})::${subject.config.idType}`;
}

/** The `url` template as a SQL text expression over row `alias`. */
export function urlExpression(template: string, alias = "s"): string {
  const parts: string[] = [];
  let last = 0;
  for (const match of template.matchAll(PLACEHOLDER)) {
    const index = match.index;
    if (index > last) parts.push(sqlString(template.slice(last, index)));
    parts.push(`${alias}.${sqlIdent(match[1] ?? "")}::text`);
    last = index + match[0].length;
  }
  if (last < template.length) parts.push(sqlString(template.slice(last)));
  return parts.length === 0 ? "''" : parts.join(" || ");
}
