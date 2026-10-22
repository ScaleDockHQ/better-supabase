import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, pageSize, SERVICE_CALLER } from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import { moderatedMessageType } from "./messaging-moderation.ts";

const WHERE = "blocks.moderation.options";

/** The report reasons apps get without `options.reasons`. */
const DEFAULT_REASONS = [
  "spam",
  "abuse",
  "harassment",
  "off_topic",
  "illegal",
  "other",
] as const;

function thresholdOf(ctx: ModuleContext): number {
  const value = ctx.number("autoHideThreshold", 3);

  if (!Number.isInteger(value) || value < 0 || value > 1000) {
    throw new TypeError(
      `${WHERE}.autoHideThreshold must be a whole number from 0 to 1000`,
    );
  }

  return value;
}

function reasonsOf(ctx: ModuleContext): readonly string[] {
  const reasons = ctx.list("reasons", DEFAULT_REASONS);

  if (
    reasons.length === 0 ||
    reasons.some((reason) => !/^[a-z][a-z0-9_]{0,62}$/u.test(reason))
  ) {
    throw new TypeError(
      `${WHERE}.reasons must list lower-case keys such as spam or abuse`,
    );
  }

  return reasons;
}

/** The moderation module's functions. */
export function moderationFunctions(ctx: ModuleContext): string {
  const items = ctx.table("items");
  const reports = ctx.table("reports");
  const actions = ctx.table("actions");
  const bans = ctx.table("bans");
  const i = (column: string): string => ctx.col("items", column);
  const r = (column: string): string => ctx.col("reports", column);
  const a = (column: string): string => ctx.col("actions", column);
  const b = (column: string): string => ctx.col("bans", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("moderation");
  const read = ctx.permission("read", permissions.read);
  const report = ctx.permission("report", permissions.report);
  const manage = ctx.permission("manage", permissions.manage);
  const ban = ctx.permission("ban", permissions.ban);
  const threshold = thresholdOf(ctx);
  const reasons = reasonsOf(ctx);
  const message = moderatedMessageType(ctx);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("MODERATION_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("MODERATION_INVALID", message, "22023");

  const itemMissing = fail(
    "MODERATION_ITEM_NOT_FOUND",
    "moderation item not found",
    "P0002",
  );

  const itemJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${i("id")}, 'organizationId', ${row}.${i("tenant")}, 'subjectType', ${row}.${i("subjectType")}, 'subjectId', ${row}.${i("subjectId")}, 'authorId', ${row}.${i("author")}, 'status', ${row}.${i("status")}, 'openReports', ${row}.${i("openReports")}, 'reason', ${row}.${i("reason")}, 'decidedBy', ${row}.${i("decidedBy")}, 'decidedAt', ${row}.${i("decidedAt")}, 'createdAt', ${row}.${i("createdAt")}, 'updatedAt', ${row}.${i("updatedAt")})`;

  const reportJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'itemId', ${row}.${r("item")}, 'reporterId', ${row}.${r("reporter")}, 'reason', ${row}.${r("reason")}, 'note', ${row}.${r("note")}, 'status', ${row}.${r("status")}, 'resolvedBy', ${row}.${r("resolvedBy")}, 'resolvedAt', ${row}.${r("resolvedAt")}, 'createdAt', ${row}.${r("createdAt")})`;

  const actionJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${a("id")}, 'action', ${row}.${a("action")}, 'fromStatus', ${row}.${a("fromStatus")}, 'toStatus', ${row}.${a("toStatus")}, 'reason', ${row}.${a("reason")}, 'actorId', ${row}.${a("actor")}, 'createdAt', ${row}.${a("createdAt")})`;

  const banJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${b("id")}, 'organizationId', ${row}.${b("tenant")}, 'userId', ${row}.${b("user")}, 'reason', ${row}.${b("reason")}, 'bannedBy', ${row}.${b("bannedBy")}, 'expiresAt', ${row}.${b("expiresAt")}, 'liftedBy', ${row}.${b("liftedBy")}, 'liftedAt', ${row}.${b("liftedAt")}, 'createdAt', ${row}.${b("createdAt")})`;

  const banRecord = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${b("tenant")}, 'id', ${row}.${b("id")}, 'userId', ${row}.${b("user")}, 'expiresAt', ${row}.${b("expiresAt")})`,
      subject: `'moderation-bans/' || ${row}.${b("id")}::text`,
      tenant: `${row}.${b("tenant")}`,
      audit: {
        category: "security",
        targetType: "user",
        recordId: `${row}.${b("user")}::text`,
        summary: sqlString(summary),
      },
    });

  const active = (row: string): string =>
    `${row}.${b("liftedAt")} is null and (${row}.${b("expiresAt")} is null or ${row}.${b("expiresAt")} > now())`;

  const messaging = message === undefined ? undefined : ctx.of("messaging");

  const mc = (column: string): string =>
    messaging === undefined ? column : messaging.col("messages", column);

  const isMessage = (type: string): string =>
    message === undefined ? "false" : `${type} = ${sqlString(message)}`;

  const messageRemove =
    messaging === undefined
      ? ""
      : `
  if ${isMessage(`v_row.${i("subjectType")}`)} and v_status = 'removed' then
    update ${messaging.table("messages")} x
    set ${mc("body")} = '', ${mc("document")} = null, ${mc("mentions")} = '{}', ${mc("mentionScope")} = null,
      ${mc("pinnedAt")} = null, ${mc("pinnedBy")} = null, ${mc("deletedAt")} = now()
    where x.${mc("id")}::text = v_row.${i("subjectId")} and x.${mc("deletedAt")} is null;
  end if;`;

  const messageRestore =
    messaging === undefined
      ? ""
      : `
  if moderation_apply.action = 'restore' and v_old.${i("status")} = 'removed' and ${isMessage(`v_old.${i("subjectType")}`)} then
    ${invalid("a removed message can't be restored")}
  end if;`;

  const messageAuthor =
    messaging === undefined
      ? ""
      : `
  if ${isMessage("report_content.subject_type")} then
    select x.${mc("author")} into v_author from ${messaging.table("messages")} x
    where x.${mc("id")}::text = report_content.subject_id and x.${mc("tenant")} = report_content.tenant and x.${mc("deletedAt")} is null;
    if not found then
      ${fail("MODERATION_SUBJECT_NOT_FOUND", "there is no such message to report", "P0002")}
    end if;
  end if;`;

  const autoHide =
    threshold === 0
      ? ""
      : `
  if v_item.${i("status")} = 'visible' and v_item.${i("openReports")} >= ${String(threshold)} then
    perform ${fn("moderation_apply")}(v_item.${i("id")}, 'auto_hide', ${sqlString(`Hidden after ${String(threshold)} reports`)}, true);
    v_auto := true;
  end if;`;

  return `-- Whether a user is banned in an organization right now.
