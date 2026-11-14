import type {
  EntityOffline,
  EntityOfflineCondition,
} from "../../blocks/entity-surface.ts";
import type { BlockSqlFile } from "../../sql/index.ts";
import type { Projection } from "./projection.ts";

import { BLOCK_MANIFESTS } from "../../blocks/registry.ts";
import { SPEC_PINS } from "../../index.ts";
import { addedColumnTypes, declaredColumnTypes } from "../../sql/index.ts";

/** The blocks `gen.powersync` can sync. */
export const POWERSYNC_BLOCKS = [
  "notifications",
  "attachments",
  "memberships",
  "teams",
  "profiles",
  "observations",
  "medications",
  "activities",
] as const;

export type PowerSyncBlock = (typeof POWERSYNC_BLOCKS)[number];

export const isPowerSyncBlock = (value: string): value is PowerSyncBlock =>
  POWERSYNC_BLOCKS.some((block) => block === value);

/** One block instance to sync: its key in `blocks` and the block it installs. */
export interface PowerSyncInstance {
  readonly key: string;
  readonly block: PowerSyncBlock;
}

/**
 * An app table tagged `@bsb subject`, as the streams read it: the type, the
 * table, its id and tenant columns and its soft delete column.
 */
export interface PowerSyncSubject {
  /** The table, as `schema.table`. */
  readonly table: string;
  readonly id: string;
  /** The tenant column; `false` for a subject without one. */
  readonly tenant: string | false;
  readonly deletedAt?: string;
}

/**
 * An app table that syncs with its parent subject: the rows whose `column`
 * points at a parent row the user's organizations hold.
 */
export interface PowerSyncChild {
  /** The child table, as `schema.table`. */
  readonly table: string;
  /** The parent subject's type. */
  readonly parent: string;
  /** The child column that holds the parent's id. */
  readonly column: string;
  /** The child's columns and their types, from the snapshot. */
  readonly columns: ReadonlyMap<string, string>;
}

export interface PowerSyncInput {
  /** The rendered block files, from `renderBlocks`. */
  readonly files: readonly BlockSqlFile[];
  readonly instances: readonly PowerSyncInstance[];
  /** The module the schema file imports `column` and `Table` from. */
  readonly importFrom: string;
  /**
   * By instance key, the app's own tables it runs over (`blocks.<key>.tables`)
   * with their column types, by `schema.table`. The block's files don't create
   * them, so their columns come from the snapshot.
   */
  readonly own?: ReadonlyMap<
    string,
    ReadonlyMap<string, ReadonlyMap<string, string>>
  >;
  /**
   * By attachments instance key, the roles that hold its `read` permission
   * under the `roles` access model. Without an entry, every active member of an
   * organization syncs its files.
   */
  readonly readRoles?: ReadonlyMap<string, readonly string[]>;
  /**
   * The app's views over the synced tables, by `schema.table`
   * (`projectionsOf`). A table with one streams the view's columns and rows
   * under the view's names, because the client reads the view.
   */
  readonly projections?: ReadonlyMap<string, Projection>;
  /**
   * The app's subjects by type, from their `@bsb subject` tags. An attachments
   * stream whose view keeps one `subject_type` also keeps only the files of
   * that subject's rows the user's organizations hold.
   */
  readonly subjects?: ReadonlyMap<string, PowerSyncSubject>;
  /** App tables that stream with a parent subject (`gen.powersync.children`). */
  readonly children?: readonly PowerSyncChild[];
}

/** A synced table: `schema.table`, its stream query and its columns. */
interface SyncedTable {
  readonly qualified: string;
  readonly name: string;
  readonly stream: string;
  readonly query: string;
  /** The stream's CTEs (`with:`), by name. */
  readonly with?: Readonly<Record<string, string>>;
  readonly columns: ReadonlyMap<string, string>;
}

export interface PowerSyncOutput {
  /** `sync-streams.yaml` for the PowerSync service. */
  readonly streams: string;
  /** Creates the `powersync` publication with the synced tables. */
  readonly publication: string;
  /** The synced tables, as `schema.table`. */
  readonly published: readonly string[];
  /** The PowerSync `Table` definitions, as a TypeScript module. */
  readonly schema: string;
  /** The SQLite table names, by instance key. */
  readonly tables: Readonly<Record<string, readonly string[]>>;
  /** The SQLite names of the child tables that stream with a parent subject. */
  readonly children: readonly string[];
}

