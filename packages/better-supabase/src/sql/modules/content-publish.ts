import type { BlockSqlContext } from "../context.ts";
import type { ContentSql } from "./content-sql.ts";

import { sqlString } from "../../core/template.ts";
import {
  pageSize,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { contentSnapshot } from "./content-functions.ts";
import { contentSql } from "./content-sql.ts";

/**
 * Opens the publish request for `v_row` at `at` (a timestamptz expression, null
 * to publish once approved) and returns the draft that waits for it.
 */
function requestPublish(q: ContentSql, at: string): string {
  const { e, entries, json } = q;

  if (q.approvals === undefined) {
    return "";
  }

  return `if not ${q.allowed(`v_row.${e("tenant")}`, q.write)} then
      ${q.forbidden("not allowed to write content")}
    end if;
    v_request := ${q.approvals.fn("open_approval")}(
      v_row.${e("tenant")}, ${q.subject}, v_row.${e("id")}::text, 'publish',
      ${sqlString(q.policy)}::jsonb, null,
      jsonb_build_object('type', v_row.${e("type")}, 'locale', v_row.${e("locale")}, 'slug', v_row.${e("slug")}, 'title', v_row.${e("title")}, 'publishAt', ${at})
    );
    update ${entries} x set
      ${e("status")} = ${q.cast("status", "'draft'")},
      ${e("publishAt")} = ${at},
      ${e("approval")} = (v_request ->> 'id')::uuid,
      ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
    ${q.record("content_entry.publish_requested", "v_row", "asked to publish a content entry")}
    return ${json("v_row")};`;
}

function publishing(ctx: BlockSqlContext): string {
  const q = contentSql(ctx);
  const { fn, e, entries, invalid, forbidden, missing, json } = q;
  const gated = q.approval && q.approvals !== undefined;

  const load = (
    func: string,
  ): string => `select * into v_row from ${entries} x where x.${e("id")} = ${func}.entry_id for update;
  if not found then
    ${missing}
  end if;`;

  const publisher = q.allowed(`v_row.${e("tenant")}`, q.publish);

  return `-- Publishes an entry now: sets it live, records a frozen "published" version
-- when versions is installed and writes content_entry.published. Publish,
-- the approval and the scheduler call it; it isn't granted to anyone.
create or replace function ${fn("content_entry_go_live")}(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${entries};
begin
  ${load("content_entry_go_live")}
  ${ctx.hook("before_content_entry_publish", [
    ["uuid", `v_row.${e("id")}`],
    [ctx.idType, `v_row.${e("tenant")}`],
  ])}
  update ${entries} x set
    ${e("status")} = ${q.cast("status", "'published'")},
    ${e("publishedAt")} = now(),
    ${e("publishAt")} = null,
    ${e("updatedAt")} = now()
  where x.${e("id")} = v_row.${e("id")}
  returning * into v_row;${contentSnapshot(q, "v_row", "published")}
  ${q.record("content_entry.published", "v_row", "published a content entry")}
  ${ctx.hook("after_content_entry_publish", [["uuid", `v_row.${e("id")}`]])}
  return ${json("v_row")};
end;
$$;
revoke execute on function ${fn("content_entry_go_live")}(uuid) from public, anon, authenticated;

-- Publishes an entry now. With options.requireApproval a writer's call opens
-- a publish request instead, and the entry goes live once it is approved.
create or replace function ${fn("publish_content_entry")}(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${entries};
  v_request jsonb;
begin
  ${load("publish_content_entry")}
  if v_row.${e("status")} = 'published' then
    if not ${q.allowed(`v_row.${e("tenant")}`, q.read)} then
      ${forbidden("not allowed to read content")}
    end if;
    return ${json("v_row")};
  end if;
  ${
    gated
      ? `if not (${SERVICE_CALLER}) then
    ${requestPublish(q, "null::timestamptz")}
  end if;`
      : ""
  }
  if not ${publisher} then
    ${forbidden("not allowed to publish content")}
  end if;
  return ${fn("content_entry_go_live")}(v_row.${e("id")});
end;
$$;
${userGrant(`${fn("publish_content_entry")}(uuid)`)}

-- Schedules an entry to go live at a future time; null unschedules it. With
-- options.requireApproval a writer's call opens a publish request, and the
-- entry is scheduled (or published, once the time has passed) when approved.
create or replace function ${fn("schedule_content_entry")}(entry_id uuid, at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${entries};
  v_request jsonb;
begin
  ${load("schedule_content_entry")}
  if schedule_content_entry.at is null then
    if not ${q.allowed(`v_row.${e("tenant")}`, q.write)}
      or (v_row.${e("status")} = 'scheduled' and not ${publisher}) then
      ${forbidden("not allowed to unschedule this entry")}
    end if;
    if v_row.${e("status")} not in ('draft', 'scheduled') or v_row.${e("publishAt")} is null then
      ${invalid("the entry is not scheduled")}
    end if;${q.withdraw("v_row")}
    update ${entries} x set
      ${e("status")} = ${q.cast("status", "'draft'")},
      ${e("publishAt")} = null,${q.has("approval") ? `\n      ${e("approval")} = case when x.${e("status")} = 'draft' then null else x.${e("approval")} end,` : ""}
      ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
    ${q.record("content_entry.unscheduled", "v_row", false)}
    return ${json("v_row")};
  end if;
  if v_row.${e("status")} = 'published' then
    ${invalid("the entry is already published; archive it before scheduling it again")}
  end if;
  if schedule_content_entry.at <= now() then
    ${invalid("the publish time must be in the future")}
  end if;
  ${
    gated
      ? `if not (${SERVICE_CALLER}) then
    ${requestPublish(q, "schedule_content_entry.at")}
  end if;`
      : ""
  }
  if not ${publisher} then
    ${forbidden("not allowed to publish content")}
  end if;
  update ${entries} x set
    ${e("status")} = ${q.cast("status", "'scheduled'")},
    ${e("publishAt")} = schedule_content_entry.at,
    ${e("updatedAt")} = now()
  where x.${e("id")} = v_row.${e("id")}
  returning * into v_row;
  ${q.record("content_entry.scheduled", "v_row", "scheduled a content entry")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("schedule_content_entry")}(uuid, timestamptz)`)}

