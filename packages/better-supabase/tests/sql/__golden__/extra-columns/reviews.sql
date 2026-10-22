-- ==== schema supabase/schemas/900_better_supabase_108_reviews.sql
-- better-supabase module: reviews
-- @bs-module reviews@1 managed
-- Ratings and reviews of catalog products and other subjects: one per user and subject, verified against paid orders, moderated before or after publishing, with a per-subject aggregate public storefronts can read.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
  "moderated_by" uuid,
  "moderated_at" timestamptz,
  "published_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "author_id")
);
alter table "better_supabase"."reviews" add column if not exists "app_note" text;
create index if not exists "reviews_subject_idx" on "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "status", "created_at" desc);
create index if not exists "reviews_queue_idx" on "better_supabase"."reviews" ("tenant_id", "status", "created_at" desc);
create index if not exists "reviews_author_idx" on "better_supabase"."reviews" ("author_id");
alter table "better_supabase"."reviews" enable row level security;
revoke all on "better_supabase"."reviews" from anon, authenticated;
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
revoke all on "better_supabase"."review_stats" from anon, authenticated;
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
  if tg_op in ('INSERT', 'UPDATE') then
    perform "better_supabase"."review_stats_refresh"(new."tenant_id", new."subject_type", new."subject_id");
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_changed"() from public, anon, authenticated;
drop trigger if exists "bs_reviews_changed" on "better_supabase"."reviews";
create trigger "bs_reviews_changed"
  after insert or update of "rating", "status" or delete on "better_supabase"."reviews"
  for each row execute function "better_supabase"."reviews_changed"();

-- Writes the caller's review of a subject, or replaces it: one review per
-- user and subject. Under pre-moderation (options.moderation "pre") it
-- waits for publish_review; under "post" it is published at once. verified
-- is true when the orders module shows a paid order for the product.
drop function if exists "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text);
create or replace function "better_supabase"."submit_review"(tenant uuid, subject_type text, subject_id text, rating integer, body text default null, title text default null, author_name text default null, fields jsonb default null)
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
  values (submit_review.tenant, submit_review.subject_type, submit_review.subject_id, v_me, nullif(trim(submit_review.author_name), ''),
    submit_review.rating, nullif(trim(submit_review.title), ''), nullif(trim(submit_review.body), ''),
    'pending', v_verified, null)
  on conflict ("tenant_id", "subject_type", "subject_id", "author_id") do update
    set "rating" = excluded."rating", "title" = excluded."title", "body" = excluded."body",
      "author_name" = excluded."author_name", "verified" = excluded."verified",
      "status" = excluded."status", "published_at" = excluded."published_at",
      "rejection_reason" = null, "moderated_by" = null, "moderated_at" = null, "updated_at" = now()
  returning * into v_row;
  update "better_supabase"."reviews" x set "app_note" = case when submit_review.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."reviews", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(submit_review.fields) e where e.key in ('app_note'))) r
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_review_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text, jsonb) to authenticated, service_role;

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

-- Publishes a pending or rejected review.
create or replace function "better_supabase"."publish_review"(review_id uuid)
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
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
  end if;
  update "better_supabase"."reviews" x
  set "status" = 'published', "published_at" = now(), "rejection_reason" = null,
    "moderated_by" = auth.uid(), "moderated_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."publish_review"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_review"(uuid) to authenticated, service_role;

-- Rejects a review with an optional reason the author sees.
create or replace function "better_supabase"."reject_review"(review_id uuid, reason text default null)
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
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  update "better_supabase"."reviews" x
  set "status" = 'rejected', "published_at" = null, "rejection_reason" = nullif(trim(reject_review.reason), ''),
    "moderated_by" = auth.uid(), "moderated_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
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
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'fields', jsonb_build_object('app_note', x."app_note")) as item, x."published_at" as published, x."id" as id
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
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'fields', jsonb_build_object('app_note', x."app_note"))
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
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'fields', jsonb_build_object('app_note', x."app_note")) as item, x."created_at" as created, x."id" as id
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
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_108_reviews.sql
-- better-supabase module: reviews
-- @bs-module-data reviews
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('reviews', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
