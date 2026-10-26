import type { SubjectConfig } from "../config/types/subjects.ts";
import type { BlockSqlContext } from "./context.ts";
import type { BlockSqlAccessProvider } from "./module-types.ts";
import type { GuestAction } from "./scope.ts";

import { fillTemplate } from "../core/access-sql.ts";
import { isRecord } from "../core/guards.ts";
import { subjectPermissionKey } from "../core/subject-permission.ts";
import { SUBJECT_TYPE_PATTERN } from "../core/subject-type.ts";
import { sqlIdent, sqlString } from "../core/template.ts";
import { accessModel } from "./modules/permissions-model.ts";
import { quotedTable, splitTable } from "./shared.ts";

/**
 * One subject type a module's rows belong to (`on`): the table its ids point
 * at, and who may read it.
 */
export interface Subject {
  /** `schema.table`, or a table in `public`. */
  readonly table: string;
  /** Default `id`. */
  readonly id?: string;
  /**
   * The id column's type, such as `uuid` or `bigint`. With it, the stored text
   * id is cast to that type, so the lookup uses the subject table's primary
   * key; without it the column is cast to text, which can't.
   */
  readonly idType?: string;
  /**
   * The subject's tenant column, default `organization_id`. `false` for a
   * subject without a tenant (a user's own records), where the subject table's
   * policies alone decide, in modules that allow it.
   */
  readonly tenant?: string | false;
  /** A permission the caller also needs in the tenant, e.g. `projects.read`. */
  readonly permission?: string;
  /** Delete the module's rows for a subject when the subject row is deleted. */
  readonly cascade?: boolean;
  /** The module's own keys, such as a bucket per subject. */
  readonly extra: Readonly<Record<string, unknown>>;
}

const BASE_KEYS = new Set([
  "table",
  "id",
  "idType",
  "tenant",
  "permission",
  "cascade",
]);

const ID_TYPE: RegExp = /^[a-z][a-z0-9_ ]{0,62}$/;

/** `s.<id> = <value>`, comparing on the id column's own type when it is known. */
export function subjectIdMatches(subject: Subject, value: string): string {
  const column = `s.${sqlIdent(subject.id ?? "id")}`;

  return subject.idType === undefined
    ? `${column}::text = ${value}`
    : `${column} = (${value})::${subject.idType}`;
}

/** The keys of a registry entry (`config.subjects.<type>`) a module reads. */
function fromRegistry(
  entry: SubjectConfig,
  extraKeys: readonly string[],
): Record<string, unknown> {
  const read = subjectPermissionKey(entry.permissions?.["read"]);

  return {
    table: entry.table,
    ...(entry.id !== undefined && { id: entry.id }),
    ...(entry.idType !== undefined && { idType: entry.idType }),
    ...(entry.tenant !== undefined && { tenant: entry.tenant }),
    ...(read !== undefined && { permission: read }),
    ...(entry.cascade === true && { cascade: true }),
    ...(entry.scope !== undefined &&
      extraKeys.includes("scope") && { scope: entry.scope }),
    ...(entry.deletedAt !== undefined &&
      extraKeys.includes("deletedAt") && { deletedAt: entry.deletedAt }),
    ...(entry.title !== undefined &&
      extraKeys.includes("title") && { title: entry.title }),
    ...(entry.versions !== undefined &&
      extraKeys.includes("versions") && { versions: entry.versions }),
  };
}

/**
 * The module's subject entries before they are checked: the instance's `on` as
 * an object (entries for registered types merge onto the registry's), as a list
 * of registered type names, or, when unset, every registered type the module
 * can hold.
 */