-- Runs once a publish request is approved: schedules the entry when its time
-- is still ahead, and publishes it otherwise. Approvals calls it; it isn't
-- granted to anyone.
create or replace function ${fn("content_entry_approved")}(entry_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${entries};
begin
  select * into v_row from ${entries} x where x.${e("id")} = content_entry_approved.entry_id for update;
  if not found or v_row.${e("status")} <> 'draft' or ${q.of("v_row", "approval")} is null then
    return;
  end if;
  if v_row.${e("publishAt")} is not null and v_row.${e("publishAt")} > now() then
    update ${entries} x set ${e("status")} = ${q.cast("status", "'scheduled'")}, ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
    ${q.record("content_entry.scheduled", "v_row", "scheduled a content entry")}
  else
    perform ${fn("content_entry_go_live")}(v_row.${e("id")});
  end if;
end;
$$;
revoke execute on function ${fn("content_entry_approved")}(uuid) from public, anon, authenticated;

-- Publishes the scheduled entries whose time has come, at most 500 a call,
-- and returns how many. The content block's publish timer calls it.
create or replace function ${fn("publish_due_content_entries")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  if not (${SERVICE_CALLER}) then
    ${forbidden("only the service role publishes due entries")}
  end if;
  for v_id in
    select x.${e("id")} from ${entries} x
    where x.${e("status")} = 'scheduled' and x.${e("publishAt")} <= now()
    order by x.${e("publishAt")}
    limit 500
    for update skip locked
  loop
    perform ${fn("content_entry_go_live")}(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("publish_due_content_entries")}()`)}
`;
}

/**
 * The two functions anon may call (ADR 0084): they return published entries
 * only, with the fields named below and nothing else.
 */
function publicReads(ctx: BlockSqlContext): string {
  const q = contentSql(ctx);
  const { fn, e, entries } = q;

  const live = (row: string): string =>
    `${row}.${e("status")} = 'published' and ${row}.${e("publishedAt")} <= now()`;

  const item = (row: string): string =>
    `jsonb_build_object('id', ${row}.${e("id")}, 'type', ${row}.${e("type")}, 'locale', ${row}.${e("locale")}, 'slug', ${row}.${e("slug")}, 'title', ${row}.${e("title")}, 'summary', ${q.of(row, "summary")}, 'coverAttachmentId', ${q.of(row, "cover")}, 'translationGroupId', ${row}.${e("translationGroup")}, 'publishedAt', ${row}.${e("publishedAt")}, 'updatedAt', ${row}.${e("updatedAt")})`;

  return `-- A published entry by type, slug and locale, or null. A slug the locale
-- lacks falls back to the default locale. Each entry lists its published
-- translations.
create or replace function ${fn("public_content_entry")}(tenant ${ctx.idType}, type text, slug text, locale text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_locale text := coalesce(nullif(public_content_entry.locale, ''), ${q.defaultLocale});
  v_row ${entries};
begin
  select * into v_row from ${entries} x
  where x.${e("tenant")} = public_content_entry.tenant
    and x.${e("type")} = ${q.cast("type", "public_content_entry.type", "null")}
    and x.${e("slug")} = public_content_entry.slug
    and x.${e("locale")} in (${q.cast("locale", "v_locale", "null")}, ${q.defaultLocale})
    and ${live("x")}
  order by (x.${e("locale")} = ${q.cast("locale", "v_locale", "null")}) desc
  limit 1;
  if not found then
    return null;
  end if;
  return ${item("v_row")} || jsonb_build_object(
    'body', v_row.${e("body")},
    'translations', (
      select coalesce(jsonb_agg(jsonb_build_object('locale', t.${e("locale")}, 'slug', t.${e("slug")}) order by t.${e("locale")}), '[]'::jsonb)
      from ${entries} t
      where t.${e("tenant")} = v_row.${e("tenant")} and t.${e("translationGroup")} = v_row.${e("translationGroup")}
        and t.${e("id")} <> v_row.${e("id")} and ${live("t")}
    )
  );
end;
$$;
revoke all on function ${fn("public_content_entry")}(${ctx.idType}, text, text, text) from public, anon, authenticated;
grant execute on function ${fn("public_content_entry")}(${ctx.idType}, text, text, text) to anon, authenticated, service_role;

-- Published entries of a type (all types when null) in a locale (the default
-- when null), newest first, without their bodies. page_size is 1 to 100
-- (default 20); before pages on publishedAt.
create or replace function ${fn("public_content_entries")}(tenant ${ctx.idType}, type text default null, locale text default null, page_size integer default 20, before timestamptz default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(q.item order by q.published desc, q.id), '[]'::jsonb)
  from (
    select ${item("x")} as item, x.${e("publishedAt")} as published, x.${e("id")} as id
    from ${entries} x
    where x.${e("tenant")} = public_content_entries.tenant
      and (public_content_entries.type is null or x.${e("type")} = ${q.cast("type", "public_content_entries.type", "null")})
      and x.${e("locale")} = ${q.cast("locale", `coalesce(nullif(public_content_entries.locale, ''), ${q.defaultLocale})`, "null")}
      and ${live("x")}
      and (public_content_entries.before is null or x.${e("publishedAt")} < public_content_entries.before)
    order by x.${e("publishedAt")} desc, x.${e("id")}
    limit ${pageSize("public_content_entries.page_size", 20, 100)}
  ) q
$$;
revoke all on function ${fn("public_content_entries")}(${ctx.idType}, text, text, integer, timestamptz) from public, anon, authenticated;
grant execute on function ${fn("public_content_entries")}(${ctx.idType}, text, text, integer, timestamptz) to anon, authenticated, service_role;
`;
}

export function contentPublishFunctions(ctx: BlockSqlContext): string {
  return `${publishing(ctx)}
${publicReads(ctx)}`;
}
