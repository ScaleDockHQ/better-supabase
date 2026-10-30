import type { BlockSqlContext } from "../context.ts";
import type { HookNames } from "./webhooks-out-sql.ts";

import { fail } from "../shared.ts";
import { grants, guard, touched } from "./webhooks-out-sql.ts";

const VARIABLES = "#variable_conflict use_column";

type Kind = "text" | "boolean" | "texts" | "texts-or-null" | "object-or-null";

/** The endpoint fields a client may write, by logical column. */
const FIELDS: readonly (readonly [string, Kind])[] = [
  ["name", "text"],
  ["url", "text"],
  ["enabled", "boolean"],
  ["eventTypes", "texts"],
  ["permissions", "texts-or-null"],
  ["batch", "boolean"],
  ["signing", "text"],
  ["format", "text"],
  ["credentialRef", "object-or-null"],
];

/** The columns an endpoint reads back as, in this order. */
const READ = [
  "id",
  "tenant",
  "name",
  "url",
  "enabled",
  "eventTypes",
  "permissions",
  "batch",
  "signing",
  "format",
  "credentialRef",
  "failingSince",
  "disabledAt",
  "disabledReason",
  "createdBy",
  "createdAt",
  "updatedAt",
] as const;

const writable = (n: HookNames) =>
  FIELDS.filter(([logical]) => n.has("endpoints", logical));

/**
 * A SQL boolean that is true when `value` (a jsonb expression) is the wrong
 * shape.
 */
function invalidField(kind: Kind, value: string): string {
  const texts = `(jsonb_typeof(${value}) <> 'array' or exists (select 1 from jsonb_array_elements(${value}) a where jsonb_typeof(a) <> 'string'))`;

  switch (kind) {
    case "text": {
      return `jsonb_typeof(${value}) <> 'string'`;
    }

    case "boolean": {
      return `jsonb_typeof(${value}) <> 'boolean'`;
    }

    case "texts": {
      return texts;
    }

    case "texts-or-null": {
      return `(jsonb_typeof(${value}) <> 'null' and ${texts})`;
    }

    case "object-or-null": {
      return `jsonb_typeof(${value}) not in ('object', 'null')`;
    }

    default: {
      const unhandled: never = kind;

      throw new TypeError(`Unknown endpoint field kind ${String(unhandled)}`);
    }
  }
}

/** The column value for `key` in `fields` (a jsonb expression). */
function valueOf(kind: Kind, fields: string, key: string): string {
  const texts = `array(select jsonb_array_elements_text(${fields} -> '${key}'))`;

  switch (kind) {
    case "text": {
      return `${fields} ->> '${key}'`;
    }

    case "boolean": {
      return `(${fields} ->> '${key}')::boolean`;
    }

    case "texts": {
      return texts;
    }

    case "texts-or-null": {
      return `case when jsonb_typeof(${fields} -> '${key}') = 'null' then null else ${texts} end`;
    }

    case "object-or-null": {
      return `nullif(${fields} -> '${key}', 'null'::jsonb)`;
    }

    default: {
      const unhandled: never = kind;

      throw new TypeError(`Unknown endpoint field kind ${String(unhandled)}`);
    }
  }
}

/** Raises unless every key of `fields` is a writable field with a valid value. */
function checkFields(n: HookNames, fields: string): string {
  const cases = writable(n)
    .map(
      ([logical, kind]) =>
        `when '${logical}' then ${invalidField(kind, "e.value")}`,
    )
    .join(" ");

  return `if jsonb_typeof(coalesce(${fields}, '{}')) <> 'object' or exists (
    select 1 from jsonb_each(coalesce(${fields}, '{}')) e
    where case e.key ${cases} else true end
  ) then
    ${fail("WEBHOOK_ENDPOINT_INVALID", "A webhook endpoint field is unknown or has the wrong type", "22023")}
  end if;`;
}

/** Raises when `url` (a text expression) is not an allowed endpoint URL. */
function checkUrl(n: HookNames, url: string): string {
  const pattern = n.allowHttp ? "^https?://" : "^https://";

  return `if ${url} is null or ${url} !~* '${pattern}' then
    ${fail("WEBHOOK_ENDPOINT_URL", n.allowHttp ? "A webhook endpoint URL must start with http:// or https://" : "A webhook endpoint URL must start with https://", "22023")}
  end if;`;
}

/** `jsonb_build_object` of the endpoint row `d`, with the columns the table has. */
function endpointJson(n: HookNames): string {
  const pairs = READ.filter((logical) => n.has("endpoints", logical)).map(
    (logical) => `'${logical}', d.${n.col("endpoints", logical)}`,
  );

  return `jsonb_build_object(${pairs.join(", ")})`;
}

/**
 * `update ... set` for the writable `fields` (a jsonb expression) of endpoint
 * `id`: a key that is absent keeps the column.
 */
function applyFields(
  n: HookNames,
  fields: string,
  id: string,
  only?: readonly string[],
): string {
  const d = (logical: string) => n.col("endpoints", logical);

  const sets = writable(n)
    .filter(([logical]) => only === undefined || only.includes(logical))
    .map(
      ([logical, kind]) =>
        `${d(logical)} = case when ${fields} ? '${logical}' then ${valueOf(kind, fields, logical)} else d.${d(logical)} end`,
    );

  return `update ${n.table("endpoints")} d set ${sets.join(", ")}${touched(n, "endpoints")}
  where d.${d("id")} = ${id};`;
}

const OPTIONAL = [
  "permissions",
  "batch",
  "signing",
  "format",
  "credentialRef",
] as const;

