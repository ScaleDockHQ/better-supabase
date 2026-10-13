import type { ModuleContext } from "./context.ts";
import type { ModuleAccessProvider } from "./module-types.ts";

import { fillTemplate } from "../core/access-sql.ts";
import { sqlIdent, sqlString } from "../core/template.ts";
import { accessModel } from "./modules/access-model.ts";
import { quotedTable, splitTable, tenantIn } from "./shared.ts";

/**
 * One subject type a module's rows belong to (`options.subjects`): the
 * table its ids point at, and who may read it.
 */
export interface Subject {
  /** `schema.table`, or a table in `public`. */
  readonly table: string;
  /** Default `id`. */
  readonly id?: string;
  /**
   * The id column's type, such as `uuid` or `bigint`. With it, the stored
   * text id is cast to that type, so the lookup uses the subject table's
   * primary key; without it the column is cast to text, which can't.
   */
  readonly idType?: string;
  /**
   * The subject's tenant column, default `organization_id`. `false` for a
   * subject without a tenant (a user's own records), where the subject
   * table's policies alone decide, in modules that allow it.
   */
  readonly tenant?: string | false;
  /** A permission the caller also needs in the tenant, e.g. `projects.read`. */
  readonly permission?: string;
  /** Delete the module's rows for a subject when the subject row is deleted. */
  readonly cascade?: boolean;
  /** The module's own keys, such as a bucket per subject. */
  readonly extra: Readonly<Record<string, unknown>>;
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const SUBJECT_TYPE: RegExp = /^[a-z][a-z0-9_]{0,62}$/;

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

/**
 * `sql.modules.<module>.options.subjects`: subject type to
 * `{ table, id?, tenant?, permission?, cascade? }` plus the `extra` keys the
 * module reads.
 */
export function subjectsOption(
  ctx: ModuleContext,
  extraKeys: readonly string[] = [],
  allow: { readonly tenantless?: boolean } = {},
): readonly [string, Subject][] {
  const where = `sql.modules.${ctx.module}.options.subjects`;
  const raw = ctx.option("subjects");
  if (raw === undefined) return [];
  if (!isObject(raw)) {
    throw new TypeError(
      `${where}: pass an object of subject type to { table, id?, tenant?, permission?, cascade? }`,
    );
  }
  return Object.entries(raw).map(([type, entry]): [string, Subject] => {
    if (!SUBJECT_TYPE.test(type)) {
      throw new TypeError(
        `${where}: "${type}" must be lowercase letters, digits and underscores`,
      );
    }
    if (!isObject(entry) || typeof entry["table"] !== "string") {
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
      if (value === undefined) return undefined;
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

export const qualifiedTable = (table: string): string => quotedTable(table);

const COLUMN_NAME = /^[a-z_][a-z0-9_]*$/;

/**
 * One adopted table a subject carries (`options.subjects.<type>.<key>`),
 * so a module can write per-entity link or history tables instead of one
 * polymorphic table. ADR 0018.
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
 * `options.subjects.<type>.<key>` as `{ table, <column>... }`. Undefined
 * when the subject doesn't set it (the module's polymorphic table is used).
 * `columns` are required; `optional` may be omitted.
 */
function subjectTableBinding(
  ctx: ModuleContext,
  type: string,
  subject: Subject,
  key: string,
  spec: {
    readonly columns: readonly string[];
    readonly optional?: readonly string[];
  },
): SubjectTableBinding | undefined {
  const raw = subject.extra[key];
  if (raw === undefined) return undefined;
  const where = `sql.modules.${ctx.module}.options.subjects.${type}.${key}`;
  if (!isObject(raw) || typeof raw["table"] !== "string") {
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
  const optional = new Set(spec.optional ?? []);
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
    if (value === undefined) continue;
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

/** Every subject table binding `key` declares, for adopt-mode column checks. */
export function subjectTableBindings(
  ctx: ModuleContext,
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
 * Whether the caller may read the subject `type`/`id` in `tenant`: its row
 * is visible to them (the subject table's own policies apply) and they hold
 * its permission. `true` without `subjects`, `false` for an unlisted type.
 */
export function subjectReadable(
  subjects: readonly (readonly [string, Subject])[],
  args: { readonly type: string; readonly id: string; readonly tenant: string },
): string {
  if (subjects.length === 0) return "true";
  return `case ${args.type}\n${subjects
    .map(([type, subject]) => {
      if (subject.tenant === false) {
        return `    when ${sqlString(type)} then exists (select 1 from ${qualifiedTable(subject.table)} s where ${subjectIdMatches(subject, args.id)})`;
      }
      const extra = subject.permission
        ? ` and coalesce(better_supabase.can('tenant', ${args.tenant}, ${sqlString(subject.permission)}), false)`
        : "";
      return `    when ${sqlString(type)} then exists (select 1 from ${qualifiedTable(subject.table)} s where ${subjectIdMatches(subject, args.id)} and s.${sqlIdent(subject.tenant ?? "organization_id")} = ${args.tenant})${extra}`;
    })
    .join("\n")}\n    else false\n  end`;
}

/**
 * `after delete` triggers on the subject tables with `cascade: true` that
 * delete the module's rows for the deleted subject. `remove` is the SQL that
 * deletes them, with `v_type` and `v_id` (text) in scope.
 */
export function subjectCascades(
  ctx: ModuleContext,
  subjects: readonly (readonly [string, Subject])[],
  remove: string,
): string {
  const cascading = subjects.filter(([, subject]) => subject.cascade);
  if (cascading.length === 0) return "";
  const name = `${ctx.module.replaceAll("-", "_")}_subject_deleted`;
  const fn = ctx.fn(name);
  const triggers = cascading.map(([type, subject]) => {
    const trigger = sqlIdent(
      `bs_${ctx.module.replaceAll("-", "_")}_${type}_cascade`.slice(0, 63),
    );
    const table = qualifiedTable(subject.table);
    return `drop trigger if exists ${trigger} on ${table};
create trigger ${trigger}
  after delete on ${table}
  for each row execute function ${fn}(${sqlString(type)}, ${sqlString(subject.id ?? "id")});`;
  });
  return `
-- options.subjects with cascade: deleting a subject row deletes its ${ctx.module} rows.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
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
   * Whether the caller holds the action's key for a row of subject `type`
   * and `id` in `tenant`: in the tenant, or on the subject record itself when
   * its type sets `scope`. One `can()` call per row, for functions.
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
 * The checks for `options.subjects.<type>.permissions` (a key per action in
 * place of the module's) and `options.subjects.<type>.scope` (a scope the
 * authorization provider declares, whose ids are the subject ids, so a grant
 * on the record counts as well as one on the tenant).
 */
export function subjectAccess<A extends string>(
  ctx: ModuleContext,
  options: {
    readonly subjects: readonly (readonly [string, Subject])[];
    readonly actions: readonly A[];
    /** The module's key for an action, as a SQL literal. */
    readonly permission: (action: A) => string;
    readonly provider: ModuleAccessProvider | undefined;
  },
): SubjectAccess<A> {
  const { subjects, actions, permission, provider } = options;
  const where = `sql.modules.${ctx.module}.options.subjects`;
  const allowed: ReadonlySet<string> = new Set(actions);
  const entries = subjects.map(([type, subject]) => {
    const keys = new Map<string, string>();
    const raw = subject.extra["permissions"];
    if (raw !== undefined) {
      if (!isObject(raw)) {
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
  return {
    canOn(tenant, type, id, action) {
      const list = keyed(action);
      if (list.length === 0) return can(tenant, permission(action));
      if (scoped) return branches(action, type, id, (key) => can(tenant, key));
      const cases = list.map(
        (entry) => `when ${sqlString(entry.type)} then ${entry.key}`,
      );
      return `coalesce(better_supabase.can('tenant', ${tenant}, case ${type} ${cases.join(" ")} else ${permission(action)} end), false)`;
    },
    memberOn(tenant, type, id, action) {
      if (keyed(action).length === 0)
        return tenantIn(tenant, permission(action));
      return branches(action, type, id, (key) => tenantIn(tenant, key));
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

/** `options.subjects.<type>.scope`, checked against the provider's scopes. */
function subjectScope(
  ctx: ModuleContext,
  provider: ModuleAccessProvider | undefined,
  type: string,
  subject: Subject,
): string | undefined {
  const scope = subject.extra["scope"];
  if (scope === undefined) return undefined;
  const where = `sql.modules.${ctx.module}.options.subjects.${type}.scope`;
  if (typeof scope !== "string") {
    throw new TypeError(`${where} must be the name of a provider scope`);
  }
  if (accessModel(ctx) !== "provider" || provider === undefined) {
    throw new TypeError(
      `${where} needs sql.modules.access.model "provider" and an authorization provider that declares the scope`,
    );
  }
  if (scope === provider.scope || !(provider.scopes ?? []).includes(scope)) {
    throw new TypeError(
      `${where}: "${scope}" is not a scope ${provider.name} declares below its tenant scope "${provider.scope}". Scopes: ${(provider.scopes ?? []).filter((name) => name !== provider.scope).join(", ") || "none"}`,
    );
  }
  return scope;
}
