import type { ModuleContext } from "./context.ts";

import { sqlIdent, sqlString } from "../core/template.ts";

/**
 * One subject type a module's rows belong to (`options.subjects`): the
 * table its ids point at, and who may read it.
 */
export interface Subject {
  /** `schema.table`, or a table in `public`. */
  readonly table: string;
  /** Default `id`. */
  readonly id?: string;
  /** The subject's tenant column, default `organization_id`. */
  readonly tenant?: string;
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

const BASE_KEYS = new Set(["table", "id", "tenant", "permission", "cascade"]);

/**
 * `sql.modules.<module>.options.subjects`: subject type to
 * `{ table, id?, tenant?, permission?, cascade? }` plus the `extra` keys the
 * module reads.
 */
export function subjectsOption(
  ctx: ModuleContext,
  extraKeys: readonly string[] = [],
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
    const tenant = text("tenant");
    const permission = text("permission");
    return [
      type,
      {
        table: text("table") ?? "",
        ...(id !== undefined && { id }),
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

export const qualifiedTable = (table: string): string => {
  const [schema, name] = table.includes(".")
    ? table.split(".", 2)
    : ["public", table];
  return `${sqlIdent(schema ?? "public")}.${sqlIdent(name ?? table)}`;
};

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
      const extra = subject.permission
        ? ` and coalesce(better_supabase.can('tenant', ${args.tenant}, ${sqlString(subject.permission)}), false)`
        : "";
      return `    when ${sqlString(type)} then exists (select 1 from ${qualifiedTable(subject.table)} s where s.${sqlIdent(subject.id ?? "id")}::text = ${args.id} and s.${sqlIdent(subject.tenant ?? "organization_id")} = ${args.tenant})${extra}`;
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
