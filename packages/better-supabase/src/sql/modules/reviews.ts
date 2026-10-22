import type { ReviewsEvents } from "../../blocks/reviews/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  triggerGrant,
  writeExtraColumns,
} from "../shared.ts";
import {
  subjectCascades,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { storefrontOption } from "./catalog-functions.ts";
import { moderationTables } from "./moderation.ts";
import { OPERATIONS } from "./permissions-model.ts";

const WHERE = "blocks.reviews.options";

const PAYLOAD = [
  "organizationId",
  "id",
  "subjectType",
  "subjectId",
  "authorId",
  "rating",
  "status",
  "verified",
] as const;

const EVENTS: BlockSqlEvents<ReviewsEvents> = {
  "review.submitted": { subject: "reviews", payload: PAYLOAD },
  "review.published": { subject: "reviews", payload: PAYLOAD },
  "review.rejected": { subject: "reviews", payload: PAYLOAD },
  "review.replied": { subject: "reviews", payload: PAYLOAD },
  "review.deleted": { subject: "reviews", payload: PAYLOAD },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  hooks: ["before_review_submit", "after_review_submit"],
  options: [
    "subjects",
    "scale",
    "maxBodyLength",
    "moderation",
    "requirePurchase",
    "extraColumns",
  ],
  tables: {
    reviews: {
      name: "reviews",
      lifecycle: { tenant: "tenant", user: "author", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        author: "author_id",
        authorName: "author_name",
        rating: "rating",
        title: "title",
        body: "body",
        status: "status",
        verified: "verified",
        rejectionReason: "rejection_reason",
        reply: "reply",
        repliedBy: "replied_by",
        repliedAt: "replied_at",
        publishedAt: "published_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    stats: {
      name: "review_stats",
      lifecycle: { tenant: "tenant" },
      columns: {
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        count: "review_count",
        total: "rating_total",
        histogram: "histogram",
        updatedAt: "updated_at",
      },
    },
  },
};

/** The subject type of a catalog product. */
const PRODUCT_SUBJECT = "product";

/** The subject type of a review's moderation item. */
const REVIEW_SUBJECT = "review";

/** The keys the review reads return next to the extra columns. */
const RESERVED = ["fields"] as const;

function scaleOf(ctx: BlockSqlContext): number {
  const scale = ctx.number("scale", 5);

  if (!Number.isInteger(scale) || scale < 2 || scale > 10) {
    throw new TypeError(`${WHERE}.scale must be an integer from 2 to 10`);
  }

  return scale;
}

function maxBodyOf(ctx: BlockSqlContext): number {
  const max = ctx.number("maxBodyLength", 5000);

  if (!Number.isInteger(max) || max < 1 || max > 100_000) {
    throw new TypeError(
      `${WHERE}.maxBodyLength must be an integer from 1 to 100000`,
    );
  }

  return max;
}

function moderationOf(ctx: BlockSqlContext): "pre" | "post" {
  const moderation = ctx.text("moderation", "pre");

  if (moderation !== "pre" && moderation !== "post") {
    throw new TypeError(`${WHERE}.moderation must be "pre" or "post"`);
  }

  return moderation;
}

/** Whether product reviews are on: the catalog is installed with its tables. */
const productsOn = (ctx: BlockSqlContext): boolean =>
  ctx.installed("catalog") && ctx.of("catalog").mode !== "custom";

/** Whether purchases can be checked: the orders tables are there. */
const ordersOn = (ctx: BlockSqlContext): boolean =>
  productsOn(ctx) &&
  ctx.installed("orders") &&
  ctx.of("orders").mode !== "custom";

function requirePurchaseOf(ctx: BlockSqlContext): boolean {
  const required = ctx.flag("requirePurchase", false);

  if (required && !ordersOn(ctx)) {
    throw new TypeError(
      `${WHERE}.requirePurchase needs the orders block, with its tables`,
    );
  }

  return required;
}

/**
 * Whether the caller may read and review the subject, as SQL for a `security
 * definer` function. A product is readable when it is active and either on a
 * published public storefront or the caller reads the catalog. Any other
 * subject type must be registered (`options.subjects` or the subjects
 * registry), and the caller must be a member of its organization.
 */
function readableCase(
  ctx: BlockSqlContext,
  args: { readonly type: string; readonly id: string; readonly tenant: string },
): string {
  const whens: string[] = [];

  if (productsOn(ctx)) {
    const catalog = ctx.of("catalog");
    const pc = (column: string): string => catalog.col("products", column);
    const read = catalog.permission("read", OPERATIONS["catalog.read"]);

    const storefront =
      catalog.hasTable("storefronts") && storefrontOption(catalog)
        ? `p.${pc("id")} in (select ${catalog.fn("storefront_products")}()) or `
        : "";

    whens.push(
      `    when ${sqlString(PRODUCT_SUBJECT)} then exists (select 1 from ${catalog.table("products")} p where p.${pc("id")}::text = ${args.id} and p.${pc("tenant")} = ${args.tenant} and p.${pc("status")} = 'active' and (${storefront}${ctx.can("tenant", args.tenant, read)}))`,
    );
  }

  const subjects = subjectsOption(ctx).filter(
    ([type]) => !(productsOn(ctx) && type === PRODUCT_SUBJECT),
  );

  const members = ctx.of("memberships");

  const rest =
    subjects.length === 0
      ? "false"
      : `(auth.uid() is not null and exists (select 1 from ${members.table("memberships")} m where m.${members.col("memberships", "tenant")} = ${args.tenant} and m.${members.col("memberships", "user")} = auth.uid()) and ${subjectReadable(ctx, subjects, args)})`;

  if (whens.length === 0) {
    return rest;
  }

  return `case ${args.type}
${whens.join("\n")}
    else ${rest}
  end`;
}

/** Whether `user` bought the product in a paid, uncancelled order. */
function purchasedSql(
  ctx: BlockSqlContext,
  args: {
    readonly tenant: string;
    readonly product: string;
    readonly user: string;
  },
): string {
  const orders = ctx.of("orders");
  const o = (column: string): string => orders.col("orders", column);
  const l = (column: string): string => orders.col("orderLines", column);

  return `${args.product} ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and exists (
    select 1 from ${orders.table("orders")} o
    join ${orders.table("orderLines")} l on l.${l("order")} = o.${o("id")}
    where o.${o("tenant")} = ${args.tenant} and o.${o("customer")} = ${args.user}
      and o.${o("paidAt")} is not null and o.${o("cancelledAt")} is null
      and l.${l("product")} = ${args.product}::uuid
  )`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const reviews = ctx.table("reviews");
  const stats = ctx.table("stats");
  const r = (column: string): string => ctx.col("reviews", column);
  const s = (column: string): string => ctx.col("stats", column);
  const fn = (name: string): string => ctx.fn(name);
  const manage = ctx.permission("manage", OPERATIONS["reviews.manage"]);
  const scale = scaleOf(ctx);
  const maxBody = maxBodyOf(ctx);
  const moderation = moderationOf(ctx);
  const requirePurchase = requirePurchaseOf(ctx);
  const subjects = subjectsOption(ctx);
  const name = ctx.tableName("reviews").name;
  const extras = ctx.extraColumns("reviews", RESERVED);
  const extra = extraFieldsArg(extras);
  const idType = ctx.idType;

  const readable = fn("review_subject_readable");
  const moderated = ctx.of("moderation");
  const mi = (column: string): string => moderated.col("items", column);
  const items = moderated.table("items");

  const readableCheck = readableCase(ctx, {
    type: "review_subject_readable.subject_type",
    id: "review_subject_readable.subject_id",
    tenant: "review_subject_readable.tenant",
  });

  const readableSql =
    readableCheck === "false" ? "false" : `coalesce(${readableCheck}, false)`;

  const refresh = fn("review_stats_refresh");

  const forbidden = (message: string): string =>
    fail("REVIEW_FORBIDDEN", message);

  const notFound = fail("REVIEW_NOT_FOUND", "review not found", "P0002");

  const json = (row: string, author: string): string =>
    `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'subjectType', ${row}.${r("subjectType")}, 'subjectId', ${row}.${r("subjectId")}, 'authorId', ${author}, 'authorName', ${row}.${r("authorName")}, 'mine', coalesce(${row}.${r("author")} = auth.uid(), false), 'rating', ${row}.${r("rating")}, 'title', ${row}.${r("title")}, 'body', ${row}.${r("body")}, 'status', ${row}.${r("status")}, 'verified', ${row}.${r("verified")}, 'rejectionReason', ${row}.${r("rejectionReason")}, 'reply', ${row}.${r("reply")}, 'repliedAt', ${row}.${r("repliedAt")}, 'publishedAt', ${row}.${r("publishedAt")}, 'createdAt', ${row}.${r("createdAt")}, 'updatedAt', ${row}.${r("updatedAt")}${extraFieldsJson(row, extras)})`;

  const full = (row: string): string => json(row, `${row}.${r("author")}`);

  const record = (type: string, row: string, audit?: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${r("tenant")}, 'id', ${row}.${r("id")}, 'subjectType', ${row}.${r("subjectType")}, 'subjectId', ${row}.${r("subjectId")}, 'authorId', ${row}.${r("author")}, 'rating', ${row}.${r("rating")}, 'status', ${row}.${r("status")}, 'verified', ${row}.${r("verified")})`,
      subject: `'reviews/' || ${row}.${r("id")}::text`,
      tenant: `${row}.${r("tenant")}`,
      audit:
        audit === undefined
          ? false
          : {
              category: "data",
              targetType: "review",
              recordId: `${row}.${r("id")}::text`,
              summary: sqlString(audit),
            },
    });

  const notifyAuthor = (event: string, summary: string): string =>
    ctx.installed("notifications")
      ? `
  if v_row.${r("author")} is not null then
    ${ctx.notify(
      `jsonb_build_object(
      'type', ${sqlString(event)},
      'tenant', v_row.${r("tenant")},
      'subject_type', v_row.${r("subjectType")},
      'subject_id', v_row.${r("subjectId")},
      'summary', ${sqlString(summary)},
      'recipients', jsonb_build_array(v_row.${r("author")}),
      'key', ${sqlString(`${event}:`)} || v_row.${r("id")}::text || ':' || extract(epoch from now())::text,
      'data', jsonb_build_object('reviewId', v_row.${r("id")}, 'status', v_row.${r("status")})
    )`,
      { indent: "    " },
    )}
  end if;`
      : "";

  const claims = ctx.installed("notifications") ? "\n  v_claims text;" : "";

  const loadForManage = (
    fnName: string,
  ): string => `select * into v_row from ${reviews} x where x.${r("id")} = ${fnName}.review_id for update;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${r("tenant")}`, manage)}) then
    ${forbidden("not allowed to moderate reviews")}
  end if;`;

  const purchased = ordersOn(ctx)
    ? `coalesce(submit_review.subject_type = ${sqlString(PRODUCT_SUBJECT)} and ${purchasedSql(ctx, { tenant: "submit_review.tenant", product: "submit_review.subject_id", user: "v_me" })}, false)`
    : "false";

  const purchaseCheck = requirePurchase
    ? `
  if submit_review.subject_type = ${sqlString(PRODUCT_SUBJECT)} and not v_verified then
    ${fail("REVIEW_PURCHASE_REQUIRED", "only customers who bought this product can review it", "42501")}
  end if;`
    : "";

  const tables = ctx.manages
    ? `create table if not exists ${reviews} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${idType} not null,
  ${r("subjectType")} text not null check (${r("subjectType")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${r("subjectId")} text not null check (length(${r("subjectId")}) between 1 and 200),
  ${r("author")} uuid references auth.users (id) on delete cascade,
  ${r("authorName")} text check (${r("authorName")} is null or length(${r("authorName")}) <= 100),
  ${r("rating")} smallint not null check (${r("rating")} between 1 and ${String(scale)}),
  ${r("title")} text check (${r("title")} is null or length(${r("title")}) <= 200),
  ${r("body")} text check (${r("body")} is null or length(${r("body")}) <= ${String(maxBody)}),
  ${r("status")} text not null default 'pending' check (${r("status")} in ('pending', 'published', 'rejected')),
  ${r("verified")} boolean not null default false,
  ${r("rejectionReason")} text check (${r("rejectionReason")} is null or length(${r("rejectionReason")}) <= 1000),
  ${r("reply")} text check (${r("reply")} is null or length(${r("reply")}) <= ${String(maxBody)}),
  ${r("repliedBy")} uuid,
  ${r("repliedAt")} timestamptz,
  ${r("publishedAt")} timestamptz,
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now(),
  unique (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")}, ${r("author")})
);${addExtraColumns(reviews, extras)}
create index if not exists ${sqlIdent(`${name}_subject_idx`)} on ${reviews} (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")}, ${r("status")}, ${r("createdAt")} desc);
create index if not exists ${sqlIdent(`${name}_queue_idx`)} on ${reviews} (${r("tenant")}, ${r("status")}, ${r("createdAt")} desc);
create index if not exists ${sqlIdent(`${name}_author_idx`)} on ${reviews} (${r("author")});
${lockTable(reviews)}

create table if not exists ${stats} (
  ${s("tenant")} ${idType} not null,
  ${s("subjectType")} text not null,
  ${s("subjectId")} text not null,
  ${s("count")} integer not null default 0,
  ${s("total")} bigint not null default 0,
  ${s("histogram")} jsonb not null default '{}'::jsonb,
  ${s("updatedAt")} timestamptz not null default now(),
  primary key (${s("tenant")}, ${s("subjectType")}, ${s("subjectId")})
);
${lockTable(stats)}
`
    : "";

  return `${schemaPreamble(ctx)}
${tables}
-- Whether the caller may read and review a subject: an active product on a
-- published public storefront or in a catalog the caller reads, or a
-- registered subject in an organization the caller belongs to. plpgsql, so
-- a subject table a later module creates (messages) binds late.
create or replace function ${readable}(tenant ${idType}, subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return ${readableSql};
end;
$$;
revoke execute on function ${readable}(${idType}, text, text) from public, anon, authenticated;

-- Recounts one subject's published reviews into review_stats.
create or replace function ${refresh}(tenant ${idType}, subject_type text, subject_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into ${stats} (${s("tenant")}, ${s("subjectType")}, ${s("subjectId")}, ${s("count")}, ${s("total")}, ${s("histogram")}, ${s("updatedAt")})
  select review_stats_refresh.tenant, review_stats_refresh.subject_type, review_stats_refresh.subject_id,
    count(*)::integer, coalesce(sum(x.${r("rating")}), 0)::bigint,
    coalesce((select jsonb_object_agg(h.rating::text, h.n) from (
      select y.${r("rating")} as rating, count(*) as n from ${reviews} y
      where y.${r("tenant")} = review_stats_refresh.tenant and y.${r("subjectType")} = review_stats_refresh.subject_type
        and y.${r("subjectId")} = review_stats_refresh.subject_id and y.${r("status")} = 'published'
      group by y.${r("rating")}
    ) h), '{}'::jsonb),
    now()
  from ${reviews} x
  where x.${r("tenant")} = review_stats_refresh.tenant and x.${r("subjectType")} = review_stats_refresh.subject_type
    and x.${r("subjectId")} = review_stats_refresh.subject_id and x.${r("status")} = 'published'
  on conflict (${s("tenant")}, ${s("subjectType")}, ${s("subjectId")}) do update
    set ${s("count")} = excluded.${s("count")}, ${s("total")} = excluded.${s("total")},
      ${s("histogram")} = excluded.${s("histogram")}, ${s("updatedAt")} = excluded.${s("updatedAt")};
$$;
revoke execute on function ${refresh}(${idType}, text, text) from public, anon, authenticated;

-- Keeps review_stats in step with every write, including user purges.
create or replace function ${fn("reviews_changed")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform ${refresh}(old.${r("tenant")}, old.${r("subjectType")}, old.${r("subjectId")});
  end if;
  if tg_op = 'DELETE' then
    delete from ${items} x
    where x.${mi("tenant")} = old.${r("tenant")} and x.${mi("subjectType")} = ${sqlString(REVIEW_SUBJECT)} and x.${mi("subjectId")} = old.${r("id")}::text;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform ${refresh}(new.${r("tenant")}, new.${r("subjectType")}, new.${r("subjectId")});
  end if;
  return null;
end;
$$;
${triggerGrant(`${fn("reviews_changed")}()`)}
drop trigger if exists ${ctx.trigger("reviews_changed")} on ${reviews};
create trigger ${ctx.trigger("reviews_changed")}
  after insert or update of ${r("rating")}, ${r("status")} or delete on ${reviews}
  for each row execute function ${fn("reviews_changed")}();

-- Writes the caller's review of a subject, or replaces it: one review per
-- user and subject. Under pre-moderation (options.moderation "pre") it
-- waits for publish_review; under "post" it is published at once. verified
-- is true when the orders module shows a paid order for the product.
${extra.drop(fn("submit_review"), `${idType}, text, text, integer, text, text, text`)}
create or replace function ${fn("submit_review")}(tenant ${idType}, subject_type text, subject_id text, rating integer, body text default null, title text default null, author_name text default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_verified boolean;
  v_row ${reviews}%rowtype;
begin
  if v_me is null then
    ${forbidden("sign in to write a review")}
  end if;
  if submit_review.rating is null or submit_review.rating not between 1 and ${String(scale)} then
    ${fail("REVIEW_INVALID", `rating must be from 1 to ${String(scale)}`, "22023")}
  end if;
  if length(submit_review.body) > ${String(maxBody)} then
    ${fail("REVIEW_INVALID", `body must be at most ${String(maxBody)} characters`, "22023")}
  end if;
  if not ${readable}(submit_review.tenant, submit_review.subject_type, submit_review.subject_id) then
    ${forbidden("not allowed to review this record")}
  end if;
  v_verified := ${purchased};${purchaseCheck}
  ${ctx.hook("before_review_submit", [
    [idType, "submit_review.tenant"],
    ["text", "submit_review.subject_type"],
    ["text", "submit_review.subject_id"],
    ["integer", "submit_review.rating"],
  ])}
  insert into ${reviews} (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")}, ${r("author")}, ${r("authorName")}, ${r("rating")}, ${r("title")}, ${r("body")}, ${r("status")}, ${r("verified")}, ${r("publishedAt")})
  values (submit_review.tenant, submit_review.subject_type, submit_review.subject_id, v_me, nullif(trim(submit_review.author_name), ''),
    submit_review.rating, nullif(trim(submit_review.title), ''), nullif(trim(submit_review.body), ''),
    ${moderation === "post" ? "'published'" : "'pending'"}, v_verified, ${moderation === "post" ? "now()" : "null"})
  on conflict (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")}, ${r("author")}) do update
    set ${r("rating")} = excluded.${r("rating")}, ${r("title")} = excluded.${r("title")}, ${r("body")} = excluded.${r("body")},
      ${r("authorName")} = excluded.${r("authorName")}, ${r("verified")} = excluded.${r("verified")},
      ${r("status")} = excluded.${r("status")}, ${r("publishedAt")} = excluded.${r("publishedAt")},
      ${r("rejectionReason")} = null, ${r("updatedAt")} = now()
  returning * into v_row;${writeExtraColumns(reviews, extras, "submit_review.fields", `x.${r("id")} = v_row.${r("id")}`, "v_row")}
  perform ${moderated.fn("moderation_track")}(v_row.${r("tenant")}, ${sqlString(REVIEW_SUBJECT)}, v_row.${r("id")}::text, v_me, ${moderation === "post" ? "'visible'" : "'pending'"});
  ${record("review.submitted", "v_row")}
  ${moderation === "post" ? record("review.published", "v_row") : ""}
  ${ctx.hook("after_review_submit", [["uuid", `v_row.${r("id")}`]])}
  return ${full("v_row")};
end;
$$;
revoke execute on function ${fn("submit_review")}(${idType}, text, text, integer, text, text, text${extra.type}) from public, anon;
grant execute on function ${fn("submit_review")}(${idType}, text, text, integer, text, text, text${extra.type}) to authenticated, service_role;

-- Deletes a review: its author, or a moderator.
create or replace function ${fn("delete_review")}(review_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reviews}%rowtype;
  v_mine boolean;
begin
  select * into v_row from ${reviews} x where x.${r("id")} = delete_review.review_id for update;
  if not found then
    return false;
  end if;
  v_mine := v_row.${r("author")} = auth.uid();
  if not (coalesce(v_mine, false) or ${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${r("tenant")}`, manage)}) then
    ${forbidden("not allowed to delete this review")}
  end if;
  delete from ${reviews} x where x.${r("id")} = v_row.${r("id")};
  ${record("review.deleted", "v_row", "deleted a review")}
  return true;