/**
 * The `offline` rules a block's manifest declares on its first offline entity.
 * The stream queries follow them (ADR 0926), so a rule is changed in the
 * manifest and the streams are written again.
 */
export function offlineOf(block: PowerSyncBlock): EntityOffline {
  const manifest = BLOCK_MANIFESTS.find(({ name }) => name === block);

  for (const surface of Object.values(manifest?.entities ?? {})) {
    if (typeof surface.offline === "object") {
      return surface.offline;
    }
  }

  throw new Error(
    `gen.powersync: the ${block} manifest declares no \`offline\` rules on an entity`,
  );
}

const sqlText = (text: string): string => `'${text.replaceAll("'", "''")}'`;

/**
 * ` AND ...` for the declared conditions that `columns` can meet; an `optional`
 * one is left out when the table lacks its column.
 */
function conditionsSql(
  where: readonly EntityOfflineCondition[] | undefined,
  columns: ReadonlyMap<string, string>,
): string {
  return (where ?? [])
    .filter(({ column, optional }) => optional !== true || columns.has(column))
    .map(
      (condition) =>
        ` AND ${ident(condition.column)} ${condition.isNull === true ? "IS NULL" : `= ${sqlText(condition.equals)}`}`,
    )
    .join("");
}

const GENERATED = "@generated by better-supabase powersync streams";

const SAFE_IDENT = /^[a-z_][a-z0-9_]*$/;

const ident = (name: string): string =>
  SAFE_IDENT.test(name) ? name : `"${name.replaceAll('"', '""')}"`;

const qualifiedIdent = (qualified: string): string => {
  const dot = qualified.indexOf(".");

  return `${ident(qualified.slice(0, dot))}.${ident(qualified.slice(dot + 1))}`;
};

const baseName = (qualified: string): string =>
  qualified.slice(qualified.indexOf(".") + 1);

/** The PowerSync column type a Postgres type syncs as. */
export function powersyncColumnType(type: string): "text" | "integer" | "real" {
  const base = type.replace(/\[\]$/, "").replace(/\(.*\)$/, "");

  if (
    /^(?:smallint|integer|int|int2|int4|int8|bigint|boolean|bool|smallserial|serial|bigserial)$/.test(
      base,
    ) &&
    !type.endsWith("[]")
  ) {
    return "integer";
  }

  if (
    /^(?:real|double precision|float4|float8|numeric|decimal)$/.test(base) &&
    !type.endsWith("[]")
  ) {
    return "real";
  }

  return "text";
}

const CREATE_TABLE =
  /create table (?:if not exists )?("(?:[^"]|"")+"|[a-z_][a-z0-9_$]*)\./gi;

const unquote = (name: string): string =>
  name.startsWith('"') ? name.slice(1, -1).replaceAll('""', '"') : name;

function tablesOf(
  input: PowerSyncInput,
  key: string,
): ReadonlyMap<string, ReadonlyMap<string, string>> {
  const files = input.files.flatMap((file) =>
    file.kind === "schema" && (file.instance ?? file.module) === key
      ? [{ text: file.contents }]
      : [],
  );

  const schemas = [
    ...new Set(
      files.flatMap(({ text }) =>
        [...text.matchAll(CREATE_TABLE)].map((match) => unquote(match[1]!)),
      ),
    ),
  ];

  const own: ReadonlyMap<string, ReadonlyMap<string, string>> = input.own?.get(
    key,
  ) ?? new Map();

  const added = addedColumnTypes(
    input.files.flatMap((file) =>
      file.kind === "schema" ? [{ text: file.contents }] : [],
    ),
    [
      ...schemas,
      ...[...own.keys()].map((table) => table.slice(0, table.indexOf("."))),
    ],
  );

  return new Map(
    [...declaredColumnTypes(files, schemas), ...own].map(([table, columns]) => [
      table,
      new Map([
        ...columns,
        ...[...(added.get(table) ?? [])].filter(
          ([column]) => !columns.has(column),
        ),
      ]),
    ]),
  );
}

const ROLE_SET_TABLE =
  /create table (?:if not exists )?((?:"(?:[^"]|"")+"|[a-z_][a-z0-9_$]*)\.(?:"(?:[^"]|"")+"|[a-z_][a-z0-9_$]*)) \((?:(?!\n\);)[\s\S])*primary key \([^)]*"?role"?\)/gi;

/**
 * The tables of `key` whose primary key ends in the `role` column, such as
 * `membership_roles`: one row per role a member holds.
 */
