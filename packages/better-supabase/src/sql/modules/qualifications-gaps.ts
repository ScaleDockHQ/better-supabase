import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  activeMembership,
  fail,
  SERVICE_CALLER,
  serviceGrant,
  triggerGrant,
  userGrant,
} from "../shared.ts";
import { roleNameOf } from "./memberships.ts";
import { moduleOperations } from "./permissions-model.ts";
import {
  expiry,
  holderCondition,
  holdingRecord,
} from "./qualifications-functions.ts";
import {
  holderTitle,
  holderTypes,
  renewalWindow,
} from "./qualifications-shared.ts";

/**
 * The gap report, the holders qualified on a date, the expiry notifications and
 * the holdings granted from course certificates.
 */
export function qualificationGapFunctions(ctx: BlockSqlContext): string {
  const types = ctx.table("types");
  const requirements = ctx.table("requirements");
  const holdings = ctx.table("qualifications");
  const t = (column: string): string => ctx.col("types", column);
  const r = (column: string): string => ctx.col("requirements", column);
  const q = (column: string): string => ctx.col("qualifications", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("qualifications");
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const members = ctx.of("memberships");
  const m = (column: string): string => members.col("memberships", column);
  const days = String(renewalWindow(ctx));
  const allowedHolders = holderTypes(ctx);
  const tenant = "qualification_gaps.tenant";

  const isMember = (tenantExpr: string, user: string): string =>
    `exists (select 1 from ${members.table("memberships")} mm where mm.${m("tenant")} = ${tenantExpr} and mm.${m("user")} = ${user}${activeMembership(members, "mm")})`;

  // The holders of each type the report covers, as (id, title) rows.
  const holderRows = allowedHolders
    .flatMap((type) => {
      const title = holderTitle(ctx, type, "h.id", tenant);

      if (title === undefined) {
        return [];
      }

      const source = holderSource(ctx, type, tenant);

      return source === undefined
        ? []
        : [
            `select h.id, ${title} as title from (${source}) h where qualification_gaps.holder_type = ${sqlString(type)}`,
          ];
    })
    .join("\n      union all\n      ");

  const teams = ctx.installed("teams") ? ctx.of("teams") : undefined;

  const teamFilter =
    teams === undefined
      ? ""
      : ` and (v_team is null or (qualification_gaps.holder_type = 'member' and exists (select 1 from ${teams.table("members")} tm where tm.${teams.col("members", "team")}::text = v_team and tm.${teams.col("members", "user")}::text = h.id)))`;

  const target = `rq.${r("targetValue")}`;

  const matches = [
    `when 'holder' then ${target} = h.id`,
    `when 'role' then qualification_gaps.holder_type = 'member' and exists (select 1 from ${members.table("memberships")} m2 where m2.${m("tenant")} = ${tenant} and m2.${m("user")}::text = h.id and ${roleNameOf(members, "m2")}::text = ${target}${activeMembership(members, "m2")})`,
    ...targetMatches(ctx, tenant, target),
  ];

  const holderExists = (tenantExpr: string, type: string, id: string): string =>
    `case ${type}
      when 'member' then exists (select 1 from ${members.table("memberships")} mh where mh.${m("tenant")} = ${tenantExpr} and mh.${m("user")}::text = ${id}${activeMembership(members, "mh")})${allowedHolders
        .filter((holder) => holder !== "member")
        .map((holder) => {
          const condition = holderCondition(ctx, holder, tenantExpr, id);

          return condition === undefined
            ? ""
            : `\n      when ${sqlString(holder)} then ${condition}`;
        })
        .join("")}
      else false
    end`;

  const subjectType = sqlString(
    ctx.resolved.entityNaming.rename("qualification_type"),
  );

  const notify = ctx.installed("notifications")
    ? `
    ${ctx.notify(
      `jsonb_build_object(
        'type', 'qualification.' || v_status,
        'tenant', v_row.${q("tenant")},
        'actor', null,
        'subject_type', ${subjectType},
        'subject_id', v_type.${t("id")}::text,
        'summary', v_type.${t("name")},
        'recipients', case when v_row.${q("holderType")} = 'member' then jsonb_build_array(v_row.${q("holderId")}) else (select coalesce(jsonb_agg(mn.${m("user")}), '[]'::jsonb) from ${members.table("memberships")} mn where mn.${m("tenant")} = v_row.${q("tenant")}${activeMembership(members, "mn")} and ${ctx.scope.canUser(`mn.${m("user")}`, `v_row.${q("tenant")}`, manage)}) end,
        'key', 'qualification.' || v_status || ':' || v_row.${q("id")}::text,
        'data', jsonb_build_object('qualificationId', v_row.${q("id")}, 'typeKey', v_type.${t("key")}, 'holderType', v_row.${q("holderType")}, 'holderId', v_row.${q("holderId")}, 'expiresOn', v_row.${q("expiresOn")})
      )`,
      { indent: "    " },
    )}`
    : "";

  const expiryRecord = (event: string): string =>
    holdingRecord(ctx, {
      event,
      row: "v_row",
      type: "v_type",
      extra: `, 'expiresOn', v_row.${q("expiresOn")}`,
      summary: "''",
      audit: false,
    });

  return `
-- The gaps of one holder type: each (holder, type) a requirement asks for
-- and the holder doesn't hold validly, as missing, expired or expiring.
-- filters takes typeKey, teamId (members of a team), status and holderId.
-- Members may read their own gaps (holderId is their user id).
create or replace function ${fn("qualification_gaps")}(tenant ${idType}, holder_type text default 'member', filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_filters jsonb := coalesce(qualification_gaps.filters, '{}'::jsonb);
  v_holder text := nullif(v_filters ->> 'holderId', '');
  v_team text := nullif(v_filters ->> 'teamId', '');
  v_type_key text := nullif(v_filters ->> 'typeKey', '');
  v_status text := nullif(v_filters ->> 'status', '');
  v_result jsonb;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", tenant, read)}
    or (qualification_gaps.holder_type = 'member' and v_holder is not null and v_holder = (select auth.uid())::text and ${isMember(tenant, "(select auth.uid())")})) then
    ${fail("QUALIFICATION_FORBIDDEN", "not allowed to read qualifications")}
  end if;
  if v_status is not null and v_status not in ('missing', 'expired', 'expiring') then
    ${fail("QUALIFICATION_INVALID", "status is missing, expired or expiring", "22023")}
  end if;${
    teams === undefined
      ? `
  if v_team is not null then
    ${fail("QUALIFICATION_INVALID", "the teamId filter needs the teams block", "22023")}
  end if;`
      : ""
  }
  with holders as (
      ${holderRows === "" ? "select null::text as id, null::text as title where false" : holderRows}
  ), required as (
    select distinct h.id as holder_id, h.title, y.${t("id")} as type_id, y.${t("key")} as type_key, y.${t("name")} as type_name
    from holders h
    join ${types} y on y.${t("tenant")} = ${tenant} and y.${t("archivedAt")} is null and qualification_gaps.holder_type = any(y.${t("holderTypes")})
      and (v_type_key is null or y.${t("key")} = v_type_key)
    join ${requirements} rq on rq.${r("type")} = y.${t("id")}
    where (v_holder is null or h.id = v_holder)${teamFilter}
      and case rq.${r("targetType")}::text
        ${matches.join("\n        ")}
        else false
      end
  ), rated as (
    select rq.*, s.valid_until from required rq
    left join lateral (
      select max(coalesce(x.${q("expiresOn")}, 'infinity'::date)) as valid_until
      from ${holdings} x
      where x.${q("type")} = rq.type_id and x.${q("holderType")} = qualification_gaps.holder_type and x.${q("holderId")} = rq.holder_id
        and x.${q("revokedAt")} is null and x.${q("grantedOn")} <= current_date
    ) s on true
  ), gaps as (
    select rt.*, case
      when rt.valid_until is null then 'missing'
      when rt.valid_until < current_date then 'expired'
      when rt.valid_until <= current_date + ${days} then 'expiring'
    end as status
    from rated rt
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'holderType', qualification_gaps.holder_type,
    'holderId', g.holder_id,
    'holderTitle', g.title,
    'typeKey', g.type_key,
    'typeName', g.type_name,
    'status', g.status,
    'expiresOn', case when g.status = 'missing' then null else g.valid_until end
  ) order by g.title, g.holder_id, g.type_name), '[]'::jsonb)
  into v_result
  from gaps g
  where g.status is not null and (v_status is null or g.status = v_status);
  return v_result;
end;
$$;
${userGrant(`${fn("qualification_gaps")}(${idType}, text, jsonb)`)}

-- The ids of the holders of one type that hold it validly on on_date, for
-- shift planning and party roles. Members of the organization may call it.
create or replace function ${fn("qualified_holders")}(tenant ${idType}, type_key text, holder_type text default 'member', on_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_on date := coalesce(qualified_holders.on_date, current_date);
  v_result jsonb;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "qualified_holders.tenant", read)} or ${isMember("qualified_holders.tenant", "(select auth.uid())")}) then
    ${fail("QUALIFICATION_FORBIDDEN", "not allowed to read qualifications")}
  end if;
  select coalesce(jsonb_agg(distinct x.${q("holderId")} order by x.${q("holderId")}), '[]'::jsonb)
  into v_result
  from ${holdings} x
  join ${types} y on y.${t("id")} = x.${q("type")}
  where y.${t("tenant")} = qualified_holders.tenant and y.${t("key")} = qualified_holders.type_key
    and x.${q("holderType")} = qualified_holders.holder_type
    and x.${q("grantedOn")} <= v_on
    and (x.${q("expiresOn")} is null or x.${q("expiresOn")} >= v_on)
    and (x.${q("revokedAt")} is null or x.${q("revokedAt")}::date > v_on)
    and ${holderExists("qualified_holders.tenant", `x.${q("holderType")}`, `x.${q("holderId")}`)};
  return v_result;
end;
$$;
${userGrant(`${fn("qualified_holders")}(${idType}, text, text, date)`)}

-- Reports each holding that entered the renewal window (${days} days) or
-- expired without a newer holding of the type, once per holding and status.
-- Returns how many it reported. Run it daily from a job.
create or replace function ${fn("notify_expiring_qualifications")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${holdings}%rowtype;
  v_type ${types}%rowtype;
  v_status text;
  v_count integer := 0;${notify === "" ? "" : "\n  v_claims text;"}
begin
  for v_row in
    select x.* from ${holdings} x
    where x.${q("revokedAt")} is null and x.${q("expiresOn")} is not null
      and x.${q("expiresOn")} <= current_date + ${days}
      and x.${q("notifiedStatus")} is distinct from (case when x.${q("expiresOn")} < current_date then 'expired' else 'expiring' end)
      and not exists (
        select 1 from ${holdings} n
        where n.${q("type")} = x.${q("type")} and n.${q("holderType")} = x.${q("holderType")} and n.${q("holderId")} = x.${q("holderId")}
          and n.${q("id")} <> x.${q("id")} and n.${q("revokedAt")} is null
          and (n.${q("expiresOn")} is null or n.${q("expiresOn")} > x.${q("expiresOn")})
      )
    order by x.${q("expiresOn")}
    for update of x skip locked
  loop
    v_status := case when v_row.${q("expiresOn")} < current_date then 'expired' else 'expiring' end;
    select * into v_type from ${types} y where y.${t("id")} = v_row.${q("type")};
    if v_status = 'expired' then
      ${expiryRecord("qualification.expired")}
    else
      ${expiryRecord("qualification.expiry_warned")}
    end if;${notify}
    update ${holdings} x set ${q("notifiedStatus")} = v_status where x.${q("id")} = v_row.${q("id")};
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("notify_expiring_qualifications")}()`)}
${courseTrigger(ctx)}`;
}

/** The `(id)` rows of the holders of `type` in `tenant`, or undefined. */
function holderSource(
  ctx: BlockSqlContext,
  type: string,
  tenant: string,
): string | undefined {
  if (type === "member") {
    const members = ctx.of("memberships");
    const m = (column: string): string => members.col("memberships", column);

    return `select ms.${m("user")}::text as id from ${members.table("memberships")} ms where ms.${m("tenant")} = ${tenant}${activeMembership(members, "ms")}`;
  }

  if (type === "company" && ctx.installed("contacts")) {
    const contacts = ctx.of("contacts");
    const c = (column: string): string => contacts.col("companies", column);

    return `select cs.${c("id")}::text as id from ${contacts.table("companies")} cs where cs.${c("tenant")} = ${tenant} and cs.${c("archivedAt")} is null and cs.${c("mergedInto")} is null`;
  }

  if (type === "asset" && ctx.installed("assets")) {
    const assets = ctx.of("assets");
    const a = (column: string): string => assets.col("assets", column);

    const retired = assets.has("assets", "retiredAt")
      ? ` and s.${a("retiredAt")} is null`
      : "";

    return `select s.${a("id")}::text as id from ${assets.table("assets")} s where s.${a("tenant")} = ${tenant}${retired}`;
  }

  return undefined;
}

/** The `when` branches for the requirement targets other blocks answer. */
function targetMatches(
  ctx: BlockSqlContext,
  tenant: string,
  target: string,
): string[] {
  const branches: string[] = [];

  if (ctx.installed("teams")) {
    const teams = ctx.of("teams");
    const tm = (column: string): string => teams.col("members", column);

    branches.push(
      `when 'team' then qualification_gaps.holder_type = 'member' and exists (select 1 from ${teams.table("members")} tq where tq.${tm("team")}::text = ${target} and tq.${tm("user")}::text = h.id)`,
    );
  }

  if (
    ctx.installed("employees") &&
    ctx.of("employees").has("employees", "jobTitle")
  ) {
    const people = ctx.of("employees");
    const e = (column: string): string => people.col("employees", column);

    branches.push(
      `when 'job_title' then qualification_gaps.holder_type = 'member' and exists (select 1 from ${people.table("employees")} eq where eq.${e("tenant")} = ${tenant} and eq.${e("user")}::text = h.id and lower(eq.${e("jobTitle")}) = lower(${target}))`,
    );
  }

  if (ctx.installed("assets")) {
    const assets = ctx.of("assets");
    const a = (column: string): string => assets.col("assets", column);

    branches.push(
      `when 'asset_kind' then qualification_gaps.holder_type = 'asset' and exists (select 1 from ${assets.table("assets")} aq where aq.${a("id")}::text = h.id and aq.${a("kind")}::text = ${target})`,
    );
  }

  if (ctx.installed("segments")) {
    const segments = ctx.of("segments");
    const s = (column: string): string => segments.col("members", column);

    branches.push(
      `when 'segment' then qualification_gaps.holder_type = 'company' and exists (select 1 from ${segments.table("members")} sq where sq.${s("segment")}::text = ${target} and sq.${s("subjectId")}::text = h.id)`,
    );
  }

  return branches;
}

/**
 * The trigger that grants the types naming a course when a member earns its
 * certificate, and revokes those holdings when the certificate is revoked. Only
 * when courses owns its certificates table and types have a course.
 */
function courseTrigger(ctx: BlockSqlContext): string {
  if (
    !ctx.installed("courses") ||
    !ctx.has("types", "course") ||
    !ctx.of("courses").owns("certificates")
  ) {
    return "";
  }

  const courses = ctx.of("courses");
  const c = (column: string): string => courses.col("certificates", column);
  const types = ctx.table("types");
  const holdings = ctx.table("qualifications");
  const t = (column: string): string => ctx.col("types", column);
  const q = (column: string): string => ctx.col("qualifications", column);
  const fn = ctx.fn("qualification_course_certificate");
  const trigger = ctx.trigger("qualification_course_certificate");
  const certificates = courses.table("certificates");

  const issued = courses.has("certificates", "issuedAt")
    ? `coalesce(new.${c("issuedAt")}, now())::date`
    : "current_date";

  const certExpiry = courses.has("certificates", "expiresAt")
    ? `new.${c("expiresAt")}::date`
    : "null::date";

  const reason = ctx.has("qualifications", "revokeReason")
    ? `, ${q("revokeReason")} = 'The course certificate was revoked'`
    : "";

  const touch = ctx.has("qualifications", "updatedAt")
    ? `, ${q("updatedAt")} = now()`
    : "";

  return `
