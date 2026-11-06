import type { BlockSqlContext } from "../context.ts";
import type { TemplateType } from "./templates-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, serviceGrant, triggerGrant, userGrant } from "../shared.ts";
import { templateTypes } from "./templates-types.ts";

/**
 * The rows-template functions: a type check for `save_template`, and
 * `instantiate_template`, `pack_template`, `unpack_template`, `clone_row` and
 * `template_table`. Empty when no type is registered and nothing else asks,
 * except `clone_row` and `template_table`, which the `@bsb template` tag
 * calls.
 */
export function templateRowsSql(ctx: BlockSqlContext): string {
  const types = templateTypes(ctx);
  const fn = (name: string): string => ctx.fn(name);

  return `${cloneRowSql(fn)}${templateTableSql(ctx, fn)}${types.length === 0 ? "" : typedSql(ctx, types, fn)}`;
}

/** The statement `save_template` runs to refuse an unregistered type. */
export function templateTypeCheck(ctx: BlockSqlContext): string {
  const types = templateTypes(ctx);

  if (types.length === 0) {
    return "";
  }

  const known = types.map((item) => sqlString(item.type)).join(", ");

  const settings = settingsCheck(ctx, types);

  return `
  if save_template.template_id is null and save_template.type not in (${known}) then
    ${fail("TEMPLATE_TYPE_UNKNOWN", "That template type is not registered", "22023")}
  end if;${settings}`;
}

function settingsCheck(
  ctx: BlockSqlContext,
  types: readonly TemplateType[],
): string {
  const checked = types.filter((item) => item.settings !== undefined);

  if (checked.length === 0 || !ctx.installed("jsonb-schemas")) {
    return "";
  }

  const branches = checked
    .map(
      (item) =>
        `when ${sqlString(item.type)} then ${sqlString(JSON.stringify(item.settings))}::json`,
    )
    .join(" ");

  return `
  if save_template.settings is not null then
    declare
      v_schema json := case coalesce(save_template.type, v_row.${ctx.col("templates", "type")}) ${branches} else null end;
      v_errors jsonb;
    begin
      if v_schema is not null then
        v_errors := extensions.jsonschema_validation_errors(v_schema, save_template.settings::json);
        if v_errors <> '[]'::jsonb then
          ${fail("TEMPLATE_SETTINGS_INVALID", "settings does not match this template type", "23514")}
        end if;
      end if;
    end;
  end if;`;
}

function typedSql(
  ctx: BlockSqlContext,
  types: readonly TemplateType[],
  fn: (name: string) => string,
): string {
  const id = ctx.idType;
  const rows = types.filter((item) => item.storage === "rows");

  return `${instantiateSql(ctx, types, fn, id)}${packSql(ctx, rows, fn)}${unpackSql(ctx, rows, fn, id)}`;
}

function instantiateSql(
  ctx: BlockSqlContext,
  types: readonly TemplateType[],
  fn: (name: string) => string,
  id: string,
): string {
  const branches = types
    .map((item) =>
      item.storage === "body"
        ? `when ${sqlString(item.type)} then
    return ${fn("template_apply_target")}(instantiate_template.template, instantiate_template.tenant);`
        : `when ${sqlString(item.type)} then
    ${rowsBranch(ctx, item)}`,
    )
    .join("\n    ");

  return `
-- Creates a record from a template: a body template returns its published
-- version, a rows template clones its root row into a live record. Writes
-- template_applications either way. templates.apply in tenant.
create or replace function ${fn("instantiate_template")}(template uuid, tenant ${id}, overrides jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tpl record;
  v_version record;
  v_source uuid;
  v_overrides jsonb;
  v_created jsonb;
  v_type text;
  v_subject text;
  v_id text;
  v_key text;
  v_value text;
begin
  if instantiate_template.tenant is null then
    ${fail("TEMPLATE_INVALID", "Applying a template needs a tenant", "22023")}
  end if;
  select * into v_tpl from ${ctx.table("templates")} x where x.${ctx.col("templates", "id")} = instantiate_template.template;
  if not found then
    ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
  end if;
  v_type := v_tpl.${ctx.col("templates", "type")};
  select * into v_version from ${ctx.table("versions")} y
    where y.${ctx.col("versions", "template")} = v_tpl.${ctx.col("templates", "id")} and y.${ctx.col("versions", "publishedAt")} is not null
    order by y.${ctx.col("versions", "version")} desc limit 1;
  if not found then
    ${fail("TEMPLATE_NOT_PUBLISHED", "This template has no published version", "P0002")}
  end if;
  v_overrides := coalesce(instantiate_template.overrides, '{}'::jsonb);
  ${applyRules(ctx, types)}
  case v_type
    ${branches}
    else
      ${fail("TEMPLATE_TYPE_UNKNOWN", "That template type is not registered", "22023")}
  end case;
  return ${fn("record_template_application")}(v_tpl.${ctx.col("templates", "id")}, v_version.${ctx.col("versions", "id")}, instantiate_template.tenant, v_subject, v_id);
end;
$$;
${userGrant(`${fn("instantiate_template")}(uuid, ${id}, jsonb)`)}
`;
}