function roleSetTables(
  input: PowerSyncInput,
  key: string,
): ReadonlySet<string> {
  const found = new Set<string>();

  for (const file of input.files) {
    if (file.kind !== "schema" || (file.instance ?? file.module) !== key) {
      continue;
    }

    for (const match of file.contents.matchAll(ROLE_SET_TABLE)) {
      found.add(
        match[1]!
          .split(".")
          .map((part) => unquote(part.trim()))
          .join("."),
      );
    }
  }

  return found;
}

/** The table of `tables` that has every one of `columns`. */
function tableWith(
  tables: ReadonlyMap<string, ReadonlyMap<string, string>>,
  columns: readonly string[],
  what: string,
): readonly [string, ReadonlyMap<string, string>] {
  const found = [...tables].find(([, declared]) =>
    columns.every((column) => declared.has(column)),
  );

  if (found === undefined) {
    throw new Error(`gen.powersync: found no ${what} table`);
  }

  return found;
}

/**
 * Fails when the generator's stream shape for `instance` isn't the declared
 * scope.
 */
function assertScope(
  instance: PowerSyncInstance,
  scope: EntityOffline["scope"],
): void {
  const declared = offlineOf(instance.block).scope;

  if (declared !== scope) {
    throw new Error(
      `gen.powersync: the ${instance.block} manifest declares the offline scope "${declared}", and its streams are written for "${scope}"`,
    );
  }
}

function notificationTables(
  input: PowerSyncInput,
  instance: PowerSyncInstance,
): SyncedTable[] {
  const tables = tablesOf(input, instance.key);

  const [recipients, recipientColumns] = tableWith(
    tables,
    ["event_id", "user_id", "read_at", "dismissed_at"],
    `${instance.key} recipients`,
  );

  const [events, eventColumns] = tableWith(
    tables,
    ["type", "idempotency_key", "summary"],
    `${instance.key} events`,
  );

  const mine = `${qualifiedIdent(recipients)} WHERE user_id = auth.user_id()`;

  const preferences = [...tables].find(
    ([, declared]) =>
      declared.has("user_id") &&
      declared.has("channel") &&
      declared.has("enabled"),
  );

  return [
    {
      qualified: recipients,
      name: baseName(recipients),
      stream: `${instance.key}_recipients`,
      query: `SELECT * FROM ${mine}`,
      columns: recipientColumns,
    },
    {
      qualified: events,
      name: baseName(events),
      stream: `${instance.key}_events`,
      query: `SELECT * FROM ${qualifiedIdent(events)} WHERE id IN (SELECT event_id FROM ${mine})`,
      columns: eventColumns,
    },
    ...(preferences === undefined
      ? []
      : [
          {
            qualified: preferences[0],
            name: baseName(preferences[0]),
            stream: `${instance.key}_preferences`,
            query: `SELECT * FROM ${qualifiedIdent(preferences[0])} WHERE user_id = auth.user_id()`,
            columns: preferences[1],
          },
        ]),
  ];
}

/**
 * The memberships table: the one with `user_id` and `role` that is not a role
 * set (`membership_roles`).
 */
function membershipsTable(
  input: PowerSyncInput,
  key: string,
): readonly [string, ReadonlyMap<string, string>] | undefined {
  const roleSets = roleSetTables(input, key);

  return [...tablesOf(input, key)].find(
    ([table, declared]) =>
      !roleSets.has(table) && declared.has("user_id") && declared.has("role"),
  );
}

/** The role set table (`roles.many`), when the memberships block has one. */
function roleSetTable(
  input: PowerSyncInput,
  key: string,
): readonly [string, ReadonlyMap<string, string>] | undefined {
  const roleSets = roleSetTables(input, key);

  return [...tablesOf(input, key)].find(([table]) => roleSets.has(table));
}

/** `AND disabled_at IS NULL` when the memberships table can disable a member. */
const active = (columns: ReadonlyMap<string, string>): string =>
  columns.has("disabled_at") ? " AND disabled_at IS NULL" : "";

/**
 * The CTE of the organizations the signed-in user is an active member of, as
 * the tenant column of the memberships block's table.
 */
function activeOrganizations(
  input: PowerSyncInput,
  what: string,
): { readonly tenant: string; readonly query: string } {
  const memberships = membershipsTable(input, "memberships");

  if (memberships === undefined) {
    throw new Error(
      `gen.powersync: ${what} syncs the rows of the user's organizations, which needs the memberships block`,
    );
  }

  const [table, columns] = memberships;
  const tenant = membershipTenant(columns, "memberships");

  return {
    tenant,
    query: `SELECT ${ident(tenant)} FROM ${qualifiedIdent(table)} WHERE user_id = auth.user_id()${active(columns)}`,
  };
}