create or replace function ${fn("moderation_banned")}(tenant ${idType}, user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select moderation_banned.user_id is not null and exists (
    select 1 from ${bans} x
    where x.${b("tenant")} = moderation_banned.tenant and x.${b("user")} = moderation_banned.user_id and ${active("x")}
  )
$$;
revoke execute on function ${fn("moderation_banned")}(${idType}, uuid) from public, anon, authenticated;

-- Puts a subject under moderation, or puts it back after its author changed
-- it: status pending waits for a decision, visible shows it. Clears the last
-- decision. For modules that moderate their own content, such as reviews.
create or replace function ${fn("moderation_track")}(tenant ${idType}, subject_type text, subject_id text, author uuid, status text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old ${items};
  v_row ${items};
begin
  if moderation_track.status not in ('pending', 'visible') then
    ${invalid("content starts pending or visible")}
  end if;
  select * into v_old from ${items} x
  where x.${i("tenant")} = moderation_track.tenant and x.${i("subjectType")} = moderation_track.subject_type and x.${i("subjectId")} = moderation_track.subject_id
  for update;
  if v_old.${i("id")} is null then
    insert into ${items} (${i("tenant")}, ${i("subjectType")}, ${i("subjectId")}, ${i("author")}, ${i("status")})
    values (moderation_track.tenant, moderation_track.subject_type, moderation_track.subject_id, moderation_track.author, moderation_track.status)
    returning * into v_row;
  else
    update ${items} x
    set ${i("status")} = moderation_track.status, ${i("author")} = coalesce(moderation_track.author, x.${i("author")}),
      ${i("reason")} = null, ${i("decidedBy")} = null, ${i("decidedAt")} = null, ${i("updatedAt")} = now()
    where x.${i("id")} = v_old.${i("id")}
    returning * into v_row;
  end if;
  if v_old.${i("status")} is distinct from v_row.${i("status")} then
    insert into ${actions} (${a("tenant")}, ${a("item")}, ${a("action")}, ${a("fromStatus")}, ${a("toStatus")}, ${a("actor")})
    values (v_row.${i("tenant")}, v_row.${i("id")}, 'submit', v_old.${i("status")}, v_row.${i("status")}, moderation_track.author);
  end if;
  return v_row.${i("id")};
end;
$$;
revoke execute on function ${fn("moderation_track")}(${idType}, text, text, uuid, text) from public, anon, authenticated;

-- Applies a decision without a permission check: approve and restore show
-- the content, hide and auto_hide hide it, remove and ban remove it, and ban
-- also bans its author. Closes the open reports, except on auto_hide, and
-- logs the action.
create or replace function ${fn("moderation_apply")}(item_id uuid, action text, reason text default null, automatic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old ${items};
  v_row ${items};
  v_ban ${bans};
  v_status text;
begin
  select * into v_old from ${items} x where x.${i("id")} = moderation_apply.item_id for update;
  if v_old.${i("id")} is null then
    ${itemMissing}
  end if;
  v_status := case moderation_apply.action
    when 'approve' then 'visible'
    when 'restore' then 'visible'
    when 'hide' then 'hidden'
    when 'auto_hide' then 'hidden'
    when 'remove' then 'removed'
    when 'ban' then 'removed'
  end;
  if v_status is null then
    ${invalid("action must be approve, hide, remove, restore or ban")}
  end if;
  if length(moderation_apply.reason) > 1000 then
    ${invalid("reason must be at most 1000 characters")}
  end if;
  if moderation_apply.action = 'restore' and v_old.${i("status")} not in ('hidden', 'removed') then
    ${invalid("only hidden or removed content can be restored")}
  end if;
  if moderation_apply.action = 'ban' and v_old.${i("author")} is null then
    ${invalid("this content has no author to ban")}
  end if;${messageRestore}
  update ${items} x
  set ${i("status")} = v_status,
    ${i("reason")} = case when v_status = 'visible' then null else nullif(trim(moderation_apply.reason), '') end,
    ${i("decidedBy")} = case when moderation_apply.automatic then null else auth.uid() end,
    ${i("decidedAt")} = now(),
    ${i("openReports")} = case when moderation_apply.action = 'auto_hide' then x.${i("openReports")} else 0 end,
    ${i("updatedAt")} = now()
  where x.${i("id")} = v_old.${i("id")}
  returning * into v_row;
  if moderation_apply.action <> 'auto_hide' then
    update ${reports} x
    set ${r("status")} = case when v_status = 'visible' then 'dismissed' else 'resolved' end,
      ${r("resolvedBy")} = auth.uid(), ${r("resolvedAt")} = now()
    where x.${r("item")} = v_row.${i("id")} and x.${r("status")} = 'open';
  end if;
  insert into ${actions} (${a("tenant")}, ${a("item")}, ${a("action")}, ${a("fromStatus")}, ${a("toStatus")}, ${a("reason")}, ${a("actor")})
  values (v_row.${i("tenant")}, v_row.${i("id")}, moderation_apply.action, v_old.${i("status")}, v_status, nullif(trim(moderation_apply.reason), ''),
    case when moderation_apply.automatic then null else auth.uid() end);${messageRemove}
  if moderation_apply.action = 'ban' and not ${fn("moderation_banned")}(v_row.${i("tenant")}, v_row.${i("author")}) then
    delete from ${bans} x where x.${b("tenant")} = v_row.${i("tenant")} and x.${b("user")} = v_row.${i("author")} and x.${b("liftedAt")} is null;
    insert into ${bans} (${b("tenant")}, ${b("user")}, ${b("reason")}, ${b("bannedBy")})
    values (v_row.${i("tenant")}, v_row.${i("author")}, nullif(trim(moderation_apply.reason), ''), auth.uid())
    returning * into v_ban;
    ${banRecord("moderation_ban.created", "v_ban", "banned a user")}
  end if;
  ${ctx.record({
    type: "moderation_item.decided",
    payload: `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'id', v_row.${i("id")}, 'subjectType', v_row.${i("subjectType")}, 'subjectId', v_row.${i("subjectId")}, 'authorId', v_row.${i("author")}, 'action', moderation_apply.action, 'status', v_status, 'previousStatus', v_old.${i("status")}, 'automatic', moderation_apply.automatic)`,
    subject: `'moderation-items/' || v_row.${i("id")}::text`,
    tenant: `v_row.${i("tenant")}`,
    audit: {
      category: "data",
      targetType: "moderation_item",
      recordId: `v_row.${i("id")}::text`,
      targetLabel: `v_row.${i("subjectType")} || '/' || v_row.${i("subjectId")}`,
      summary: `'moderation: ' || moderation_apply.action`,
    },
  })}
  return ${itemJson("v_row")};
end;
$$;
revoke execute on function ${fn("moderation_apply")}(uuid, text, text, boolean) from public, anon, authenticated;

-- Reports a subject for a reason (${reasons.join(", ")}). A member reports a
-- subject once until a moderator decides on it; reporting again returns the
-- open report.${threshold === 0 ? "" : ` Content with ${String(threshold)} open reports is hidden until a moderator decides.`}
create or replace function ${fn("report_content")}(tenant ${idType}, subject_type text, subject_id text, reason text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_author uuid;
  v_item ${items};
  v_report ${reports};
  v_auto boolean := false;
begin
  if v_me is null then
    ${forbidden("sign in to report content")}
  end if;
  if not ${ctx.can("tenant", "report_content.tenant", report)} then
    ${forbidden("not allowed to report content")}
  end if;
  if ${fn("moderation_banned")}(report_content.tenant, v_me) then
    ${fail("MODERATION_BANNED", "you are banned in this organization")}
  end if;
  if report_content.reason is null or report_content.reason not in (${reasons.map((reason) => sqlString(reason)).join(", ")}) then
    ${invalid(`reason must be one of ${reasons.join(", ")}`)}
  end if;
  if length(report_content.note) > 1000 then
    ${invalid("note must be at most 1000 characters")}
  end if;
  if report_content.subject_type is null or report_content.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$'
    or report_content.subject_id is null or length(report_content.subject_id) not between 1 and 200 then
    ${invalid("a report needs a subject type and id")}
  end if;${messageAuthor}
  insert into ${items} (${i("tenant")}, ${i("subjectType")}, ${i("subjectId")}, ${i("author")})
  values (report_content.tenant, report_content.subject_type, report_content.subject_id, v_author)
  on conflict (${i("tenant")}, ${i("subjectType")}, ${i("subjectId")}) do nothing;
  select * into v_item from ${items} x
  where x.${i("tenant")} = report_content.tenant and x.${i("subjectType")} = report_content.subject_type and x.${i("subjectId")} = report_content.subject_id
  for update;
  if v_item.${i("author")} = v_me then
    ${invalid("you can't report your own content")}
  end if;
  insert into ${reports} (${r("tenant")}, ${r("item")}, ${r("reporter")}, ${r("reason")}, ${r("note")})
  values (report_content.tenant, v_item.${i("id")}, v_me, report_content.reason, nullif(trim(report_content.note), ''))
  on conflict (${r("item")}, ${r("reporter")}) where ${r("status")} = 'open' do nothing
  returning * into v_report;
  if v_report.${r("id")} is null then
    select * into v_report from ${reports} x
    where x.${r("item")} = v_item.${i("id")} and x.${r("reporter")} = v_me and x.${r("status")} = 'open';
    return ${reportJson("v_report")} || jsonb_build_object('autoHidden', false);
  end if;
  update ${items} x
  set ${i("openReports")} = (select count(*) from ${reports} y where y.${r("item")} = x.${i("id")} and y.${r("status")} = 'open'),
    ${i("updatedAt")} = now()
  where x.${i("id")} = v_item.${i("id")}
  returning * into v_item;
  ${ctx.record({
    type: "moderation_report.created",
    payload: `jsonb_build_object('organizationId', v_item.${i("tenant")}, 'id', v_report.${r("id")}, 'itemId', v_item.${i("id")}, 'subjectType', v_item.${i("subjectType")}, 'subjectId', v_item.${i("subjectId")}, 'reason', v_report.${r("reason")})`,
    subject: `'moderation-reports/' || v_report.${r("id")}::text`,
    tenant: `v_item.${i("tenant")}`,
    audit: false,
  })}${autoHide}
  return ${reportJson("v_report")} || jsonb_build_object('autoHidden', v_auto);
end;
$$;
revoke execute on function ${fn("report_content")}(${idType}, text, text, text, text) from public, anon;
grant execute on function ${fn("report_content")}(${idType}, text, text, text, text) to authenticated, service_role;

-- A moderator's decision on an item: approve, hide, remove, restore, or ban
-- (remove the content and ban its author, which also needs the ban
-- permission).
create or replace function ${fn("moderate")}(item_id uuid, action text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${idType};
begin
  select x.${i("tenant")} into v_tenant from ${items} x where x.${i("id")} = moderate.item_id;
  if not found then
    ${itemMissing}
  end if;
  if not ${allowed("v_tenant", manage)} then
    ${forbidden("not allowed to moderate content")}
  end if;
  if moderate.action = 'ban' and not ${allowed("v_tenant", ban)} then
    ${forbidden("not allowed to ban users")}
  end if;
  if moderate.action = 'auto_hide' then
    ${invalid("auto_hide is the module's own action")}
  end if;
  return ${fn("moderation_apply")}(moderate.item_id, moderate.action, moderate.reason, false);
end;
$$;
revoke execute on function ${fn("moderate")}(uuid, text, text) from public, anon;
grant execute on function ${fn("moderate")}(uuid, text, text) to authenticated, service_role;

-- The review queue, most recently changed first. Without a status it holds
-- what needs a moderator: pending content and content with open reports.
create or replace function ${fn("moderation_queue")}(tenant ${idType}, status text default null, subject_type text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
begin
  if not ${allowed("moderation_queue.tenant", read)} then
    ${forbidden("not allowed to read the moderation queue")}
  end if;
  select coalesce(jsonb_agg(q.item order by q.updated desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select ${itemJson("x")} as item, x.${i("updatedAt")} as updated, x.${i("id")} as id
    from ${items} x
    where x.${i("tenant")} = moderation_queue.tenant
      and (case when moderation_queue.status is null then x.${i("status")} = 'pending' or x.${i("openReports")} > 0 else x.${i("status")} = moderation_queue.status end)
      and (moderation_queue.subject_type is null or x.${i("subjectType")} = moderation_queue.subject_type)
      and (moderation_queue.before is null or x.${i("updatedAt")} < moderation_queue.before)
    order by x.${i("updatedAt")} desc, x.${i("id")} desc
    limit ${pageSize("moderation_queue.page_size", 50, 200)}
  ) q;
  return v_rows;
end;
$$;
revoke execute on function ${fn("moderation_queue")}(${idType}, text, text, integer, timestamptz) from public, anon;
grant execute on function ${fn("moderation_queue")}(${idType}, text, text, integer, timestamptz) to authenticated, service_role;

-- One subject's item with its latest 100 reports and actions, or null when
-- nothing moderated it.
create or replace function ${fn("moderation_item")}(tenant ${idType}, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${items};
begin
  if not ${allowed("moderation_item.tenant", read)} then
    ${forbidden("not allowed to read moderation")}
  end if;
  select * into v_row from ${items} x
  where x.${i("tenant")} = moderation_item.tenant and x.${i("subjectType")} = moderation_item.subject_type and x.${i("subjectId")} = moderation_item.subject_id;
  if v_row.${i("id")} is null then
    return null;
  end if;
  return ${itemJson("v_row")} || jsonb_build_object(
    'reports', coalesce((select jsonb_agg(${reportJson("y")} order by y.${r("createdAt")} desc) from (select * from ${reports} z where z.${r("item")} = v_row.${i("id")} order by z.${r("createdAt")} desc limit 100) y), '[]'::jsonb),
    'actions', coalesce((select jsonb_agg(${actionJson("y")} order by y.${a("createdAt")} desc) from (select * from ${actions} z where z.${a("item")} = v_row.${i("id")} order by z.${a("createdAt")} desc limit 100) y), '[]'::jsonb)
  );
end;
$$;
revoke execute on function ${fn("moderation_item")}(${idType}, text, text) from public, anon;
grant execute on function ${fn("moderation_item")}(${idType}, text, text) to authenticated, service_role;

-- The subjects of up to 500 ids that are not visible, as { id: status }, for
-- members filtering a list. Visible and unmoderated subjects are left out.
create or replace function ${fn("moderation_statuses")}(tenant ${idType}, subject_type text, subject_ids text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_out jsonb;
begin
  if not (${allowed("moderation_statuses.tenant", report)} or ${ctx.can("tenant", "moderation_statuses.tenant", read)}) then
    ${forbidden("not allowed to read moderation")}
  end if;
  select coalesce(jsonb_object_agg(x.${i("subjectId")}, x.${i("status")}), '{}'::jsonb) into v_out
  from ${items} x
  where x.${i("tenant")} = moderation_statuses.tenant and x.${i("subjectType")} = moderation_statuses.subject_type
    and x.${i("subjectId")} = any (moderation_statuses.subject_ids[1:500]) and x.${i("status")} <> 'visible';
  return v_out;
end;
$$;
revoke execute on function ${fn("moderation_statuses")}(${idType}, text, text[]) from public, anon;
grant execute on function ${fn("moderation_statuses")}(${idType}, text, text[]) to authenticated, service_role;

-- Bans a user in an organization until expires_at, or for good. Banning a
-- banned user changes the reason and the end.
create or replace function ${fn("ban_user")}(tenant ${idType}, user_id uuid, reason text default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${bans};
begin
  if not ${allowed("ban_user.tenant", ban)} then
    ${forbidden("not allowed to ban users")}
  end if;
  if ban_user.user_id is null or ban_user.user_id = auth.uid() then
    ${invalid("pick another user to ban")}
  end if;
  if ban_user.expires_at is not null and ban_user.expires_at <= now() then
    ${invalid("expires_at must be in the future")}
  end if;
  if length(ban_user.reason) > 1000 then
    ${invalid("reason must be at most 1000 characters")}
  end if;
  delete from ${bans} x where x.${b("tenant")} = ban_user.tenant and x.${b("user")} = ban_user.user_id and x.${b("liftedAt")} is null and x.${b("expiresAt")} <= now();
  insert into ${bans} (${b("tenant")}, ${b("user")}, ${b("reason")}, ${b("bannedBy")}, ${b("expiresAt")})
  values (ban_user.tenant, ban_user.user_id, nullif(trim(ban_user.reason), ''), auth.uid(), ban_user.expires_at)
  on conflict (${b("tenant")}, ${b("user")}) where ${b("liftedAt")} is null do update
    set ${b("reason")} = excluded.${b("reason")}, ${b("bannedBy")} = excluded.${b("bannedBy")}, ${b("expiresAt")} = excluded.${b("expiresAt")}
  returning * into v_row;
  ${banRecord("moderation_ban.created", "v_row", "banned a user")}
  return ${banJson("v_row")};
end;
$$;
revoke execute on function ${fn("ban_user")}(${idType}, uuid, text, timestamptz) from public, anon;
grant execute on function ${fn("ban_user")}(${idType}, uuid, text, timestamptz) to authenticated, service_role;

-- Lifts a ban. False when it was already lifted.
create or replace function ${fn("unban_user")}(ban_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${bans};
begin
  select * into v_row from ${bans} x where x.${b("id")} = unban_user.ban_id for update;
  if v_row.${b("id")} is null then
    ${fail("MODERATION_BAN_NOT_FOUND", "ban not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${b("tenant")}`, ban)} then
    ${forbidden("not allowed to lift bans")}
  end if;
  if v_row.${b("liftedAt")} is not null then
    return false;
  end if;
  update ${bans} x set ${b("liftedAt")} = now(), ${b("liftedBy")} = auth.uid()
  where x.${b("id")} = v_row.${b("id")}
  returning * into v_row;
  ${banRecord("moderation_ban.lifted", "v_row", "lifted a ban")}
  return true;
end;
$$;
revoke execute on function ${fn("unban_user")}(uuid) from public, anon;
grant execute on function ${fn("unban_user")}(uuid) to authenticated, service_role;

-- An organization's bans, newest first: active ones by default.
create or replace function ${fn("list_bans")}(tenant ${idType}, active boolean default true, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
begin
  if not ${allowed("list_bans.tenant", read)} then
    ${forbidden("not allowed to read bans")}
  end if;
  select coalesce(jsonb_agg(q.item order by q.created desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select ${banJson("x")} as item, x.${b("createdAt")} as created, x.${b("id")} as id
    from ${bans} x
    where x.${b("tenant")} = list_bans.tenant
      and (not coalesce(list_bans.active, false) or (${active("x")}))
    order by x.${b("createdAt")} desc, x.${b("id")} desc
    limit ${pageSize("list_bans.page_size", 50, 200)}
  ) q;
  return v_rows;
end;
$$;
revoke execute on function ${fn("list_bans")}(${idType}, boolean, integer) from public, anon;
grant execute on function ${fn("list_bans")}(${idType}, boolean, integer) to authenticated, service_role;
${moderationHidden(ctx)}`;
}

/**
 * Whether a moderator hid, removed or holds back a subject, for the messages
 * read policy the messaging module adds.
 */
function moderationHidden(ctx: ModuleContext): string {
  if (moderatedMessageType(ctx) === undefined) {
    return "";
  }

  const i = (column: string): string => ctx.col("items", column);
  const hidden = ctx.fn("moderation_hidden");

  return `
-- Whether a moderator hid, removed or holds back a subject. Security definer
-- so read policies can ask without reading the moderation tables.
create or replace function ${hidden}(subject_type text, subject_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${ctx.table("items")} m
    where m.${i("subjectType")} = moderation_hidden.subject_type and m.${i("subjectId")} = moderation_hidden.subject_id and m.${i("status")} <> 'visible'
  )
$$;
revoke execute on function ${hidden}(text, text) from public, anon;
grant execute on function ${hidden}(text, text) to authenticated, service_role;
`;
}
