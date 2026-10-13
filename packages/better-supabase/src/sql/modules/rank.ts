import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { RANK_ALPHABET, RANK_REBALANCE_QUEUE } from "../../core/rank-keys.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, schemaPreamble, serviceGrant, userGrant } from "../shared.ts";
import {
  type RegisteredSubject,
  registeredIdMatches,
  registeredSubjects,
} from "../subject-registry.ts";

const NAMES: ModuleNames = { tables: {} };

/** Keys longer than this queue a rebalance of their group. */
const RANK_REBALANCE_LENGTH = 24;

/** The rebalance job's queue. */

const ALPHABET = sqlString(RANK_ALPHABET);

function ranked(ctx: ModuleContext): readonly RegisteredSubject[] {
  return registeredSubjects(ctx.subjects).filter(
    (subject) => subject.config.rank !== undefined,
  );
}

function cases(
  selector: string,
  subjects: readonly RegisteredSubject[],
  branch: (subject: RegisteredSubject) => string,
  otherwise: string,
): string {
  if (subjects.length === 0) return otherwise;
  return `case ${selector}
${subjects.map((subject) => `    when ${sqlString(subject.type)} then\n${branch(subject)}`).join("\n")}
    else
      ${otherwise}
  end case;`;
}

/** The `move` branch for one subject: neighbours, the new key, one update. */
function moveBranch(ctx: ModuleContext, subject: RegisteredSubject): string {
  const rank = sqlIdent(subject.config.rank?.column ?? "rank");
  const groupName = subject.config.rank?.group;
  const group = groupName === undefined ? undefined : sqlIdent(groupName);
  const tenant = subject.tenant === undefined ? "null" : `s.${subject.tenant}`;
  const neighbour = (id: string, key: string, at: string): string => `
      if ${id} is not null then
        select s.${rank}, ${tenant}::text${group === undefined ? ", null" : `, s.${group}::text`}
          into ${key}, v_other_tenant, v_other_group
          from ${subject.qualified} s where ${registeredIdMatches(subject, id)};
        if not found then
          ${fail("RANK_NEIGHBOR_NOT_FOUND", `the ${at} row was not found`, "P0002")}
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          ${fail("RANK_NEIGHBOR_MISMATCH", `the ${at} row is in another tenant or group`, "22023")}
        end if;
      end if;`;
  return `      select ${tenant}::text${group === undefined ? ", null" : `, s.${group}::text`}
        into v_tenant, v_group
        from ${subject.qualified} s where ${registeredIdMatches(subject, "move.subject_id")};
      if not found then
        ${fail("RANK_NOT_FOUND", "row not found", "P0002")}
      end if;
      ${
        group === undefined
          ? `if move.to_group is not null then
        ${fail("RANK_NO_GROUP", "this subject has no rank group", "22023")}
      end if;`
          : "v_group := coalesce(move.to_group, v_group);"
      }${neighbour("move.previous_id", "v_previous", "previous")}${neighbour("move.next_id", "v_next", "next")}
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        ${fail("RANK_CONFLICT", "the neighbours share a rank key; rebalance the group first", "22023")}
      end if;
      v_key := ${ctx.fn("rank_between")}(v_previous, v_next);
      update ${subject.qualified} s set ${rank} = v_key${group === undefined ? "" : `, ${group} = v_group`}
        where ${registeredIdMatches(subject, "move.subject_id")};
      if not found then
        ${fail("RANK_FORBIDDEN", "not allowed to move this row")}
      end if;`;
}

