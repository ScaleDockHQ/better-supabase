import type {
  SubjectConfig,
  SubjectsConfig,
} from "../config/types/subjects.ts";
import type { EntityNames } from "../core/entity-naming.ts";

import { tenantNames } from "../core/entity-naming.ts";
import {
  subjectPermissionKey,
  subjectPermissionOf,
} from "../core/subject-permission.ts";
import {
  SUBJECT_TYPE_PATTERN,
  subjectTypeIdent,
} from "../core/subject-type.ts";
import { sqlIdent, sqlString } from "../core/template.ts";
import { splitTable } from "./shared.ts";

/** A `config.records` entry, checked, with its table split and quoted. */
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

const TYPE = SUBJECT_TYPE_PATTERN;
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

const RESOURCE = /^[a-z][a-z0-9_]{0,62}$/;

/** `search.from` and `search.watch`: tables and columns. */
function checkSearchSources(where: string, entry: SubjectConfig): void {
  const table = (at: string, value: unknown): void => {
    if (typeof value !== "string") {
      throw new TypeError(`${at} must be "table" or "schema.table"`);
    }

    try {
      const [schema, name] = splitTable(value);
      column(at, schema);
      column(at, name);
    } catch {
      throw new TypeError(`${at} must be "table" or "schema.table"`);
    }
  };

  const from = entry.search?.from;

  if (from !== undefined) {
    table(`${where}.from.view`, from.view);
    column(`${where}.from.key`, from.key);
  }

  for (const [index, watched] of (entry.search?.watch ?? []).entries()) {
    const at = `${where}.watch[${String(index)}]`;
    table(`${at}.table`, watched.table);
    column(`${at}.key`, watched.key);

    if (watched.via !== undefined) {
      column(`${at}.via`, watched.via);
    }
  }
}

/** One `permissions.<action>` entry: a key, or `{ key?, rows?, owner? }`. */
function checkPermission(where: string, action: string, value: unknown): void {
  if (!ACTION.test(action)) {
    throw new TypeError(`${where}: use an action name with a permission key`);
  }

  if (typeof value === "string") {
    if (value === "") {
      throw new TypeError(`${where}: use an action name with a permission key`);
    }

    return;
  }

  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(
      `${where}: use a permission key or { key, rows, owner }`,
    );
  }

  const entry: Readonly<Record<string, unknown>> = { ...value };

  for (const name of Object.keys(entry)) {
    if (name !== "key" && name !== "rows" && name !== "owner") {
      throw new TypeError(
        `${where}.${name} is not an option. Options: key, rows, owner`,
      );
    }
  }

  const { key, rows, owner } = entry;

  if (key !== undefined && (typeof key !== "string" || key === "")) {
    throw new TypeError(`${where}.key must be a permission key`);
  }

  if (rows !== undefined) {
    if (typeof rows !== "string" || !RESOURCE.test(rows)) {
      throw new TypeError(
        `${where}.rows must be the provider's SQL name of a resource, such as file_node`,
      );
    }

    if (key === undefined) {
      throw new TypeError(
        `${where}.rows needs the key the rows are granted for`,
      );
    }
  }

  if (owner !== undefined) {
    column(`${where}.owner`, owner);
  }

  if (key === undefined && owner === undefined) {
    throw new TypeError(`${where} needs a key or an owner column`);
  }
}

/**
 * `config.records`, checked: every entry with its table split and quoted. A
 * subject without `tenant` gets the tenant column `naming` names
 * (`organization_id`, or `workspace_id` for
 * `blocks.memberships.names.organization: workspace`).
 */