function rowsBranch(ctx: BlockSqlContext, item: TemplateType): string {
  const table = quoted(item.table ?? "");
  const id = sqlIdent(item.idColumn);
  const template = sqlIdent(item.templateColumn ?? "template_id");
  const templateId = `v_tpl.${ctx.col("templates", "id")}`;

  return `select ${id} into v_source from ${table} r where r.${template} = ${templateId};
    if not found then
      ${fail("TEMPLATE_EMPTY", "This template has no record to copy", "P0002")}
    end if;
    v_created := ${item.clone}(v_source, v_overrides);
    v_subject := ${sqlString(item.subject ?? item.type)};
    v_id := v_created ->> 'id';`;
}

/** Relative dates and `{{name}}` substitution, from the type's rules. */
function applyRules(
  ctx: BlockSqlContext,
  types: readonly TemplateType[],
): string {
  const settings = ctx.has("templates", "settings")
    ? `v_tpl.${ctx.col("templates", "settings")}`
    : "'{}'::jsonb";

  return types
    .flatMap((item) => {
      const dates = item.rules?.dates ?? [];
      const variables = item.rules?.variables ?? [];

      if (dates.length === 0 && variables.length === 0) {
        return [];
      }

      const dated = dates
        .map((date) => {
          const base =
            date.from === "now"
              ? "now()"
              : `coalesce((v_overrides ->> ${sqlString(date.from)})::timestamptz, now())`;

          return `v_overrides := v_overrides || jsonb_build_object(${sqlString(date.column)}, to_char(${base} + make_interval(days => coalesce((${settings} ->> ${sqlString(date.days)})::integer, 0)), 'YYYY-MM-DD"T"HH24:MI:SSOF'));`;
        })
        .join("\n      ");

      const substituted = variables
        .map((column) =>
          `for v_key, v_value in select * from jsonb_each_text(coalesce(v_overrides -> 'variables', '{}'::jsonb)) loop
        v_overrides := jsonb_set(v_overrides, array[${sqlString(column)}], to_jsonb(replace(coalesce(v_overrides ->> ${sqlString(column)}, ''), '{{' || v_key || '}}', v_value)));
      end loop;`.replace(
            "for v_key, v_value in select * from jsonb_each_text",
            "for v_key, v_value in select key, value from jsonb_each_text",
          ),
        )
        .join("\n      ");

      return `if v_type = ${sqlString(item.type)} then
      ${dated}
      ${substituted}
    end if;`;
    })
    .join("\n  ");
}