function rawSubjects(
  ctx: BlockSqlContext,
  where: string,
  extraKeys: readonly string[],
  allow: {
    readonly tenantless?: boolean;
    readonly fallback?: boolean;
    readonly registryOnly?: boolean;
  },
): Record<string, unknown> {
  const registry = ctx.subjects;

  const raw = allow.registryOnly === true ? undefined : ctx.on;

  const tenantless = allow.tenantless === true;

  if (raw === undefined) {
    if (allow.fallback === false) {
      return {};
    }

    return Object.fromEntries(
      Object.entries(registry)
        .filter(([, entry]) => tenantless || entry.tenant !== false)
        .map(([type, entry]) => [type, fromRegistry(entry, extraKeys)]),
    );
  }

  if (Array.isArray(raw)) {
    if (raw.length === 0) {
      throw new TypeError(
        `${where}: list at least one config.records type, or pass an object of subject type to { table, ... }`,
      );
    }

    return Object.fromEntries(
      raw.map((type: unknown) => {
        if (typeof type !== "string" || !Object.hasOwn(registry, type)) {
          throw new TypeError(
            `${where}: "${String(type)}" is not a subject type in config.records. Types: ${Object.keys(registry).join(", ") || "none"}`,
          );
        }

        return [type, fromRegistry(registry[type]!, extraKeys)];
      }),
    );
  }

  if (!isRecord(raw)) {
    throw new TypeError(
      `${where}: pass a list of config.records types, or an object of subject type to { table, id?, tenant?, permission?, cascade? }`,
    );
  }

  return Object.fromEntries(
    Object.entries(raw).map(([type, entry]) => {
      const registered = Object.hasOwn(registry, type)
        ? registry[type]
        : undefined;

      return [
        type,
        registered && isRecord(entry)
          ? { ...fromRegistry(registered, extraKeys), ...entry }
          : entry,
      ];
    }),
  );
}

function withAlways(
  ctx: BlockSqlContext,
  raw: Record<string, unknown>,
  extraKeys: readonly string[],
  always: ((entry: SubjectConfig) => boolean) | undefined,
): Record<string, unknown> {
  if (always === undefined) {
    return raw;
  }

  const joined = Object.entries(ctx.subjects)
    .filter(([type, entry]) => !Object.hasOwn(raw, type) && always(entry))
    .map(([type, entry]) => [type, fromRegistry(entry, extraKeys)] as const);

  return { ...Object.fromEntries(joined), ...raw };
}

/**
 * `blocks.<instance>.on`: subject type to `{ table, id?, tenant?, permission?,
 * cascade? }` plus the `extra` keys the module reads, falling back to the
 * app-wide `config.records` registry.
 */
export function subjectsOption(
  ctx: BlockSqlContext,
  extraKeys: readonly string[] = [],
  allow: {
    readonly tenantless?: boolean;
    /** `false`: read the registry only for the types `on` names. */
    readonly fallback?: boolean;
    /** Every registered type, for a module that takes no `on`. */
    readonly registryOnly?: boolean;
    /**
     * Registered types this picks join the module's subjects even when `on`
     * lists others, such as app tables with `subject.versions` for the versions
     * block.
     */
    readonly always?: (entry: SubjectConfig) => boolean;
  } = {},
): readonly [string, Subject][] {
  const where = `blocks.${ctx.instance}.on`;

  const raw = withAlways(
    ctx,
    rawSubjects(ctx, where, extraKeys, allow),
    extraKeys,
    allow.always,
  );

  return Object.entries(raw).map(([type, entry]): [string, Subject] => {
    if (!SUBJECT_TYPE_PATTERN.test(type)) {
      throw new TypeError(
        `${where}: "${type}" must be lowercase letters, digits, hyphens and underscores`,
      );
    }

    if (!isRecord(entry) || typeof entry["table"] !== "string") {
      throw new TypeError(`${where}.${type} needs a table`);
    }

    for (const key of Object.keys(entry)) {
      if (!BASE_KEYS.has(key) && !extraKeys.includes(key)) {
        throw new TypeError(
          `${where}.${type}.${key} is not an option. Options: ${[...BASE_KEYS, ...extraKeys].join(", ")}`,
        );
      }
    }

    const text = (key: string): string | undefined => {
      const value = entry[key];

      if (value === undefined) {
        return undefined;
      }

      if (typeof value !== "string") {
        throw new TypeError(`${where}.${type}.${key} must be a string`);
      }

      return value;
    };

    const cascade = entry["cascade"];

    if (cascade !== undefined && typeof cascade !== "boolean") {
      throw new TypeError(`${where}.${type}.cascade must be true or false`);
    }

    const id = text("id");
    const idType = text("idType");

    if (idType !== undefined && !ID_TYPE.test(idType)) {
      throw new TypeError(
        `${where}.${type}.idType must be a type name such as uuid, text or bigint`,
      );
    }

    const tenantless = entry["tenant"] === false;

    if (tenantless && allow.tenantless !== true) {
      throw new TypeError(
        `${where}.${type}.tenant can't be false: this module keeps a tenant on every row`,
      );
    }

    const tenant = tenantless ? false : text("tenant");
    const permission = text("permission");

    return [
      type,
      {
        table: text("table") ?? "",
        ...(id !== undefined && { id }),
        ...(idType !== undefined && { idType }),
        ...(tenant !== undefined && { tenant }),
        ...(permission !== undefined && { permission }),
        ...(cascade === true && { cascade }),
        extra: Object.fromEntries(
          Object.entries(entry).filter(([key]) => extraKeys.includes(key)),
        ),
      },
    ];
  });
}

