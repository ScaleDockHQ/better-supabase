import type { ReadType } from "../../core/read-type.ts";
import type { BlockSqlRead } from "../reads.ts";

import { declareRead } from "../reads.ts";

/** What `sessions_overview` returns. */
export const SESSIONS_OVERVIEW_RESULT: ReadType = {
  count: "number",
  currentId: "text?",
  sessions: [
    {
      id: "text",
      createdAt: "text?",
      lastActiveAt: "text?",
      userAgent: "text?",
      ip: "text?",
      aal: "text?",
      current: "bool",
    },
  ],
};

/** One session of `SessionsOverviewRaw`, with the timestamps still text. */
export interface SessionsOverviewRaw {
  readonly count: number;
  readonly currentId: string | null;
  readonly sessions: readonly {
    readonly id: string;
    readonly createdAt: string | null;
    readonly lastActiveAt: string | null;
    readonly userAgent: string | null;
    readonly ip: string | null;
    readonly aal: string | null;
    readonly current: boolean;
  }[];
}

export const SESSIONS_READS: readonly BlockSqlRead[] = [
  declareRead(
    "overview",
    "sessions_overview",
    {},
    SESSIONS_OVERVIEW_RESULT,
    "The caller's security page in one call: every unexpired session, most recently active first, the current one marked, and how many there are.",
    [],
  ),
];

/**
 * `sessions_overview`: `list_my_sessions` and the id of the session behind the
 * token, so a page needs no second pass over the list.
 */
export const SESSIONS_OVERVIEW_SQL = `

-- The caller's security page in one call: the sessions from
-- list_my_sessions(), the count and the current session's id.
create or replace function better_supabase.sessions_overview()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'count', jsonb_array_length(s.payload),
    'currentId', (select x ->> 'id' from jsonb_array_elements(s.payload) x where (x ->> 'current')::boolean limit 1),
    'sessions', s.payload)
  from (select better_supabase.list_my_sessions() as payload) s
$$;

revoke execute on function better_supabase.sessions_overview() from public, anon;
grant execute on function better_supabase.sessions_overview() to authenticated;`;