function packSql(
  ctx: BlockSqlContext,
  rows: readonly TemplateType[],
  fn: (name: string) => string,
): string {
  if (rows.length === 0) {
    return "";
  }

  const branches = rows
    .map(
      (item) =>
        `when ${sqlString(item.type)} then\n      ${packBranch(ctx, item)}`,
    )
    .join("\n    ");

  return `
-- Snapshots a rows template (its root row, children and extension) into the
-- template's draft version, which publish_template_version then publishes.
create or replace function ${fn("pack_template")}(template uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tpl record;
  v_root record;
  v_body jsonb;
begin
  select * into v_tpl from ${ctx.table("templates")} x where x.${ctx.col("templates", "id")} = pack_template.template;
  if not found then
    ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
  end if;
  case v_tpl.${ctx.col("templates", "type")}
    ${branches}
    else
      ${fail("TEMPLATE_TYPE_UNKNOWN", "That template type is not packed from rows", "22023")}
  end case;
  return ${fn("save_template_draft")}(v_tpl.${ctx.col("templates", "id")}, v_body);
end;
$$;
${userGrant(`${fn("pack_template")}(uuid)`)}
`;
}

function packBranch(ctx: BlockSqlContext, item: TemplateType): string {
  const table = quoted(item.table ?? "");
  const id = sqlIdent(item.idColumn);
  const template = sqlIdent(item.templateColumn ?? "");
  const templateId = `v_tpl.${ctx.col("templates", "id")}`;

  const children = (item.children ?? [])
    .map(
      (child) =>
        `coalesce((select jsonb_agg(to_jsonb(c)) from ${quoted(child.table)} c where c.${sqlIdent(child.parent)} = v_root.${id}), '[]'::jsonb)`,
    )
    .join(", ");

  const extension =
    item.extension === undefined
      ? "null"
      : `coalesce((select to_jsonb(e) from ${quoted(item.extension)} e where e.template_id = ${templateId}), 'null'::jsonb)`;

  return `select * into v_root from ${table} r where r.${template} = ${templateId};
    if not found then
      ${fail("TEMPLATE_EMPTY", "This template has no record to pack", "P0002")}
    end if;
    v_body := jsonb_build_object('table', ${sqlString(item.table ?? "")}, 'row', to_jsonb(v_root), 'children', jsonb_build_array(${children === "" ? "" : children}), 'extension', ${extension});`;
}

function unpackSql(
  ctx: BlockSqlContext,
  rows: readonly TemplateType[],
  fn: (name: string) => string,
  id: string,
): string {
  if (rows.length === 0) {
    return "";
  }

  const branches = rows
    .map(
      (item) => `when ${sqlString(item.type)} then
      perform ${fn("clone_row")}(${sqlString(item.table ?? "")}::regclass, (v_body -> 'row' ->> 'id')::uuid, jsonb_build_object('template_id', unpack_template.template));`,
    )
    .join("\n    ");

  return `
-- Materializes a packed body back into tenant rows owned by template.
create or replace function ${fn("unpack_template")}(template uuid, version uuid, tenant ${id})
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tpl record;
  v_body jsonb;
begin
  select * into v_tpl from ${ctx.table("templates")} x where x.${ctx.col("templates", "id")} = unpack_template.template;
  if not found then
    ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
  end if;
  select y.${ctx.col("versions", "body")} into v_body from ${ctx.table("versions")} y
    where y.${ctx.col("versions", "id")} = unpack_template.version and y.${ctx.col("versions", "template")} = v_tpl.${ctx.col("templates", "id")};
  if v_body is null or v_body -> 'row' is null then
    ${fail("TEMPLATE_NOT_PUBLISHED", "That version has no packed rows", "P0002")}
  end if;
  case v_tpl.${ctx.col("templates", "type")}
    ${branches}
    else
      ${fail("TEMPLATE_TYPE_UNKNOWN", "That template type is not unpacked into rows", "22023")}
  end case;
  return unpack_template.template;
end;
$$;
${userGrant(`${fn("unpack_template")}(uuid, uuid, ${id})`)}
`;
}

/**
 * Copies one row and the rows that reference it, clearing `template_id` unless
 * overrides sets it, and recording `source_template_id` when the source is a
 * template. Used by app tables tagged `@bsb template`.
 */