/**
 * The record types `blocks.<instance>.on` allows, checked against
 * `config.records`, or `undefined` when `on` is unset and every registered type
 * is allowed.
 */
function allowedSubjectTypes(
  ctx: BlockSqlContext,
): readonly string[] | undefined {
  return ctx.on === undefined
    ? undefined
    : subjectsOption(ctx).map(([type]) => type);
}

/**
 * A PL/pgSQL `if` that fails with `hint` unless the text expression `type` is
 * one of the types `blocks.<instance>.on` allows; empty when `on` is unset.
 */
export function subjectTypeGuard(
  ctx: BlockSqlContext,
  type: string,
  hint: string,
  indent: string,
): string {
  const allowed = allowedSubjectTypes(ctx);

  if (allowed === undefined) {
    return "";
  }

  const list = allowed.map((each) => sqlString(each)).join(", ");

  return `\n${indent}if ${allowed.length === 0 ? "true" : `${type} is null or ${type} not in (${list})`} then
${indent}  raise exception 'blocks.${ctx.instance}.on does not allow this record type'
${indent}    using errcode = '22023', hint = '${hint}';
${indent}end if;`;
}

/**
 * `blocks.<instance>.on` keyed by record type: a list gives each type empty
 * settings, and unset gives none.
 */
export function onSettings(
  ctx: BlockSqlContext,
): Readonly<Record<string, unknown>> {
  const on = ctx.on;

  if (on === undefined) {
    return {};
  }

  if (Array.isArray(on)) {
    return Object.fromEntries(
      on.map((type: unknown): [string, object] => [String(type), {}]),
    );
  }

  if (!isRecord(on)) {
    throw new TypeError(
      `blocks.${ctx.instance}.on must be a list of record types or an object keyed by record type`,
    );
  }

  return on;
}

export const qualifiedTable = (table: string): string => quotedTable(table);

const COLUMN_NAME = /^[a-z_][a-z0-9_]*$/;

/**
 * One adopted table a subject carries (`on.<type>.<key>`), so a module can
 * write per-entity link or history tables instead of one polymorphic table. ADR 0018.
 */
export interface SubjectTableBinding {
  readonly type: string;
  readonly key: string;
  readonly schema: string;
  readonly table: string;
  readonly qualified: string;
  /** Logical column to the physical name the adopted table uses. */
  readonly columns: Readonly<Record<string, string>>;
}

