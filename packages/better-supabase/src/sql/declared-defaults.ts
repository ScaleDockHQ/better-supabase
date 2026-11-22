import { RANK_ALPHABET } from "../core/rank-keys.ts";
import { grantExecute, grantTable } from "./emit/grant.ts";
import { createTable, enableRowSecurity } from "./emit/table.ts";

/**
 * The kinds of default a block function reads from
 * `better_supabase.declared_defaults` (ADR 1220). The app declares the rows in
 * `supabase/rows/*.sql`; a function that finds none falls back to what the
 * config renders.
 */
export const DEFAULT_KINDS = [
  "option_set_item",
  "pipeline_stage",
  "numbering_format",
  "approval_floor",
] as const;

export type DefaultKind = (typeof DEFAULT_KINDS)[number];

/** The table the declared rows of every kind go to, one row per key. */
export const DECLARED_DEFAULTS_TABLE = "better_supabase.declared_defaults";

/** The function that returns the rows of one kind and subject as a jsonb list. */
export const DECLARED_DEFAULTS_FN = "better_supabase.declared_defaults_of";

/**
 * The table and its reader, for the prelude. `declared_defaults_of` returns
 * `null` when no row exists, so a caller tells "nothing declared" from "an
 * empty list" and keeps its own default. It runs as its owner: the block
 * functions that call it run as a user, who may not read the table.
 */
export const DECLARED_DEFAULTS: string = `${createTable(
  DECLARED_DEFAULTS_TABLE,
  [
    "kind text not null",
    "subject text not null",
    "key text not null",
    "position integer not null default 0",
    "value jsonb not null",
    "primary key (kind, subject, key)",
  ],
)}
${enableRowSecurity(DECLARED_DEFAULTS_TABLE)}
revoke all on ${DECLARED_DEFAULTS_TABLE} from public, anon, authenticated;
${grantTable(DECLARED_DEFAULTS_TABLE, ["select"], ["service_role"])}

-- The declared rows of one kind and subject, ordered by position and then key,
-- as a jsonb list; null when the app declared none.
create or replace function ${DECLARED_DEFAULTS_FN}(kind text, subject text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_agg(d.value order by d.position, d.key)
  from better_supabase.declared_defaults d
  where d.kind = declared_defaults_of.kind and d.subject = declared_defaults_of.subject
$$;
${grantExecute(`${DECLARED_DEFAULTS_FN}(text, text)`, ["authenticated", "service_role"])}`.trim();

/**
 * A rank key for the row at `ordinal` (1-based) of a declared list: two base-62
 * digits of the position, then `V`, so up to 3,843 rows keep their order and
 * the key never ends in `0`.
 */
export function declaredRank(ordinal: string): string {
  const alphabet = `'${RANK_ALPHABET}'`;

  return `substr(${alphabet}, ((${ordinal} / 62) % 62)::integer + 1, 1) || substr(${alphabet}, (${ordinal} % 62)::integer + 1, 1) || 'V'`;
}
