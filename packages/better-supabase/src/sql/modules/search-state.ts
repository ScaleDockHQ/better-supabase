import type { BlockSqlContext } from "../context.ts";

import { fail, userGrant } from "../shared.ts";

export interface StateNames {
  readonly table: string;
  readonly col: (column: string) => string;
}

/** Recents and favorites over the share-links block's per-user state. */
export function userStateFunctions(
  ctx: BlockSqlContext,
  state: StateNames | undefined,
): string {
  const subjects = ctx.of("subjects");
  const canSubject = subjects.fn("can_subject");
  const title = subjects.fn("subject_title");
  const url = subjects.fn("subject_url");
  const fn = (name: string): string => ctx.fn(name);

  const rows = state
    ? `select s.${state.col("subjectType")}, s.${state.col("subjectId")}, s.${state.col("starredAt")}, s.${state.col("lastOpenedAt")}
  from ${state.table} s
  where s.${state.col("user")} = auth.uid()`
    : "select null::text, null::text, null::timestamptz, null::timestamptz where false";

  const upsert = (set: "opened" | "starred"): string => {
    if (!state) {
      return "return false;";
    }

    const keys = `${state.col("subjectType")}, ${state.col("subjectId")}, ${state.col("user")}`;

    const value =
      set === "opened"
        ? `${state.col("lastOpenedAt")}) values (search_touch.subject_type, search_touch.subject_id, auth.uid(), now())
  on conflict (${keys}) do update set ${state.col("lastOpenedAt")} = now();`
        : `${state.col("starredAt")}) values (search_star.subject_type, search_star.subject_id, auth.uid(), case when search_star.starred then now() end)
  on conflict (${keys}) do update set ${state.col("starredAt")} = case when search_star.starred then coalesce(st.${state.col("starredAt")}, now()) end;`;

    return `insert into ${state.table} as st (${keys}, ${value}
  return true;`;
  };

  const list = (
    name: "search_recents" | "search_favorites",
    at: "opened_at" | "starred_at",
  ): string => `
create or replace function ${fn(name)}(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.${at} as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', ${title}(s.subject_type, s.subject_id),
      'url', ${url}(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from ${fn("search_user_state")}() s
    where s.${at} is not null
      and (${name}.types is null or s.subject_type = any (${name}.types))
      and ${canSubject}(s.subject_type, s.subject_id, 'read')
    order by s.${at} desc
    limit least(greatest(coalesce(${name}.max_results, 10), 1), 100)
  ) x
$$;
${userGrant(`${fn(name)}(integer, text[])`)}`;

  return `
-- The caller's own rows of the share-links per-user state. The lists below
-- run as the caller, so can_subject sees what they can read.
create or replace function ${fn("search_user_state")}()
returns table (subject_type text, subject_id text, starred_at timestamptz, opened_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  ${rows}
$$;
${userGrant(`${fn("search_user_state")}()`)}
${list("search_recents", "opened_at")}
${list("search_favorites", "starred_at")}

create or replace function ${fn("search_touch")}(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    ${fail("SEARCH_SIGNED_OUT", "sign in to keep recents")}
  end if;
  ${upsert("opened")}
end;
$$;
${userGrant(`${fn("search_touch")}(text, text)`)}

create or replace function ${fn("search_star")}(subject_type text, subject_id text, starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    ${fail("SEARCH_SIGNED_OUT", "sign in to keep favorites")}
  end if;
  ${upsert("starred")}
end;
$$;
${userGrant(`${fn("search_star")}(text, text, boolean)`)}`;
}
