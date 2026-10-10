import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

export const requestHeader = (name: string): string =>
  `better_supabase.request_header(${sqlString(name)})`;

const traceId = (setting: string, header: string): string =>
  `coalesce(better_supabase.request_id_or_null(current_setting(${sqlString(setting)}, true)), better_supabase.request_id_or_null(${requestHeader(header)}))`;

export const requestIdSql = (ctx: ModuleContext): string =>
  traceId(
    "better_supabase.request_id",
    ctx.text("requestIdHeader", "x-request-id").toLowerCase(),
  );

export const correlationIdSql = (ctx: ModuleContext): string =>
  traceId(
    "better_supabase.correlation_id",
    ctx.text("correlationIdHeader", "x-correlation-id").toLowerCase(),
  );

export const REQUEST_ID_OR_NULL = `create or replace function better_supabase.request_id_or_null(value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when value ~ '^[A-Za-z0-9._:;,@/+=-]{1,128}$' then value end;
$$;`;
