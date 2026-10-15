import type { ImportsEvents } from "../../blocks/imports/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { fail, lockTable, schemaPreamble, userGrant } from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";

const EVENTS: ModuleEvents<ImportsEvents> = {
  "import.completed": {
    subject: "imports",
    payload: ["organizationId", "id", "count"],
  },
  "import.failed": {
    subject: "imports",
    payload: ["organizationId", "id", "error"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  tables: {
    runs: {
      name: "import_runs",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        status: "status",
        mapping: "mapping",
        counts: "counts",
        errors: "errors",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
  },
};

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const runs = ctx.table("runs");
  const manage = ctx.permission("manage", OPERATIONS["imports.manage"]);
  const tables = ctx.manages
    ? `create table if not exists ${runs} (
  ${ctx.col("runs", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("runs", "tenant")} ${ctx.idType} not null,
  ${ctx.col("runs", "kind")} text not null,
  ${ctx.col("runs", "status")} text not null default 'pending' check (${ctx.col("runs", "status")} in ('pending', 'running', 'completed', 'failed')),
  ${ctx.col("runs", "mapping")} jsonb not null default '{}'::jsonb,
  ${ctx.col("runs", "counts")} jsonb not null default '{}'::jsonb,
  ${ctx.col("runs", "errors")} jsonb not null default '[]'::jsonb,
  ${ctx.col("runs", "createdBy")} uuid,
  ${ctx.col("runs", "createdAt")} timestamptz not null default now()
);
${lockTable(runs, { read: true })}
`
    : "";
  return `${schemaPreamble(ctx)}
${tables}
create or replace function ${ctx.fn("start_import")}(tenant ${ctx.idType}, kind text, mapping jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', start_import.tenant, ${manage}), false)) then
    ${fail("IMPORT_FORBIDDEN", "not allowed to import")}
  end if;
  insert into ${runs} (${ctx.col("runs", "tenant")}, ${ctx.col("runs", "kind")}, ${ctx.col("runs", "mapping")}, ${ctx.col("runs", "createdBy")})
  values (start_import.tenant, start_import.kind, coalesce(start_import.mapping, '{}'::jsonb), auth.uid())
  returning ${ctx.col("runs", "id")} into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${ctx.fn("start_import")}(${ctx.idType}, text, jsonb)`)}

create or replace function ${ctx.fn("finish_import")}(id uuid, status text, count integer, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
begin
  update ${runs} set ${ctx.col("runs", "status")} = finish_import.status,
    ${ctx.col("runs", "counts")} = jsonb_build_object('imported', finish_import.count),
    ${ctx.col("runs", "errors")} = case when finish_import.error is null then '[]'::jsonb else jsonb_build_array(finish_import.error) end
  where ${ctx.col("runs", "id")} = finish_import.id
  returning ${ctx.col("runs", "tenant")} into v_tenant;
  if not found then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if finish_import.status = 'failed' then
    ${ctx.record({
      type: "import.failed",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', finish_import.id, 'error', finish_import.error)`,
      subject: `'imports/' || finish_import.id::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  else
    ${ctx.record({
      type: "import.completed",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', finish_import.id, 'count', finish_import.count)`,
      subject: `'imports/' || finish_import.id::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  end if;
  return true;
end;
$$;
revoke execute on function ${ctx.fn("finish_import")}(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function ${ctx.fn("finish_import")}(uuid, text, integer, text) to service_role;
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "start_import", args: ["{id}", "text", "jsonb"], returns: "jsonb" },
    {
      name: "finish_import",
      args: ["uuid", "text", "integer", "text"],
      returns: "boolean",
    },
  ];
}

export const IMPORTS: ModuleDefinition = {
  name: "imports",
  title: "Imports",
  description:
    "Import runs. Parsing, mapping and the dry run live in TypeScript. The job records import.completed or import.failed.",
  requires: ["tenant", "access", "jobs"],
  integrates: ["attachments", "outbox"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
