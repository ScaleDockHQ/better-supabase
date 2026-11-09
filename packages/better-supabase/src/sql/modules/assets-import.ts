import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { fail, lockTable, serviceGrant } from "../shared.ts";

const plain = (qualified: string): string => qualified.replaceAll('"', "");

/** Asset and identifier import targets. */
export function assetImportSql(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const assets = ctx.table("assets");
  const s = (column: string): string => ctx.col("assets", column);
  const identifiers = `${ctx.schema}.${ctx.tableName("identifiers").name}`;
  const i = (column: string): string => ctx.col("identifiers", column);
  const qualify = (name: string): string => ctx.fnName(name);
  const fn = (name: string): string => ctx.fn(name);

  const set = (logical: string, expr: string): string =>
    ctx.has("assets", logical)
      ? `, ${s(logical)} = coalesce(${expr}, x.${s(logical)})`
      : "";

  return `
create table if not exists ${identifiers} (
  "id" uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,
  ${i("asset")} uuid not null references ${assets} (${s("id")}) on delete cascade,
  "type" text not null,
  "value" text not null,
  "updated_at" timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("asset_identifiers_asset_idx")} on ${identifiers} (${i("asset")});
${lockTable(identifiers)}
create unique index if not exists ${ctx.naming.rename("asset_identifiers_key")} on ${identifiers} (${i("tenant")}, ${i("type")}, ${i("value")});

create or replace function ${fn("import_asset")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := ${qualify("import_asset")}.item -> 'data';
  v_tenant ${ctx.idType} := (${qualify("import_asset")}.item ->> 'tenant')::${ctx.idType};
  v_id uuid := nullif(${qualify("import_asset")}.subject_id, '')::uuid;
  v_updated timestamptz;
begin
  if jsonb_typeof(v_data) is distinct from 'object' or nullif(btrim(v_data ->> 'name'), '') is null then
    ${fail("IMPORT_ITEM_INVALID", "an asset needs a name", "22023")}
  end if;
  if v_id is null then
    insert into ${assets} (${s("tenant")}, ${s("kind")}, ${s("name")}${ctx.has("assets", "make") ? `, ${s("make")}` : ""}${ctx.has("assets", "model") ? `, ${s("model")}` : ""}${ctx.has("assets", "ownership") ? `, ${s("ownership")}` : ""})
    values (v_tenant, coalesce(nullif(v_data ->> 'kind', ''), 'asset'), btrim(v_data ->> 'name')${ctx.has("assets", "make") ? `, nullif(btrim(v_data ->> 'make'), '')` : ""}${ctx.has("assets", "model") ? `, nullif(btrim(v_data ->> 'model'), '')` : ""}${ctx.has("assets", "ownership") ? `, nullif(v_data ->> 'ownership', '')` : ""})
    returning ${s("id")}, ${s("updatedAt")} into v_id, v_updated;
  else
    update ${assets} x set ${s("name")} = btrim(v_data ->> 'name')${set("make", "nullif(btrim(v_data ->> 'make'), '')")}${set("model", "nullif(btrim(v_data ->> 'model'), '')")}${set("ownership", "nullif(v_data ->> 'ownership', '')")}, ${s("updatedAt")} = now()
    where x.${s("id")} = v_id and x.${s("tenant")} = v_tenant
    returning x.${s("updatedAt")} into v_updated;
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_asset")}(uuid, jsonb, text)`)}

create or replace function ${fn("asset_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${s("updatedAt")} from ${assets} x where x.${s("id")}::text = ${qualify("asset_updated_at")}.subject_id
$$;
${serviceGrant(`${fn("asset_updated_at")}(text)`)}

create or replace function ${fn("import_asset_identifier")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := ${qualify("import_asset_identifier")}.item -> 'data';
  v_asset uuid := nullif(coalesce(${qualify("import_asset_identifier")}.item -> 'resolved' ->> 'asset', v_data ->> 'assetId'), '')::uuid;
  v_id uuid;
  v_updated timestamptz;
begin
  if v_asset is null or nullif(btrim(v_data ->> 'type'), '') is null or nullif(btrim(v_data ->> 'value'), '') is null then
    ${fail("IMPORT_ITEM_INVALID", "an identifier needs an asset, a type and a value", "22023")}
  end if;
  insert into ${identifiers} (${i("tenant")}, ${i("asset")}, ${i("type")}, ${i("value")})
  values ((${qualify("import_asset_identifier")}.item ->> 'tenant')::${ctx.idType}, v_asset, btrim(v_data ->> 'type'), btrim(v_data ->> 'value'))
  on conflict (${i("tenant")}, ${i("type")}, ${i("value")}) do update set ${i("asset")} = excluded.${i("asset")}, ${i("updatedAt")} = now()
  returning "id", "updated_at" into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_asset_identifier")}(uuid, jsonb, text)`)}

create or replace function ${fn("asset_identifier_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${i("updatedAt")} from ${identifiers} x where x.${i("id")}::text = ${qualify("asset_identifier_updated_at")}.subject_id
$$;
${serviceGrant(`${fn("asset_identifier_updated_at")}(text)`)}
`;
}

/** Asset import targets. */
export function assetImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  if (own.mode === "custom") {
    return [];
  }

  return [
    {
      entity: "asset",
      subjectType: "asset",
      write: plain(own.fn("import_asset")),
      updatedAt: plain(own.fn("asset_updated_at")),
    },
    {
      entity: "asset_identifier",
      subjectType: "asset_identifier",
      write: plain(own.fn("import_asset_identifier")),
      updatedAt: plain(own.fn("asset_identifier_updated_at")),
      refs: { asset: "asset" },
    },
  ];
}
