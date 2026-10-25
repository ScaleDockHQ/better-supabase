import type { BlockSqlContext } from "../context.ts";

import {
  dropExpiredPartitions,
  fail,
  PARTITION_VARIABLES,
  pageSize,
} from "../shared.ts";

export interface UsageHistoryOptions {
  /** Whether the caller may read usage in `tenant`, as SQL. */
  readonly canRead: (tenant: string) => string;
  /** Whether the module partitions its own history table by month. */
  readonly partitioned: boolean;
}

/** The functions that read and purge the usage history (`options.history`). */
export function usageHistorySql(
  ctx: BlockSqlContext,
  options: UsageHistoryOptions,
): string {
  const { canRead, partitioned } = options;
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const history = ctx.table("history");
  const hc = (logical: string): string => ctx.col("history", logical);
  const keepHistory = ctx.flag("history", false);

  const historyField = (logical: string): string =>
    ctx.has("history", logical) ? `h.${hc(logical)}` : "null::text";

  return `-- A tenant's usage history, newest first, of one meter when given, before
-- before_id for the next page. [] without options.history. Needs usage.read.
create or replace function ${fn("usage_history")}(tenant ${id}, meter text default null, max_rows integer default 100, before_id bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${canRead("tenant")} then
    ${fail("USAGE_FORBIDDEN", "Not allowed to read usage in this tenant")}
  end if;
  ${
    keepHistory
      ? `return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', h.${hc("id")}, 'meter', h.${hc("meter")}, 'quantity', h.${hc("quantity")},
      'actor', h.${hc("actor")}, 'source', ${historyField("source")}, 'metadata', ${historyField("metadata")},
      'recorded_at', h.${hc("recordedAt")}
    ) order by h.${hc("id")} desc), '[]'::jsonb)
    from (
      select * from ${history} h
      where h.${hc("tenant")} = usage_history.tenant
        and (usage_history.meter is null or h.${hc("meter")} = usage_history.meter)
        and (before_id is null or h.${hc("id")} < before_id)
      order by h.${hc("id")} desc
      limit ${pageSize("max_rows", 100, 1000)}
    ) h
  );`
      : "return '[]'::jsonb;"
  }
end;
$$;

-- Who and what used a meter in the current window of its quota period:
-- [{ actor, source, quantity }], largest first. [] without options.history.
create or replace function ${fn("usage_breakdown")}(tenant ${id}, meter text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  quota record;
  win record;
begin
  if not ${canRead("tenant")} then
    ${fail("USAGE_FORBIDDEN", "Not allowed to read usage in this tenant")}
  end if;
  select * into quota from ${fn("usage_quota")}(tenant, meter);
  select * into win from ${fn("usage_window")}(tenant, coalesce(quota.period, 'month'));
  ${
    keepHistory
      ? `return (
    select coalesce(jsonb_agg(jsonb_build_object('actor', b.actor, 'source', b.source, 'quantity', b.quantity) order by b.quantity desc), '[]'::jsonb)
    from (
      select h.${hc("actor")} as actor, ${historyField("source")} as source, sum(h.${hc("quantity")}) as quantity
      from ${history} h
      where h.${hc("tenant")} = usage_breakdown.tenant and h.${hc("meter")} = usage_breakdown.meter
        and h.${hc("recordedAt")} >= win.starts_at and h.${hc("recordedAt")} < win.ends_at
      group by 1, 2
    ) b
  );`
      : "return '[]'::jsonb;"
  }
end;
$$;

-- Deletes up to batch history rows older than older_than; returns how many.
create or replace function ${fn("purge_usage_history")}(older_than interval default '400 days', batch integer default 10000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
${
  keepHistory
    ? `declare
  purged integer;${
    partitioned
      ? `
  v_dropped integer := 0;${PARTITION_VARIABLES}`
      : ""
  }
begin${
        partitioned
          ? `
  -- Whole months past every tenant's retention go at once.
  ${dropExpiredPartitions({ table: history, cutoff: ctx.cutoff("usage", "older_than"), purged: "v_dropped" })}`
          : ""
      }
  with gone as (
    delete from ${history} where ${hc("id")} in (
      select h.${hc("id")} from ${history} h
      where ${ctx.expired("usage", { at: `h.${hc("recordedAt")}`, tenant: `h.${hc("tenant")}`, fallback: "older_than" })}
      order by h.${hc("id")} limit batch
    )
    returning 1
  )
  select count(*)::integer into purged from gone;
  return purged${partitioned ? " + v_dropped" : ""};
end;`
    : `begin
  return 0;
end;`
}
$$;
`;
}
