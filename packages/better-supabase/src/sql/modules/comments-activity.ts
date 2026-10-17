import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { hasColumn } from "./audit-columns.ts";

export interface ActivityReads {
  /** The activity_subject_readable function, before the read policy. */
  readonly readable: string;
  /** Drops activity_subject_readable when the policy doesn't call it. */
  readonly dropReadable: string;
  /** The per-row registry check appended to the read policy. */
  readonly rowCheck: string;
  /** list_activity's early return for a subject the caller can't read. */
  readonly gate: string;
  /** Sets v_table to the subject type's registry table. */
  readonly auditSetup: string;
  /** The audit log entries on the subject's row, unioned into the timeline. */
  readonly auditBranch: string;
}

/**
 * How the activity feed reads through the `subjects` registry and the
 * audit log. A registered subject type needs `can_subject(read)`, per row in
 * the read policy and once for a subject's timeline; types the registry
 * doesn't know keep the tenant check alone. With `audit` and its
 * `readPolicy`, a registered subject's timeline also returns the log's
 * entries on its row, which that policy gates by the audit read permission.
 */
export function activityReads(ctx: ModuleContext): ActivityReads {
  const none: ActivityReads = {
    readable: "",
    dropReadable: `\ndrop function if exists ${ctx.fn("activity_subject_readable")}(text, text);`,
    rowCheck: "",
    gate: "",
    auditSetup: "",
    auditBranch: "",
  };

  if (!ctx.installed("subjects")) {
    return none;
  }

  const registry = registeredSubjects(ctx.subjects);

  if (registry.length === 0) {
    return none;
  }

  const a = (logical: string): string => ctx.col("activity", logical);
  const readable = ctx.fn("activity_subject_readable");
  const types = `${sqlString(`{${registry.map((subject) => subject.type).join(",")}}`)}::text[]`;
  const audit = ctx.installed("audit") ? ctx.of("audit") : undefined;

  const auditOn =
    audit !== undefined &&
    audit.mode !== "custom" &&
    audit.flag("readPolicy", false) &&
    hasColumn(audit, "log", "table") &&
    hasColumn(audit, "log", "record");

  return {
    // PL/pgSQL resolves can_subject when it runs: the subjects module
    // installs after this one.
    readable: `-- Whether the caller can read a registered subject (can_subject).
create or replace function ${readable}(subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return coalesce(${ctx.of("subjects").fn("can_subject")}(subject_type, subject_id, 'read'), false);
end;
$$;
revoke execute on function ${readable}(text, text) from public, anon;
grant execute on function ${readable}(text, text) to authenticated, service_role;
`,
    dropReadable: "",
    rowCheck: `
    and (${a("subjectType")} is null or ${a("subjectId")} is null
      or not (${a("subjectType")} = any (${types}))
      or ${readable}(${a("subjectType")}, ${a("subjectId")}))`,
    gate: `
  if list_activity.subject_id is not null and list_activity.subject_type = any (${types})
    and not ${readable}(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;`,
    auditSetup: auditOn
      ? `
  if list_activity.subject_id is not null then
    v_table := case list_activity.subject_type
${registry.map((subject) => `      when ${sqlString(subject.type)} then ${sqlString(`${subject.schema}.${subject.table}`)}`).join("\n")}
    end;
  end if;`
      : "",
    auditBranch: auditOn ? auditBranch(ctx, audit) : "",
  };
}

/** The union branch that reads the audit log's entries on v_table's row. */
function auditBranch(ctx: ModuleContext, audit: ModuleContext): string {
  const a = (logical: string): string =>
    sqlString(ctx.col("activity", logical).replaceAll('"', ""));

  const l = (logical: string): string => `l.${audit.col("log", logical)}`;
  const has = (logical: string): boolean => hasColumn(audit, "log", logical);
  const op = has("op") ? l("op") : "null::text";

  const type = has("eventType")
    ? `coalesce(${l("eventType")}, 'audit.' || ${op})`
    : `'audit.' || coalesce(${op}, 'event')`;

  const data = [
    `'op', ${op}`,
    ...(has("changed") ? [`'changed', to_jsonb(${l("changed")})`] : []),
    `'table', ${l("table")}`,
  ];

  const entry = [
    `${a("id")}, ${l("id")}::text`,
    `${a("tenant")}, ${l("tenant")}`,
    `${a("event")}, null::text`,
    `${a("type")}, ${type}`,
    `${a("actor")}, ${l("actor")}`,
    `${a("subjectType")}, list_activity.subject_type`,
    `${a("subjectId")}, list_activity.subject_id`,
    `${a("summary")}, ${has("summary") ? l("summary") : "null::text"}`,
    `${a("data")}, jsonb_strip_nulls(jsonb_build_object(${data.join(", ")}))`,
    `${a("occurredAt")}, ${l("occurredAt")}`,
    `'source', 'audit'`,
  ];

  return `
    union all
    (select jsonb_build_object(${entry.join(", ")}) as entry,
      ${l("occurredAt")} as at, ${l("id")}::text as id
    from ${audit.table("log")} l
    where v_table is not null
      and ${l("table")} = v_table
      and ${l("record")} = list_activity.subject_id
      and ${ctx.scope.eq(l("tenant"), ctx.scope.value("list_activity.tenant"))}
      and (list_activity.before is null or ${l("occurredAt")} < list_activity.before)
    order by ${l("occurredAt")} desc, ${l("id")} desc
    limit v_limit)`;
}
