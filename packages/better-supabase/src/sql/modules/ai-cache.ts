import type { BlockSqlContext, BlockSqlNames } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { raise, schemaPreamble, serviceGrant, lockTable } from "../shared.ts";

const ENTRIES = {
  key: "key",
  tenant: "organization_id",
  kind: "kind",
  model: "model",
  value: "value",
  hits: "hits",
  createdAt: "created_at",
  lastHitAt: "last_hit_at",
  expiresAt: "expires_at",
} as const;

const NAMES: BlockSqlNames = {
  options: ["maxTtl", "maxBytes"],
  tables: {
    entries: {
      name: "ai_cache_entries",
      columns: ENTRIES,
      lifecycle: { tenant: "tenant" },
      app: {},
      optional: ["model", "hits", "createdAt", "lastHitAt"],
      typed: ["kind"],
    },
  },
};

function build(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);

  const has = (column: keyof typeof ENTRIES): boolean =>
    ctx.has("entries", column);

  const col = (column: keyof typeof ENTRIES): string =>
    ctx.col("entries", column);

  const e = {
    key: col("key"),
    tenant: col("tenant"),
    kind: col("kind"),
    value: col("value"),
    expiresAt: col("expiresAt"),
  };

  const entries = ctx.table("entries");
  const { name } = ctx.tableName("entries");

  const line = (column: keyof typeof ENTRIES, type: string): string =>
    has(column) ? `\n  ${col(column)} ${type},` : "";

  const maxTtl = ctx.number("maxTtl", 7 * 24 * 60 * 60);
  const maxBytes = ctx.number("maxBytes", 1024 * 1024);

  if (!Number.isInteger(maxTtl) || maxTtl < 1) {
    throw new TypeError(
      "blocks.ai-cache.options.maxTtl must be a whole number of seconds",
    );
  }

  if (!Number.isInteger(maxBytes) || maxBytes < 1) {
    throw new TypeError(
      "blocks.ai-cache.options.maxBytes must be a whole number of bytes",
    );
  }

  const entryJson = (row: string): string =>
    `jsonb_build_object(${Object.entries(ENTRIES)
      .map(
        ([logical, key]) =>
          `'${key}', ${ctx.has("entries", logical) ? `${row}.${ctx.col("entries", logical)}` : logical === "hits" ? "0" : "null"}`,
      )
      .join(", ")})`;

  const hit = [
    ...(has("hits") ? [`${col("hits")} = x.${col("hits")} + 1`] : []),
    ...(has("lastHitAt") ? [`${col("lastHitAt")} = now()`] : []),
  ];

  const lookup =
    hit.length > 0
      ? `update ${entries} x set ${hit.join(", ")}
  where x.${e.key} = ai_cache_get.key and x.${e.expiresAt} > now()
  returning * into v_row;`
      : `select * into v_row from ${entries} x
  where x.${e.key} = ai_cache_get.key and x.${e.expiresAt} > now();`;

  const model = has("model");

  const resets = [
    ...(has("hits") ? [`${col("hits")} = 0`] : []),
    ...(has("createdAt") ? [`${col("createdAt")} = now()`] : []),
    ...(has("lastHitAt") ? [`${col("lastHitAt")} = null`] : []),
  ];

  return `${schemaPreamble(ctx)}
-- Model responses cached by a key the application derives from the request
-- (a SHA-256 of the model, the prompt and the settings). Entries hold prompts
-- and outputs, so only the service role reads and writes them.
create table if not exists ${entries} (
  ${e.key} text primary key check (length(${e.key}) between 1 and 256),
  ${e.tenant} ${id},
  ${e.kind} text not null default 'generate' check (${e.kind} in ('generate', 'stream', 'embed', 'other')),${model ? `\n  ${col("model")} text check (length(${col("model")}) <= 200),` : ""}
  ${e.value} jsonb not null check (octet_length(${e.value}::text) <= ${maxBytes}),${line("hits", "integer not null default 0")}${line("createdAt", "timestamptz not null default now()")}${line("lastHitAt", "timestamptz")}
  ${e.expiresAt} timestamptz not null
);
create index if not exists ai_cache_entries_expires_idx on ${entries} (${e.expiresAt});
create index if not exists ai_cache_entries_tenant_idx on ${entries} (${e.tenant});${
    ctx.owns("entries")
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${name}_key_key`)} on ${entries} (${e.key});`
  }
${lockTable(entries)}

-- The entry under key, or null when there is none or it expired; counts the hit.
create or replace function ${fn("ai_cache_get")}(key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${entries}%rowtype;
begin
  ${lookup}
  if not found then
    return null;
  end if;
  return ${entryJson("v_row")};
end;
$$;
${serviceGrant(`${fn("ai_cache_get")}(text)`)}

-- Stores or replaces the entry under key for ttl seconds, at most ${maxTtl}.
create or replace function ${fn("ai_cache_set")}(key text, value jsonb, ttl integer, tenant ${id} default null, kind text default 'generate', model text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entries}%rowtype;
begin
  if ai_cache_set.ttl is null or ai_cache_set.ttl < 1 then
    ${raise("ttl must be at least one second", "22023", "AI_CACHE_INVALID")}
  end if;
  insert into ${entries} (${e.key}, ${e.tenant}, ${e.kind}, ${model ? `${col("model")}, ` : ""}${e.value}, ${e.expiresAt})
  values (ai_cache_set.key, ai_cache_set.tenant, ${ctx.cast("entries", "kind", "coalesce(ai_cache_set.kind, 'generate')")}, ${model ? "ai_cache_set.model, " : ""}ai_cache_set.value,
    now() + make_interval(secs => least(ai_cache_set.ttl, ${maxTtl})))
  on conflict (${e.key}) do update set
    ${e.tenant} = excluded.${e.tenant},
    ${e.kind} = excluded.${e.kind},${model ? `\n    ${col("model")} = excluded.${col("model")},` : ""}
    ${e.value} = excluded.${e.value},${resets.map((reset) => `\n    ${reset},`).join("")}
    ${e.expiresAt} = excluded.${e.expiresAt}
  returning * into v_row;
  return ${entryJson("v_row")} - '${ENTRIES.value}';
end;
$$;
${serviceGrant(`${fn("ai_cache_set")}(text, jsonb, integer, ${id}, text, text)`)}

-- Deletes one key, or every entry of a tenant (or with a model), and returns how many.
create or replace function ${fn("ai_cache_delete")}(key text default null, tenant ${id} default null, model text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if ai_cache_delete.key is null and ai_cache_delete.tenant is null and ai_cache_delete.model is null then
    ${raise("name a key, a tenant or a model", "22023", "AI_CACHE_INVALID")}
  end if;
  delete from ${entries} x
  where (ai_cache_delete.key is null or x.${e.key} = ai_cache_delete.key)
    and (ai_cache_delete.tenant is null or x.${e.tenant} = ai_cache_delete.tenant)
    and (ai_cache_delete.model is null or ${model ? `x.${col("model")} = ai_cache_delete.model` : "false"});
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("ai_cache_delete")}(text, ${id}, text)`)}

-- Deletes up to batch expired entries and returns how many; schedule it.
create or replace function ${fn("purge_ai_cache")}(batch integer default 5000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from ${entries} x
  where x.${e.key} in (
    select y.${e.key} from ${entries} y
    where y.${e.expiresAt} <= now()
    order by y.${e.expiresAt}
    limit least(greatest(purge_ai_cache.batch, 1), 50000)
    for update skip locked
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("purge_ai_cache")}(integer)`)}`;
}

export const AI_CACHE: BlockSqlDefinition = {
  name: "ai-cache",
  title: "AI response cache",
  description:
    "Model responses cached by a key the application derives from the request, with a TTL capped by maxTtl, hit counts and a purge of expired entries; only the service role reads and writes it.",
  requires: [],
  target: "schema",
  version: 1,
  names: NAMES,
  build,
};