end;
$$;
revoke execute on function ${fn("delete_review")}(uuid) from public, anon;
grant execute on function ${fn("delete_review")}(uuid) to authenticated, service_role;

-- Projects a review's moderation item onto the review: visible publishes it,
-- hidden and removed reject it with the item's reason. A decision (from
-- publish_review, reject_review or the moderation block) records
-- review.published or review.rejected and tells the author.
create or replace function ${fn("reviews_moderated")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reviews}%rowtype;${claims}
begin
  update ${reviews} x
  set ${r("status")} = case new.${mi("status")} when 'visible' then 'published' when 'pending' then 'pending' else 'rejected' end,
    ${r("publishedAt")} = case when new.${mi("status")} = 'visible' then coalesce(x.${r("publishedAt")}, now()) end,
    ${r("rejectionReason")} = case when new.${mi("status")} in ('hidden', 'removed') then new.${mi("reason")} end,
    ${r("updatedAt")} = now()
  where x.${r("id")}::text = new.${mi("subjectId")} and x.${r("tenant")} = new.${mi("tenant")}
  returning * into v_row;
  if v_row.${r("id")} is null or new.${mi("decidedAt")} is null or old.${mi("status")} = new.${mi("status")} then
    return null;
  end if;
  if new.${mi("status")} = 'visible' then
    ${record("review.published", "v_row", "published a review")}${notifyAuthor("review.published", "Your review was published")}
  elsif old.${mi("status")} not in ('hidden', 'removed') then
    ${record("review.rejected", "v_row", "rejected a review")}${notifyAuthor("review.rejected", "Your review was not published")}
  end if;
  return null;