/**
 * `on.<type>.<key>` as `{ table, <column>... }`. Undefined when the subject
 * doesn't set it (the module's polymorphic table is used). `columns` are
 * required; `optional` may be omitted.
 */
function subjectTableBinding(
  ctx: BlockSqlContext,
  type: string,
  subject: Subject,
  key: string,
  spec: {
    readonly columns: readonly string[];
    readonly optional?: readonly string[];
  },
): SubjectTableBinding | undefined {
  const raw = subject.extra[key];

  if (raw === undefined) {
    return undefined;
  }

  const where = `blocks.${ctx.instance}.on.${type}.${key}`;

  if (!isRecord(raw) || typeof raw["table"] !== "string") {
    throw new TypeError(`${where} needs { table, ${spec.columns.join(", ")} }`);
  }

  let schema: string;
  let table: string;

  try {
    [schema, table] = splitTable(raw["table"]);
  } catch {
    throw new TypeError(`${where}.table must be "table" or "schema.table"`);
  }

  if (!COLUMN_NAME.test(schema) || !COLUMN_NAME.test(table)) {
    throw new TypeError(`${where}.table must be "table" or "schema.table"`);
  }

  const columns: Record<string, string> = {};
  const optional = new Set(spec.optional);
  const known = new Set([...spec.columns, ...optional, "table"]);

  for (const name of Object.keys(raw)) {
    if (!known.has(name)) {
      throw new TypeError(
        `${where}.${name} is not a column. Columns: ${[...spec.columns, ...optional].join(", ")}`,
      );
    }
  }

  for (const name of spec.columns) {
    const value = raw[name];

    if (typeof value !== "string" || !COLUMN_NAME.test(value)) {
      throw new TypeError(`${where}.${name} must be a column name`);
    }

    columns[name] = value;
  }

  for (const name of optional) {
    const value = raw[name];

    if (value === undefined) {
      continue;
    }

    if (typeof value !== "string" || !COLUMN_NAME.test(value)) {
      throw new TypeError(`${where}.${name} must be a column name`);
    }

    columns[name] = value;
  }

  return {
    type,
    key,
    schema,
    table,
    qualified: `${sqlIdent(schema)}.${sqlIdent(table)}`,
    columns,
  };
}

/**
 * Every subject table binding `key` declares, for the column checks over app
 * tables.
 */
export function subjectTableBindings(
  ctx: BlockSqlContext,
  subjects: readonly (readonly [string, Subject])[],
  key: string,
  spec: {
    readonly columns: readonly string[];
    readonly optional?: readonly string[];
  },
): readonly SubjectTableBinding[] {
  return subjects.flatMap(([type, subject]) => {
    const binding = subjectTableBinding(ctx, type, subject, key, spec);

    return binding === undefined ? [] : [binding];
  });
}

/**
 * Whether the caller may read the subject `type`/`id` in `tenant`: its row is
 * visible to them (the subject table's own policies apply) and they hold its
 * permission. `true` without `subjects`, `false` for an unlisted type.
 */