/** The tenant column of the memberships table: its `*_id` besides `user_id`. */
function membershipTenant(
  columns: ReadonlyMap<string, string>,
  what: string,
): string {
  const tenant = [...columns.keys()].find(
    (column) => column.endsWith("_id") && column !== "user_id",
  );

  if (tenant === undefined) {
    throw new Error(`gen.powersync: ${what} has no organization column`);
  }

  return tenant;
}

/**
 * Only `names` of `columns`, for a stream that selects them. PowerSync
 * replicates past the column grants, so a stream lists what it may expose.
 */
function only(
  columns: ReadonlyMap<string, string>,
  names: readonly string[],
): ReadonlyMap<string, string> {
  return new Map([...columns].filter(([column]) => names.includes(column)));
}

function membershipTables(
  input: PowerSyncInput,
  instance: PowerSyncInstance,
): SyncedTable[] {
  const found = membershipsTable(input, instance.key);

  if (found === undefined) {
    throw new Error(
      `gen.powersync: found no ${instance.key} memberships table`,
    );
  }

  const [memberships, columns] = found;
  const tenant = membershipTenant(columns, `${instance.key} memberships`);
  const mine = `SELECT ${ident(tenant)} FROM ${qualifiedIdent(memberships)} WHERE user_id = auth.user_id()${active(columns)}`;

  const synced: SyncedTable[] = [
    {
      qualified: memberships,
      name: baseName(memberships),
      stream: `${instance.key}_memberships`,
      query: `SELECT ${columns.has("id") ? "" : `${ident(tenant)} || ':' || user_id AS id, `}* FROM ${qualifiedIdent(memberships)} WHERE user_id = auth.user_id()${active(columns)}`,
      columns,
    },
  ];

  const roleSet = roleSetTable(input, instance.key);

  if (roleSet !== undefined) {
    const [table, roleColumns] = roleSet;

    synced.push({
      qualified: table,
      name: baseName(table),
      stream: `${instance.key}_roles`,
      with: {
        member_orgs: `SELECT ${ident(tenant)} FROM ${qualifiedIdent(memberships)} WHERE user_id = auth.user_id()`,
      },
      query: `SELECT ${roleColumns.has("id") ? "" : `${ident(tenant)} || ':' || user_id || ':' || role AS id, `}* FROM ${qualifiedIdent(table)} WHERE ${ident(tenant)} IN member_orgs`,
      columns: roleColumns,
    });
  }

  const organizations = [...tablesOf(input, "organizations")].find(
    ([, declared]) =>
      declared.has("id") && declared.has("name") && !declared.has("user_id"),
  );

  if (organizations !== undefined) {
    const [table, declared] = organizations;

    const selected = ["id", "name", "slug", "disabled_at", "deleted_at"].filter(
      (column) => declared.has(column),
    );

    synced.push({
      qualified: table,
      name: baseName(table),
      stream: `${instance.key}_organizations`,
      query: `SELECT ${selected.map(ident).join(", ")} FROM ${qualifiedIdent(table)} WHERE id IN (${mine})`,
      columns: only(declared, selected),
    });
  }

  return synced;
}

function teamTables(
  input: PowerSyncInput,
  instance: PowerSyncInstance,
): SyncedTable[] {
  assertScope(instance, "tenant");
  const tables = tablesOf(input, instance.key);

  const [members, memberColumns] = tableWith(
    tables,
    ["team_id", "user_id"],
    `${instance.key} team members`,
  );

  const [teams, teamColumns] = tableWith(
    tables,
    ["id", "name", "slug", "status"],
    `${instance.key} teams`,
  );

  const orgs = activeOrganizations(input, instance.key);

  const tenantOf = (
    columns: ReadonlyMap<string, string>,
    what: string,
  ): string => {
    const found = [...columns.keys()].find(
      (column) =>
        column.endsWith("_id") && column !== "team_id" && column !== "user_id",
    );

    if (found === undefined) {
      throw new Error(`gen.powersync: ${what} has no organization column`);
    }

    return found;
  };

  const teamTenant = tenantOf(teamColumns, `${instance.key} teams`);
  const memberTenant = tenantOf(memberColumns, `${instance.key} team members`);

  return [
    {
      qualified: teams,
      name: baseName(teams),
      stream: `${instance.key}_teams`,
      with: { my_orgs: orgs.query },
      query: `SELECT * FROM ${qualifiedIdent(teams)} WHERE ${ident(teamTenant)} IN my_orgs`,
      columns: teamColumns,
    },
    {
      qualified: members,
      name: baseName(members),
      stream: `${instance.key}_members`,
      with: { my_orgs: orgs.query },
      query: `SELECT team_id || ':' || user_id AS id, * FROM ${qualifiedIdent(members)} WHERE ${ident(memberTenant)} IN my_orgs`,
      columns: memberColumns,
    },
  ];
}