export function registeredSubjects(
  subjects: SubjectsConfig,
  naming: EntityNames = tenantNames(),
): readonly RegisteredSubject[] {
  const idents = new Map<string, string>();

  for (const type of Object.keys(subjects)) {
    const other = idents.get(subjectTypeIdent(type));

    if (other !== undefined) {
      throw new TypeError(
        `subjects.${type}: "${type}" and "${other}" name the same SQL objects. Keep one of them.`,
      );
    }

    idents.set(subjectTypeIdent(type), type);
  }

  return Object.entries(subjects).map(([type, entry]) => {
    const where = `subjects.${type}`;

    if (!TYPE.test(type)) {
      throw new TypeError(
        `${where}: a subject type is lowercase letters, digits, hyphens and underscores, starting with a letter`,
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
        : column(
            `${where}.tenant`,
            entry.tenant ?? naming.rename("organization_id"),
          );

    if (entry.title !== undefined) {
      column(`${where}.title`, entry.title);
    }

    if (entry.deletedAt !== undefined) {
      column(`${where}.deletedAt`, entry.deletedAt);
    }

    if (entry.url !== undefined) {
      for (const [, name] of entry.url.matchAll(PLACEHOLDER)) {
        column(`${where}.url {${name ?? ""}}`, name);
      }
    }

    for (const [action, value] of Object.entries(entry.permissions ?? {})) {
      checkPermission(`${where}.permissions.${action}`, action, value);
    }

    if (
      tenant === undefined &&
      entry.scope === undefined &&
      Object.values(entry.permissions ?? {}).some(
        (value) => subjectPermissionKey(value) !== undefined,
      )
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

    for (const name of [
      entry.search?.title,
      ...(entry.search?.body ?? []),
      entry.search?.description,
      entry.search?.exclude,
    ]) {
      if (name !== undefined) {
        column(`${where}.search`, name);
      }
    }

    checkSearchSources(`${where}.search`, entry);

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

/**
 * The tenant column of `table` (`schema.table`, or a table in `public`): the
 * `tenant` of the `config.records` entry for that table, else the tenant column
 * `naming` names. `undefined` when the entry says the table has no tenant.
 */
export function tenantColumnOf(
  table: string,
  subjects: SubjectsConfig,
  naming: EntityNames = tenantNames(),
): string | undefined {
  const qualify = (name: string): string =>
    name.includes(".") ? name : `public.${name}`;

  const entry = Object.values(subjects).find(
    (candidate) => qualify(candidate.table) === qualify(table),
  );

  if (entry?.tenant === false) {
    return undefined;
  }

  return entry?.tenant ?? naming.rename("organization_id");
}

/**
 * Every column a registry entry names, keyed by the config path that names it.
 * A subject without `tenant` gets the tenant column of `tenant`, the noun
 * `blocks.memberships.entities.organization` renames the tenant to.
 */
export function subjectColumns(
  entry: SubjectConfig,
  tenant?: string,
): readonly (readonly [path: string, column: string])[] {
  const columns: [string, string][] = [["id", entry.id ?? "id"]];

  if (entry.tenant !== false) {
    columns.push([
      "tenant",
      entry.tenant ?? tenantNames(tenant).rename("organization_id"),
    ]);
  }

  if (entry.title !== undefined) {
    columns.push(["title", entry.title]);
  }

  if (entry.deletedAt !== undefined) {
    columns.push(["deletedAt", entry.deletedAt]);
  }

  for (const [, name] of entry.url?.matchAll(PLACEHOLDER) ?? []) {
    if (name !== undefined) {
      columns.push([`url {${name}}`, name]);
    }
  }

  if (entry.rank !== undefined) {
    columns.push(["rank.column", entry.rank.column]);

    if (entry.rank.group !== undefined) {
      columns.push(["rank.group", entry.rank.group]);
    }
  }

  if (entry.search?.from === undefined) {
    if (entry.search?.title !== undefined) {
      columns.push(["search.title", entry.search.title]);
    }

    for (const name of entry.search?.body ?? []) {
      columns.push(["search.body", name]);
    }

    for (const key of ["description", "exclude"] as const) {
      const name = entry.search?.[key];

      if (name !== undefined) {
        columns.push([`search.${key}`, name]);
      }
    }
  }

  for (const watched of entry.search?.watch ?? []) {
    if (watched.via !== undefined) {
      columns.push(["search.watch.via", watched.via]);
    }
  }

  for (const [action, value] of Object.entries(entry.permissions ?? {})) {
    const owner = subjectPermissionOf(value)?.owner;

    if (owner !== undefined) {
      columns.push([`permissions.${action}.owner`, owner]);
    }
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

    if (index > last) {
      parts.push(sqlString(template.slice(last, index)));
    }

    parts.push(`${alias}.${sqlIdent(match[1] ?? "")}::text`);
    last = index + match[0].length;
  }

  if (last < template.length) {
    parts.push(sqlString(template.slice(last)));
  }

  return parts.length === 0 ? "''" : parts.join(" || ");
}
