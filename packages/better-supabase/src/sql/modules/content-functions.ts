import type { BlockSqlContext } from "../context.ts";
import type { ContentSql } from "./content-sql.ts";

import { sqlString } from "../../core/template.ts";
import { fail, pageSize, userGrant } from "../shared.ts";
import { contentSql, MAX_BODY, SLUG } from "./content-sql.ts";

/** The checks every write runs on the title, slug, summary, body and cover. */
function validate(q: ContentSql, tenant: string): string {
  const { invalid } = q;

  const cover = q.has("cover")
    ? q.attachments === undefined
      ? q.attachmentsInstalled
        ? ""
        : `
  if v_cover is not null then
    ${fail("CONTENT_MEDIA_UNSUPPORTED", "a cover image needs the attachments block", "0A000")}
  end if;`
      : `
  if v_cover is not null and not exists (
    select 1 from ${q.attachments.table("attachments")} a
    where a.${q.attachments.col("attachments", "id")} = v_cover and a.${q.attachments.col("attachments", "tenant")} = ${tenant}
  ) then
    ${invalid("the cover image is not an attachment of this organization")}
  end if;`
    : `
  if v_cover is not null then
    ${fail("CONTENT_MEDIA_UNSUPPORTED", "the entries table has no cover column", "0A000")}
  end if;`;

  return `if coalesce(length(v_title), 0) not between 1 and 300 then
    ${invalid("an entry needs a title of 1 to 300 characters")}
  end if;
  if v_slug is null or length(v_slug) > 200 or v_slug !~ ${sqlString(SLUG)} then
    ${invalid("a slug is lowercase letters and digits joined by dashes, with / between segments, at most 200 characters")}
  end if;
  if length(v_summary) > 2000 then
    ${invalid("a summary is at most 2000 characters")}
  end if;
  if jsonb_typeof(v_body) not in ('object', 'array') then
    ${invalid("an entry's body is a JSON object or array")}
  end if;
  if octet_length(v_body::text) > ${String(MAX_BODY)} then
    ${invalid(`an entry's body is at most ${String(MAX_BODY)} bytes of JSON`)}
  end if;${cover}`;
}

/** Fails when another entry of the organization has the slug. */
function slugFree(q: ContentSql, self: string): string {
  const { e, entries } = q;

  return `if exists (
    select 1 from ${entries} x
    where x.${e("tenant")} = v_row.${e("tenant")} and x.${e("type")} = v_row.${e("type")}
      and x.${e("locale")} = v_row.${e("locale")} and x.${e("slug")} = v_slug
      and x.${e("id")} is distinct from ${self}
  ) then
    ${fail("CONTENT_SLUG_TAKEN", "another entry of this type and locale has this slug", "23505")}
  end if;`;
}

/**
 * Records a version of an entry's content when versions is installed: an
 * automatic one, or a frozen one with `label`.
 */
export function contentSnapshot(
  q: ContentSql,
  row: string,
  label: string | undefined,
): string {
  if (q.versions === undefined) {
    return "";
  }

  const { e } = q;

  return `
  perform ${q.versions.fn("version_insert")}(${row}.${e("tenant")}, ${q.subject}, ${row}.${e("id")}::text,
    jsonb_build_object('title', ${row}.${e("title")}, 'slug', ${row}.${e("slug")}, 'summary', ${q.of(row, "summary")}, 'body', ${row}.${e("body")}),
    null, ${label === undefined ? "null" : sqlString(label)}, ${label === undefined ? "'auto'" : "'manual'"}, ${label === undefined ? "false" : "true"}, auth.uid());`;
}

function entryWrites(ctx: BlockSqlContext): string {
  const q = contentSql(ctx);
  const { fn, e, entries, invalid, forbidden, missing, json, has } = q;

  const load = (
    func: string,
  ): string => `select * into v_row from ${entries} x where x.${e("id")} = ${func}.entry_id for update;
  if not found then
    ${missing}
  end if;`;

  const clearApproval = has("approval")
    ? `\n    ${e("approval")} = case when x.${e("status")} = 'draft' then null else x.${e("approval")} end,`
    : "";

  // Under requireApproval only publishers change what is live or scheduled.
  const liveGuard = q.approval
    ? `
  if v_row.${e("status")} in ('scheduled', 'published') and not ${q.allowed(`v_row.${e("tenant")}`, q.publish)} then
    ${forbidden("only a publisher changes a scheduled or published entry")}
  end if;`
    : "";

  return `-- An entry the caller writes: attrs is { type, locale, slug, title, summary,
-- body, coverAttachmentId, translationOf }. It starts as a draft. translationOf
-- names an entry of the same type whose translation group it joins.
create or replace function ${fn("create_content_entry")}(tenant ${ctx.idType}, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${entries};
  v_source ${entries};
  v_type text := create_content_entry.attrs ->> 'type';
  v_locale text := coalesce(nullif(create_content_entry.attrs ->> 'locale', ''), ${q.defaultLocale});
  v_slug text := lower(trim(create_content_entry.attrs ->> 'slug'));
  v_title text := trim(create_content_entry.attrs ->> 'title');
  v_summary text := nullif(trim(create_content_entry.attrs ->> 'summary'), '');
  v_body jsonb := coalesce(create_content_entry.attrs -> 'body', '{}'::jsonb);
  v_cover uuid := nullif(create_content_entry.attrs ->> 'coverAttachmentId', '')::uuid;
  v_group uuid := gen_random_uuid();
begin
  if not ${q.allowed("create_content_entry.tenant", q.write)} then
    ${forbidden("not allowed to write content")}
  end if;
  if jsonb_typeof(create_content_entry.attrs) is distinct from 'object' then
    ${invalid("attrs must be an object")}
  end if;
  if v_type is null or not (v_type = any (${q.types})) then
    ${invalid("the type is not one of options.types")}
  end if;
  if not (v_locale = any (${q.locales})) then
    ${invalid("the locale is not one of options.locales")}
  end if;
  ${validate(q, "create_content_entry.tenant")}
  if nullif(create_content_entry.attrs ->> 'translationOf', '') is not null then
    select * into v_source from ${entries} x
    where x.${e("id")} = (create_content_entry.attrs ->> 'translationOf')::uuid
      and x.${e("tenant")} = create_content_entry.tenant;
    if not found then
      ${missing}
    end if;
    if v_source.${e("type")} <> ${q.cast("type", "v_type", "null")} then
      ${invalid("a translation has the type of the entry it translates")}
    end if;
    v_group := v_source.${e("translationGroup")};
    if exists (
      select 1 from ${entries} x
      where x.${e("tenant")} = create_content_entry.tenant and x.${e("translationGroup")} = v_group and x.${e("locale")} = ${q.cast("locale", "v_locale", "null")}
    ) then
      ${fail("CONTENT_TRANSLATION_EXISTS", "the entry already has a translation in this locale", "23505")}
    end if;
  end if;
  v_row.${e("tenant")} := create_content_entry.tenant;
  v_row.${e("type")} := ${q.cast("type", "v_type")};
  v_row.${e("locale")} := ${q.cast("locale", "v_locale")};
  ${slugFree(q, "null::uuid")}
  insert into ${entries} (${e("tenant")}, ${e("type")}, ${e("locale")}, ${e("slug")}, ${e("title")}, ${has("summary") ? `${e("summary")}, ` : ""}${e("body")}${has("cover") ? `, ${e("cover")}` : ""}, ${e("translationGroup")}, ${e("author")}${has("createdBy") ? `, ${e("createdBy")}` : ""})
  values (create_content_entry.tenant, ${q.cast("type", "v_type")}, ${q.cast("locale", "v_locale")}, v_slug, v_title, ${has("summary") ? "v_summary, " : ""}v_body${has("cover") ? ", v_cover" : ""}, v_group, auth.uid()${has("createdBy") ? ", auth.uid()" : ""})
  returning * into v_row;
  ${q.record("content_entry.created", "v_row", false)}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("create_content_entry")}(${ctx.idType}, jsonb)`)}

-- Changes an entry's slug, title, summary, body or cover. A change to a draft
-- withdraws its pending publish request, so the approver sees what goes live.
create or replace function ${fn("update_content_entry")}(entry_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${entries};
  v_slug text;
  v_title text;
  v_summary text;
  v_body jsonb;
  v_cover uuid;
begin
  ${load("update_content_entry")}
  if not ${q.allowed(`v_row.${e("tenant")}`, q.write)} then
    ${forbidden("not allowed to write content")}
  end if;${liveGuard}
  if jsonb_typeof(update_content_entry.attrs) is distinct from 'object' then
    ${invalid("attrs must be an object")}
  end if;
  v_slug := case when update_content_entry.attrs ? 'slug' then lower(trim(update_content_entry.attrs ->> 'slug')) else v_row.${e("slug")} end;
  v_title := case when update_content_entry.attrs ? 'title' then trim(update_content_entry.attrs ->> 'title') else v_row.${e("title")} end;
  v_summary := case when update_content_entry.attrs ? 'summary' then nullif(trim(update_content_entry.attrs ->> 'summary'), '') else ${q.of("v_row", "summary")} end;
  v_body := case when update_content_entry.attrs ? 'body' then coalesce(update_content_entry.attrs -> 'body', '{}'::jsonb) else v_row.${e("body")} end;
  v_cover := case when update_content_entry.attrs ? 'coverAttachmentId' then nullif(update_content_entry.attrs ->> 'coverAttachmentId', '')::uuid else ${q.of("v_row", "cover")} end;
  ${validate(q, `v_row.${e("tenant")}`)}
  ${slugFree(q, `v_row.${e("id")}`)}${q.withdraw("v_row")}
  update ${entries} x set
    ${e("slug")} = v_slug,
    ${e("title")} = v_title,${has("summary") ? `\n    ${e("summary")} = v_summary,` : ""}
    ${e("body")} = v_body,${has("cover") ? `\n    ${e("cover")} = v_cover,` : ""}${clearApproval}
    ${e("updatedAt")} = now()
  where x.${e("id")} = v_row.${e("id")}
  returning * into v_row;${contentSnapshot(q, "v_row", undefined)}
  ${q.record("content_entry.updated", "v_row", false)}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("update_content_entry")}(uuid, jsonb)`)}

