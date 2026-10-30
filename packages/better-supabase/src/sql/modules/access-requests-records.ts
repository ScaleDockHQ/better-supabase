import type { BlockSqlContext } from "../context.ts";
import type { RegisteredSubject } from "../subject-registry.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { uniqueContributions } from "../contributions.ts";
import { fail, pageSize, SERVICE_CALLER, userGrant } from "../shared.ts";
import { registeredSubjects, teamActions } from "../subject-registry.ts";
import { OPERATIONS } from "./permissions-model.ts";

const WHERE = "blocks.access-requests.options";

/** The columns a record request adds; an adopted table may leave them out. */
export const RECORD_COLUMNS = [
  "target",
  "subjectType",
  "subjectId",
  "action",
  "emergency",
  "member",
  "reviewVerdict",
  "reviewNote",
  "reviewedBy",
  "reviewedAt",
] as const;

/** What the record functions share with the rest of the module. */
export interface RecordAccessKit {
  readonly requests: string;
  readonly c: (column: string) => string;
  readonly json: (row: string, state: string) => string;
  readonly record: (event: string, row: string, extra?: string) => string;
  readonly reasonOf: (row: string) => string;
  readonly hasReason: boolean;
  readonly policy: string;
  readonly max: string | undefined;
  readonly approvals: BlockSqlContext;
  readonly membership: (tenant: string) => string;
  /** A request's status over its row and its approval row. */
  readonly status: (row: string, approval: string) => string;
  /** The `access_requests.read` permission check. */
  readonly read: string;
}

/** A record type a request can name, with the actions it can ask for. */
interface RequestableType {
  readonly subject: RegisteredSubject;
  readonly actions: readonly string[];
  /** The accessGrant function that grants it instead of a team row. */
  readonly grant: string | undefined;
  /** The accessGrant function that names approvers without a team lead. */
  readonly approvers: string | undefined;
}

/**
 * Whether record requests render: subjects is installed and renders its record
 * team with `endsAt`, and the requests table has the record columns.
 */
export function recordsEnabled(ctx: BlockSqlContext): boolean {
  if (!ctx.installed("subjects")) {
    return false;
  }

  const subjects = ctx.of("subjects");

  return (
    subjects.mode !== "custom" &&
    subjects.hasTable("members") &&
    subjects.has("members", "endsAt") &&
    RECORD_COLUMNS.every((column) => ctx.has("requests", column))
  );
}

/** `options.emergency.maxHours`, default 8. */
function emergencyHours(ctx: BlockSqlContext): number {
  const raw = ctx.option("emergency");

  if (raw === undefined) {
    return 8;
  }

  const hours = isRecord(raw) ? raw["maxHours"] : undefined;

  if (
    !isRecord(raw) ||
    Object.keys(raw).some((key) => key !== "maxHours") ||
    (hours !== undefined &&
      (typeof hours !== "number" ||
        !Number.isInteger(hours) ||
        hours < 1 ||
        hours > 168))
  ) {
    throw new TypeError(
      `${WHERE}.emergency must be { maxHours } with a whole number of hours from 1 to 168`,
    );
  }

  return typeof hours === "number" ? hours : 8;
}

function requestableTypes(ctx: BlockSqlContext): readonly RequestableType[] {
  const subjects = ctx.of("subjects");

  const grants = uniqueContributions(
    "access-requests",
    ctx.contributions("access-requests"),
    (each) => each.subject,
  );

  const registered = registeredSubjects(subjects.subjects, subjects.naming);

  const withTeam = registered.filter(
    (subject) => teamActions(subject).length > 0,
  );

  for (const each of grants) {
    if (!withTeam.some((subject) => subject.type === each.subject)) {
      throw new TypeError(
        `An accessGrant contribution names subject "${each.subject}", which needs subjects.${each.subject}.team`,
      );
    }
  }

  return withTeam.map((subject) => {
    const contribution = grants.find((each) => each.subject === subject.type);

    return {
      subject,
      actions: teamActions(subject),
      grant: contribution?.grant,
      approvers: contribution?.approvers,
    };
  });
}