end;
$$;
${triggerGrant(`${fn("reviews_moderated")}()`)}
drop trigger if exists ${ctx.trigger("reviews_moderated")} on ${items};
create trigger ${ctx.trigger("reviews_moderated")}
  after update of ${mi("status")}, ${mi("decidedAt")} on ${items}
  for each row when (new.${mi("subjectType")} = ${sqlString(REVIEW_SUBJECT)})
  execute function ${fn("reviews_moderated")}();

-- The moderation item of a review, created when the review predates it.
create or replace function ${fn("review_moderation_item")}(review_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reviews}%rowtype;
  v_item uuid;
begin
  select * into v_row from ${reviews} x where x.${r("id")} = review_moderation_item.review_id;
  select x.${mi("id")} into v_item from ${items} x
  where x.${mi("tenant")} = v_row.${r("tenant")} and x.${mi("subjectType")} = ${sqlString(REVIEW_SUBJECT)} and x.${mi("subjectId")} = v_row.${r("id")}::text;
  if v_item is null then
    v_item := ${moderated.fn("moderation_track")}(v_row.${r("tenant")}, ${sqlString(REVIEW_SUBJECT)}, v_row.${r("id")}::text, v_row.${r("author")},
      case when v_row.${r("status")} = 'published' then 'visible' else 'pending' end);
  end if;
  return v_item;