function profileTables(
  input: PowerSyncInput,
  instance: PowerSyncInstance,
): SyncedTable[] {
  assertScope(instance, "self");

  const [profiles, columns] = tableWith(
    tablesOf(input, instance.key),
    ["id"],
    `${instance.key} profiles`,
  );

  return [
    {
      qualified: profiles,
      name: baseName(profiles),
      stream: instance.key,
      query: `SELECT * FROM ${qualifiedIdent(profiles)} WHERE id = auth.user_id()`,
      columns,
    },
  ];
}

function attachmentTables(
  input: PowerSyncInput,
  instance: PowerSyncInstance,
): SyncedTable[] {
  const [attachments, columns] = tableWith(
    tablesOf(input, instance.key),
    ["bucket", "object_path", "uploaded_by"],
    `${instance.key} attachments`,
  );

  const orgs = activeOrganizations(input, instance.key);

  const tenant = columns.has(orgs.tenant)
    ? orgs.tenant
    : [...columns.keys()].find(
        (column) => column.endsWith("_id") && column !== "user_id",
      );

  if (tenant === undefined) {
    throw new Error(
      `gen.powersync: ${instance.key} and memberships share no organization column`,
    );
  }

  const readers = readerOrganizations(input, instance.key, orgs.tenant);
  const subject = attachmentSubjects(input, attachments, columns);

  return [
    {
      qualified: attachments,
      name: baseName(attachments),
      stream: instance.key,
      with: {
        active_orgs: orgs.query,
        ...(readers === undefined ? {} : { reader_orgs: readers }),
      },
      query: `SELECT * FROM ${qualifiedIdent(attachments)} WHERE ${ident(tenant)} IN active_orgs${readers === undefined ? "" : ` AND ${ident(tenant)} IN reader_orgs`}${subject === undefined ? "" : ` AND ${subject}`}`,
      columns,
    },
  ];
}

const SUBJECT_EQUALS = /\bsubject_type\s*=\s*'((?:[^']|'')+)'/g;
const SUBJECT_IN = /\bsubject_type\s+in\s*\(([^)]*)\)/gi;
const QUOTED = /'((?:[^']|'')+)'/g;

/** The subject types a view's `where` names, in order, without repeats. */
function subjectTypesOf(where: string): string[] {
  const found: { at: number; type: string }[] = [];

  for (const match of where.matchAll(SUBJECT_EQUALS)) {
    found.push({ at: match.index, type: match[1]! });
  }

  for (const list of where.matchAll(SUBJECT_IN)) {
    for (const item of list[1]!.matchAll(QUOTED)) {
      found.push({ at: list.index + item.index, type: item[1]! });
    }
  }

  return [
    ...new Set(
      found
        .toSorted((a, b) => a.at - b.at)
        .map(({ type }) => type.replaceAll("''", "'")),
    ),
  ];
}

/**
 * The condition that scopes the attachments of the subjects a view keeps. One
 * subject type with a tenant gives `subject_id IN (...)`. Several give one
 * `subject_type = ... AND subject_id IN (...)` branch per type, so a file only
 * syncs with a row of its own subject; a type the app doesn't register with a
 * tenant keeps its organization bound and nothing more. Undefined when no type
 * has a registered subject, and the stream stays organization-wide.
 */
function attachmentSubjects(
  input: PowerSyncInput,
  attachments: string,
  columns: ReadonlyMap<string, string>,
): string | undefined {
  const where = input.projections?.get(attachments)?.where;

  if (where === undefined || !columns.has("subject_id")) {
    return undefined;
  }

  const types = subjectTypesOf(where);

  const subjects = types.map((type) => {
    const subject = input.subjects?.get(type);

    return { type, subject: subject?.tenant === false ? undefined : subject };
  });

  if (subjects.every(({ subject }) => subject === undefined)) {
    return undefined;
  }

  const [only] = subjects;

  if (subjects.length === 1 && only?.subject !== undefined) {
    return `subject_id IN (${parentRows(only.subject, true)})`;
  }

  const branches = subjects.map(({ type, subject }) => {
    const named = `subject_type = '${type.replaceAll("'", "''")}'`;

    return subject === undefined
      ? named
      : `${named} AND subject_id IN (${parentRows(subject, true)})`;
  });

  return `(${branches.join(" OR ")})`;
}

