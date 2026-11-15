import {
  filterAny,
  filterFirst,
  filterFlag,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";

/** What the page function reads from the time entries builder. */
export interface TimeEntryPageParts {
  readonly idType: string;
  readonly fn: (name: string) => string;
  readonly entries: string;
  readonly e: (column: string) => string;
  /** The owner column of an entry: the user, or the employee in employee mode. */
  readonly owner: string;
  readonly employeeMode: boolean;
  readonly archivable: boolean;
  readonly ended: (alias: string) => string;
  readonly seconds: (alias: string) => string;
  readonly subjectType: (alias: string) => string;
  readonly subjectId: (alias: string) => string;
  readonly entryJson: (alias: string) => string;
  /** The employee that `user` is in `tenant`, as a SQL expression. */
  readonly employeeIdOfUser: (tenant: string, user: string) => string;
  /** The caller's own employee in `tenant`, as a SQL expression. */
  readonly myEmployee: (tenant: string) => string;
  readonly canTrack: (tenant: string) => string;
  readonly canRead: (tenant: string) => string;
  readonly forbidden: (message: string) => string;
}

/**
 * `page_time_entries` and `get_time_entry` (ADR 1077). The page applies the
 * rules of `list_time_entries`: the caller's own entries unless `everyone` is
 * set, and another member's or everyone's entries need `time_entries.read`.
 */
export function timeEntryPageSql(h: TimeEntryPageParts): string {
  const { fn, entries, e, owner, ended, seconds, entryJson } = h;
  const key = { expr: `x.${e("id")}`, dir: "desc", type: "uuid" } as const;

  const started = [
    { expr: `x.${e("startedAt")}`, dir: "desc", type: "timestamptz" },
    key,
  ] as const;

  const spec = {
    name: "page_time_entries",
    from: entries,
    alias: "x",
    where: [
      `x.${e("tenant")} = page_time_entries.tenant`,
      `(v_everyone or x.${owner} = ${h.employeeMode ? "v_owner" : "v_user"})`,
      `(${filterFirst("from")} is null or coalesce(${ended("x")}, 'infinity'::timestamptz) > (${filterFirst("from")})::timestamptz)`,
      `(${filterFirst("to")} is null or x.${e("startedAt")} < (${filterFirst("to")})::timestamptz)`,
      filterAny("subjectType", h.subjectType("x")),
      filterAny("subjectId", h.subjectId("x")),
      filterAny("billable", `x.${e("billable")}::text`),
      h.archivable
        ? `((x.${e("archivedAt")} is not null) = ${filterFlag("archived")})`
        : "true",
      `(v_search is null or x.${e("note")} ilike v_search)`,
    ],
    keys: started,
    sorts: {
      startedAt: started,
      endedAt: [
        {
          expr: `coalesce(${ended("x")}, 'infinity'::timestamptz)`,
          dir: "desc",
          type: "timestamptz",
        },
        key,
      ],
      seconds: [
        { expr: `coalesce(${seconds("x")}, 0)`, dir: "desc", type: "bigint" },
        key,
      ],
      createdAt: [
        { expr: `x.${e("createdAt")}`, dir: "desc", type: "timestamptz" },
        key,
      ],
    },
    facets: {
      subjectType: h.subjectType("x"),
      billable: `x.${e("billable")}::text`,
    },
    rowJson: entryJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("TIME_ENTRY_INVALID", message, "22023"),
  } as const;

  const mine = h.employeeMode
    ? `v_owner = ${h.myEmployee("page_time_entries.tenant")}`
    : "coalesce(v_user = auth.uid(), false)";

  const ownerDeclare = h.employeeMode
    ? `v_owner uuid := coalesce(nullif(${filterFirst("employeeId")}, '')::uuid, ${h.employeeIdOfUser("page_time_entries.tenant", `coalesce(nullif(${filterFirst("userId")}, '')::uuid, auth.uid())`)});`
    : `v_user uuid := coalesce(nullif(${filterFirst("userId")}, '')::uuid, auth.uid());`;

  return `
-- A member's entries (the caller's by default) as a keyset page, newest first
-- (ADR 1077). filters is { subjectType, subjectId, billable (each a value or a
-- list), userId${h.employeeMode ? ", employeeId" : ""}, from, to (the first value counts), everyone (true for all
-- members), archived (true lists only archived entries), search (note), sort
-- (startedAt, endedAt, seconds, createdAt), direction, facet, count, limit,
-- after, offset, paged, total, totalCap }.
create or replace function ${fn("page_time_entries")}(tenant ${h.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_time_entries.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  v_everyone boolean := ${filterFlag("everyone")};
  ${ownerDeclare}
  ${listDeclare(spec)}
begin
  if not (${SERVICE_CALLER} or ((${mine} and not v_everyone) and ${h.canTrack("page_time_entries.tenant")}) or ${h.canRead("page_time_entries.tenant")}) then
    ${h.forbidden("not allowed to read these entries")}
  end if;
  ${listBody(spec)}
end;
$$;
${userGrant(`${fn("page_time_entries")}(${h.idType}, jsonb)`)}

-- One entry the caller may read, or null.
create or replace function ${fn("get_time_entry")}(entry_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${entries}%rowtype;
begin
  select * into v_row from ${entries} x where x.${e("id")} = get_time_entry.entry_id;
  if not found then
    return null;
  end if;
  if not (${SERVICE_CALLER} or (${h.employeeMode ? `v_row.${e("employee")} = ${h.myEmployee(`v_row.${e("tenant")}`)}` : `coalesce(v_row.${e("user")} = auth.uid(), false)`} and ${h.canTrack(`v_row.${e("tenant")}`)}) or ${h.canRead(`v_row.${e("tenant")}`)}) then
    ${h.forbidden("not allowed to read this entry")}
  end if;
  return ${entryJson("v_row")};
end;
$$;
${userGrant(`${fn("get_time_entry")}(uuid)`)}
`;
}