end;
$$;
revoke execute on function ${fn("review_moderation_item")}(uuid) from public, anon, authenticated;

-- Publishes a pending or rejected review: approves its moderation item.
create or replace function ${fn("publish_review")}(review_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reviews}%rowtype;
begin
  ${loadForManage("publish_review")}
  if v_row.${r("status")} = 'published' then
    return ${full("v_row")};
  end if;
  perform ${moderated.fn("moderation_apply")}(${fn("review_moderation_item")}(v_row.${r("id")}), 'approve', null, false);
  select * into v_row from ${reviews} x where x.${r("id")} = publish_review.review_id;
  return ${full("v_row")};
end;
$$;
revoke execute on function ${fn("publish_review")}(uuid) from public, anon;
grant execute on function ${fn("publish_review")}(uuid) to authenticated, service_role;

-- Rejects a review with an optional reason the author sees: hides its
-- moderation item.
create or replace function ${fn("reject_review")}(review_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reviews}%rowtype;
begin
  ${loadForManage("reject_review")}
  perform ${moderated.fn("moderation_apply")}(${fn("review_moderation_item")}(v_row.${r("id")}), 'hide', reject_review.reason, false);
  select * into v_row from ${reviews} x where x.${r("id")} = reject_review.review_id;
  return ${full("v_row")};