/**
 * The select of `subject`'s rows in the user's organizations, for `IN (...)`.
 * `active_orgs` is the stream's CTE.
 */
function parentRows(subject: PowerSyncSubject, asText: boolean): string {
  const tenant = subject.tenant === false ? "" : ident(subject.tenant);
  const id = `${ident(subject.id)}${asText ? "::text" : ""}`;

  return `SELECT ${id} FROM ${qualifiedIdent(subject.table)} WHERE ${tenant} IN active_orgs${subject.deletedAt === undefined ? "" : ` AND ${ident(subject.deletedAt)} IS NULL`}`;
}

/** The streams of the app tables that sync with their parent subject. */
function childTables(input: PowerSyncInput): SyncedTable[] {
  return (input.children ?? []).map((child) => {
    const subject = input.subjects?.get(child.parent);

    if (subject === undefined) {
      throw new Error(
        `gen.powersync: ${child.table} names the parent ${child.parent}, which no table tags as \`@bsb subject\``,
      );
    }

    if (subject.tenant === false) {
      throw new Error(
        `gen.powersync: the parent ${child.parent} has no tenant column, so ${child.table} can't be bounded by the user's organizations`,
      );
    }

    if (!child.columns.has(child.column)) {
      throw new Error(
        `gen.powersync: ${child.table} has no ${child.column} column; save a snapshot with \`better-supabase gen --save-snapshot\``,
      );
    }

    if (!child.columns.has("id")) {
      throw new Error(
        `gen.powersync: ${child.table} has no id column, which PowerSync needs on every row`,
      );
    }

    const name = baseName(child.table);

    return {
      qualified: child.table,
      name,
      stream: name,
      with: { active_orgs: activeOrganizations(input, child.table).query },
      query: `SELECT * FROM ${qualifiedIdent(child.table)} WHERE ${ident(child.column)} IN (${parentRows(subject, false)})`,
      columns: child.columns,
    };
  });
}

/**
 * The CTE of the organizations where the user holds a role with the instance's
 * `read` permission, read from the role set when the memberships block keeps
 * one. Undefined when every member reads.
 */
function readerOrganizations(
  input: PowerSyncInput,
  key: string,
  tenant: string,
): string | undefined {
  const roles = input.readRoles?.get(key);

  if (roles === undefined) {
    return undefined;
  }

  const source =
    roleSetTable(input, "memberships") ??
    membershipsTable(input, "memberships");

  if (source === undefined) {
    return undefined;
  }

  const matches =
    roles.length === 0
      ? "FALSE"
      : roles
          .map((role) => `role = '${role.replaceAll("'", "''")}'`)
          .join(" OR ");

  return `SELECT ${ident(tenant)} FROM ${qualifiedIdent(source[0])} WHERE user_id = auth.user_id() AND (${matches})`;
}

/**
 * The care tables of an instance: every table of an observations or medications
 * instance, and the progress notes of an activities instance (`note` activities
 * that are open to the team, and their links). Rows sync to the members of the
 * organizations where the user holds a role with the instance's `read`
 * permission. PowerSync replicates past row-level security, so without a roles
 * access model there is nothing to narrow the rows by and the command refuses
 * to generate the stream.
 */
