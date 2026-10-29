import type { BlockSqlContext } from "../context.ts";
import type { RelationContribution } from "../contributions.ts";
import type { PartyNames } from "./contacts-functions.ts";

import {
  REPRESENTATIVE_AUTHORITIES,
  REPRESENTATIVE_ROLES,
} from "../../blocks/contacts/representatives.ts";
import { sqlString } from "../../core/template.ts";
import { userGrant } from "../shared.ts";

/** The relation kind a representative's link has. */
export const REPRESENTS = "represents";

const list = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

/** Whether `key` of `data` (a jsonb expression) is missing or a date string. */
const dateOrMissing = (data: string, key: string): string =>
  `(${data} -> '${key}' is null or (jsonb_typeof(${data} -> '${key}') = 'string' and pg_input_is_valid(${data} ->> '${key}', 'date')))`;

/**
 * The check `link` runs on a `represents` link's data: a role, an authority,
 * and `valid_from` and `valid_until` dates in order when set.
 */
function representationData(data: string): string {
  const from = `${data} ->> 'valid_from'`;
  const until = `${data} ->> 'valid_until'`;

  return `(jsonb_typeof(${data}) = 'object'
      and (${data} ->> 'role') in (${list(REPRESENTATIVE_ROLES)})
      and (${data} ->> 'authority') in (${list(REPRESENTATIVE_AUTHORITIES)})
      and ${dateOrMissing(data, "valid_from")}
      and ${dateOrMissing(data, "valid_until")}
      and case when pg_input_is_valid(${from}, 'date') and pg_input_is_valid(${until}, 'date')
        then (${from})::date <= (${until})::date else true end)`;
}

/**
 * Whether a `represents` link with `data` holds today: `valid_from` is past or
 * unset and `valid_until` is today or later or unset. A date Postgres can't
 * read ends the link, so an app kind without the check never throws here.
 */
export function representationActive(data: string): string {
  const bound = (key: string, compare: string): string =>
    `case when ${data} ->> '${key}' is null then true
      when pg_input_is_valid(${data} ->> '${key}', 'date') then (${data} ->> '${key}')::date ${compare} current_date
      else false end`;

  return `(${bound("valid_from", "<=")}) and (${bound("valid_until", ">=")})`;
}

/**
 * The `represents` kind contacts adds to relations: a person represents a
 * record.
 */
export function representsKind(own: BlockSqlContext): RelationContribution {
  return {
    kind: REPRESENTS,
    inverse: "represented_by",
    types: { source: [own.naming.rename("person")] },
    data: representationData,
  };
}

/**
 * `list_representatives` and `represented_by_me` over the relations block's
 * links, with a leading newline. Empty without relations.
 */
export function representativeFunctions(
  ctx: BlockSqlContext,
  names: PartyNames,
): string {
  if (!ctx.installed("relations")) {
    return "";
  }

  const relations = ctx.of("relations");
  const links = relations.table("relations");

  const r = (column: string): string =>
    `r.${relations.col("relations", column)}`;

  const p = (column: string): string => `p.${names.c("people", column)}`;
  const person = sqlString(ctx.naming.rename("person"));
  const active = representationActive(r("data"));
  const kind = sqlString(REPRESENTS);

  const terms = `'role', ${r("data")} ->> 'role', 'authority', ${r("data")} ->> 'authority',
    'validFrom', ${r("data")} ->> 'valid_from', 'validUntil', ${r("data")} ->> 'valid_until'`;

  return `
-- The people who represent a record (a client's guardian, a legal
-- representative), with their role and authority. Runs as the caller, so the
-- relations and people policies decide what they see. Ended links come last.
create or replace function ${names.fn("list_representatives")}(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', ${r("id")}, 'organizationId', ${r("tenant")}::text,
    'personId', ${p("id")}, 'name', ${p("name")}, 'email', ${p("email")}, 'phone', ${p("phone")},
    ${terms},
    'active', ${active}, 'createdAt', ${r("createdAt")}
  ) order by ${active} desc, ${p("name")}, ${r("id")}), '[]'::jsonb)
  from ${links} r
  join ${names.t("people")} p on ${p("id")}::text = ${r("sourceId")} and ${p("tenant")} = ${r("tenant")}
  where ${r("kind")} = ${kind} and ${r("sourceType")} = ${person}
    and ${r("targetType")} = list_representatives.subject_type
    and ${r("targetId")} = list_representatives.subject_id
$$;
${userGrant(`${names.fn("list_representatives")}(text, text)`)}

-- The records the caller represents in tenant, as a guest whose party is the
-- representative, while the link holds.
create or replace function ${names.fn("represented_by_me")}(tenant ${ctx.idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', ${r("id")}, 'organizationId', ${r("tenant")}::text, 'personId', ${r("sourceId")},
      'subjectType', ${r("targetType")}, 'subjectId', ${r("targetId")},
      ${terms}
    ) order by ${r("createdAt")}, ${r("id")}), '[]'::jsonb)
    from ${links} r
    where ${r("tenant")} = represented_by_me.tenant
      and ${r("kind")} = ${kind} and ${r("sourceType")} = ${person}
      and ${active}
      and ${names.scope.guestParty("represented_by_me.tenant", person, r("sourceId"))}
  );
end;
$$;
${userGrant(`${names.fn("represented_by_me")}(${ctx.idType})`)}
`;
}