end;
$$;
revoke execute on function ${fn("reject_review")}(uuid, text) from public, anon;
grant execute on function ${fn("reject_review")}(uuid, text) to authenticated, service_role;

-- Sets the organization's public reply to a review; null removes it.
create or replace function ${fn("reply_to_review")}(review_id uuid, reply text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reviews}%rowtype;${claims}
begin
  ${loadForManage("reply_to_review")}
  if length(reply_to_review.reply) > ${String(maxBody)} then
    ${fail("REVIEW_INVALID", `reply must be at most ${String(maxBody)} characters`, "22023")}
  end if;
  update ${reviews} x
  set ${r("reply")} = nullif(trim(reply_to_review.reply), ''),
    ${r("repliedBy")} = case when nullif(trim(reply_to_review.reply), '') is null then null else auth.uid() end,
    ${r("repliedAt")} = case when nullif(trim(reply_to_review.reply), '') is null then null else now() end,
    ${r("updatedAt")} = now()
  where x.${r("id")} = v_row.${r("id")}
  returning * into v_row;
  ${record("review.replied", "v_row", "replied to a review")}${notifyAuthor("review.replied", "Your review has a reply")}
  return ${full("v_row")};
end;
$$;
revoke execute on function ${fn("reply_to_review")}(uuid, text) from public, anon;
grant execute on function ${fn("reply_to_review")}(uuid, text) to authenticated, service_role;