function careTables(
  input: PowerSyncInput,
  instance: PowerSyncInstance,
): SyncedTable[] {
  assertScope(instance, "readers");
  const offline = offlineOf(instance.block);
  const orgs = activeOrganizations(input, instance.key);
  const readers = readerOrganizations(input, instance.key, orgs.tenant);

  if (readers === undefined) {
    throw new Error(
      `gen.powersync: ${instance.key} syncs clinical rows, so it needs the roles access model: PowerSync can't apply row-level security, and the stream narrows rows to the roles with ${instance.block}.read`,
    );
  }

  const synced: SyncedTable[] = [];

  for (const [qualified, columns] of tablesOf(input, instance.key)) {
    const name = baseName(qualified);

    // The memberships table names its organization column by the tenancy
    // setting; the care tables use `tenant_id` unless it renames that column.
    const tenantColumn = [orgs.tenant, "tenant_id"].find((column) =>
      columns.has(column),
    );

    if (tenantColumn === undefined) {
      continue;
    }

    const tenant = ident(tenantColumn);
    const table = qualifiedIdent(qualified);

    const system =
      offline.systemRows !== undefined && name.endsWith(offline.systemRows)
        ? ` OR ${tenant} IS NULL`
        : "";

    const base = {
      qualified,
      name,
      stream: `${instance.key}_${name}`,
      with: { reader_orgs: readers },
      columns,
    };

    if (offline.where === undefined) {
      synced.push({
        ...base,
        query: `SELECT * FROM ${table} WHERE ${tenant} IN reader_orgs${system}`,
      });

      continue;
    }

    if (columns.has("type") && columns.has("title")) {
      synced.push({
        ...base,
        query: `SELECT * FROM ${table} WHERE ${tenant} IN reader_orgs${conditionsSql(offline.where, columns)}`,
      });
    } else if (columns.has("activity_id") && columns.has("subject_type")) {
      const activities = [...tablesOf(input, instance.key)].find(
        ([, declared]) => declared.has("type") && declared.has("title"),
      );

      if (activities === undefined) {
        continue;
      }

      synced.push({
        ...base,
        query: `SELECT activity_id || ':' || subject_type || ':' || subject_id AS id, * FROM ${table} WHERE ${tenant} IN reader_orgs AND activity_id IN (SELECT id FROM ${qualifiedIdent(activities[0])} WHERE ${tenant} IN reader_orgs${conditionsSql(offline.where, activities[1])})`,
      });
    }
  }

  if (synced.length === 0) {
    throw new Error(
      `gen.powersync: found no ${instance.key} tables with an organization column`,
    );
  }

  return synced;
}

function syncedTables(
  input: PowerSyncInput,
  instance: PowerSyncInstance,
): SyncedTable[] {
  switch (instance.block) {
    case "notifications": {
      return notificationTables(input, instance);
    }

    case "attachments": {
      return attachmentTables(input, instance);
    }

    case "memberships": {
      return membershipTables(input, instance);
    }

    case "teams": {
      return teamTables(input, instance);
    }

    case "profiles": {
      return profileTables(input, instance);
    }

    case "observations":
    case "medications":
    case "activities": {
      return careTables(input, instance);
    }

    default: {
      const unknown: never = instance.block;
      throw new Error(`gen.powersync: ${String(unknown)} can't sync`);
    }
  }
}

/** The authorization provider's version of a user's permissions, kept on a row. */
const VERSION_COLUMN = /^(?:authz|permissions?)_ver(?:sion)?$/;

const STAR = /^SELECT ((?:[^*]*?, )?)\* FROM /;

const isBigint = (type: string | undefined): boolean =>
  type === "bigint" || type === "int8";

/**
 * `table` with the provider's version column left out (the native client
 * refreshes on the provider's broadcast, ADR 0129), a bigint id sent as text,
 * and the columns and rows of the app's view over it when there is one. A
 * stream that already lists its columns stays as it is.
 */
function streamedFrom(
  table: SyncedTable,
  projection: Projection | undefined,
): SyncedTable {
  const match = STAR.exec(table.query);

  const dropped = [...table.columns.keys()].some((column) =>
    VERSION_COLUMN.test(column),
  );

  const bigintId = isBigint(table.columns.get("id"));

  if (match === null || (!dropped && !bigintId && projection === undefined)) {
    return table;
  }

  const selected = (
    projection === undefined
      ? [...table.columns.keys()].map((column) => ({
          source: column,
          name: column,
        }))
      : projection.columns.filter((column) => table.columns.has(column.source))
  ).filter((column) => !VERSION_COLUMN.test(column.source));

  const list = selected.map((column) => {
    if (column.source === "id" && bigintId) {
      return `id::text AS ${ident(column.name)}`;
    }

    return column.source === column.name
      ? ident(column.source)
      : `${ident(column.source)} AS ${ident(column.name)}`;
  });

  // A table that has its own id streams it; the composite key only stands in
  // when the table has none.
  const prefix = selected.some((column) => column.name === "id")
    ? ""
    : match[1]!;

  const rest = table.query.slice(match[0].length);
  const where = projection?.where;

  const query = `SELECT ${prefix}${list.join(", ")} FROM ${rest}${
    where === undefined
      ? ""
      : /\sWHERE\s/.test(rest)
        ? ` AND (${where})`
        : ` WHERE (${where})`
  }`;

  return {
    ...table,
    query,
    columns: new Map(
      selected.map((column) => [
        column.name,
        table.columns.get(column.source)!,
      ]),
    ),
  };
}