/** Request, emergency, review and list functions for record access. */
export function recordAccessSql(
  ctx: BlockSqlContext,
  kit: RecordAccessKit,
): string {
  const { requests, c, json, record, reasonOf, hasReason } = kit;
  const fn = (name: string): string => ctx.fn(name);
  const subjects = ctx.of("subjects");
  const sfn = (name: string): string => subjects.fn(name);
  const ar = kit.approvals.table("requests");
  const a = (column: string): string => kit.approvals.col("requests", column);
  const types = requestableTypes(ctx);
  const create = ctx.permission("create", OPERATIONS["access-requests.create"]);

  const emergency = ctx.permission(
    "emergency",
    OPERATIONS["access-requests.emergency"],
  );

  const review = ctx.permission("review", OPERATIONS["access-requests.review"]);

  const reviewKey = ctx.permissionKey(
    "review",
    OPERATIONS["access-requests.review"],
  );

  const manageKey = subjects.permissionKey(
    "manage",
    OPERATIONS["subjects.manage"],
  );

  const hours = emergencyHours(ctx);

  const typeList =
    types.length === 0
      ? "array[]::text[]"
      : `array[${types.map((each) => sqlString(each.subject.type)).join(", ")}]::text[]`;

  // Parenthesized: PL/pgSQL ends an `if` condition at the first bare `then`.
  const actionCheck = (type: string, action: string): string =>
    types.length === 0
      ? "true"
      : `(case ${type}
      ${types.map((each) => `when ${sqlString(each.subject.type)} then not (${action} = any (array[${each.actions.map(sqlString).join(", ")}]::text[]))`).join("\n      ")}
      else true end)`;

  const typeCheck = (type: string, action: string): string => `
  if not (${type} = any (${typeList})) or ${actionCheck(type, action)} then
    ${fail("ACCESS_REQUEST_RECORD_INVALID", "this record or action can't be requested", "22023")}
  end if;`;

  const reasonColumn = hasReason ? `${c("reason")}, ` : "";

  const named = types.filter((each) => each.approvers !== undefined);

  const approverFallback =
    named.length === 0
      ? ""
      : `
  if coalesce(cardinality(v_leads), 0) = 0 then
    v_leads := case request_record_access.subject_type
      ${named.map((each) => `when ${sqlString(each.subject.type)} then array_remove(${each.approvers}(request_record_access.subject_id), v_me)`).join("\n      ")}
      else v_leads end;
  end if;`;

  const isApprover =
    named.length === 0
      ? "false"
      : `coalesce(auth.uid() = any (case list_record_access_requests.subject_type
      ${named.map((each) => `when ${sqlString(each.subject.type)} then ${each.approvers}(list_record_access_requests.subject_id)`).join("\n      ")}
      end), false)`;

  return `
-- Asks for access to one record: its team leads approve, then the record's
-- own approvers when its type names them, or the holders of subjects.manage.
-- The final approval adds a team row (or the record's accessGrant) that ends
-- after the duration.
create or replace function ${fn("request_record_access")}(subject_type text, subject_id text, action text default 'read', reason text default null, duration interval default interval '7 days')
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant ${ctx.idType};
  v_duration interval := coalesce(request_record_access.duration, ${kit.max === undefined ? "interval '7 days'" : `least(interval '7 days', ${sqlString(kit.max)}::interval)`});
  v_leads uuid[];
  v_row ${requests}%rowtype;
  v_approval jsonb;
begin
  if v_me is null then
    ${fail("ACCESS_SIGN_IN", "sign in to request access")}
  end if;${typeCheck("request_record_access.subject_type", "request_record_access.action")}
  v_tenant := ${sfn("record_team_tenant")}(request_record_access.subject_type, request_record_access.subject_id);
  if v_tenant is null then
    ${fail("ACCESS_REQUEST_RECORD_INVALID", "record not found", "P0002")}
  end if;
  if not ${kit.membership("v_tenant")} or not ${ctx.can("tenant", "v_tenant", create)} then
    ${fail("ACCESS_REQUEST_FORBIDDEN", "not allowed to request access here")}
  end if;
  if ${sfn("can_subject")}(request_record_access.subject_type, request_record_access.subject_id, request_record_access.action) then
    ${fail("ACCESS_REQUEST_RECORD_INVALID", "you already have this access", "22023")}
  end if;${
    kit.max === undefined
      ? ""
      : `
  if v_duration > ${sqlString(kit.max)}::interval then
    ${fail("ACCESS_DURATION_INVALID", `access can last at most ${kit.max}`, "22023")}
  end if;`
  }
  if v_duration <= interval '0' then
    ${fail("ACCESS_DURATION_INVALID", "duration must be positive", "22023")}
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_record_access.subject_type || ':' || request_record_access.subject_id || ':' || v_me::text, 0));
  if exists (
    select 1 from ${requests} r join ${ar} x on x.${a("id")} = r.${c("approval")}
    where r.${c("subjectType")} = request_record_access.subject_type and r.${c("subjectId")} = request_record_access.subject_id
      and r.${c("user")} = v_me and x.${a("status")} = 'pending'
  ) then
    ${fail("ACCESS_REQUEST_PENDING", "you already have a pending access request for this record", "23505")}
  end if;
  insert into ${requests} (${c("tenant")}, ${c("user")}, ${c("target")}, ${c("subjectType")}, ${c("subjectId")}, ${c("action")}, ${reasonColumn}${c("duration")})
  values (v_tenant, v_me, 'record', request_record_access.subject_type, request_record_access.subject_id, request_record_access.action, ${hasReason ? "request_record_access.reason, " : ""}v_duration)
  returning * into v_row;
  v_leads := ${sfn("record_team_leads")}(request_record_access.subject_type, request_record_access.subject_id);${approverFallback}
  v_approval := ${kit.approvals.fn("open_approval")}(
    v_tenant, 'access_request', v_row.${c("id")}::text, 'grant',
    ${sqlString(kit.policy)}::jsonb || jsonb_build_object('steps', jsonb_build_array(jsonb_build_object(
      'approvers', case when cardinality(v_leads) > 0 then jsonb_build_object('users', to_jsonb(v_leads)) else jsonb_build_object('permission', ${sqlString(manageKey)}) end,
      'required', 1))),
    request_record_access.reason,
    jsonb_build_object('subjectType', request_record_access.subject_type, 'subjectId', request_record_access.subject_id, 'action', request_record_access.action, 'userId', v_me, 'duration', v_duration::text)
  );
  update ${requests} r set ${c("approval")} = (v_approval ->> 'id')::uuid
  where r.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${record("access.requested", "v_row")}
  return ${json("v_row", "'pending'")};
end;
$$;
${userGrant(`${fn("request_record_access")}(text, text, text, text, interval)`)}

-- Break-the-glass: read access to one record right away, for at most
-- options.emergency.maxHours, with a reason that a reviewer checks later.
create or replace function ${fn("open_emergency_access")}(subject_type text, subject_id text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant ${ctx.idType};
  v_row ${requests}%rowtype;
  v_claims text;
begin
  if v_me is null then
    ${fail("ACCESS_SIGN_IN", "sign in to open emergency access")}
  end if;
  if length(btrim(coalesce(open_emergency_access.reason, ''))) < 10 then
    ${fail("ACCESS_REQUEST_REASON_REQUIRED", "say why you need emergency access, in at least 10 characters", "22023")}
  end if;${typeCheck("open_emergency_access.subject_type", "'read'")}
  v_tenant := ${sfn("record_team_tenant")}(open_emergency_access.subject_type, open_emergency_access.subject_id);
  if v_tenant is null then
    ${fail("ACCESS_REQUEST_RECORD_INVALID", "record not found", "P0002")}
  end if;
  if not ${kit.membership("v_tenant")} or not ${ctx.can("tenant", "v_tenant", emergency)} then
    ${fail("ACCESS_REQUEST_FORBIDDEN", "not allowed to open emergency access here")}
  end if;
  insert into ${requests} (${c("tenant")}, ${c("user")}, ${c("target")}, ${c("subjectType")}, ${c("subjectId")}, ${c("action")}, ${c("emergency")}, ${reasonColumn}${c("duration")})
  values (v_tenant, v_me, 'record', open_emergency_access.subject_type, open_emergency_access.subject_id, 'read', true, ${hasReason ? "btrim(open_emergency_access.reason), " : ""}interval '${hours} hours')
  returning * into v_row;
  perform ${fn("grant_access_request")}(v_row.${c("id")});
  select * into v_row from ${requests} r where r.${c("id")} = v_row.${c("id")};
  ${ctx.notify(
    `jsonb_build_object(
      'type', 'access_request.emergency_opened',
      'tenant', v_tenant,
      'actor', v_me,
      'subject_type', open_emergency_access.subject_type,
      'subject_id', open_emergency_access.subject_id,
      'summary', btrim(open_emergency_access.reason),
      'recipients', to_jsonb(${sfn("record_team_leads")}(open_emergency_access.subject_type, open_emergency_access.subject_id)),
      'permission', ${sqlString(reviewKey)},
      'watchers', false,
      'key', 'access_request.emergency_opened:' || v_row.${c("id")}::text,
      'data', jsonb_build_object('accessRequestId', v_row.${c("id")})
    )`,
    { indent: "  " },
  )}
  ${record("access_request.emergency_opened", "v_row", `, 'reason', ${reasonOf("v_row")}`)}
  return ${json("v_row", "'granted'")};
end;
$$;
${userGrant(`${fn("open_emergency_access")}(text, text, text)`)}

-- Records whether an emergency access was justified. Needs
-- access_requests.review; nobody reviews their own.
create or replace function ${fn("review_emergency_access")}(request_id uuid, verdict text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_row ${requests}%rowtype;
begin
  if review_emergency_access.verdict is null or review_emergency_access.verdict not in ('justified', 'unjustified') then
    ${fail("ACCESS_REQUEST_REVIEW_INVALID", "verdict must be justified or unjustified", "22023")}
  end if;
  if length(review_emergency_access.note) > 2000 then
    ${fail("ACCESS_REQUEST_REVIEW_INVALID", "a note is at most 2000 characters", "22023")}
  end if;
  select * into v_row from ${requests} r where r.${c("id")} = review_emergency_access.request_id and r.${c("emergency")} for update;
  if not found then
    ${fail("ACCESS_REQUEST_NOT_FOUND", "emergency access not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${c("tenant")}`, review)}) then
    ${fail("ACCESS_REQUEST_FORBIDDEN", "not allowed to review emergency access")}
  end if;
  if v_row.${c("user")} = auth.uid() then
    ${fail("ACCESS_REQUEST_REVIEW_INVALID", "you can't review your own emergency access", "22023")}
  end if;
  if v_row.${c("reviewedAt")} is not null then
    ${fail("ACCESS_REQUEST_REVIEW_INVALID", "this emergency access is already reviewed", "22023")}
  end if;
  update ${requests} r
  set ${c("reviewVerdict")} = review_emergency_access.verdict,
      ${c("reviewNote")} = nullif(btrim(review_emergency_access.note), ''),
      ${c("reviewedBy")} = auth.uid(),
      ${c("reviewedAt")} = now()
  where r.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${record("access_request.emergency_reviewed", "v_row", `, 'verdict', v_row.${c("reviewVerdict")}`)}
  return ${json("v_row", `case when v_row.${c("endedAt")} is not null then 'ended' else 'granted' end`)};
