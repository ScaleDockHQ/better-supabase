import type { BlockSqlContext } from "../context.ts";

import {
  filterAny,
  filterFirst,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";

/** What the review page and get functions read from the reviews module. */
export interface ReviewPageParts {
  readonly ctx: BlockSqlContext;
  readonly reviews: string;
  readonly r: (column: string) => string;
  readonly has: (column: string) => boolean;
  readonly json: (row: string, author: string) => string;
  readonly full: (row: string) => string;
  readonly notFound: string;
  readonly forbidden: (message: string) => string;
  readonly readable: string;
}

/** The keyset page and the get of reviews (ADR 1077). */
export function reviewPageFunctions(parts: ReviewPageParts): string {
  const { ctx, reviews, r, has, json, full, notFound, forbidden, readable } =
    parts;

  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;

  const reviewKeys = (
    first: "publishedAt" | "rating",
  ): readonly {
    readonly expr: string;
    readonly dir: "asc" | "desc";
    readonly type: string;
  }[] => [
    first === "rating"
      ? { expr: `x.${r("rating")}`, dir: "desc", type: "integer" }
      : {
          expr: `coalesce(x.${r("publishedAt")}, x.${r("createdAt")})`,
          dir: "desc",
          type: "timestamptz",
        },
    { expr: `x.${r("id")}`, dir: "desc", type: "uuid" },
  ];

  const reviewPage = {
    name: "page_reviews",
    from: reviews,
    alias: "x",
    where: [
      `x.${r("tenant")} = page_reviews.tenant`,
      `x.${r("subjectType")} = v_subject_type`,
      `x.${r("subjectId")} = v_subject_id`,
      `x.${r("status")} = 'published'`,
      filterAny("rating", `x.${r("rating")}::text`),
      filterAny("verified", `x.${r("verified")}::text`),
      `(v_search is null or ${has("title") ? `coalesce(x.${r("title")}, '') ilike v_search or ` : ""}coalesce(x.${r("body")}, '') ilike v_search)`,
    ],
    keys: reviewKeys("publishedAt"),
    sorts: {
      publishedAt: reviewKeys("publishedAt"),
      rating: reviewKeys("rating"),
    },
    facets: {
      rating: `x.${r("rating")}::text`,
      verified: `x.${r("verified")}::text`,
    },
    rowJson: json("x", "null::uuid"),
    defaultLimit: 20,
    maxLimit: 100,
    invalid: (message: string): string =>
      fail("REVIEW_INVALID", message, "22023"),
  } as const;

  return `-- A subject's published reviews as a keyset page, newest first (ADR 1077), for
-- anyone who can read the subject. filters must hold subjectType and
-- subjectId, and may hold rating and verified (each a value or a list),
-- search, sort (publishedAt, rating), direction, facet, count, limit, after,
-- offset, paged, total, totalCap. Author ids stay hidden.
create or replace function ${fn("page_reviews")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_reviews.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  v_subject_type text := ${filterFirst("subjectType")};
  v_subject_id text := ${filterFirst("subjectId")};
  ${listDeclare(reviewPage)}
begin
  if jsonb_typeof(v_filters) <> 'object' or v_subject_type is null or v_subject_id is null then
    ${fail("REVIEW_INVALID", "filters must name one subjectType and one subjectId", "22023")}
  end if;
  if not (${SERVICE_CALLER} or ${readable}(page_reviews.tenant, v_subject_type, v_subject_id)) then
    ${forbidden("not allowed to read this record's reviews")}
  end if;
  ${listBody(reviewPage)}
end;
$$;
revoke execute on function ${fn("page_reviews")}(${idType}, jsonb) from public;
grant execute on function ${fn("page_reviews")}(${idType}, jsonb) to anon, authenticated, service_role;

-- One review: the caller's own in any status, or a published one of a subject
-- the caller can read (author id hidden).
create or replace function ${fn("get_review")}(review_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${reviews}%rowtype;
begin
  select * into v_row from ${reviews} x where x.${r("id")} = get_review.review_id;
  if not found then
    ${notFound}
  end if;
  if coalesce(v_row.${r("author")} = auth.uid(), false) then
    return ${full("v_row")};
  end if;
  if v_row.${r("status")} <> 'published'
    or not (${SERVICE_CALLER} or ${readable}(v_row.${r("tenant")}, v_row.${r("subjectType")}, v_row.${r("subjectId")})) then
    ${notFound}
  end if;
  return ${json("v_row", "null::uuid")};
end;
$$;
revoke execute on function ${fn("get_review")}(uuid) from public;
grant execute on function ${fn("get_review")}(uuid) to anon, authenticated, service_role;`;
}