function cloneRowSql(fn: (name: string) => string): string {
  return `
create or replace function ${fn("clone_row")}(target regclass, source uuid, overrides jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_new uuid := gen_random_uuid();
  v_template uuid;
  v_cols text;
  v_vals text;
  v_child record;
begin
  execute format('select to_jsonb(t) from %s t where t.id = $1', target) into v_row using source;
  if v_row is null then
    ${fail("TEMPLATE_NOT_FOUND", "No such row", "P0002")}
  end if;
  v_template := nullif(v_row ->> 'template_id', '')::uuid;
  v_row := v_row || coalesce(overrides, '{}'::jsonb) || jsonb_build_object('id', v_new);
  if not (coalesce(overrides, '{}'::jsonb) ? 'template_id') then
    v_row := v_row || jsonb_build_object('template_id', null);
  end if;
  if v_template is not null and not (coalesce(overrides, '{}'::jsonb) ? 'source_template_id') then
    v_row := v_row || jsonb_build_object('source_template_id', v_template);
  end if;
  select string_agg(format('%I', key), ', '), string_agg(format('%L', value), ', ')
    into v_cols, v_vals
    from jsonb_each_text(v_row);
  execute format('insert into %s (%s) values (%s)', target, v_cols, v_vals);
  for v_child in
    select c.conrelid::regclass as child, a.attname as parent
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.confrelid = target and c.contype = 'f' and c.conrelid <> target
  loop
    execute format(
      'insert into %s select (jsonb_populate_record(null::%s, to_jsonb(x) || jsonb_build_object(%L, $1, ''id'', gen_random_uuid()))).* from %s x where x.%I = $2',
      v_child.child, v_child.child, v_child.parent, v_child.child, v_child.parent
    ) using v_new, source;
  end loop;
  return v_new;
end;
$$;
${serviceGrant(`${fn("clone_row")}(regclass, uuid, jsonb)`)}
`;
}

/** Adds the template columns and the immutability trigger to an app table. */
function templateTableSql(
  ctx: BlockSqlContext,
  fn: (name: string) => string,
): string {
  const templates = ctx.table("templates");

  return `
create or replace function ${fn("template_table")}(target regclass)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  execute format('alter table %s add column if not exists template_id uuid unique references ${templates} (id) on delete cascade', target);
  execute format('alter table %s add column if not exists source_template_id uuid references ${templates} (id) on delete set null', target);
  execute format('drop trigger if exists bsb_template_row on %s', target);
  execute format('create trigger bsb_template_row before update of template_id on %s for each row execute function ${fn("template_row_guard")}()', target);
end;
$$;
${serviceGrant(`${fn("template_table")}(regclass)`)}

create or replace function ${fn("template_row_guard")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.template_id is distinct from old.template_id then
    ${fail("TEMPLATE_IMMUTABLE", "A row cannot change between a template and a live record", "23514")}
  end if;
  return new;
end;
$$;
${triggerGrant(`${fn("template_row_guard")}()`)}
`;
}

/** After a fork, materialize a rows template's packed body into tenant rows. */
export function forkUnpackSql(ctx: BlockSqlContext): string {
  const rows = templateTypes(ctx).filter((item) => item.storage === "rows");

  if (rows.length === 0) {
    return "";
  }

  const known = rows.map((item) => sqlString(item.type)).join(", ");

  return `
  if v_row.${ctx.col("templates", "type")} in (${known}) then
    perform ${ctx.fn("unpack_template")}(v_row.${ctx.col("templates", "id")}, (select y.${ctx.col("versions", "id")} from ${ctx.table("versions")} y where y.${ctx.col("versions", "template")} = v_row.${ctx.col("templates", "id")} and y.${ctx.col("versions", "version")} = 1), fork_template.tenant);
  end if;`;
}

function quoted(table: string): string {
  const [schema, name] = table.includes(".")
    ? table.split(".")
    : ["public", table];

  return `${sqlIdent(schema ?? "public")}.${sqlIdent(name ?? table)}`;
}