export function subjectReadable(
  ctx: Pick<BlockSqlContext, "scope" | "naming">,
  subjects: readonly (readonly [string, Subject])[],
  args: { readonly type: string; readonly id: string; readonly tenant: string },
  options: {
    /**
     * Also require the subject row to be live: its `deletedAt` column (read
     * with the `deletedAt` extra key) is null.
     */
    readonly live?: boolean;
    /**
     * Also let in a guest granted `read` on the record (ADR 0070), whom the
     * subject table's policies and the tenant permission don't.
     */
    readonly guest?: boolean;
  } = {},
): string {
  if (subjects.length === 0) {
    return "true";
  }

  const guest =
    options.guest === true
      ? ctx.scope.guest(args.tenant, args.type, args.id, "read")
      : "false";

  const readable = `case ${args.type}\n${subjects
    .map(([type, subject]) => {
      const deletedAt = subject.extra["deletedAt"];

      const live =
        options.live === true && typeof deletedAt === "string"
          ? ` and s.${sqlIdent(deletedAt)} is null`
          : "";

      if (subject.tenant === false) {
        return `    when ${sqlString(type)} then exists (select 1 from ${qualifiedTable(subject.table)} s where ${subjectIdMatches(subject, args.id)}${live})`;
      }

      const extra = subject.permission
        ? ` and ${ctx.scope.can(args.tenant, sqlString(subject.permission))}`
        : "";

      return `    when ${sqlString(type)} then exists (select 1 from ${qualifiedTable(subject.table)} s where ${subjectIdMatches(subject, args.id)} and ${ctx.scope.eq(`s.${sqlIdent(subject.tenant ?? ctx.naming.rename("organization_id"))}`, args.tenant)}${live})${extra}`;
    })
    .join("\n")}\n    else false\n  end`;

  return guest === "false" ? readable : `(${guest} or ${readable})`;
}

/**
 * Whether the caller may take `action` on subject `type`/`id`, for each of
 * `subjects` whose `config.records` entry declares it (the first of `actions`
 * it declares): `can_subject(type, id, action)` as the caller, so a key, the
 * provider's per-row grants and an owner column all count. Other types pass.
 * `undefined` when no subject declares one of `actions` or the `subjects`
 * module isn't installed, so the module's own check stays as it was; a module
 * that uses it lists `subjects` in `integrates`.
 */
export function subjectActionCheck(
  ctx: BlockSqlContext,
  subjects: readonly (readonly [string, Subject])[],
  args: { readonly type: string; readonly id: string },
  actions: readonly string[],
): string | undefined {
  const declared = subjects.flatMap(([type]) => {
    const permissions = ctx.subjects[type]?.permissions ?? {};
    const action = actions.find((name) => Object.hasOwn(permissions, name));

    return action === undefined ? [] : [[type, action] as const];
  });

  if (declared.length === 0 || !ctx.installed("subjects")) {
    return undefined;
  }

  const canSubject = ctx.of("subjects").fn("can_subject");

  return `(case ${args.type}\n${declared
    .map(
      ([type, action]) =>
        `    when ${sqlString(type)} then coalesce(${canSubject}(${args.type}, ${args.id}, ${sqlString(action)}), false)`,
    )
    .join("\n")}\n    else true\n  end)`;
}

/** `check` and `extra` (from `subjectActionCheck`), or `check` alone. */
export const andSubjectAction = (
  check: string,
  extra: string | undefined,
): string => (extra === undefined ? check : `(${check}) and ${extra}`);

/**
 * `after delete` triggers on the subject tables with `cascade: true` that
 * delete the module's rows for the deleted subject. `remove` is the SQL that
 * deletes them, with `v_type` and `v_id` (text) in scope. With `tenant: true`,
 * `v_tenant` (text) holds the subject row's tenant, or null for a subject with
 * `tenant: false`.
 */
export function subjectCascades(
  ctx: BlockSqlContext,
  subjects: readonly (readonly [string, Subject])[],
  remove: string,
  options: { readonly tenant?: boolean } = {},
): string {
  const cascading = subjects.filter(([, subject]) => subject.cascade);

  if (cascading.length === 0) {
    return "";
  }

  const name = `${ctx.module.replaceAll("-", "_")}_subject_deleted`;
  const fn = ctx.fn(name);

  const triggers = cascading.map(([type, subject]) => {
    const trigger = sqlIdent(
      `bsb_${ctx.module.replaceAll("-", "_")}_${type}_cascade`.slice(0, 63),
    );

    const table = qualifiedTable(subject.table);

    const tenant =
      options.tenant === true && subject.tenant !== false
        ? `, ${sqlString(subject.tenant ?? ctx.naming.rename("organization_id"))}`
        : "";

    return `drop trigger if exists ${trigger} on ${table};
create trigger ${trigger}
  after delete on ${table}
  for each row execute function ${fn}(${sqlString(type)}, ${sqlString(subject.id ?? "id")}${tenant});`;
  });

  const tenantVariable =
    options.tenant === true
      ? "\n  v_tenant text := case when tg_nargs > 2 then to_jsonb(old) ->> tg_argv[2] end;"
      : "";

  return `
-- on with cascade: deleting a subject row deletes its ${ctx.module} rows.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];${tenantVariable}
begin
  ${remove}
  return null;
end;
$$;
revoke execute on function ${fn}() from public, anon, authenticated;

${triggers.join("\n\n")}
`;
}