-- A subject's published reviews, newest first, for anyone who can read the
-- subject (anonymous visitors for a public storefront's products). Author
-- ids stay hidden; mine marks the caller's own review.
create or replace function ${fn("list_reviews")}(tenant ${idType}, subject_type text, subject_id text, page_size integer default 20, before timestamptz default null, rating integer default null, verified boolean default null)
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
  if not (${SERVICE_CALLER} or ${readable}(list_reviews.tenant, list_reviews.subject_type, list_reviews.subject_id)) then
    ${forbidden("not allowed to read this record's reviews")}
  end if;
  select coalesce(jsonb_agg(q.item order by q.published desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select ${json("x", "null::uuid")} as item, x.${r("publishedAt")} as published, x.${r("id")} as id
    from ${reviews} x
    where x.${r("tenant")} = list_reviews.tenant and x.${r("subjectType")} = list_reviews.subject_type
      and x.${r("subjectId")} = list_reviews.subject_id and x.${r("status")} = 'published'
      and (list_reviews.before is null or x.${r("publishedAt")} < list_reviews.before)
      and (list_reviews.rating is null or x.${r("rating")} = list_reviews.rating)
      and (list_reviews.verified is null or x.${r("verified")} = list_reviews.verified)
    order by x.${r("publishedAt")} desc, x.${r("id")} desc
    limit ${pageSize("list_reviews.page_size", 20, 100)}
  ) q;
  return v_rows;
end;
$$;
revoke execute on function ${fn("list_reviews")}(${idType}, text, text, integer, timestamptz, integer, boolean) from public;
grant execute on function ${fn("list_reviews")}(${idType}, text, text, integer, timestamptz, integer, boolean) to anon, authenticated, service_role;

-- The caller's own review of a subject in any status, or null.
create or replace function ${fn("my_review")}(tenant ${idType}, subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${full("x")}
  from ${reviews} x
  where x.${r("tenant")} = my_review.tenant and x.${r("subjectType")} = my_review.subject_type
    and x.${r("subjectId")} = my_review.subject_id and x.${r("author")} = auth.uid()
$$;
revoke execute on function ${fn("my_review")}(${idType}, text, text) from public, anon;
grant execute on function ${fn("my_review")}(${idType}, text, text) to authenticated, service_role;

-- Reviews for moderators, newest first: pending by default.
create or replace function ${fn("review_queue")}(tenant ${idType}, status text default 'pending', page_size integer default 50, before timestamptz default null, subject_type text default null, subject_id text default null)
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
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "review_queue.tenant", manage)}) then
    ${forbidden("not allowed to moderate reviews")}
  end if;
  select coalesce(jsonb_agg(q.item order by q.created desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select ${full("x")} as item, x.${r("createdAt")} as created, x.${r("id")} as id
    from ${reviews} x
    where x.${r("tenant")} = review_queue.tenant
      and (review_queue.status is null or x.${r("status")} = review_queue.status)
      and (review_queue.subject_type is null or x.${r("subjectType")} = review_queue.subject_type)
      and (review_queue.subject_id is null or x.${r("subjectId")} = review_queue.subject_id)
      and (review_queue.before is null or x.${r("createdAt")} < review_queue.before)
    order by x.${r("createdAt")} desc, x.${r("id")} desc
    limit ${pageSize("review_queue.page_size", 50, 200)}
  ) q;
  return v_rows;
end;
$$;
revoke execute on function ${fn("review_queue")}(${idType}, text, integer, timestamptz, text, text) from public, anon;
grant execute on function ${fn("review_queue")}(${idType}, text, integer, timestamptz, text, text) to authenticated, service_role;

-- The rating aggregate of up to 200 subjects of one type, as
-- { subjectId: { count, average, histogram } }, for the subjects the caller
-- can read. Subjects without published reviews are left out.
create or replace function ${fn("review_summary")}(tenant ${idType}, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x.${s("subjectId")}, jsonb_build_object(
    'count', x.${s("count")},
    'average', case when x.${s("count")} = 0 then null else round(x.${s("total")}::numeric / x.${s("count")}, 2) end,
    'histogram', x.${s("histogram")}
  )), '{}'::jsonb)
  from ${stats} x
  where x.${s("tenant")} = review_summary.tenant and x.${s("subjectType")} = review_summary.subject_type
    and x.${s("subjectId")} = any (review_summary.subject_ids[1:200]) and x.${s("count")} > 0
    and (${SERVICE_CALLER} or ${readable}(review_summary.tenant, review_summary.subject_type, x.${s("subjectId")}))
