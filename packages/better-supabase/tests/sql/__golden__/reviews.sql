-- ==== alone: schema supabase/schemas/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block reviews@2 managed
-- @bsb-hash sha256:ee2df637864b24bf2f9c14aa120fe633c4216f184dea5413910870cc7aeccb3d
-- Ratings and reviews of catalog products and other subjects: one per user and subject, verified against paid orders, moderated before or after publishing through the moderation block, with a per-subject aggregate public storefronts can read.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reviews";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."review_stats";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."reviews" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "author_id" uuid references auth.users (id) on delete cascade,
  "author_name" text check ("author_name" is null or length("author_name") <= 100),
  "rating" smallint not null check ("rating" between 1 and 5),
  "title" text check ("title" is null or length("title") <= 200),
  "body" text check ("body" is null or length("body") <= 5000),
  "status" text not null default 'pending' check ("status" in ('pending', 'published', 'rejected')),
  "verified" boolean not null default false,
  "rejection_reason" text check ("rejection_reason" is null or length("rejection_reason") <= 1000),
  "reply" text check ("reply" is null or length("reply") <= 5000),
  "replied_by" uuid,
  "replied_at" timestamptz,
  "published_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "author_id")
);
create index if not exists "reviews_subject_idx" on "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "status", "created_at" desc);
create index if not exists "reviews_queue_idx" on "better_supabase"."reviews" ("tenant_id", "status", "created_at" desc);
create index if not exists "reviews_author_idx" on "better_supabase"."reviews" ("author_id");
alter table "better_supabase"."reviews" enable row level security;
revoke all on "better_supabase"."reviews" from public, anon, authenticated;
grant all on "better_supabase"."reviews" to service_role;

create table if not exists "better_supabase"."review_stats" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "review_count" integer not null default 0,
  "rating_total" bigint not null default 0,
  "histogram" jsonb not null default '{}'::jsonb,
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "subject_type", "subject_id")
);
alter table "better_supabase"."review_stats" enable row level security;
revoke all on "better_supabase"."review_stats" from public, anon, authenticated;
grant all on "better_supabase"."review_stats" to service_role;

-- Whether the caller may read and review a subject: an active product on a
-- published public storefront or in a catalog the caller reads, or a
-- registered subject in an organization the caller belongs to. plpgsql, so
-- a subject table a later module creates (messages) binds late.
create or replace function "better_supabase"."review_subject_readable"(tenant uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return false;
end;
$$;
revoke execute on function "better_supabase"."review_subject_readable"(uuid, text, text) from public, anon, authenticated;

-- Recounts one subject's published reviews into review_stats.
create or replace function "better_supabase"."review_stats_refresh"(tenant uuid, subject_type text, subject_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into "better_supabase"."review_stats" ("tenant_id", "subject_type", "subject_id", "review_count", "rating_total", "histogram", "updated_at")
  select review_stats_refresh.tenant, review_stats_refresh.subject_type, review_stats_refresh.subject_id,
    count(*)::integer, coalesce(sum(x."rating"), 0)::bigint,
    coalesce((select jsonb_object_agg(h.rating::text, h.n) from (
      select y."rating" as rating, count(*) as n from "better_supabase"."reviews" y
      where y."tenant_id" = review_stats_refresh.tenant and y."subject_type" = review_stats_refresh.subject_type
        and y."subject_id" = review_stats_refresh.subject_id and y."status" = 'published'
      group by y."rating"
    ) h), '{}'::jsonb),
    now()
  from "better_supabase"."reviews" x
  where x."tenant_id" = review_stats_refresh.tenant and x."subject_type" = review_stats_refresh.subject_type
    and x."subject_id" = review_stats_refresh.subject_id and x."status" = 'published'
  on conflict ("tenant_id", "subject_type", "subject_id") do update
    set "review_count" = excluded."review_count", "rating_total" = excluded."rating_total",
      "histogram" = excluded."histogram", "updated_at" = excluded."updated_at";
$$;
revoke execute on function "better_supabase"."review_stats_refresh"(uuid, text, text) from public, anon, authenticated;

-- Keeps review_stats in step with every write, including user purges.
create or replace function "better_supabase"."reviews_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform "better_supabase"."review_stats_refresh"(old."tenant_id", old."subject_type", old."subject_id");
  end if;
  if tg_op = 'DELETE' then
    delete from "better_supabase"."moderation_items" x
    where x."tenant_id" = old."tenant_id" and x."subject_type" = 'review' and x."subject_id" = old."id"::text;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform "better_supabase"."review_stats_refresh"(new."tenant_id", new."subject_type", new."subject_id");
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_changed" on "better_supabase"."reviews";
create trigger "bsb_reviews_changed"
  after insert or update of "rating", "status" or delete on "better_supabase"."reviews"
  for each row execute function "better_supabase"."reviews_changed"();

-- Writes the caller's review of a subject, or replaces it: one review per
-- user and subject. Under pre-moderation (options.moderation "pre") it
-- waits for publish_review; under "post" it is published at once. verified
-- is true when the orders module shows a paid order for the product.
drop function if exists "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text, jsonb);
create or replace function "better_supabase"."submit_review"(tenant uuid, subject_type text, subject_id text, rating integer, body text default null, title text default null, author_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_verified boolean;
  v_row "better_supabase"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to write a review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if submit_review.rating is null or submit_review.rating not between 1 and 5 then
    raise exception 'rating must be from 1 to 5' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if length(submit_review.body) > 5000 then
    raise exception 'body must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if not "better_supabase"."review_subject_readable"(submit_review.tenant, submit_review.subject_type, submit_review.subject_id) then
    raise exception 'not allowed to review this record' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  v_verified := false;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_review_submit"(uuid, text, text, integer)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::integer)', v_hook::oid::regproc)
        using submit_review.tenant, submit_review.subject_type, submit_review.subject_id, submit_review.rating;
    end if;
  end;
  insert into "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "author_id", "author_name", "rating", "title", "body", "status", "verified", "published_at")
  values (submit_review.tenant, submit_review.subject_type, submit_review.subject_id, v_me, nullif(trim(submit_review.author_name), ''), submit_review.rating, nullif(trim(submit_review.title), ''), nullif(trim(submit_review.body), ''), 'pending', v_verified, null)
  on conflict ("tenant_id", "subject_type", "subject_id", "author_id") do update
    set "rating" = excluded."rating", "title" = excluded."title", "body" = excluded."body", "author_name" = excluded."author_name", "verified" = excluded."verified", "status" = excluded."status", "published_at" = excluded."published_at", "rejection_reason" = null, "updated_at" = now()
  returning * into v_row;
  perform "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_me, 'pending');
  null;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_review_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) from public, anon;
grant execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) to authenticated, service_role;

-- Deletes a review: its author, or a moderator.
create or replace function "better_supabase"."delete_review"(review_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_mine boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = delete_review.review_id for update;
  if not found then
    return false;
  end if;
  v_mine := v_row."author_id" = auth.uid();
  if not (coalesce(v_mine, false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to delete this review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  delete from "better_supabase"."reviews" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_review"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_review"(uuid) to authenticated, service_role;

-- Projects a review's moderation item onto the review: visible publishes it,
-- hidden and removed reject it with the item's reason. A decision (from
-- publish_review, reject_review or the moderation block) records
-- review.published or review.rejected and tells the author.
create or replace function "better_supabase"."reviews_moderated"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  update "better_supabase"."reviews" x
  set "status" = case new."status" when 'visible' then 'published' when 'pending' then 'pending' else 'rejected' end,
    "published_at" = case when new."status" = 'visible' then coalesce(x."published_at", now()) end,
    "rejection_reason" = case when new."status" in ('hidden', 'removed') then new."reason" end,
    "updated_at" = now()
  where x."id"::text = new."subject_id" and x."tenant_id" = new."tenant_id"
  returning * into v_row;
  if v_row."id" is null or new."decided_at" is null or old."status" = new."status" then
    return null;
  end if;
  if new."status" = 'visible' then
    null;
  elsif old."status" not in ('hidden', 'removed') then
    null;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_moderated"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_moderated" on "better_supabase"."moderation_items";
create trigger "bsb_reviews_moderated"
  after update of "status", "decided_at" on "better_supabase"."moderation_items"
  for each row when (new."subject_type" = 'review')
  execute function "better_supabase"."reviews_moderated"();

-- The moderation item of a review, created when the review predates it.
create or replace function "better_supabase"."review_moderation_item"(review_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_item uuid;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = review_moderation_item.review_id;
  select x."id" into v_item from "better_supabase"."moderation_items" x
  where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'review' and x."subject_id" = v_row."id"::text;
  if v_item is null then
    v_item := "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_row."author_id",
      case when v_row."status" = 'published' then 'visible' else 'pending' end);
  end if;
  return v_item;
end;
$$;
revoke execute on function "better_supabase"."review_moderation_item"(uuid) from public, anon, authenticated;

-- Publishes a pending or rejected review: approves its moderation item.
create or replace function "better_supabase"."publish_review"(review_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'approve', null, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."publish_review"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_review"(uuid) to authenticated, service_role;

-- Rejects a review with an optional reason the author sees: hides its
-- moderation item.
create or replace function "better_supabase"."reject_review"(review_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'hide', reject_review.reason, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reject_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reject_review"(uuid, text) to authenticated, service_role;

-- Sets the organization's public reply to a review; null removes it.
create or replace function "better_supabase"."reply_to_review"(review_id uuid, reply text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = reply_to_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if length(reply_to_review.reply) > 5000 then
    raise exception 'reply must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  update "better_supabase"."reviews" x
  set "reply" = nullif(trim(reply_to_review.reply), ''),
    "replied_by" = case when nullif(trim(reply_to_review.reply), '') is null then null else auth.uid() end,
    "replied_at" = case when nullif(trim(reply_to_review.reply), '') is null then null else now() end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reply_to_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reply_to_review"(uuid, text) to authenticated, service_role;

-- A subject's published reviews, newest first, for anyone who can read the
-- subject (anonymous visitors for a public storefront's products). Author
-- ids stay hidden; mine marks the caller's own review.
create or replace function "better_supabase"."list_reviews"(tenant uuid, subject_type text, subject_id text, page_size integer default 20, before timestamptz default null, rating integer default null, verified boolean default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(list_reviews.tenant, list_reviews.subject_type, list_reviews.subject_id)) then
    raise exception 'not allowed to read this record''s reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.published desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."published_at" as published, x."id" as id
    from "better_supabase"."reviews" x
    where x."tenant_id" = list_reviews.tenant and x."subject_type" = list_reviews.subject_type
      and x."subject_id" = list_reviews.subject_id and x."status" = 'published'
      and (list_reviews.before is null or x."published_at" < list_reviews.before)
      and (list_reviews.rating is null or x."rating" = list_reviews.rating)
      and (list_reviews.verified is null or x."verified" = list_reviews.verified)
    order by x."published_at" desc, x."id" desc
    limit least(greatest(coalesce(list_reviews.page_size, 20), 1), 100)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) from public;
grant execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) to anon, authenticated, service_role;

-- The caller's own review of a subject in any status, or null.
create or replace function "better_supabase"."my_review"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")
  from "better_supabase"."reviews" x
  where x."tenant_id" = my_review.tenant and x."subject_type" = my_review.subject_type
    and x."subject_id" = my_review.subject_id and x."author_id" = auth.uid()
$$;
revoke execute on function "better_supabase"."my_review"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."my_review"(uuid, text, text) to authenticated, service_role;

-- Reviews for moderators, newest first: pending by default.
create or replace function "better_supabase"."review_queue"(tenant uuid, status text default 'pending', page_size integer default 50, before timestamptz default null, subject_type text default null, subject_id text default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', review_queue.tenant, 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.created desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created, x."id" as id
    from "better_supabase"."reviews" x
    where x."tenant_id" = review_queue.tenant
      and (review_queue.status is null or x."status" = review_queue.status)
      and (review_queue.subject_type is null or x."subject_type" = review_queue.subject_type)
      and (review_queue.subject_id is null or x."subject_id" = review_queue.subject_id)
      and (review_queue.before is null or x."created_at" < review_queue.before)
    order by x."created_at" desc, x."id" desc
    limit least(greatest(coalesce(review_queue.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text) from public, anon;
grant execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text) to authenticated, service_role;

-- The rating aggregate of up to 200 subjects of one type, as
-- { subjectId: { count, average, histogram } }, for the subjects the caller
-- can read. Subjects without published reviews are left out.
create or replace function "better_supabase"."review_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x."subject_id", jsonb_build_object(
    'count', x."review_count",
    'average', case when x."review_count" = 0 then null else round(x."rating_total"::numeric / x."review_count", 2) end,
    'histogram', x."histogram"
  )), '{}'::jsonb)
  from "better_supabase"."review_stats" x
  where x."tenant_id" = review_summary.tenant and x."subject_type" = review_summary.subject_type
    and x."subject_id" = any (review_summary.subject_ids[1:200]) and x."review_count" > 0
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(review_summary.tenant, review_summary.subject_type, x."subject_id"))
$$;
revoke execute on function "better_supabase"."review_summary"(uuid, text, text[]) from public;
grant execute on function "better_supabase"."review_summary"(uuid, text, text[]) to anon, authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block-data reviews
-- @bsb-hash sha256:eca482e72d47f7bec9778aee91022da731eeb8923934dd7c289ea657debbff27
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Puts the reviews written before the moderation module under it.
insert into "better_supabase"."moderation_items" ("tenant_id", "subject_type", "subject_id", "author_id", "status", "reason", "decided_by", "decided_at", "created_at", "updated_at")
  select x."tenant_id", 'review', x."id"::text, x."author_id",
    case x."status"::text when 'published' then 'visible' when 'rejected' then 'hidden' else 'pending' end,
    case when x."status" = 'rejected' then x."rejection_reason" end, null, null, x."created_at", x."updated_at"
  from "better_supabase"."reviews" x
  on conflict ("tenant_id", "subject_type", "subject_id") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reviews', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block reviews@2 managed
-- @bsb-hash sha256:593eba4d129ce8cbe470e7ef19f15438d08f5c6296761c7d7ed9198c4e8b6b0f
-- Ratings and reviews of catalog products and other subjects: one per user and subject, verified against paid orders, moderated before or after publishing through the moderation block, with a per-subject aggregate public storefronts can read.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reviews";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."review_stats";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."reviews" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "author_id" uuid references auth.users (id) on delete cascade,
  "author_name" text check ("author_name" is null or length("author_name") <= 100),
  "rating" smallint not null check ("rating" between 1 and 5),
  "title" text check ("title" is null or length("title") <= 200),
  "body" text check ("body" is null or length("body") <= 5000),
  "status" text not null default 'pending' check ("status" in ('pending', 'published', 'rejected')),
  "verified" boolean not null default false,
  "rejection_reason" text check ("rejection_reason" is null or length("rejection_reason") <= 1000),
  "reply" text check ("reply" is null or length("reply") <= 5000),
  "replied_by" uuid,
  "replied_at" timestamptz,
  "published_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "author_id")
);
create index if not exists "reviews_subject_idx" on "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "status", "created_at" desc);
create index if not exists "reviews_queue_idx" on "better_supabase"."reviews" ("tenant_id", "status", "created_at" desc);
create index if not exists "reviews_author_idx" on "better_supabase"."reviews" ("author_id");
alter table "better_supabase"."reviews" enable row level security;
revoke all on "better_supabase"."reviews" from public, anon, authenticated;
grant all on "better_supabase"."reviews" to service_role;

create table if not exists "better_supabase"."review_stats" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "review_count" integer not null default 0,
  "rating_total" bigint not null default 0,
  "histogram" jsonb not null default '{}'::jsonb,
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "subject_type", "subject_id")
);
alter table "better_supabase"."review_stats" enable row level security;
revoke all on "better_supabase"."review_stats" from public, anon, authenticated;
grant all on "better_supabase"."review_stats" to service_role;

