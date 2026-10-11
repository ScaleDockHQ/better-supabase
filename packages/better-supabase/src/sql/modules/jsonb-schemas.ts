import type { SqlModule } from "../module-types.ts";

import { jsonSchemaChecks, SCHEMA } from "../shared.ts";

export const JSONB_SCHEMAS: SqlModule = {
  name: "jsonb-schemas",
  title: "JSON Schema checks for jsonb",
  description:
    "pg_jsonschema check constraints for jsonb columns with a `schema` in the `json` config, so the database enforces the same shape as the types. A trigger reports what failed through jsonschema_validation_errors, which the client maps to a validation error.",
  requires: [],
  target: "schema",
  sql: `create extension if not exists pg_jsonschema with schema extensions;

${SCHEMA}

-- check_json_schema(column, schema[, where_column, where_value]) runs before the
-- check constraint of the same name and raises 23514 with the schema errors as
-- a JSON array in DETAIL and the hint JSON_SCHEMA_INVALID. A SQL null passes,
-- as it does for the check.
create or replace function better_supabase.check_json_schema()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  row_data jsonb := to_jsonb(new);
  value jsonb;
  errors text[];
begin
  if tg_nargs > 2 and row_data ->> tg_argv[2] is distinct from tg_argv[3] then
    return new;
  end if;
  value := row_data -> tg_argv[0];
  if value is null or jsonb_typeof(value) = 'null' then
    return new;
  end if;
  errors := extensions.jsonschema_validation_errors(tg_argv[1]::json, value::json);
  if cardinality(errors) > 0 then
    raise exception '%.% does not match its JSON Schema: %',
      tg_table_name, tg_argv[0], array_to_string(errors, '; ')
      using errcode = '23514',
        constraint = tg_name,
        schema = tg_table_schema,
        table = tg_table_name,
        column = tg_argv[0],
        detail = to_jsonb(errors)::text,
        hint = 'JSON_SCHEMA_INVALID';
  end if;
  return new;
end;
$$;

revoke execute on function better_supabase.check_json_schema() from public, anon, authenticated;`,
  extras: (_ctx, layout) => jsonSchemaChecks(layout.jsonSchemas ?? []),
};