function create(ctx: BlockSqlContext, n: HookNames): string {
  const fn = ctx.fn("create_webhook_endpoint");
  const d = (logical: string) => n.col("endpoints", logical);
  const fields = "create_webhook_endpoint.fields";
  const tenant = n.has("endpoints", "tenant");

  const columns: [string, string][] = [
    [d("url"), `${fields} ->> 'url'`],
    [d("enabled"), `coalesce((${fields} ->> 'enabled')::boolean, true)`],
    [
      d("eventTypes"),
      `coalesce(array(select jsonb_array_elements_text(${fields} -> 'eventTypes')), '{}')`,
    ],
  ];

  if (tenant) {
    columns.unshift([d("tenant"), "create_webhook_endpoint.tenant"]);
  }

  if (n.has("endpoints", "name")) {
    columns.push([d("name"), `${fields} ->> 'name'`]);
  }

  const optional = OPTIONAL.filter((logical) => n.has("endpoints", logical));

  const rest =
    optional.length === 0
      ? ""
      : `
  if ${fields} ?| array[${optional.map((logical) => `'${logical}'`).join(", ")}] then
    ${applyFields(n, fields, "v_id", optional)}
  end if;`;

  return `
-- Adds an endpoint to tenant, from fields such as {"url", "eventTypes",
-- "name"}; returns it. A field it leaves out gets the column default.
create or replace function ${fn}(tenant ${ctx.idType}, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  v_tenant ${ctx.idType} := create_webhook_endpoint.tenant;
  v_id uuid;
  v_endpoint jsonb;
begin
  ${guard(n, "v_tenant", "manage")}
  ${checkFields(n, fields)}
  ${checkUrl(n, `${fields} ->> 'url'`)}
  insert into ${n.table("endpoints")} (${columns.map(([column]) => column).join(", ")})
  values (${columns.map(([, value]) => value).join(", ")})
  returning ${d("id")} into v_id;${rest}
  select ${endpointJson(n)} into v_endpoint
  from ${n.table("endpoints")} d where d.${d("id")} = v_id;
  return v_endpoint;
end;
$$;
${grants(fn, `${ctx.idType}, jsonb`, true)}`;
}

/** Reads an endpoint's tenant into `v_tenant`, or raises when it doesn't exist. */
function findEndpoint(n: HookNames, id: string): string {
  const tenant = n.has("endpoints", "tenant")
    ? `d.${n.col("endpoints", "tenant")}`
    : "null";

  return `select ${tenant} into v_tenant
  from ${n.table("endpoints")} d where d.${n.col("endpoints", "id")} = ${id};
  if not found then
    ${fail("WEBHOOK_ENDPOINT_NOT_FOUND", "Webhook endpoint not found", "P0002")}
  end if;`;
}

function update(ctx: BlockSqlContext, n: HookNames): string {
  const fn = ctx.fn("update_webhook_endpoint");
  const d = (logical: string) => n.col("endpoints", logical);
  const fields = "update_webhook_endpoint.fields";

  return `
-- Changes the fields of an endpoint that fields names; returns it. Turning
-- enabled back on clears the failure streak.
create or replace function ${fn}(endpoint uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  v_tenant ${ctx.idType};
  v_endpoint jsonb;
begin
  ${findEndpoint(n, "update_webhook_endpoint.endpoint")}
  ${guard(n, "v_tenant", "manage")}
  ${checkFields(n, fields)}
  if ${fields} ? 'url' then
    ${checkUrl(n, `${fields} ->> 'url'`)}
  end if;
  ${applyFields(n, fields, "update_webhook_endpoint.endpoint")}
  select ${endpointJson(n)} into v_endpoint
  from ${n.table("endpoints")} d where d.${d("id")} = update_webhook_endpoint.endpoint;
  return v_endpoint;
end;
$$;
${grants(fn, "uuid, jsonb", true)}`;
}

function list(ctx: BlockSqlContext, n: HookNames): string {
  const fn = ctx.fn("list_webhook_endpoints");
  const d = (logical: string) => n.col("endpoints", logical);

  const where = n.has("endpoints", "tenant")
    ? `where d.${d("tenant")} = list_webhook_endpoints.tenant`
    : "";

  return `
-- The tenant's endpoints, newest first, without their secrets.
create or replace function ${fn}(tenant ${ctx.idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  v_tenant ${ctx.idType} := list_webhook_endpoints.tenant;
  v_endpoints jsonb;
begin
  ${guard(n, "v_tenant", "view")}
  select coalesce(jsonb_agg(${endpointJson(n)} order by d.${d("createdAt")} desc, d.${d("id")}), '[]')
  into v_endpoints
  from ${n.table("endpoints")} d
  ${where};
  return v_endpoints;
end;
$$;
${grants(fn, ctx.idType, true)}`;
}

function remove(ctx: BlockSqlContext, n: HookNames): string {
  const fn = ctx.fn("delete_webhook_endpoint");

  return `
-- Deletes an endpoint with its secrets and deliveries.
create or replace function ${fn}(endpoint uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
${VARIABLES}
declare
  v_tenant ${ctx.idType};
begin
  ${findEndpoint(n, "delete_webhook_endpoint.endpoint")}
  ${guard(n, "v_tenant", "manage")}
  delete from ${n.table("endpoints")} d
  where d.${n.col("endpoints", "id")} = delete_webhook_endpoint.endpoint;
  return true;
end;
$$;
${grants(fn, "uuid", true)}`;
}

/** `create_`, `update_`, `list_` and `delete_webhook_endpoint(s)`. */
export function endpointFunctions(ctx: BlockSqlContext, n: HookNames): string {
  return [create(ctx, n), update(ctx, n), list(ctx, n), remove(ctx, n)].join(
    "\n",
  );
}