/** The permission checks of a module whose rows belong to subjects. */
export interface SubjectAccess<A extends string> {
  /**
   * Whether the caller holds the action's key for a row of subject `type` and
   * `id` in `tenant`: in the tenant, or on the subject record itself when its
   * type sets `scope`. One `can()` call per row, for functions. A guest granted
   * the action's guest action on the record passes too.
   */
  canOn(tenant: string, type: string, id: string, action: A): string;
  /**
   * The policy form of `canOn`: one `tenant_ids_with` (or provider `idsWith`)
   * set per key, each computed once per statement.
   */
  memberOn(tenant: string, type: string, id: string, action: A): string;
  /** The action's key for subject `type`, as a SQL expression. */
  keyFor(type: string, action: A): string;
}

/**
 * The checks for `on.<type>.permissions` (a key per action in place of the
 * module's) and `on.<type>.scope` (a scope the authorization provider declares,
 * whose ids are the subject ids, so a grant on the record counts as well as one
 * on the tenant).
 */
export function subjectAccess<A extends string>(
  ctx: BlockSqlContext,
  options: {
    readonly subjects: readonly (readonly [string, Subject])[];
    readonly actions: readonly A[];
    /** The module's key for an action, as a SQL literal. */
    readonly permission: (action: A) => string;
    readonly provider: BlockSqlAccessProvider | undefined;
    /**
     * The guest action each module action needs (ADR 0070): a guest granted it
     * on the record passes the check without being a member.
     */
    readonly guest?: Partial<Readonly<Record<A, GuestAction>>>;
  },
): SubjectAccess<A> {
  const { subjects, actions, permission, provider } = options;
  const where = `blocks.${ctx.instance}.on`;
  const allowed: ReadonlySet<string> = new Set(actions);

  const entries = subjects.map(([type, subject]) => {
    const keys = new Map<string, string>();
    const raw = subject.extra["permissions"];

    // `read` in the registry is the subject's own read key (`subject.permission`), not this module's action.
    for (const [key, entry] of Object.entries(
      ctx.subjects[type]?.permissions ?? {},
    )) {
      const value = subjectPermissionKey(entry);

      if (
        key !== "read" &&
        allowed.has(key) &&
        value !== undefined &&
        value.length > 0
      ) {
        keys.set(key, value);
      }
    }

    if (raw !== undefined) {
      if (!isRecord(raw)) {
        throw new TypeError(
          `${where}.${type}.permissions must be { ${actions.map((action) => `${action}?`).join(", ")} }`,
        );
      }

      for (const [key, value] of Object.entries(raw)) {
        if (
          !allowed.has(key) ||
          typeof value !== "string" ||
          value.length === 0
        ) {
          throw new TypeError(
            `${where}.${type}.permissions.${key}: use ${actions.slice(0, -1).join(", ")} and ${actions.at(-1) ?? ""} with a permission key`,
          );
        }

        keys.set(key, value);
      }
    }

    return { type, keys, scope: subjectScope(ctx, provider, type, subject) };
  });

  const keyed = (action: A) =>
    entries.flatMap((entry) => {
      const key = entry.keys.get(action);

      return key === undefined && entry.scope === undefined
        ? []
        : [
            {
              type: entry.type,
              key: key === undefined ? permission(action) : sqlString(key),
              scope: entry.scope,
            },
          ];
    });

  const onRecord = (
    scope: string | undefined,
    id: string,
    key: string,
  ): string =>
    scope === undefined || provider === undefined
      ? ""
      : ` or ${id} in (select t.id::text from ${fillTemplate(
          `${where} scope ${scope}`,
          provider.functions.idsWith,
          { permission: key, scope },
        )} as t(id))`;

  const branches = (
    action: A,
    type: string,
    id: string,
    check: (key: string) => string,
  ): string => {
    const list = keyed(action);

    const parts = list.map(
      (entry) =>
        `(${type} = ${sqlString(entry.type)} and (${check(entry.key)}${onRecord(entry.scope, id, entry.key)}))`,
    );

    parts.push(
      `(not coalesce(${type} in (${list.map((entry) => sqlString(entry.type)).join(", ")}), false) and ${check(permission(action))})`,
    );

    return `(${parts.join(" or ")})`;
  };

  const scoped = entries.some((entry) => entry.scope !== undefined);

  const can = (tenant: string, key: string): string =>
    ctx.can("tenant", tenant, key);

  const orGuest = (
    sql: string,
    tenant: string,
    type: string,
    id: string,
    action: A,
  ): string => {
    const as = options.guest?.[action];

    const check =
      as === undefined ? "false" : ctx.scope.guest(tenant, type, id, as);

    return check === "false" ? sql : `(${sql} or ${check})`;
  };

  const member = (tenant: string, type: string, id: string, action: A) => {
    const list = keyed(action);

    if (list.length === 0) {
      return can(tenant, permission(action));
    }

    if (scoped) {
      return branches(action, type, id, (key) => can(tenant, key));
    }

    const cases = list.map(
      (entry) => `when ${sqlString(entry.type)} then ${entry.key}`,
    );

    return ctx.scope.can(
      tenant,
      `case ${type} ${cases.join(" ")} else ${permission(action)} end`,
    );
  };

  return {
    canOn(tenant, type, id, action) {
      return orGuest(
        member(tenant, type, id, action),
        tenant,
        type,
        id,
        action,
      );
    },
    memberOn(tenant, type, id, action) {
      const check =
        keyed(action).length === 0
          ? ctx.scope.check(tenant, permission(action))
          : branches(action, type, id, (key) => ctx.scope.check(tenant, key));

      return orGuest(check, tenant, type, id, action);
    },
    keyFor(type, action) {
      const cases = entries.flatMap((entry) => {
        const key = entry.keys.get(action);

        return key === undefined
          ? []
          : [`when ${sqlString(entry.type)} then ${sqlString(key)}`];
      });

      return cases.length === 0
        ? permission(action)
        : `case ${type} ${cases.join(" ")} else ${permission(action)} end`;
    },
  };
}

/** `on.<type>.scope`, checked against the provider's scopes. */
function subjectScope(
  ctx: BlockSqlContext,
  provider: BlockSqlAccessProvider | undefined,
  type: string,
  subject: Subject,
): string | undefined {
  const scope = subject.extra["scope"];

  if (scope === undefined) {
    return undefined;
  }

  const where = `blocks.${ctx.instance}.on.${type}.scope`;

  if (typeof scope !== "string") {
    throw new TypeError(`${where} must be the name of a provider scope`);
  }

  if (accessModel(ctx) !== "provider" || provider === undefined) {
    throw new TypeError(
      `${where} needs blocks.permissions.model "provider" and an authorization provider that declares the scope`,
    );
  }

  if (scope === provider.scope || !(provider.scopes ?? []).includes(scope)) {
    throw new TypeError(
      `${where}: "${scope}" is not a scope ${provider.name} declares below its tenant scope "${provider.scope}". Scopes: ${(provider.scopes ?? []).filter((name) => name !== provider.scope).join(", ") || "none"}`,
    );
  }

  return scope;
}