$$;
revoke execute on function ${fn("review_summary")}(${idType}, text, text[]) from public;
grant execute on function ${fn("review_summary")}(${idType}, text, text[]) to anon, authenticated, service_role;
${subjectCascades(ctx, subjects, `delete from ${reviews} x where x.${r("subjectType")} = v_type and x.${r("subjectId")} = v_id;\n  delete from ${stats} x where x.${s("subjectType")} = v_type and x.${s("subjectId")} = v_id;`)}
`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(ctx.extraColumns("reviews", RESERVED)).contract;

  return [
    {
      name: "submit_review",
      args: [
        "{id}",
        "text",
        "text",
        "integer",
        "text",
        "text",
        "text",
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "list_reviews",
      args: [
        "{id}",
        "text",
        "text",
        "integer",
        "timestamptz",
        "integer",
        "boolean",
      ],
      returns: "jsonb",
    },
    {
      name: "review_summary",
      args: ["{id}", "text", "text[]"],
      returns: "jsonb",
    },
    { name: "publish_review", args: ["uuid"], returns: "jsonb" },
    { name: "reject_review", args: ["uuid", "text"], returns: "jsonb" },
  ];
}

/** The items, as rows the moderation module would have written. */
function itemRows(ctx: BlockSqlContext, decided: boolean): string {
  const moderated = ctx.of("moderation");
  const mi = (column: string): string => moderated.col("items", column);
  const r = (column: string): string => ctx.col("reviews", column);
  const decision = decided ? "x.moderated_by, x.moderated_at" : "null, null";

  return `insert into ${moderated.table("items")} (${mi("tenant")}, ${mi("subjectType")}, ${mi("subjectId")}, ${mi("author")}, ${mi("status")}, ${mi("reason")}, ${mi("decidedBy")}, ${mi("decidedAt")}, ${mi("createdAt")}, ${mi("updatedAt")})
  select x.${r("tenant")}, ${sqlString(REVIEW_SUBJECT)}, x.${r("id")}::text, x.${r("author")},
    case x.${r("status")} when 'published' then 'visible' when 'rejected' then 'hidden' else 'pending' end,
    case when x.${r("status")} = 'rejected' then x.${r("rejectionReason")} end, ${decision}, x.${r("createdAt")}, x.${r("updatedAt")}
  from ${ctx.table("reviews")} x
  on conflict (${mi("tenant")}, ${mi("subjectType")}, ${mi("subjectId")}) do nothing;`;
}

/** Moves the moderation columns of version 1 onto moderation items. */
function moderationUpgrade(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  const moderated = ctx.of("moderation");
  const mi = (column: string): string => moderated.col("items", column);
  const ma = (column: string): string => moderated.col("actions", column);
  const { schema, name } = ctx.tableName("reviews");

  return `${moderationTables(moderated)}