const yamlString = (text: string): string => JSON.stringify(text);

function streamsYaml(tables: readonly SyncedTable[]): string {
  const streams = tables.flatMap((table) => [
    `  ${table.stream}:`,
    "    auto_subscribe: true",
    ...(table.with === undefined || Object.keys(table.with).length === 0
      ? []
      : [
          "    with:",
          ...Object.entries(table.with).map(
            ([name, query]) => `      ${name}: ${yamlString(query)}`,
          ),
        ]),
    `    query: ${yamlString(table.query)}`,
  ]);

  return [
    `# ${GENERATED}. Do not edit; run \`better-supabase powersync streams\` instead.`,
    "config:",
    `  edition: ${SPEC_PINS.powersyncSyncStreams}`,
    "",
    "streams:",
    ...streams,
    "",
  ].join("\n");
}

/**
 * The publication migration for `tables`: `create publication` when no earlier
 * migration made it, otherwise one `alter publication` per table that
 * `published` lacks. Undefined when there is nothing to add.
 */
export function publicationSql(
  tables: readonly string[],
  published?: ReadonlySet<string>,
): string | undefined {
  const quoted = (table: string): string => qualifiedIdent(table);
  const header = `-- ${GENERATED}: the block tables PowerSync replicates.`;

  if (published === undefined) {
    return `${header}\ncreate publication powersync for table ${tables.map(quoted).join(", ")};\n`;
  }

  const added = tables.filter((table) => !published.has(table));

  return added.length === 0
    ? undefined
    : `${header}\n${added.map((table) => `alter publication powersync add table ${quoted(table)};`).join("\n")}\n`;
}

/**
 * The `powersync` publication as a declarative schema file. A publication is
 * not tracked by migrations alone: `declarative sync --strict-coverage` drops
 * one that no schema file declares, so the file lists every synced table.
 */
export function publicationDeclaration(tables: readonly string[]): string {
  return `-- ${GENERATED}: the block tables PowerSync replicates.\ncreate publication powersync for table ${tables.map((table) => qualifiedIdent(table)).join(", ")};\n`;
}

const propertyName = (name: string): string =>
  /^[A-Za-z_$][\w$]*$/.test(name) ? name : JSON.stringify(name);

function schemaModule(
  tables: readonly SyncedTable[],
  importFrom: string,
): string {
  const definitions = tables.map((table) => {
    const columns = [...table.columns]
      .filter(([column]) => column !== "id")
      .map(
        ([column, type]) =>
          `  ${propertyName(column)}: column.${powersyncColumnType(type)},`,
      );

    return [`export const ${table.name} = new Table({`, ...columns, "});"].join(
      "\n",
    );
  });

  return [
    `// ${GENERATED}. Do not edit; run \`better-supabase powersync streams\` instead.`,
    "",
    `import { column, Table } from ${JSON.stringify(importFrom)};`,
    "",
    ...definitions.flatMap((definition) => [definition, ""]),
    "/** The block tables, to spread into the app's `new Schema({ ... })`. */",
    `export const blockTables = { ${tables.map((table) => table.name).join(", ")} };`,
    "",
  ].join("\n");
}

/** The sync streams, publication and PowerSync schema for `input.instances`. */
export function powersyncOutput(input: PowerSyncInput): PowerSyncOutput {
  const byInstance = input.instances.map(
    (instance) =>
      [
        instance.key,
        syncedTables(input, instance).map((table) =>
          streamedFrom(table, input.projections?.get(table.qualified)),
        ),
      ] as const,
  );

  const children = childTables(input).map((table) =>
    streamedFrom(table, input.projections?.get(table.qualified)),
  );

  const tables = [...byInstance.flatMap(([, synced]) => synced), ...children];
  const published = [...new Set(tables.map(({ qualified }) => qualified))];

  return {
    streams: streamsYaml(tables),
    publication: publicationSql(published) ?? "",
    published,
    schema: schemaModule(tables, input.importFrom),
    children: children.map(({ name }) => name),
    tables: Object.fromEntries(
      byInstance.map(([key, synced]) => [key, synced.map(({ name }) => name)]),
    ),
  };
}