-- Grants each type that names the course when a member earns its
-- certificate (source course, expiring with the type or the certificate),
-- and revokes those holdings when the certificate is revoked.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type ${types}%rowtype;
  v_row ${holdings}%rowtype;
  v_on date;
begin
  if tg_op = 'INSERT' then
    if new.${c("revokedAt")} is not null then
      return null;
    end if;
    v_on := ${issued};
    for v_type in
      select * from ${types} y
      where y.${t("tenant")} = new.${c("tenant")} and y.${t("course")} = new.${c("course")}
        and y.${t("archivedAt")} is null and 'member' = any(y.${t("holderTypes")})
    loop
      if not exists (select 1 from ${holdings} x where x.${q("type")} = v_type.${t("id")} and x.${q("source")} = 'course' and x.${q("sourceId")} = new.${c("id")}::text) then
        insert into ${holdings} (${q("tenant")}, ${q("type")}, ${q("holderType")}, ${q("holderId")}, ${q("grantedOn")}, ${q("expiresOn")}, ${q("source")}, ${q("sourceId")})
        values (new.${c("tenant")}, v_type.${t("id")}, 'member', new.${c("user")}::text, v_on, greatest(v_on, coalesce(${expiry(`v_type.${t("validForMonths")}`, "v_on")}, ${certExpiry})), 'course', new.${c("id")}::text)
        returning * into v_row;
        ${holdingRecord(ctx, {
          event: "qualification.granted",
          row: "v_row",
          type: "v_type",
          extra: `, 'grantedOn', v_row.${q("grantedOn")}, 'expiresOn', v_row.${q("expiresOn")}, 'source', v_row.${q("source")}`,
          summary: "'Qualification granted from a course certificate'",
        })}
      end if;
    end loop;
  elsif new.${c("revokedAt")} is not null and old.${c("revokedAt")} is null then
    for v_row in
      update ${holdings} x set ${q("revokedAt")} = now()${reason}${touch}
      where x.${q("source")} = 'course' and x.${q("sourceId")} = new.${c("id")}::text and x.${q("revokedAt")} is null
      returning x.*
    loop
      select * into v_type from ${types} y where y.${t("id")} = v_row.${q("type")};
      ${holdingRecord(ctx, {
        event: "qualification.revoked",
        row: "v_row",
        type: "v_type",
        extra: ", 'reason', 'The course certificate was revoked'",
        summary: "'Qualification revoked with its course certificate'",
      })}
    end loop;
  end if;
  return null;
end;
$$;
${triggerGrant(`${fn}()`)}
drop trigger if exists ${trigger} on ${certificates};
create trigger ${trigger}
after insert or update of ${c("revokedAt")} on ${certificates}
for each row execute function ${fn}();
`;
}