do $upgrade$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = ${sqlString(schema)} and table_name = ${sqlString(name)} and column_name = 'moderated_by'
  ) then
    return;
  end if;
  ${itemRows(ctx, true)}
  insert into ${moderated.table("actions")} (${ma("tenant")}, ${ma("item")}, ${ma("action")}, ${ma("fromStatus")}, ${ma("toStatus")}, ${ma("reason")}, ${ma("actor")}, ${ma("createdAt")})
  select x.${mi("tenant")}, x.${mi("id")}, case x.${mi("status")} when 'visible' then 'approve' else 'hide' end, 'pending', x.${mi("status")}, x.${mi("reason")}, x.${mi("decidedBy")}, x.${mi("decidedAt")}
  from ${moderated.table("items")} x
  where x.${mi("subjectType")} = ${sqlString(REVIEW_SUBJECT)} and x.${mi("decidedAt")} is not null;
  alter table ${ctx.table("reviews")} drop column moderated_by, drop column moderated_at;
end;
$upgrade$;`;
}

/** Moderation items for the reviews written before moderation tracked them. */
function moderationBackfill(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  return `-- Puts the reviews written before the moderation module under it.
${itemRows(ctx, false)}`;
}

export const REVIEWS: BlockSqlDefinition = {
  internal: [
    "review_subject_readable",
    "review_stats_refresh",
    "review_moderation_item",
  ],
  name: "reviews",
  scopes: ["tenant"],
  title: "Reviews",
  description:
    "Ratings and reviews of catalog products and other subjects: one per user and subject, verified against paid orders, moderated before or after publishing through the moderation block, with a per-subject aggregate public storefronts can read.",
  requires: ["memberships", "permissions", "moderation"],
  integrates: [
    "catalog",
    "orders",
    "subjects",
    "notifications",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Review moderation moves onto the moderation block: each review gets a moderation item with its status, reason and last decision, and moderated_by and moderated_at are dropped.",
      sql: moderationUpgrade,
    },
  ],
  names: NAMES,
  contract,
  build,
  data: moderationBackfill,
};