-- Takes an entry down: archived entries leave the public reads. A draft needs
-- the write permission; a scheduled or published entry needs publish.
create or replace function ${fn("archive_content_entry")}(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${entries};
begin
  ${load("archive_content_entry")}
  if not ${q.allowed(`v_row.${e("tenant")}`, q.write)}
    or (v_row.${e("status")} in ('scheduled', 'published') and not ${q.allowed(`v_row.${e("tenant")}`, q.publish)}) then
    ${forbidden("not allowed to archive this entry")}
  end if;
  if v_row.${e("status")} = 'archived' then
    return ${json("v_row")};
  end if;${q.withdraw("v_row")}
  update ${entries} x set
    ${e("status")} = ${q.cast("status", "'archived'")},
    ${e("publishAt")} = null,${clearApproval}
    ${e("updatedAt")} = now()
  where x.${e("id")} = v_row.${e("id")}
  returning * into v_row;
  ${q.record("content_entry.archived", "v_row", "archived a content entry")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("archive_content_entry")}(uuid)`)}
`;
}

function entryReads(ctx: BlockSqlContext): string {
  const q = contentSql(ctx);
  const { fn, e, entries, json } = q;

  return `-- One entry with its translations, or null when there is none the caller reads.
create or replace function ${fn("get_content_entry")}(entry_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${entries};
begin
  select * into v_row from ${entries} x where x.${e("id")} = get_content_entry.entry_id;
  if not found or not ${q.allowed(`v_row.${e("tenant")}`, q.read)} then
    return null;
  end if;
  return ${json("v_row")} || jsonb_build_object('translations', (
    select coalesce(jsonb_agg(jsonb_build_object('id', t.${e("id")}, 'locale', t.${e("locale")}, 'slug', t.${e("slug")}, 'status', t.${e("status")}) order by t.${e("locale")}), '[]'::jsonb)
    from ${entries} t
    where t.${e("tenant")} = v_row.${e("tenant")} and t.${e("translationGroup")} = v_row.${e("translationGroup")} and t.${e("id")} <> v_row.${e("id")}
  ));
end;
$$;
${userGrant(`${fn("get_content_entry")}(uuid)`)}

-- The organization's entries, latest change first. filter is { type, locale,
-- status, translationGroupId, query, limit (1 to 200, default 50), offset }.
create or replace function ${fn("list_content_entries")}(tenant ${ctx.idType}, filter jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filter jsonb := coalesce(list_content_entries.filter, '{}'::jsonb);
  v_query text := nullif(trim(v_filter ->> 'query'), '');
  v_rows jsonb;
begin
  if not ${q.allowed("list_content_entries.tenant", q.read)} then
    ${q.forbidden("not allowed to read content")}
  end if;
  select coalesce(jsonb_agg(q.item order by q.updated desc, q.id), '[]'::jsonb) into v_rows
  from (
    select ${json("x")} as item, x.${e("updatedAt")} as updated, x.${e("id")} as id
    from ${entries} x
    where x.${e("tenant")} = list_content_entries.tenant
      and (v_filter ->> 'type' is null or x.${e("type")} = ${q.cast("type", "v_filter ->> 'type'", "null")})
      and (v_filter ->> 'locale' is null or x.${e("locale")} = ${q.cast("locale", "v_filter ->> 'locale'", "null")})
      and (v_filter ->> 'status' is null or x.${e("status")} = ${q.cast("status", "v_filter ->> 'status'", "null")})
      and (v_filter ->> 'translationGroupId' is null or x.${e("translationGroup")} = (v_filter ->> 'translationGroupId')::uuid)
      and (v_query is null or x.${e("title")} ilike '%' || v_query || '%' or x.${e("slug")} ilike '%' || v_query || '%')
    order by x.${e("updatedAt")} desc, x.${e("id")}
    limit ${pageSize("(v_filter ->> 'limit')::integer", 50, 200)}
    offset greatest(coalesce((v_filter ->> 'offset')::integer, 0), 0)
  ) q;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_content_entries")}(${ctx.idType}, jsonb)`)}
`;
}

export function contentFunctions(ctx: BlockSqlContext): string {
  return `${entryWrites(ctx)}
${entryReads(ctx)}`;
}