/** The `rebalance_ranks` branch: even keys for every row of the tenant, per group. */
function rebalanceBranch(
  ctx: ModuleContext,
  subject: RegisteredSubject,
): string {
  const rank = sqlIdent(subject.config.rank?.column ?? "rank");
  const groupName = subject.config.rank?.group;
  const group = groupName === undefined ? undefined : sqlIdent(groupName);
  const partition = group === undefined ? "" : `partition by s.${group} `;
  const filters = [
    subject.tenant === undefined
      ? ""
      : `s.${subject.tenant}::text = rebalance_ranks.tenant`,
    group === undefined
      ? ""
      : `(rebalance_ranks.rank_group is null or s.${group}::text = rebalance_ranks.rank_group)`,
  ].filter((part) => part !== "");
  return `      with ordered as (
        select s.${subject.id} as row_id,
          row_number() over (${partition}order by s.${rank} collate "C", s.${subject.id}) as nth,
          count(*) over (${partition.trimEnd()}) as total
        from ${subject.qualified} s${filters.length === 0 ? "" : `\n        where ${filters.join("\n          and ")}`}
      )
      update ${subject.qualified} t set ${rank} = ${ctx.fn("rank_key")}(o.nth, o.total)
      from ordered o
      where t.${subject.id} = o.row_id;
      get diagnostics v_count = row_count;`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const subjects = ranked(ctx);
  const fn = (name: string): string => ctx.fn(name);
  const unknown = fail(
    "RANK_SUBJECT_UNKNOWN",
    "this subject type has no rank column in config.subjects",
    "22023",
  );
  const invalid = (
    arg: string,
  ): string => `if ${arg} is not null and ${arg} !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    ${fail("RANK_KEY_INVALID", "not a rank key", "22023")}
  end if;`;
  return `${schemaPreamble(ctx)}
-- Fractional rank keys (ADR 0021). Keys are base-62 text compared with
-- collate "C"; the steps match rankBetween in better-supabase/blocks/rank.
create or replace function ${fn("rank_between")}(previous text, next text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_alphabet constant text := ${ALPHABET};
  v_low text := coalesce(rank_between.previous, '');
  v_key text := '';
  v_bounded boolean := rank_between.next is not null;
  v_index integer := 1;
  v_low_digit integer;
  v_high_digit integer;
begin
  ${invalid("rank_between.previous")}
  ${invalid("rank_between.next")}
  if rank_between.previous is not null and rank_between.next is not null
    and rank_between.previous collate "C" >= rank_between.next collate "C" then
    ${fail("RANK_KEY_ORDER", "previous must sort before next", "22023")}
  end if;
  loop
    v_low_digit := case when v_index <= length(v_low) then strpos(v_alphabet, substr(v_low, v_index, 1)) - 1 else 0 end;
    v_high_digit := case
      when not v_bounded then 62
      when v_index <= length(rank_between.next) then strpos(v_alphabet, substr(rank_between.next, v_index, 1)) - 1
      else 0
    end;
    if v_high_digit = v_low_digit then
      v_key := v_key || substr(v_alphabet, v_low_digit + 1, 1);
    elsif v_high_digit - v_low_digit > 1 then
      return v_key || substr(v_alphabet, (v_low_digit + v_high_digit) / 2 + 1, 1);
    elsif v_bounded and v_index < length(rank_between.next) then
      return v_key || substr(rank_between.next, v_index, 1);
    else
      v_key := v_key || substr(v_alphabet, v_low_digit + 1, 1);
      v_bounded := false;
    end if;
    v_index := v_index + 1;
  end loop;
end;
$$;
${userGrant(`${fn("rank_between")}(text, text)`)}

-- Key number nth of total, spread evenly at one width (rankKeys).
create or replace function ${fn("rank_key")}(nth bigint, total bigint)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_alphabet constant text := ${ALPHABET};
  v_width integer := 1;
  v_value numeric;
  v_key text := '';
begin
  if rank_key.nth < 1 or rank_key.nth > rank_key.total then
    ${fail("RANK_KEY_POSITION", "nth must be between 1 and total", "22023")}
  end if;
  while 62::numeric ^ v_width <= rank_key.total loop
    v_width := v_width + 1;
  end loop;
  v_value := floor(62::numeric ^ v_width / (rank_key.total + 1)) * rank_key.nth;
  for v_place in 1..v_width loop
    v_key := substr(v_alphabet, (v_value % 62)::integer + 1, 1) || v_key;
    v_value := floor(v_value / 62);
  end loop;
  return rtrim(v_key, '0');
end;
$$;
${userGrant(`${fn("rank_key")}(bigint, bigint)`)}

-- Moves a subject between two neighbours (either may be null for an end),
-- into to_group when given. It runs as the caller: the table's policies
-- decide what it can read and update, and a state-machine trigger on the
-- group column checks the stage change. Returns the new key.
create or replace function ${fn("move")}(subject_type text, subject_id text, previous_id text, next_id text, to_group text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_tenant text;
  v_group text;
  v_other_tenant text;
  v_other_group text;
  v_previous text;
  v_next text;
  v_key text;
begin
  if not ${fn("can_subject")}(move.subject_type, move.subject_id, 'write') then
    ${fail("RANK_FORBIDDEN", "not allowed to move this row")}
  end if;
  ${cases("move.subject_type", subjects, (subject) => moveBranch(ctx, subject), unknown)}
  if length(v_key) > ${String(RANK_REBALANCE_LENGTH)} then
    ${ctx.enqueue(RANK_REBALANCE_QUEUE, "jsonb_build_object('subjectType', move.subject_type, 'tenant', v_tenant, 'group', v_group)", "'rank:' || move.subject_type || ':' || coalesce(v_tenant, '') || ':' || coalesce(v_group, '')")}
  end if;
  return v_key;
end;
$$;
${userGrant(`${fn("move")}(text, text, text, text, text)`)}

-- Rewrites every key of a tenant's rows (in rank_group, or every group) to
-- short, evenly spaced keys in the same order. Returns the rows rewritten.
create or replace function ${fn("rebalance_ranks")}(subject_type text, tenant text, rank_group text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
begin
  ${cases("rebalance_ranks.subject_type", subjects, (subject) => rebalanceBranch(ctx, subject), unknown)}
  return v_count;
end;
$$;
${serviceGrant(`${fn("rebalance_ranks")}(text, text, text)`)}
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "rank_between", args: ["text", "text"], returns: "text" },
    { name: "rank_key", args: ["bigint", "bigint"], returns: "text" },
    {
      name: "move",
      args: ["text", "text", "text", "text", "text"],
      returns: "text",
    },
    {
      name: "rebalance_ranks",
      args: ["text", "text", "text"],
      returns: "integer",
    },
  ];
}

export const RANK: ModuleDefinition = {
  name: "rank",
  title: "Rank",
  description:
    "Fractional rank keys: rank_between, move() for every config.subjects entry with a rank column (through the caller's policies and any state-machine trigger), and a rebalance job.",
  requires: ["access", "subjects"],
  integrates: ["jobs"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