-- Whether the caller may read and review a subject: an active product on a
-- published public storefront or in a catalog the caller reads, or a
-- registered subject in an organization the caller belongs to. plpgsql, so
-- a subject table a later module creates (messages) binds late.
create or replace function "better_supabase"."review_subject_readable"(tenant uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce(case review_subject_readable.subject_type
    when 'product' then exists (select 1 from "better_supabase"."products" p where p."id"::text = review_subject_readable.subject_id and p."tenant_id" = review_subject_readable.tenant and p."status" = 'active' and (coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'catalog.read'), false)))
    else false
  end, false);
end;
$$;
revoke execute on function "better_supabase"."review_subject_readable"(uuid, text, text) from public, anon, authenticated;

-- Recounts one subject's published reviews into review_stats.
create or replace function "better_supabase"."review_stats_refresh"(tenant uuid, subject_type text, subject_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into "better_supabase"."review_stats" ("tenant_id", "subject_type", "subject_id", "review_count", "rating_total", "histogram", "updated_at")
  select review_stats_refresh.tenant, review_stats_refresh.subject_type, review_stats_refresh.subject_id,
    count(*)::integer, coalesce(sum(x."rating"), 0)::bigint,
    coalesce((select jsonb_object_agg(h.rating::text, h.n) from (
      select y."rating" as rating, count(*) as n from "better_supabase"."reviews" y
      where y."tenant_id" = review_stats_refresh.tenant and y."subject_type" = review_stats_refresh.subject_type
        and y."subject_id" = review_stats_refresh.subject_id and y."status" = 'published'
      group by y."rating"
    ) h), '{}'::jsonb),
    now()
  from "better_supabase"."reviews" x
  where x."tenant_id" = review_stats_refresh.tenant and x."subject_type" = review_stats_refresh.subject_type
    and x."subject_id" = review_stats_refresh.subject_id and x."status" = 'published'
  on conflict ("tenant_id", "subject_type", "subject_id") do update
    set "review_count" = excluded."review_count", "rating_total" = excluded."rating_total",
      "histogram" = excluded."histogram", "updated_at" = excluded."updated_at";
$$;
revoke execute on function "better_supabase"."review_stats_refresh"(uuid, text, text) from public, anon, authenticated;

-- Keeps review_stats in step with every write, including user purges.
create or replace function "better_supabase"."reviews_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform "better_supabase"."review_stats_refresh"(old."tenant_id", old."subject_type", old."subject_id");
  end if;
  if tg_op = 'DELETE' then
    delete from "better_supabase"."moderation_items" x
    where x."tenant_id" = old."tenant_id" and x."subject_type" = 'review' and x."subject_id" = old."id"::text;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform "better_supabase"."review_stats_refresh"(new."tenant_id", new."subject_type", new."subject_id");
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_changed" on "better_supabase"."reviews";
create trigger "bsb_reviews_changed"
  after insert or update of "rating", "status" or delete on "better_supabase"."reviews"
  for each row execute function "better_supabase"."reviews_changed"();

-- Writes the caller's review of a subject, or replaces it: one review per
-- user and subject. Under pre-moderation (options.moderation "pre") it
-- waits for publish_review; under "post" it is published at once. verified
-- is true when the orders module shows a paid order for the product.
drop function if exists "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text, jsonb);
create or replace function "better_supabase"."submit_review"(tenant uuid, subject_type text, subject_id text, rating integer, body text default null, title text default null, author_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_verified boolean;
  v_row "better_supabase"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to write a review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if submit_review.rating is null or submit_review.rating not between 1 and 5 then
    raise exception 'rating must be from 1 to 5' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if length(submit_review.body) > 5000 then
    raise exception 'body must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if not "better_supabase"."review_subject_readable"(submit_review.tenant, submit_review.subject_type, submit_review.subject_id) then
    raise exception 'not allowed to review this record' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  v_verified := coalesce(submit_review.subject_type = 'product' and submit_review.subject_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and exists (
    select 1 from "better_supabase"."orders" o
    join "better_supabase"."order_lines" l on l."order_id" = o."id"
    where o."tenant_id" = submit_review.tenant and o."customer_id" = v_me
      and o."paid_at" is not null and o."cancelled_at" is null
      and l."product_id" = submit_review.subject_id::uuid
  ), false);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_review_submit"(uuid, text, text, integer)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::integer)', v_hook::oid::regproc)
        using submit_review.tenant, submit_review.subject_type, submit_review.subject_id, submit_review.rating;
    end if;
  end;
  insert into "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "author_id", "author_name", "rating", "title", "body", "status", "verified", "published_at")
  values (submit_review.tenant, submit_review.subject_type, submit_review.subject_id, v_me, nullif(trim(submit_review.author_name), ''), submit_review.rating, nullif(trim(submit_review.title), ''), nullif(trim(submit_review.body), ''), 'pending', v_verified, null)
  on conflict ("tenant_id", "subject_type", "subject_id", "author_id") do update
    set "rating" = excluded."rating", "title" = excluded."title", "body" = excluded."body", "author_name" = excluded."author_name", "verified" = excluded."verified", "status" = excluded."status", "published_at" = excluded."published_at", "rejection_reason" = null, "updated_at" = now()
  returning * into v_row;
  perform "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_me, 'pending');
  perform "better_supabase".emit_event('review.submitted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified"), 'reviews/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reviews');
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_review_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) from public, anon;
grant execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) to authenticated, service_role;

-- Deletes a review: its author, or a moderator.
create or replace function "better_supabase"."delete_review"(review_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_mine boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = delete_review.review_id for update;
  if not found then
    return false;
  end if;
  v_mine := v_row."author_id" = auth.uid();
  if not (coalesce(v_mine, false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to delete this review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  delete from "better_supabase"."reviews" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('review.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified"), 'reviews/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reviews');
  perform better_supabase.audit_event(
    event_type => 'review.deleted',
    category => 'data',
    target_type => 'review',
    record_id => v_row."id"::text,
    summary => 'deleted a review',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_review"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_review"(uuid) to authenticated, service_role;

-- Projects a review's moderation item onto the review: visible publishes it,
-- hidden and removed reject it with the item's reason. A decision (from
-- publish_review, reject_review or the moderation block) records
-- review.published or review.rejected and tells the author.
create or replace function "better_supabase"."reviews_moderated"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_claims text;
begin
  update "better_supabase"."reviews" x
  set "status" = case new."status" when 'visible' then 'published' when 'pending' then 'pending' else 'rejected' end,
    "published_at" = case when new."status" = 'visible' then coalesce(x."published_at", now()) end,
    "rejection_reason" = case when new."status" in ('hidden', 'removed') then new."reason" end,
    "updated_at" = now()
  where x."id"::text = new."subject_id" and x."tenant_id" = new."tenant_id"
  returning * into v_row;
  if v_row."id" is null or new."decided_at" is null or old."status" = new."status" then
    return null;
  end if;
  if new."status" = 'visible' then
    perform "better_supabase".emit_event('review.published', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified"), 'reviews/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reviews');
  perform better_supabase.audit_event(
    event_type => 'review.published',
    category => 'data',
    target_type => 'review',
    record_id => v_row."id"::text,
    summary => 'published a review',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified")
  );
  if v_row."author_id" is not null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'review.published',
      'tenant', v_row."tenant_id",
      'subject_type', v_row."subject_type",
      'subject_id', v_row."subject_id",
      'summary', 'Your review was published',
      'recipients', jsonb_build_array(v_row."author_id"),
      'key', 'review.published:' || v_row."id"::text || ':' || extract(epoch from now())::text,
      'data', jsonb_build_object('reviewId', v_row."id", 'status', v_row."status")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  elsif old."status" not in ('hidden', 'removed') then
    perform "better_supabase".emit_event('review.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified"), 'reviews/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reviews');
  perform better_supabase.audit_event(
    event_type => 'review.rejected',
    category => 'data',
    target_type => 'review',
    record_id => v_row."id"::text,
    summary => 'rejected a review',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified")
  );
  if v_row."author_id" is not null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'review.rejected',
      'tenant', v_row."tenant_id",
      'subject_type', v_row."subject_type",
      'subject_id', v_row."subject_id",
      'summary', 'Your review was not published',
      'recipients', jsonb_build_array(v_row."author_id"),
      'key', 'review.rejected:' || v_row."id"::text || ':' || extract(epoch from now())::text,
      'data', jsonb_build_object('reviewId', v_row."id", 'status', v_row."status")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_moderated"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_moderated" on "better_supabase"."moderation_items";
create trigger "bsb_reviews_moderated"
  after update of "status", "decided_at" on "better_supabase"."moderation_items"
  for each row when (new."subject_type" = 'review')
  execute function "better_supabase"."reviews_moderated"();

-- The moderation item of a review, created when the review predates it.
create or replace function "better_supabase"."review_moderation_item"(review_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_item uuid;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = review_moderation_item.review_id;
  select x."id" into v_item from "better_supabase"."moderation_items" x
  where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'review' and x."subject_id" = v_row."id"::text;
  if v_item is null then
    v_item := "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_row."author_id",
      case when v_row."status" = 'published' then 'visible' else 'pending' end);
  end if;
  return v_item;
end;
$$;
revoke execute on function "better_supabase"."review_moderation_item"(uuid) from public, anon, authenticated;

-- Publishes a pending or rejected review: approves its moderation item.
create or replace function "better_supabase"."publish_review"(review_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'approve', null, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."publish_review"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_review"(uuid) to authenticated, service_role;

-- Rejects a review with an optional reason the author sees: hides its
-- moderation item.
create or replace function "better_supabase"."reject_review"(review_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'hide', reject_review.reason, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reject_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reject_review"(uuid, text) to authenticated, service_role;

-- Sets the organization's public reply to a review; null removes it.
create or replace function "better_supabase"."reply_to_review"(review_id uuid, reply text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = reply_to_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if length(reply_to_review.reply) > 5000 then
    raise exception 'reply must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  update "better_supabase"."reviews" x
  set "reply" = nullif(trim(reply_to_review.reply), ''),
    "replied_by" = case when nullif(trim(reply_to_review.reply), '') is null then null else auth.uid() end,
    "replied_at" = case when nullif(trim(reply_to_review.reply), '') is null then null else now() end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('review.replied', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified"), 'reviews/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reviews');
  perform better_supabase.audit_event(
    event_type => 'review.replied',
    category => 'data',
    target_type => 'review',
    record_id => v_row."id"::text,
    summary => 'replied to a review',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified")
  );
  if v_row."author_id" is not null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'review.replied',
      'tenant', v_row."tenant_id",
      'subject_type', v_row."subject_type",
      'subject_id', v_row."subject_id",
      'summary', 'Your review has a reply',
      'recipients', jsonb_build_array(v_row."author_id"),
      'key', 'review.replied:' || v_row."id"::text || ':' || extract(epoch from now())::text,
      'data', jsonb_build_object('reviewId', v_row."id", 'status', v_row."status")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reply_to_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reply_to_review"(uuid, text) to authenticated, service_role;

-- A subject's published reviews, newest first, for anyone who can read the
-- subject (anonymous visitors for a public storefront's products). Author
-- ids stay hidden; mine marks the caller's own review.
create or replace function "better_supabase"."list_reviews"(tenant uuid, subject_type text, subject_id text, page_size integer default 20, before timestamptz default null, rating integer default null, verified boolean default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(list_reviews.tenant, list_reviews.subject_type, list_reviews.subject_id)) then
    raise exception 'not allowed to read this record''s reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.published desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."published_at" as published, x."id" as id
    from "better_supabase"."reviews" x
    where x."tenant_id" = list_reviews.tenant and x."subject_type" = list_reviews.subject_type
      and x."subject_id" = list_reviews.subject_id and x."status" = 'published'
      and (list_reviews.before is null or x."published_at" < list_reviews.before)
      and (list_reviews.rating is null or x."rating" = list_reviews.rating)
      and (list_reviews.verified is null or x."verified" = list_reviews.verified)
    order by x."published_at" desc, x."id" desc
    limit least(greatest(coalesce(list_reviews.page_size, 20), 1), 100)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) from public;
grant execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) to anon, authenticated, service_role;

-- The caller's own review of a subject in any status, or null.
create or replace function "better_supabase"."my_review"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")
  from "better_supabase"."reviews" x
  where x."tenant_id" = my_review.tenant and x."subject_type" = my_review.subject_type
    and x."subject_id" = my_review.subject_id and x."author_id" = auth.uid()
$$;
revoke execute on function "better_supabase"."my_review"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."my_review"(uuid, text, text) to authenticated, service_role;

-- Reviews for moderators, newest first: pending by default.
create or replace function "better_supabase"."review_queue"(tenant uuid, status text default 'pending', page_size integer default 50, before timestamptz default null, subject_type text default null, subject_id text default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', review_queue.tenant, 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.created desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created, x."id" as id
    from "better_supabase"."reviews" x
    where x."tenant_id" = review_queue.tenant
      and (review_queue.status is null or x."status" = review_queue.status)
      and (review_queue.subject_type is null or x."subject_type" = review_queue.subject_type)
      and (review_queue.subject_id is null or x."subject_id" = review_queue.subject_id)
      and (review_queue.before is null or x."created_at" < review_queue.before)
    order by x."created_at" desc, x."id" desc
    limit least(greatest(coalesce(review_queue.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text) from public, anon;
grant execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text) to authenticated, service_role;

-- The rating aggregate of up to 200 subjects of one type, as
-- { subjectId: { count, average, histogram } }, for the subjects the caller
-- can read. Subjects without published reviews are left out.
create or replace function "better_supabase"."review_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x."subject_id", jsonb_build_object(
    'count', x."review_count",
    'average', case when x."review_count" = 0 then null else round(x."rating_total"::numeric / x."review_count", 2) end,
    'histogram', x."histogram"
  )), '{}'::jsonb)
  from "better_supabase"."review_stats" x
  where x."tenant_id" = review_summary.tenant and x."subject_type" = review_summary.subject_type
    and x."subject_id" = any (review_summary.subject_ids[1:200]) and x."review_count" > 0
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(review_summary.tenant, review_summary.subject_type, x."subject_id"))
$$;
revoke execute on function "better_supabase"."review_summary"(uuid, text, text[]) from public;
grant execute on function "better_supabase"."review_summary"(uuid, text, text[]) to anon, authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block-data reviews
-- @bsb-hash sha256:eca482e72d47f7bec9778aee91022da731eeb8923934dd7c289ea657debbff27
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Puts the reviews written before the moderation module under it.
insert into "better_supabase"."moderation_items" ("tenant_id", "subject_type", "subject_id", "author_id", "status", "reason", "decided_by", "decided_at", "created_at", "updated_at")
  select x."tenant_id", 'review', x."id"::text, x."author_id",
    case x."status"::text when 'published' then 'visible' when 'rejected' then 'hidden' else 'pending' end,
    case when x."status" = 'rejected' then x."rejection_reason" end, null, null, x."created_at", x."updated_at"
  from "better_supabase"."reviews" x
  on conflict ("tenant_id", "subject_type", "subject_id") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reviews', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block reviews@2 managed
-- @bsb-hash sha256:3177c3c203ac9d0990a12739ae433fd2cc2cf645706f778fe18205a0de90e1a0
-- Ratings and reviews of catalog products and other subjects: one per user and subject, verified against paid orders, moderated before or after publishing through the moderation block, with a per-subject aggregate public storefronts can read.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."reviews";
    drop policy if exists bsb_tenant_scope_select on "app_private"."reviews";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."reviews";
    drop policy if exists bsb_tenant_scope_update on "app_private"."reviews";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."reviews";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."review_stats";
    drop policy if exists bsb_tenant_scope_select on "app_private"."review_stats";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."review_stats";
    drop policy if exists bsb_tenant_scope_update on "app_private"."review_stats";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."review_stats";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
create table if not exists "app_private"."reviews" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "author_id" uuid references auth.users (id) on delete cascade,
  "author_name" text check ("author_name" is null or length("author_name") <= 100),
  "rating" smallint not null check ("rating" between 1 and 5),
  "title" text check ("title" is null or length("title") <= 200),
  "body" text check ("body" is null or length("body") <= 5000),
  "status" text not null default 'pending' check ("status" in ('pending', 'published', 'rejected')),
  "verified" boolean not null default false,
  "rejection_reason" text check ("rejection_reason" is null or length("rejection_reason") <= 1000),
  "reply" text check ("reply" is null or length("reply") <= 5000),
  "replied_by" uuid,
  "replied_at" timestamptz,
  "published_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "author_id")
);
create index if not exists "reviews_subject_idx" on "app_private"."reviews" ("tenant_id", "subject_type", "subject_id", "status", "created_at" desc);
create index if not exists "reviews_queue_idx" on "app_private"."reviews" ("tenant_id", "status", "created_at" desc);
create index if not exists "reviews_author_idx" on "app_private"."reviews" ("author_id");
alter table "app_private"."reviews" enable row level security;
revoke all on "app_private"."reviews" from public, anon, authenticated;
grant all on "app_private"."reviews" to service_role;

create table if not exists "app_private"."review_stats" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "review_count" integer not null default 0,
  "rating_total" bigint not null default 0,
  "histogram" jsonb not null default '{}'::jsonb,
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "subject_type", "subject_id")
);
alter table "app_private"."review_stats" enable row level security;
revoke all on "app_private"."review_stats" from public, anon, authenticated;
grant all on "app_private"."review_stats" to service_role;

-- Whether the caller may read and review a subject: an active product on a
-- published public storefront or in a catalog the caller reads, or a
-- registered subject in an organization the caller belongs to. plpgsql, so
-- a subject table a later module creates (messages) binds late.
create or replace function "app_private"."review_subject_readable"(tenant uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return false;
end;
$$;
revoke execute on function "app_private"."review_subject_readable"(uuid, text, text) from public, anon, authenticated;

-- Recounts one subject's published reviews into review_stats.
create or replace function "app_private"."review_stats_refresh"(tenant uuid, subject_type text, subject_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into "app_private"."review_stats" ("tenant_id", "subject_type", "subject_id", "review_count", "rating_total", "histogram", "updated_at")
  select review_stats_refresh.tenant, review_stats_refresh.subject_type, review_stats_refresh.subject_id,
    count(*)::integer, coalesce(sum(x."rating"), 0)::bigint,
    coalesce((select jsonb_object_agg(h.rating::text, h.n) from (
      select y."rating" as rating, count(*) as n from "app_private"."reviews" y
      where y."tenant_id" = review_stats_refresh.tenant and y."subject_type" = review_stats_refresh.subject_type
        and y."subject_id" = review_stats_refresh.subject_id and y."status" = 'published'
      group by y."rating"
    ) h), '{}'::jsonb),
    now()
  from "app_private"."reviews" x
  where x."tenant_id" = review_stats_refresh.tenant and x."subject_type" = review_stats_refresh.subject_type
    and x."subject_id" = review_stats_refresh.subject_id and x."status" = 'published'
  on conflict ("tenant_id", "subject_type", "subject_id") do update
    set "review_count" = excluded."review_count", "rating_total" = excluded."rating_total",
      "histogram" = excluded."histogram", "updated_at" = excluded."updated_at";
$$;
revoke execute on function "app_private"."review_stats_refresh"(uuid, text, text) from public, anon, authenticated;

-- Keeps review_stats in step with every write, including user purges.
create or replace function "app_private"."reviews_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform "app_private"."review_stats_refresh"(old."tenant_id", old."subject_type", old."subject_id");
  end if;
  if tg_op = 'DELETE' then
    delete from "better_supabase"."moderation_items" x
    where x."tenant_id" = old."tenant_id" and x."subject_type" = 'review' and x."subject_id" = old."id"::text;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform "app_private"."review_stats_refresh"(new."tenant_id", new."subject_type", new."subject_id");
  end if;
  return null;
end;
$$;
revoke execute on function "app_private"."reviews_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_changed" on "app_private"."reviews";
create trigger "bsb_reviews_changed"
  after insert or update of "rating", "status" or delete on "app_private"."reviews"
  for each row execute function "app_private"."reviews_changed"();

-- Writes the caller's review of a subject, or replaces it: one review per
-- user and subject. Under pre-moderation (options.moderation "pre") it
-- waits for publish_review; under "post" it is published at once. verified
-- is true when the orders module shows a paid order for the product.
drop function if exists "app_private"."submit_review"(uuid, text, text, integer, text, text, text, jsonb);
create or replace function "app_private"."submit_review"(tenant uuid, subject_type text, subject_id text, rating integer, body text default null, title text default null, author_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_verified boolean;
  v_row "app_private"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to write a review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if submit_review.rating is null or submit_review.rating not between 1 and 5 then
    raise exception 'rating must be from 1 to 5' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if length(submit_review.body) > 5000 then
    raise exception 'body must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if not "app_private"."review_subject_readable"(submit_review.tenant, submit_review.subject_type, submit_review.subject_id) then
    raise exception 'not allowed to review this record' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  v_verified := false;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_review_submit"(uuid, text, text, integer)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::integer)', v_hook::oid::regproc)
        using submit_review.tenant, submit_review.subject_type, submit_review.subject_id, submit_review.rating;
    end if;
  end;
  insert into "app_private"."reviews" ("tenant_id", "subject_type", "subject_id", "author_id", "author_name", "rating", "title", "body", "status", "verified", "published_at")
  values (submit_review.tenant, submit_review.subject_type, submit_review.subject_id, v_me, nullif(trim(submit_review.author_name), ''), submit_review.rating, nullif(trim(submit_review.title), ''), nullif(trim(submit_review.body), ''), 'pending', v_verified, null)
  on conflict ("tenant_id", "subject_type", "subject_id", "author_id") do update
    set "rating" = excluded."rating", "title" = excluded."title", "body" = excluded."body", "author_name" = excluded."author_name", "verified" = excluded."verified", "status" = excluded."status", "published_at" = excluded."published_at", "rejection_reason" = null, "updated_at" = now()
  returning * into v_row;
  perform "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_me, 'pending');
  null;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_review_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."submit_review"(uuid, text, text, integer, text, text, text) from public, anon;
grant execute on function "app_private"."submit_review"(uuid, text, text, integer, text, text, text) to authenticated, service_role;

-- Deletes a review: its author, or a moderator.
create or replace function "app_private"."delete_review"(review_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."reviews"%rowtype;
  v_mine boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."reviews" x where x."id" = delete_review.review_id for update;
  if not found then
    return false;
  end if;
  v_mine := v_row."author_id" = auth.uid();
  if not (coalesce(v_mine, false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to delete this review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  delete from "app_private"."reviews" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_review"(uuid) from public, anon;
grant execute on function "app_private"."delete_review"(uuid) to authenticated, service_role;

-- Projects a review's moderation item onto the review: visible publishes it,
-- hidden and removed reject it with the item's reason. A decision (from
-- publish_review, reject_review or the moderation block) records
-- review.published or review.rejected and tells the author.
create or replace function "app_private"."reviews_moderated"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."reviews"%rowtype;
begin
  update "app_private"."reviews" x
  set "status" = case new."status" when 'visible' then 'published' when 'pending' then 'pending' else 'rejected' end,
    "published_at" = case when new."status" = 'visible' then coalesce(x."published_at", now()) end,
    "rejection_reason" = case when new."status" in ('hidden', 'removed') then new."reason" end,
    "updated_at" = now()
  where x."id"::text = new."subject_id" and x."tenant_id" = new."tenant_id"
  returning * into v_row;
  if v_row."id" is null or new."decided_at" is null or old."status" = new."status" then
    return null;
  end if;
  if new."status" = 'visible' then
    null;
  elsif old."status" not in ('hidden', 'removed') then
    null;
  end if;
  return null;
end;
$$;
revoke execute on function "app_private"."reviews_moderated"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_moderated" on "better_supabase"."moderation_items";
create trigger "bsb_reviews_moderated"
  after update of "status", "decided_at" on "better_supabase"."moderation_items"
  for each row when (new."subject_type" = 'review')
  execute function "app_private"."reviews_moderated"();

-- The moderation item of a review, created when the review predates it.
create or replace function "app_private"."review_moderation_item"(review_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."reviews"%rowtype;
  v_item uuid;
begin
  select * into v_row from "app_private"."reviews" x where x."id" = review_moderation_item.review_id;
  select x."id" into v_item from "better_supabase"."moderation_items" x
  where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'review' and x."subject_id" = v_row."id"::text;
  if v_item is null then
    v_item := "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_row."author_id",
      case when v_row."status" = 'published' then 'visible' else 'pending' end);
  end if;
  return v_item;
end;
$$;
revoke execute on function "app_private"."review_moderation_item"(uuid) from public, anon, authenticated;

-- Publishes a pending or rejected review: approves its moderation item.
create or replace function "app_private"."publish_review"(review_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."reviews"%rowtype;
begin
  select * into v_row from "app_private"."reviews" x where x."id" = publish_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  perform "better_supabase"."moderation_apply"("app_private"."review_moderation_item"(v_row."id"), 'approve', null, false);
  select * into v_row from "app_private"."reviews" x where x."id" = publish_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."publish_review"(uuid) from public, anon;
grant execute on function "app_private"."publish_review"(uuid) to authenticated, service_role;

-- Rejects a review with an optional reason the author sees: hides its
-- moderation item.
create or replace function "app_private"."reject_review"(review_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."reviews"%rowtype;
begin
  select * into v_row from "app_private"."reviews" x where x."id" = reject_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  perform "better_supabase"."moderation_apply"("app_private"."review_moderation_item"(v_row."id"), 'hide', reject_review.reason, false);
  select * into v_row from "app_private"."reviews" x where x."id" = reject_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."reject_review"(uuid, text) from public, anon;
grant execute on function "app_private"."reject_review"(uuid, text) to authenticated, service_role;

-- Sets the organization's public reply to a review; null removes it.
create or replace function "app_private"."reply_to_review"(review_id uuid, reply text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."reviews" x where x."id" = reply_to_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if length(reply_to_review.reply) > 5000 then
    raise exception 'reply must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  update "app_private"."reviews" x
  set "reply" = nullif(trim(reply_to_review.reply), ''),
    "replied_by" = case when nullif(trim(reply_to_review.reply), '') is null then null else auth.uid() end,
    "replied_at" = case when nullif(trim(reply_to_review.reply), '') is null then null else now() end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."reply_to_review"(uuid, text) from public, anon;
grant execute on function "app_private"."reply_to_review"(uuid, text) to authenticated, service_role;

-- A subject's published reviews, newest first, for anyone who can read the
-- subject (anonymous visitors for a public storefront's products). Author
-- ids stay hidden; mine marks the caller's own review.
create or replace function "app_private"."list_reviews"(tenant uuid, subject_type text, subject_id text, page_size integer default 20, before timestamptz default null, rating integer default null, verified boolean default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "app_private"."review_subject_readable"(list_reviews.tenant, list_reviews.subject_type, list_reviews.subject_id)) then
    raise exception 'not allowed to read this record''s reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.published desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."published_at" as published, x."id" as id
    from "app_private"."reviews" x
    where x."tenant_id" = list_reviews.tenant and x."subject_type" = list_reviews.subject_type
      and x."subject_id" = list_reviews.subject_id and x."status" = 'published'
      and (list_reviews.before is null or x."published_at" < list_reviews.before)
      and (list_reviews.rating is null or x."rating" = list_reviews.rating)
      and (list_reviews.verified is null or x."verified" = list_reviews.verified)
    order by x."published_at" desc, x."id" desc
    limit least(greatest(coalesce(list_reviews.page_size, 20), 1), 100)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "app_private"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) from public;
grant execute on function "app_private"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) to anon, authenticated, service_role;

-- The caller's own review of a subject in any status, or null.
create or replace function "app_private"."my_review"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")
  from "app_private"."reviews" x
  where x."tenant_id" = my_review.tenant and x."subject_type" = my_review.subject_type
    and x."subject_id" = my_review.subject_id and x."author_id" = auth.uid()
$$;
revoke execute on function "app_private"."my_review"(uuid, text, text) from public, anon;
grant execute on function "app_private"."my_review"(uuid, text, text) to authenticated, service_role;

-- Reviews for moderators, newest first: pending by default.
create or replace function "app_private"."review_queue"(tenant uuid, status text default 'pending', page_size integer default 50, before timestamptz default null, subject_type text default null, subject_id text default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', review_queue.tenant, 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.created desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created, x."id" as id
    from "app_private"."reviews" x
    where x."tenant_id" = review_queue.tenant
      and (review_queue.status is null or x."status" = review_queue.status)
      and (review_queue.subject_type is null or x."subject_type" = review_queue.subject_type)
      and (review_queue.subject_id is null or x."subject_id" = review_queue.subject_id)
      and (review_queue.before is null or x."created_at" < review_queue.before)
    order by x."created_at" desc, x."id" desc
    limit least(greatest(coalesce(review_queue.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "app_private"."review_queue"(uuid, text, integer, timestamptz, text, text) from public, anon;
grant execute on function "app_private"."review_queue"(uuid, text, integer, timestamptz, text, text) to authenticated, service_role;

-- The rating aggregate of up to 200 subjects of one type, as
-- { subjectId: { count, average, histogram } }, for the subjects the caller
-- can read. Subjects without published reviews are left out.
create or replace function "app_private"."review_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x."subject_id", jsonb_build_object(
    'count', x."review_count",
    'average', case when x."review_count" = 0 then null else round(x."rating_total"::numeric / x."review_count", 2) end,
    'histogram', x."histogram"
  )), '{}'::jsonb)
  from "app_private"."review_stats" x
  where x."tenant_id" = review_summary.tenant and x."subject_type" = review_summary.subject_type
    and x."subject_id" = any (review_summary.subject_ids[1:200]) and x."review_count" > 0
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "app_private"."review_subject_readable"(review_summary.tenant, review_summary.subject_type, x."subject_id"))
$$;
revoke execute on function "app_private"."review_summary"(uuid, text, text[]) from public;
grant execute on function "app_private"."review_summary"(uuid, text, text[]) to anon, authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block-data reviews
-- @bsb-hash sha256:d0de9e6695a3b89f998f6858bd7c9adad38e2e6043374b74a2d3a11c41f643d6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Puts the reviews written before the moderation module under it.
insert into "better_supabase"."moderation_items" ("tenant_id", "subject_type", "subject_id", "author_id", "status", "reason", "decided_by", "decided_at", "created_at", "updated_at")
  select x."tenant_id", 'review', x."id"::text, x."author_id",
    case x."status"::text when 'published' then 'visible' when 'rejected' then 'hidden' else 'pending' end,
    case when x."status" = 'rejected' then x."rejection_reason" end, null, null, x."created_at", x."updated_at"
  from "app_private"."reviews" x
  on conflict ("tenant_id", "subject_type", "subject_id") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reviews', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block reviews@2 managed
-- @bsb-hash sha256:28484c82db9b7863a6956a4bd31a50053f5fcfa64f0f2f7ba9790290982e5783
-- Ratings and reviews of catalog products and other subjects: one per user and subject, verified against paid orders, moderated before or after publishing through the moderation block, with a per-subject aggregate public storefronts can read.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reviews";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."review_stats";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."reviews" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "author_id" uuid references auth.users (id) on delete cascade,
  "author_name" text check ("author_name" is null or length("author_name") <= 100),
  "rating" smallint not null check ("rating" between 1 and 5),
  "title" text check ("title" is null or length("title") <= 200),
  "body" text check ("body" is null or length("body") <= 5000),
  "status" text not null default 'pending' check ("status" in ('pending', 'published', 'rejected')),
  "verified" boolean not null default false,
  "rejection_reason" text check ("rejection_reason" is null or length("rejection_reason") <= 1000),
  "reply" text check ("reply" is null or length("reply") <= 5000),
  "replied_by" uuid,
  "replied_at" timestamptz,
  "published_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "author_id")
);
create index if not exists "reviews_subject_idx" on "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "status", "created_at" desc);
create index if not exists "reviews_queue_idx" on "better_supabase"."reviews" ("tenant_id", "status", "created_at" desc);
create index if not exists "reviews_author_idx" on "better_supabase"."reviews" ("author_id");
alter table "better_supabase"."reviews" enable row level security;
revoke all on "better_supabase"."reviews" from public, anon, authenticated;
grant all on "better_supabase"."reviews" to service_role;

create table if not exists "better_supabase"."review_stats" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "review_count" integer not null default 0,
  "rating_total" bigint not null default 0,
  "histogram" jsonb not null default '{}'::jsonb,
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "subject_type", "subject_id")
);
alter table "better_supabase"."review_stats" enable row level security;
revoke all on "better_supabase"."review_stats" from public, anon, authenticated;
grant all on "better_supabase"."review_stats" to service_role;

-- Whether the caller may read and review a subject: an active product on a
-- published public storefront or in a catalog the caller reads, or a
-- registered subject in an organization the caller belongs to. plpgsql, so
-- a subject table a later module creates (messages) binds late.
create or replace function "better_supabase"."review_subject_readable"(tenant uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return false;
end;
$$;
revoke execute on function "better_supabase"."review_subject_readable"(uuid, text, text) from public, anon, authenticated;

-- Recounts one subject's published reviews into review_stats.
create or replace function "better_supabase"."review_stats_refresh"(tenant uuid, subject_type text, subject_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into "better_supabase"."review_stats" ("tenant_id", "subject_type", "subject_id", "review_count", "rating_total", "histogram", "updated_at")
  select review_stats_refresh.tenant, review_stats_refresh.subject_type, review_stats_refresh.subject_id,
    count(*)::integer, coalesce(sum(x."rating"), 0)::bigint,
    coalesce((select jsonb_object_agg(h.rating::text, h.n) from (
      select y."rating" as rating, count(*) as n from "better_supabase"."reviews" y
      where y."tenant_id" = review_stats_refresh.tenant and y."subject_type" = review_stats_refresh.subject_type
        and y."subject_id" = review_stats_refresh.subject_id and y."status" = 'published'
      group by y."rating"
    ) h), '{}'::jsonb),
    now()
  from "better_supabase"."reviews" x
  where x."tenant_id" = review_stats_refresh.tenant and x."subject_type" = review_stats_refresh.subject_type
    and x."subject_id" = review_stats_refresh.subject_id and x."status" = 'published'
  on conflict ("tenant_id", "subject_type", "subject_id") do update
    set "review_count" = excluded."review_count", "rating_total" = excluded."rating_total",
      "histogram" = excluded."histogram", "updated_at" = excluded."updated_at";
$$;
revoke execute on function "better_supabase"."review_stats_refresh"(uuid, text, text) from public, anon, authenticated;

-- Keeps review_stats in step with every write, including user purges.
create or replace function "better_supabase"."reviews_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform "better_supabase"."review_stats_refresh"(old."tenant_id", old."subject_type", old."subject_id");
  end if;
  if tg_op = 'DELETE' then
    delete from "better_supabase"."moderation_items" x
    where x."tenant_id" = old."tenant_id" and x."subject_type" = 'review' and x."subject_id" = old."id"::text;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform "better_supabase"."review_stats_refresh"(new."tenant_id", new."subject_type", new."subject_id");
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_changed" on "better_supabase"."reviews";
create trigger "bsb_reviews_changed"
  after insert or update of "rating", "status" or delete on "better_supabase"."reviews"
  for each row execute function "better_supabase"."reviews_changed"();

-- Writes the caller's review of a subject, or replaces it: one review per
-- user and subject. Under pre-moderation (options.moderation "pre") it
-- waits for publish_review; under "post" it is published at once. verified
-- is true when the orders module shows a paid order for the product.
drop function if exists "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text, jsonb);
create or replace function "better_supabase"."submit_review"(tenant uuid, subject_type text, subject_id text, rating integer, body text default null, title text default null, author_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_verified boolean;
  v_row "better_supabase"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to write a review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if submit_review.rating is null or submit_review.rating not between 1 and 5 then
    raise exception 'rating must be from 1 to 5' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if length(submit_review.body) > 5000 then
    raise exception 'body must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if not "better_supabase"."review_subject_readable"(submit_review.tenant, submit_review.subject_type, submit_review.subject_id) then
    raise exception 'not allowed to review this record' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  v_verified := false;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_review_submit"(uuid, text, text, integer)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::integer)', v_hook::oid::regproc)
        using submit_review.tenant, submit_review.subject_type, submit_review.subject_id, submit_review.rating;
    end if;
  end;
  insert into "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "author_id", "author_name", "rating", "title", "body", "status", "verified", "published_at")
  values (submit_review.tenant, submit_review.subject_type, submit_review.subject_id, v_me, nullif(trim(submit_review.author_name), ''), submit_review.rating, nullif(trim(submit_review.title), ''), nullif(trim(submit_review.body), ''), 'pending', v_verified, null)
  on conflict ("tenant_id", "subject_type", "subject_id", "author_id") do update
    set "rating" = excluded."rating", "title" = excluded."title", "body" = excluded."body", "author_name" = excluded."author_name", "verified" = excluded."verified", "status" = excluded."status", "published_at" = excluded."published_at", "rejection_reason" = null, "updated_at" = now()
  returning * into v_row;
  perform "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_me, 'pending');
  null;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_review_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) from public, anon;
grant execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) to authenticated, service_role;

-- Deletes a review: its author, or a moderator.
create or replace function "better_supabase"."delete_review"(review_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_mine boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = delete_review.review_id for update;
  if not found then
    return false;
  end if;
  v_mine := v_row."author_id" = auth.uid();
  if not (coalesce(v_mine, false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to delete this review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  delete from "better_supabase"."reviews" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_review"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_review"(uuid) to authenticated, service_role;

-- Projects a review's moderation item onto the review: visible publishes it,
-- hidden and removed reject it with the item's reason. A decision (from
-- publish_review, reject_review or the moderation block) records
-- review.published or review.rejected and tells the author.
create or replace function "better_supabase"."reviews_moderated"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  update "better_supabase"."reviews" x
  set "status" = case new."status" when 'visible' then 'published' when 'pending' then 'pending' else 'rejected' end,
    "published_at" = case when new."status" = 'visible' then coalesce(x."published_at", now()) end,
    "rejection_reason" = case when new."status" in ('hidden', 'removed') then new."reason" end,
    "updated_at" = now()
  where x."id"::text = new."subject_id" and x."tenant_id" = new."tenant_id"
  returning * into v_row;
  if v_row."id" is null or new."decided_at" is null or old."status" = new."status" then
    return null;
  end if;
  if new."status" = 'visible' then
    null;
  elsif old."status" not in ('hidden', 'removed') then
    null;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_moderated"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_moderated" on "better_supabase"."moderation_items";
create trigger "bsb_reviews_moderated"
  after update of "status", "decided_at" on "better_supabase"."moderation_items"
  for each row when (new."subject_type" = 'review')
  execute function "better_supabase"."reviews_moderated"();

-- The moderation item of a review, created when the review predates it.
create or replace function "better_supabase"."review_moderation_item"(review_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_item uuid;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = review_moderation_item.review_id;
  select x."id" into v_item from "better_supabase"."moderation_items" x
  where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'review' and x."subject_id" = v_row."id"::text;
  if v_item is null then
    v_item := "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_row."author_id",
      case when v_row."status" = 'published' then 'visible' else 'pending' end);
  end if;
  return v_item;
end;
$$;
revoke execute on function "better_supabase"."review_moderation_item"(uuid) from public, anon, authenticated;

-- Publishes a pending or rejected review: approves its moderation item.
create or replace function "better_supabase"."publish_review"(review_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'approve', null, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."publish_review"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_review"(uuid) to authenticated, service_role;

-- Rejects a review with an optional reason the author sees: hides its
-- moderation item.
create or replace function "better_supabase"."reject_review"(review_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'hide', reject_review.reason, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reject_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reject_review"(uuid, text) to authenticated, service_role;

-- Sets the organization's public reply to a review; null removes it.
create or replace function "better_supabase"."reply_to_review"(review_id uuid, reply text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = reply_to_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if length(reply_to_review.reply) > 5000 then
    raise exception 'reply must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  update "better_supabase"."reviews" x
  set "reply" = nullif(trim(reply_to_review.reply), ''),
    "replied_by" = case when nullif(trim(reply_to_review.reply), '') is null then null else auth.uid() end,
    "replied_at" = case when nullif(trim(reply_to_review.reply), '') is null then null else now() end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reply_to_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reply_to_review"(uuid, text) to authenticated, service_role;

-- A subject's published reviews, newest first, for anyone who can read the
-- subject (anonymous visitors for a public storefront's products). Author
-- ids stay hidden; mine marks the caller's own review.
create or replace function "better_supabase"."list_reviews"(tenant uuid, subject_type text, subject_id text, page_size integer default 20, before timestamptz default null, rating integer default null, verified boolean default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(list_reviews.tenant, list_reviews.subject_type, list_reviews.subject_id)) then
    raise exception 'not allowed to read this record''s reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.published desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."published_at" as published, x."id" as id
    from "better_supabase"."reviews" x
    where x."tenant_id" = list_reviews.tenant and x."subject_type" = list_reviews.subject_type
      and x."subject_id" = list_reviews.subject_id and x."status" = 'published'
      and (list_reviews.before is null or x."published_at" < list_reviews.before)
      and (list_reviews.rating is null or x."rating" = list_reviews.rating)
      and (list_reviews.verified is null or x."verified" = list_reviews.verified)
    order by x."published_at" desc, x."id" desc
    limit least(greatest(coalesce(list_reviews.page_size, 20), 1), 100)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) from public;
grant execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) to anon, authenticated, service_role;

-- The caller's own review of a subject in any status, or null.
create or replace function "better_supabase"."my_review"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")
  from "better_supabase"."reviews" x
  where x."tenant_id" = my_review.tenant and x."subject_type" = my_review.subject_type
    and x."subject_id" = my_review.subject_id and x."author_id" = auth.uid()
$$;
revoke execute on function "better_supabase"."my_review"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."my_review"(uuid, text, text) to authenticated, service_role;

-- Reviews for moderators, newest first: pending by default.
create or replace function "better_supabase"."review_queue"(tenant uuid, status text default 'pending', page_size integer default 50, before timestamptz default null, subject_type text default null, subject_id text default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', review_queue.tenant, 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.created desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created, x."id" as id
    from "better_supabase"."reviews" x
    where x."tenant_id" = review_queue.tenant
      and (review_queue.status is null or x."status" = review_queue.status)
      and (review_queue.subject_type is null or x."subject_type" = review_queue.subject_type)
      and (review_queue.subject_id is null or x."subject_id" = review_queue.subject_id)
      and (review_queue.before is null or x."created_at" < review_queue.before)
    order by x."created_at" desc, x."id" desc
    limit least(greatest(coalesce(review_queue.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text) from public, anon;
grant execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text) to authenticated, service_role;

-- The rating aggregate of up to 200 subjects of one type, as
-- { subjectId: { count, average, histogram } }, for the subjects the caller
-- can read. Subjects without published reviews are left out.
create or replace function "better_supabase"."review_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x."subject_id", jsonb_build_object(
    'count', x."review_count",
    'average', case when x."review_count" = 0 then null else round(x."rating_total"::numeric / x."review_count", 2) end,
    'histogram', x."histogram"
  )), '{}'::jsonb)
  from "better_supabase"."review_stats" x
  where x."tenant_id" = review_summary.tenant and x."subject_type" = review_summary.subject_type
    and x."subject_id" = any (review_summary.subject_ids[1:200]) and x."review_count" > 0
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(review_summary.tenant, review_summary.subject_type, x."subject_id"))
$$;
revoke execute on function "better_supabase"."review_summary"(uuid, text, text[]) from public;
grant execute on function "better_supabase"."review_summary"(uuid, text, text[]) to anon, authenticated, service_role;

-- blocks.reviews.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."submit_review"(uuid, text, text, integer, text, text, text, jsonb);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."submit_review"(tenant uuid, subject_type text, subject_id text, rating integer, body text default null, title text default null, author_name text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."submit_review"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."submit_review"(uuid, text, text, integer, text, text, text) from public, anon;
grant execute on function "api"."submit_review"(uuid, text, text, integer, text, text, text) to authenticated, service_role;

create or replace function "api"."delete_review"(review_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_review"($1) $$;
revoke execute on function "api"."delete_review"(uuid) from public, anon;
grant execute on function "api"."delete_review"(uuid) to authenticated, service_role;

create or replace function "api"."publish_review"(review_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_review"($1) $$;
revoke execute on function "api"."publish_review"(uuid) from public, anon;
grant execute on function "api"."publish_review"(uuid) to authenticated, service_role;

create or replace function "api"."reject_review"(review_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reject_review"($1, $2) $$;
revoke execute on function "api"."reject_review"(uuid, text) from public, anon;
grant execute on function "api"."reject_review"(uuid, text) to authenticated, service_role;

create or replace function "api"."reply_to_review"(review_id uuid, reply text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reply_to_review"($1, $2) $$;
revoke execute on function "api"."reply_to_review"(uuid, text) from public, anon;
grant execute on function "api"."reply_to_review"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_reviews"(tenant uuid, subject_type text, subject_id text, page_size integer default 20, before timestamptz default null, rating integer default null, verified boolean default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_reviews"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) from public;
grant execute on function "api"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) to anon, authenticated, service_role;

create or replace function "api"."my_review"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."my_review"($1, $2, $3) $$;
revoke execute on function "api"."my_review"(uuid, text, text) from public, anon;
grant execute on function "api"."my_review"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."review_queue"(tenant uuid, status text default 'pending', page_size integer default 50, before timestamptz default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."review_queue"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."review_queue"(uuid, text, integer, timestamptz, text, text) from public, anon;
grant execute on function "api"."review_queue"(uuid, text, integer, timestamptz, text, text) to authenticated, service_role;

create or replace function "api"."review_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."review_summary"($1, $2, $3) $$;
revoke execute on function "api"."review_summary"(uuid, text, text[]) from public;
grant execute on function "api"."review_summary"(uuid, text, text[]) to anon, authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block-data reviews
-- @bsb-hash sha256:eca482e72d47f7bec9778aee91022da731eeb8923934dd7c289ea657debbff27
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Puts the reviews written before the moderation module under it.
insert into "better_supabase"."moderation_items" ("tenant_id", "subject_type", "subject_id", "author_id", "status", "reason", "decided_by", "decided_at", "created_at", "updated_at")
  select x."tenant_id", 'review', x."id"::text, x."author_id",
    case x."status"::text when 'published' then 'visible' when 'rejected' then 'hidden' else 'pending' end,
    case when x."status" = 'rejected' then x."rejection_reason" end, null, null, x."created_at", x."updated_at"
  from "better_supabase"."reviews" x
  on conflict ("tenant_id", "subject_type", "subject_id") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reviews', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block reviews@2 managed
-- @bsb-hash sha256:d6646104175c769c7bb96f8e921d72fca9d789535ac9179fd90f5c485199a618
-- Ratings and reviews of catalog products and other subjects: one per user and subject, verified against paid orders, moderated before or after publishing through the moderation block, with a per-subject aggregate public storefronts can read.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.try_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  result alias for $0;
begin
  result := value;
  return result;
exception when data_exception or check_violation then
  return null;
end;
$$;
revoke execute on function better_supabase.try_column_type(text, anyelement) from public;
grant execute on function better_supabase.try_column_type(text, anyelement) to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reviews";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."review_stats";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- better_supabase.reviews is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."reviews" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."reviews" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."reviews" add column if not exists "subject_type" text check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."reviews" add column if not exists "subject_id" text check (length("subject_id") between 1 and 200);
alter table "better_supabase"."reviews" add column if not exists "author_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."reviews" add column if not exists "author_name" text check ("author_name" is null or length("author_name") <= 100);
alter table "better_supabase"."reviews" add column if not exists "rating" smallint check ("rating" between 1 and 5);
alter table "better_supabase"."reviews" add column if not exists "title" text check ("title" is null or length("title") <= 200);
alter table "better_supabase"."reviews" add column if not exists "body" text check ("body" is null or length("body") <= 5000);
alter table "better_supabase"."reviews" add column if not exists "status" text not null default 'pending' check ("status" in ('pending', 'published', 'rejected'));
alter table "better_supabase"."reviews" add column if not exists "verified" boolean not null default false;
alter table "better_supabase"."reviews" add column if not exists "rejection_reason" text check ("rejection_reason" is null or length("rejection_reason") <= 1000);
alter table "better_supabase"."reviews" add column if not exists "reply" text check ("reply" is null or length("reply") <= 5000);
alter table "better_supabase"."reviews" add column if not exists "replied_by" uuid;
alter table "better_supabase"."reviews" add column if not exists "replied_at" timestamptz;
alter table "better_supabase"."reviews" add column if not exists "published_at" timestamptz;
alter table "better_supabase"."reviews" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."reviews" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "reviews_subject_idx" on "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "status", "created_at" desc);
create index if not exists "reviews_queue_idx" on "better_supabase"."reviews" ("tenant_id", "status", "created_at" desc);
create index if not exists "reviews_author_idx" on "better_supabase"."reviews" ("author_id");
create unique index if not exists "bsb_reviews_author_key" on "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "author_id");
alter table "better_supabase"."reviews" enable row level security;
grant all on "better_supabase"."reviews" to service_role;

-- better_supabase.review_stats is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."review_stats" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."review_stats" add column if not exists "subject_type" text;
alter table "better_supabase"."review_stats" add column if not exists "subject_id" text;
alter table "better_supabase"."review_stats" add column if not exists "review_count" integer not null default 0;
alter table "better_supabase"."review_stats" add column if not exists "rating_total" bigint not null default 0;
alter table "better_supabase"."review_stats" add column if not exists "histogram" jsonb not null default '{}'::jsonb;
alter table "better_supabase"."review_stats" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_review_stats_subject_key" on "better_supabase"."review_stats" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."review_stats" enable row level security;
grant all on "better_supabase"."review_stats" to service_role;

-- Whether the caller may read and review a subject: an active product on a
-- published public storefront or in a catalog the caller reads, or a
-- registered subject in an organization the caller belongs to. plpgsql, so
-- a subject table a later module creates (messages) binds late.
create or replace function "better_supabase"."review_subject_readable"(tenant uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return false;
end;
$$;
revoke execute on function "better_supabase"."review_subject_readable"(uuid, text, text) from public, anon, authenticated;

-- Recounts one subject's published reviews into review_stats.
create or replace function "better_supabase"."review_stats_refresh"(tenant uuid, subject_type text, subject_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into "better_supabase"."review_stats" ("tenant_id", "subject_type", "subject_id", "review_count", "rating_total", "histogram", "updated_at")
  select review_stats_refresh.tenant, review_stats_refresh.subject_type, review_stats_refresh.subject_id,
    count(*)::integer, coalesce(sum(x."rating"), 0)::bigint,
    coalesce((select jsonb_object_agg(h.rating::text, h.n) from (
      select y."rating" as rating, count(*) as n from "better_supabase"."reviews" y
      where y."tenant_id" = review_stats_refresh.tenant and y."subject_type" = review_stats_refresh.subject_type
        and y."subject_id" = review_stats_refresh.subject_id and y."status" = 'published'
      group by y."rating"
    ) h), '{}'::jsonb),
    now()
  from "better_supabase"."reviews" x
  where x."tenant_id" = review_stats_refresh.tenant and x."subject_type" = review_stats_refresh.subject_type
    and x."subject_id" = review_stats_refresh.subject_id and x."status" = 'published'
  on conflict ("tenant_id", "subject_type", "subject_id") do update
    set "review_count" = excluded."review_count", "rating_total" = excluded."rating_total",
      "histogram" = excluded."histogram", "updated_at" = excluded."updated_at";
$$;
revoke execute on function "better_supabase"."review_stats_refresh"(uuid, text, text) from public, anon, authenticated;

-- Keeps review_stats in step with every write, including user purges.
create or replace function "better_supabase"."reviews_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform "better_supabase"."review_stats_refresh"(old."tenant_id", old."subject_type", old."subject_id");
  end if;
  if tg_op = 'DELETE' then
    delete from "better_supabase"."moderation_items" x
    where x."tenant_id" = old."tenant_id" and x."subject_type" = 'review' and x."subject_id" = old."id"::text;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform "better_supabase"."review_stats_refresh"(new."tenant_id", new."subject_type", new."subject_id");
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_changed" on "better_supabase"."reviews";
create trigger "bsb_reviews_changed"
  after insert or update of "rating", "status" or delete on "better_supabase"."reviews"
  for each row execute function "better_supabase"."reviews_changed"();

-- Writes the caller's review of a subject, or replaces it: one review per
-- user and subject. Under pre-moderation (options.moderation "pre") it
-- waits for publish_review; under "post" it is published at once. verified
-- is true when the orders module shows a paid order for the product.
drop function if exists "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text, jsonb);
create or replace function "better_supabase"."submit_review"(tenant uuid, subject_type text, subject_id text, rating integer, body text default null, title text default null, author_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_verified boolean;
  v_row "better_supabase"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to write a review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if submit_review.rating is null or submit_review.rating not between 1 and 5 then
    raise exception 'rating must be from 1 to 5' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if length(submit_review.body) > 5000 then
    raise exception 'body must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if not "better_supabase"."review_subject_readable"(submit_review.tenant, submit_review.subject_type, submit_review.subject_id) then
    raise exception 'not allowed to review this record' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  v_verified := false;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_review_submit"(uuid, text, text, integer)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::integer)', v_hook::oid::regproc)
        using submit_review.tenant, submit_review.subject_type, submit_review.subject_id, submit_review.rating;
    end if;
  end;
  insert into "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "author_id", "author_name", "rating", "title", "body", "status", "verified", "published_at")
  values (submit_review.tenant, submit_review.subject_type, submit_review.subject_id, v_me, nullif(trim(submit_review.author_name), ''), submit_review.rating, nullif(trim(submit_review.title), ''), nullif(trim(submit_review.body), ''), better_supabase.as_column_type('pending', (null::"better_supabase"."reviews")."status"), v_verified, null)
  on conflict ("tenant_id", "subject_type", "subject_id", "author_id") do update
    set "rating" = excluded."rating", "title" = excluded."title", "body" = excluded."body", "author_name" = excluded."author_name", "verified" = excluded."verified", "status" = excluded."status", "published_at" = excluded."published_at", "rejection_reason" = null, "updated_at" = now()
  returning * into v_row;
  perform "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_me, 'pending');
  null;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_review_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) from public, anon;
grant execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) to authenticated, service_role;

-- Deletes a review: its author, or a moderator.
create or replace function "better_supabase"."delete_review"(review_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_mine boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = delete_review.review_id for update;
  if not found then
    return false;
  end if;
  v_mine := v_row."author_id" = auth.uid();
  if not (coalesce(v_mine, false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to delete this review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  delete from "better_supabase"."reviews" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_review"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_review"(uuid) to authenticated, service_role;

-- Projects a review's moderation item onto the review: visible publishes it,
-- hidden and removed reject it with the item's reason. A decision (from
-- publish_review, reject_review or the moderation block) records
-- review.published or review.rejected and tells the author.
create or replace function "better_supabase"."reviews_moderated"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  update "better_supabase"."reviews" x
  set "status" = better_supabase.as_column_type(case new."status" when 'visible' then 'published' when 'pending' then 'pending' else 'rejected' end, (null::"better_supabase"."reviews")."status"),
    "published_at" = case when new."status" = 'visible' then coalesce(x."published_at", now()) end,
    "rejection_reason" = case when new."status" in ('hidden', 'removed') then new."reason" end,
    "updated_at" = now()
  where x."id"::text = new."subject_id" and x."tenant_id" = new."tenant_id"
  returning * into v_row;
  if v_row."id" is null or new."decided_at" is null or old."status" = new."status" then
    return null;
  end if;
  if new."status" = 'visible' then
    null;
  elsif old."status" not in ('hidden', 'removed') then
    null;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_moderated"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_moderated" on "better_supabase"."moderation_items";
create trigger "bsb_reviews_moderated"
  after update of "status", "decided_at" on "better_supabase"."moderation_items"
  for each row when (new."subject_type" = 'review')
  execute function "better_supabase"."reviews_moderated"();

-- The moderation item of a review, created when the review predates it.
create or replace function "better_supabase"."review_moderation_item"(review_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_item uuid;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = review_moderation_item.review_id;
  select x."id" into v_item from "better_supabase"."moderation_items" x
  where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'review' and x."subject_id" = v_row."id"::text;
  if v_item is null then
    v_item := "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_row."author_id",
      case when v_row."status" = 'published' then 'visible' else 'pending' end);
  end if;
  return v_item;
end;
$$;
revoke execute on function "better_supabase"."review_moderation_item"(uuid) from public, anon, authenticated;

-- Publishes a pending or rejected review: approves its moderation item.
create or replace function "better_supabase"."publish_review"(review_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'approve', null, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."publish_review"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_review"(uuid) to authenticated, service_role;

-- Rejects a review with an optional reason the author sees: hides its
-- moderation item.
create or replace function "better_supabase"."reject_review"(review_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'hide', reject_review.reason, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reject_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reject_review"(uuid, text) to authenticated, service_role;

-- Sets the organization's public reply to a review; null removes it.
create or replace function "better_supabase"."reply_to_review"(review_id uuid, reply text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = reply_to_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if length(reply_to_review.reply) > 5000 then
    raise exception 'reply must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  update "better_supabase"."reviews" x
  set "reply" = nullif(trim(reply_to_review.reply), ''),
    "replied_by" = case when nullif(trim(reply_to_review.reply), '') is null then null else auth.uid() end,
    "replied_at" = case when nullif(trim(reply_to_review.reply), '') is null then null else now() end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reply_to_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reply_to_review"(uuid, text) to authenticated, service_role;

-- A subject's published reviews, newest first, for anyone who can read the
-- subject (anonymous visitors for a public storefront's products). Author
-- ids stay hidden; mine marks the caller's own review.
create or replace function "better_supabase"."list_reviews"(tenant uuid, subject_type text, subject_id text, page_size integer default 20, before timestamptz default null, rating integer default null, verified boolean default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(list_reviews.tenant, list_reviews.subject_type, list_reviews.subject_id)) then
    raise exception 'not allowed to read this record''s reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.published desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."published_at" as published, x."id" as id
    from "better_supabase"."reviews" x
    where x."tenant_id" = list_reviews.tenant and x."subject_type" = list_reviews.subject_type
      and x."subject_id" = list_reviews.subject_id and x."status" = 'published'
      and (list_reviews.before is null or x."published_at" < list_reviews.before)
      and (list_reviews.rating is null or x."rating" = list_reviews.rating)
      and (list_reviews.verified is null or x."verified" = list_reviews.verified)
    order by x."published_at" desc, x."id" desc
    limit least(greatest(coalesce(list_reviews.page_size, 20), 1), 100)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) from public;
grant execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) to anon, authenticated, service_role;

-- The caller's own review of a subject in any status, or null.
create or replace function "better_supabase"."my_review"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")
  from "better_supabase"."reviews" x
  where x."tenant_id" = my_review.tenant and x."subject_type" = my_review.subject_type
    and x."subject_id" = my_review.subject_id and x."author_id" = auth.uid()
$$;
revoke execute on function "better_supabase"."my_review"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."my_review"(uuid, text, text) to authenticated, service_role;

-- Reviews for moderators, newest first: pending by default.
create or replace function "better_supabase"."review_queue"(tenant uuid, status text default 'pending', page_size integer default 50, before timestamptz default null, subject_type text default null, subject_id text default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', review_queue.tenant, 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.created desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created, x."id" as id
    from "better_supabase"."reviews" x
    where x."tenant_id" = review_queue.tenant
      and (review_queue.status is null or x."status" = better_supabase.try_column_type(review_queue.status, (null::"better_supabase"."reviews")."status"))
      and (review_queue.subject_type is null or x."subject_type" = review_queue.subject_type)
      and (review_queue.subject_id is null or x."subject_id" = review_queue.subject_id)
      and (review_queue.before is null or x."created_at" < review_queue.before)
    order by x."created_at" desc, x."id" desc
    limit least(greatest(coalesce(review_queue.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text) from public, anon;
grant execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text) to authenticated, service_role;

-- The rating aggregate of up to 200 subjects of one type, as
-- { subjectId: { count, average, histogram } }, for the subjects the caller
-- can read. Subjects without published reviews are left out.
create or replace function "better_supabase"."review_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x."subject_id", jsonb_build_object(
    'count', x."review_count",
    'average', case when x."review_count" = 0 then null else round(x."rating_total"::numeric / x."review_count", 2) end,
    'histogram', x."histogram"
  )), '{}'::jsonb)
  from "better_supabase"."review_stats" x
  where x."tenant_id" = review_summary.tenant and x."subject_type" = review_summary.subject_type
    and x."subject_id" = any (review_summary.subject_ids[1:200]) and x."review_count" > 0
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(review_summary.tenant, review_summary.subject_type, x."subject_id"))
$$;
revoke execute on function "better_supabase"."review_summary"(uuid, text, text[]) from public;
grant execute on function "better_supabase"."review_summary"(uuid, text, text[]) to anon, authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block-data reviews
-- @bsb-hash sha256:eca482e72d47f7bec9778aee91022da731eeb8923934dd7c289ea657debbff27
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Puts the reviews written before the moderation module under it.
insert into "better_supabase"."moderation_items" ("tenant_id", "subject_type", "subject_id", "author_id", "status", "reason", "decided_by", "decided_at", "created_at", "updated_at")
  select x."tenant_id", 'review', x."id"::text, x."author_id",
    case x."status"::text when 'published' then 'visible' when 'rejected' then 'hidden' else 'pending' end,
    case when x."status" = 'rejected' then x."rejection_reason" end, null, null, x."created_at", x."updated_at"
  from "better_supabase"."reviews" x
  on conflict ("tenant_id", "subject_type", "subject_id") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reviews', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block reviews@2 managed
-- @bsb-hash sha256:e738beab9d0da78ae8e36effc60ecace0a85ffd785ca091be509f399820fab39
-- Ratings and reviews of catalog products and other subjects: one per user and subject, verified against paid orders, moderated before or after publishing through the moderation block, with a per-subject aggregate public storefronts can read.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reviews";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reviews";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."review_stats";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."review_stats";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."reviews" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "author_id" uuid references auth.users (id) on delete cascade,
  "author_name" text check ("author_name" is null or length("author_name") <= 100),
  "rating" smallint not null check ("rating" between 1 and 5),
  "title" text check ("title" is null or length("title") <= 200),
  "body" text check ("body" is null or length("body") <= 5000),
  "status" text not null default 'pending' check ("status" in ('pending', 'published', 'rejected')),
  "verified" boolean not null default false,
  "rejection_reason" text check ("rejection_reason" is null or length("rejection_reason") <= 1000),
  "reply" text check ("reply" is null or length("reply") <= 5000),
  "replied_by" uuid,
  "replied_at" timestamptz,
  "published_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "subject_type", "subject_id", "author_id")
);
create index if not exists "reviews_subject_idx" on "better_supabase"."reviews" ("org_id", "subject_type", "subject_id", "status", "created_at" desc);
create index if not exists "reviews_queue_idx" on "better_supabase"."reviews" ("org_id", "status", "created_at" desc);
create index if not exists "reviews_author_idx" on "better_supabase"."reviews" ("author_id");
alter table "better_supabase"."reviews" enable row level security;
revoke all on "better_supabase"."reviews" from public, anon, authenticated;
grant all on "better_supabase"."reviews" to service_role;

create table if not exists "better_supabase"."review_stats" (
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "review_count" integer not null default 0,
  "rating_total" bigint not null default 0,
  "histogram" jsonb not null default '{}'::jsonb,
  "updated_at" timestamptz not null default now(),
  primary key ("org_id", "subject_type", "subject_id")
);
alter table "better_supabase"."review_stats" enable row level security;
revoke all on "better_supabase"."review_stats" from public, anon, authenticated;
grant all on "better_supabase"."review_stats" to service_role;

-- Whether the caller may read and review a subject: an active product on a
-- published public storefront or in a catalog the caller reads, or a
-- registered subject in an organization the caller belongs to. plpgsql, so
-- a subject table a later module creates (messages) binds late.
create or replace function "better_supabase"."review_subject_readable"(tenant uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return false;
end;
$$;
revoke execute on function "better_supabase"."review_subject_readable"(uuid, text, text) from public, anon, authenticated;

-- Recounts one subject's published reviews into review_stats.
create or replace function "better_supabase"."review_stats_refresh"(tenant uuid, subject_type text, subject_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into "better_supabase"."review_stats" ("org_id", "subject_type", "subject_id", "review_count", "rating_total", "histogram", "updated_at")
  select review_stats_refresh.tenant, review_stats_refresh.subject_type, review_stats_refresh.subject_id,
    count(*)::integer, coalesce(sum(x."rating"), 0)::bigint,
    coalesce((select jsonb_object_agg(h.rating::text, h.n) from (
      select y."rating" as rating, count(*) as n from "better_supabase"."reviews" y
      where y."org_id" = review_stats_refresh.tenant and y."subject_type" = review_stats_refresh.subject_type
        and y."subject_id" = review_stats_refresh.subject_id and y."status" = 'published'
      group by y."rating"
    ) h), '{}'::jsonb),
    now()
  from "better_supabase"."reviews" x
  where x."org_id" = review_stats_refresh.tenant and x."subject_type" = review_stats_refresh.subject_type
    and x."subject_id" = review_stats_refresh.subject_id and x."status" = 'published'
  on conflict ("org_id", "subject_type", "subject_id") do update
    set "review_count" = excluded."review_count", "rating_total" = excluded."rating_total",
      "histogram" = excluded."histogram", "updated_at" = excluded."updated_at";
$$;
revoke execute on function "better_supabase"."review_stats_refresh"(uuid, text, text) from public, anon, authenticated;

-- Keeps review_stats in step with every write, including user purges.
create or replace function "better_supabase"."reviews_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform "better_supabase"."review_stats_refresh"(old."org_id", old."subject_type", old."subject_id");
  end if;
  if tg_op = 'DELETE' then
    delete from "better_supabase"."moderation_items" x
    where x."org_id" = old."org_id" and x."subject_type" = 'review' and x."subject_id" = old."id"::text;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform "better_supabase"."review_stats_refresh"(new."org_id", new."subject_type", new."subject_id");
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_changed" on "better_supabase"."reviews";
create trigger "bsb_reviews_changed"
  after insert or update of "rating", "status" or delete on "better_supabase"."reviews"
  for each row execute function "better_supabase"."reviews_changed"();

-- Writes the caller's review of a subject, or replaces it: one review per
-- user and subject. Under pre-moderation (options.moderation "pre") it
-- waits for publish_review; under "post" it is published at once. verified
-- is true when the orders module shows a paid order for the product.
drop function if exists "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text, jsonb);
create or replace function "better_supabase"."submit_review"(tenant uuid, subject_type text, subject_id text, rating integer, body text default null, title text default null, author_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_verified boolean;
  v_row "better_supabase"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to write a review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if submit_review.rating is null or submit_review.rating not between 1 and 5 then
    raise exception 'rating must be from 1 to 5' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if length(submit_review.body) > 5000 then
    raise exception 'body must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if not "better_supabase"."review_subject_readable"(submit_review.tenant, submit_review.subject_type, submit_review.subject_id) then
    raise exception 'not allowed to review this record' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  v_verified := false;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_review_submit"(uuid, text, text, integer)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::integer)', v_hook::oid::regproc)
        using submit_review.tenant, submit_review.subject_type, submit_review.subject_id, submit_review.rating;
    end if;
  end;
  insert into "better_supabase"."reviews" ("org_id", "subject_type", "subject_id", "author_id", "author_name", "rating", "title", "body", "status", "verified", "published_at")
  values (submit_review.tenant, submit_review.subject_type, submit_review.subject_id, v_me, nullif(trim(submit_review.author_name), ''), submit_review.rating, nullif(trim(submit_review.title), ''), nullif(trim(submit_review.body), ''), 'pending', v_verified, null)
  on conflict ("org_id", "subject_type", "subject_id", "author_id") do update
    set "rating" = excluded."rating", "title" = excluded."title", "body" = excluded."body", "author_name" = excluded."author_name", "verified" = excluded."verified", "status" = excluded."status", "published_at" = excluded."published_at", "rejection_reason" = null, "updated_at" = now()
  returning * into v_row;
  perform "better_supabase"."moderation_track"(v_row."org_id", 'review', v_row."id"::text, v_me, 'pending');
  null;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_review_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) from public, anon;
grant execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) to authenticated, service_role;

-- Deletes a review: its author, or a moderator.
create or replace function "better_supabase"."delete_review"(review_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_mine boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = delete_review.review_id for update;
  if not found then
    return false;
  end if;
  v_mine := v_row."author_id" = auth.uid();
  if not (coalesce(v_mine, false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to delete this review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  delete from "better_supabase"."reviews" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_review"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_review"(uuid) to authenticated, service_role;

-- Projects a review's moderation item onto the review: visible publishes it,
-- hidden and removed reject it with the item's reason. A decision (from
-- publish_review, reject_review or the moderation block) records
-- review.published or review.rejected and tells the author.
create or replace function "better_supabase"."reviews_moderated"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  update "better_supabase"."reviews" x
  set "status" = case new."status" when 'visible' then 'published' when 'pending' then 'pending' else 'rejected' end,
    "published_at" = case when new."status" = 'visible' then coalesce(x."published_at", now()) end,
    "rejection_reason" = case when new."status" in ('hidden', 'removed') then new."reason" end,
    "updated_at" = now()
  where x."id"::text = new."subject_id" and x."org_id" = new."org_id"
  returning * into v_row;
  if v_row."id" is null or new."decided_at" is null or old."status" = new."status" then
    return null;
  end if;
  if new."status" = 'visible' then
    null;
  elsif old."status" not in ('hidden', 'removed') then
    null;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_moderated"() from public, anon, authenticated;
drop trigger if exists "bsb_reviews_moderated" on "better_supabase"."moderation_items";
create trigger "bsb_reviews_moderated"
  after update of "status", "decided_at" on "better_supabase"."moderation_items"
  for each row when (new."subject_type" = 'review')
  execute function "better_supabase"."reviews_moderated"();

-- The moderation item of a review, created when the review predates it.
create or replace function "better_supabase"."review_moderation_item"(review_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_item uuid;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = review_moderation_item.review_id;
  select x."id" into v_item from "better_supabase"."moderation_items" x
  where x."org_id" = v_row."org_id" and x."subject_type" = 'review' and x."subject_id" = v_row."id"::text;
  if v_item is null then
    v_item := "better_supabase"."moderation_track"(v_row."org_id", 'review', v_row."id"::text, v_row."author_id",
      case when v_row."status" = 'published' then 'visible' else 'pending' end);
  end if;
  return v_item;
end;
$$;
revoke execute on function "better_supabase"."review_moderation_item"(uuid) from public, anon, authenticated;

-- Publishes a pending or rejected review: approves its moderation item.
create or replace function "better_supabase"."publish_review"(review_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'approve', null, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."publish_review"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_review"(uuid) to authenticated, service_role;

-- Rejects a review with an optional reason the author sees: hides its
-- moderation item.
create or replace function "better_supabase"."reject_review"(review_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'hide', reject_review.reason, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reject_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reject_review"(uuid, text) to authenticated, service_role;

-- Sets the organization's public reply to a review; null removes it.
create or replace function "better_supabase"."reply_to_review"(review_id uuid, reply text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = reply_to_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if length(reply_to_review.reply) > 5000 then
    raise exception 'reply must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  update "better_supabase"."reviews" x
  set "reply" = nullif(trim(reply_to_review.reply), ''),
    "replied_by" = case when nullif(trim(reply_to_review.reply), '') is null then null else auth.uid() end,
    "replied_at" = case when nullif(trim(reply_to_review.reply), '') is null then null else now() end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reply_to_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reply_to_review"(uuid, text) to authenticated, service_role;

-- A subject's published reviews, newest first, for anyone who can read the
-- subject (anonymous visitors for a public storefront's products). Author
-- ids stay hidden; mine marks the caller's own review.
create or replace function "better_supabase"."list_reviews"(tenant uuid, subject_type text, subject_id text, page_size integer default 20, before timestamptz default null, rating integer default null, verified boolean default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(list_reviews.tenant, list_reviews.subject_type, list_reviews.subject_id)) then
    raise exception 'not allowed to read this record''s reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.published desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."published_at" as published, x."id" as id
    from "better_supabase"."reviews" x
    where x."org_id" = list_reviews.tenant and x."subject_type" = list_reviews.subject_type
      and x."subject_id" = list_reviews.subject_id and x."status" = 'published'
      and (list_reviews.before is null or x."published_at" < list_reviews.before)
      and (list_reviews.rating is null or x."rating" = list_reviews.rating)
      and (list_reviews.verified is null or x."verified" = list_reviews.verified)
    order by x."published_at" desc, x."id" desc
    limit least(greatest(coalesce(list_reviews.page_size, 20), 1), 100)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) from public;
grant execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) to anon, authenticated, service_role;

-- The caller's own review of a subject in any status, or null.
create or replace function "better_supabase"."my_review"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")
  from "better_supabase"."reviews" x
  where x."org_id" = my_review.tenant and x."subject_type" = my_review.subject_type
    and x."subject_id" = my_review.subject_id and x."author_id" = auth.uid()
$$;
revoke execute on function "better_supabase"."my_review"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."my_review"(uuid, text, text) to authenticated, service_role;

-- Reviews for moderators, newest first: pending by default.
create or replace function "better_supabase"."review_queue"(tenant uuid, status text default 'pending', page_size integer default 50, before timestamptz default null, subject_type text default null, subject_id text default null)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', review_queue.tenant, 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.created desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created, x."id" as id
    from "better_supabase"."reviews" x
    where x."org_id" = review_queue.tenant
      and (review_queue.status is null or x."status" = review_queue.status)
      and (review_queue.subject_type is null or x."subject_type" = review_queue.subject_type)
      and (review_queue.subject_id is null or x."subject_id" = review_queue.subject_id)
      and (review_queue.before is null or x."created_at" < review_queue.before)
    order by x."created_at" desc, x."id" desc
    limit least(greatest(coalesce(review_queue.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text) from public, anon;
grant execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text) to authenticated, service_role;

-- The rating aggregate of up to 200 subjects of one type, as
-- { subjectId: { count, average, histogram } }, for the subjects the caller
-- can read. Subjects without published reviews are left out.
create or replace function "better_supabase"."review_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x."subject_id", jsonb_build_object(
    'count', x."review_count",
    'average', case when x."review_count" = 0 then null else round(x."rating_total"::numeric / x."review_count", 2) end,
    'histogram', x."histogram"
  )), '{}'::jsonb)
  from "better_supabase"."review_stats" x
  where x."org_id" = review_summary.tenant and x."subject_type" = review_summary.subject_type
    and x."subject_id" = any (review_summary.subject_ids[1:200]) and x."review_count" > 0
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(review_summary.tenant, review_summary.subject_type, x."subject_id"))
$$;
revoke execute on function "better_supabase"."review_summary"(uuid, text, text[]) from public;
grant execute on function "better_supabase"."review_summary"(uuid, text, text[]) to anon, authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_109_reviews.sql
-- better-supabase module: reviews
-- @bsb-block-data reviews
-- @bsb-hash sha256:ff6e2b5ce12102af9246a3230c49ad16f06490fb089475d95614aa11df3ee486
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Puts the reviews written before the moderation module under it.
insert into "better_supabase"."moderation_items" ("org_id", "subject_type", "subject_id", "author_id", "status", "reason", "decided_by", "decided_at", "created_at", "updated_at")
  select x."org_id", 'review', x."id"::text, x."author_id",
    case x."status"::text when 'published' then 'visible' when 'rejected' then 'hidden' else 'pending' end,
    case when x."status" = 'rejected' then x."rejection_reason" end, null, null, x."created_at", x."updated_at"
  from "better_supabase"."reviews" x
  on conflict ("org_id", "subject_type", "subject_id") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reviews', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