end;
$$;
${userGrant(`${fn("review_emergency_access")}(uuid, text, text)`)}

-- Emergency accesses in an organization, newest first; by default the ones
-- nobody has reviewed. Empty for a caller without access_requests.review.
create or replace function ${fn("list_emergency_access")}(tenant ${ctx.idType}, unreviewed boolean default true, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
  select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
  from (
    select ${json("r", `case when r.${c("endedAt")} is not null then 'ended' else 'granted' end`)} as item, r.${c("createdAt")} as created
    from ${requests} r
    where r.${c("tenant")} = list_emergency_access.tenant and r.${c("emergency")}
      and (${SERVICE_CALLER} or ${ctx.can("tenant", "list_emergency_access.tenant", review)})
      and (not coalesce(list_emergency_access.unreviewed, true) or r.${c("reviewedAt")} is null)
      and (list_emergency_access.before is null or r.${c("createdAt")} < list_emergency_access.before)
    order by r.${c("createdAt")} desc
    limit ${pageSize("list_emergency_access.page_size", 50, 200)}
  ) items
$$;
${userGrant(`${fn("list_emergency_access")}(${ctx.idType}, boolean, integer, timestamptz)`)}

-- The access requests on one record, newest first: every one for a holder of
-- access_requests.read, a team lead or one of the record's approvers, and the
-- caller's own for anyone else.
create or replace function ${fn("list_record_access_requests")}(subject_type text, subject_id text, status text default null, page_size integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_all boolean;
begin
  v_tenant := ${sfn("record_team_tenant")}(list_record_access_requests.subject_type, list_record_access_requests.subject_id);
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  v_all := ${SERVICE_CALLER} or ${ctx.can("tenant", "v_tenant", kit.read)}
    or coalesce(auth.uid() = any (${sfn("record_team_leads")}(list_record_access_requests.subject_type, list_record_access_requests.subject_id)), false)
    or ${isApprover};
  return (
    select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
    from (
      select ${json("r", kit.status("r", "x"))} as item, r.${c("createdAt")} as created
      from ${requests} r
      left join ${ar} x on x.${a("id")} = r.${c("approval")}
      where r.${c("tenant")} = v_tenant and r.${c("target")} = 'record'
        and r.${c("subjectType")} = list_record_access_requests.subject_type and r.${c("subjectId")} = list_record_access_requests.subject_id
        and (v_all or r.${c("user")} = auth.uid())
        and (list_record_access_requests.status is null or ${kit.status("r", "x")} = list_record_access_requests.status)
      order by r.${c("createdAt")} desc
      limit ${pageSize("list_record_access_requests.page_size", 50, 200)}
    ) items
  );
end;
$$;
${userGrant(`${fn("list_record_access_requests")}(text, text, text, integer)`)}
`;
}

/** Grants a record request's access until `v_ends`; sets `v_member`. */
export function grantRecordSql(
  ctx: BlockSqlContext,
  kit: RecordAccessKit,
): string {
  const { c, reasonOf } = kit;
  const subjects = ctx.of("subjects");

  const grants = requestableTypes(ctx).filter(
    (each) => each.grant !== undefined,
  );

  const member = `v_member := ${subjects.fn("grant_subject_member")}(v_row.${c("subjectType")}, v_row.${c("subjectId")}, v_row.${c("user")}, v_ends, v_row.${c("emergency")}, ${reasonOf("v_row")});`;

  if (grants.length === 0) {
    return `
    ${member}`;
  }

  return `
    case v_row.${c("subjectType")}
    ${grants
      .map(
        (each) => `when ${sqlString(each.subject.type)} then
      perform ${each.grant}(v_row.${c("subjectId")}, v_row.${c("user")}, v_row.${c("action")}, v_ends);`,
      )
      .join("\n    ")}
    else
      ${member}
    end case;`;
}

/** Ends a record request's access now. */
export function endRecordSql(
  ctx: BlockSqlContext,
  kit: RecordAccessKit,
): string {
  const { c } = kit;
  const subjects = ctx.of("subjects");

  const grants = requestableTypes(ctx).filter(
    (each) => each.grant !== undefined,
  );

  const member = `if v_row.${c("member")} is not null then
        perform ${subjects.fn("close_subject_member")}(v_row.${c("member")});
      end if;`;

  if (grants.length === 0) {
    return `
    ${member}`;
  }

  return `
    case v_row.${c("subjectType")}
    ${grants
      .map(
        (each) => `when ${sqlString(each.subject.type)} then
      perform ${each.grant}(v_row.${c("subjectId")}, v_row.${c("user")}, v_row.${c("action")}, now());`,
      )
      .join("\n    ")}
    else
      ${member}
    end case;`;
}
