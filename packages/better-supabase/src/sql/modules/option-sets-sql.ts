import type { BlockSqlContext } from "../context.ts";
import type { BrandSource } from "./brand-source.ts";
import type { ItemTemplate, OptionBinding } from "./option-sets-bindings.ts";

import { rankKeys } from "../../core/rank-keys.ts";
import { subjectTypeIdent } from "../../core/subject-type.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { createdOrUpdated } from "../event-verbs.ts";
import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import { fail, userGrant } from "../shared.ts";
import { byField, templateRows } from "./option-sets-bindings.ts";

/** The names a module's SQL reads its tables and columns by. */
export interface OptionNames {
  readonly idType: string;
  readonly read: string;
  readonly manage: string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
}

/** One `insert` of the items a set starts with. */
function itemInsert(
  names: OptionNames,
  items: readonly ItemTemplate[],
): string {
  const { t, c } = names;
  const i = (column: string): string => c("items", column);

  return `insert into ${t("items")} (${i("tenant")}, ${i("set")}, ${i("key")}, ${i("systemKey")}, ${i("label")}, ${i("color")}, ${i("icon")}, ${i("rank")}, ${i("level")})
      select default_option_set.tenant, v_id, x.key, x.key, x.label, x.color, x.icon, x.rank, x.level
      from (values
          ${templateRows(items, rankKeys(items.length))}
      ) x(key, label, level, color, icon, rank);`;
}

/**
 * The default option set of a field in a tenant and scope. The first call
 * creates it from the binding's item template, or from the template of the
 * tenant's brand when `options.brand` is set and the binding has one.
 */
export function defaultSet(
  ctx: BlockSqlContext,
  names: OptionNames,
  bindings: readonly OptionBinding[],
  brand: BrandSource | undefined,
): string {
  const { t, c, idType } = names;
  const self = ctx.fn("default_option_set");
  const s = (column: string): string => c("sets", column);

  const seed = (binding: OptionBinding): string => {
    const brands = Object.entries(binding.brands);

    if (brands.length > 0 && brand === undefined) {
      throw new TypeError(
        `blocks.${ctx.instance}.on.${binding.type}.${binding.field}.brands needs blocks.${ctx.instance}.options.brand`,
      );
    }

    const items =
      brand === undefined || brands.length === 0
        ? itemInsert(names, binding.items)
        : `v_brand := (select b.${brand.column}::text from ${brand.table} b where b.${brand.tenant}::text = default_option_set.tenant::text limit 1);
      ${brands
        .map(
          ([name, list], index) =>
            `${index === 0 ? "if" : "elsif"} v_brand = ${sqlString(name)} then
      ${itemInsert(names, list)}`,
        )
        .join("\n      ")}
      else
      ${itemInsert(names, binding.items)}
      end if;`;

    return `      insert into ${t("sets")} (${s("tenant")}, ${s("subjectType")}, ${s("field")}, ${s("scope")}, ${s("key")}, ${s("name")}, ${s("isDefault")})
      values (default_option_set.tenant, default_option_set.subject_type, default_option_set.field, default_option_set.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning ${s("id")} into v_id;
      if v_id is null then
        select x.${s("id")} into v_id from ${t("sets")} x
        where x.${s("tenant")} = default_option_set.tenant
          and x.${s("subjectType")} = default_option_set.subject_type
          and x.${s("field")} = default_option_set.field
          and x.${s("scope")} is not distinct from default_option_set.scope_id
          and x.${s("archivedAt")} is null
        order by x.${s("isDefault")} desc, x.${s("createdAt")}, x.${s("id")}
        limit 1;
        if v_id is null then
          ${fail("OPTION_SET_UNAVAILABLE", "the default option set of this field is archived", "55000")}
        end if;
        return v_id;
      end if;
      ${items}`;
  };

  return `
-- The default option set of a field in a tenant and scope. The first call
-- creates it from the field's item template in on.
create or replace function ${self}(tenant ${idType}, subject_type text, field text, scope_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_brand text;
begin
  select x.${s("id")} into v_id from ${t("sets")} x
  where x.${s("tenant")} = default_option_set.tenant
    and x.${s("subjectType")} = default_option_set.subject_type
    and x.${s("field")} = default_option_set.field
    and x.${s("scope")} is not distinct from default_option_set.scope_id
    and x.${s("archivedAt")} is null
  order by x.${s("isDefault")} desc, x.${s("createdAt")}, x.${s("id")}
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  ${byField(
    "default_option_set.subject_type",
    "default_option_set.field",
    bindings,
    seed,
    fail(
      "OPTION_SET_FIELD_UNKNOWN",
      "this field has no option set binding",
      "22023",
    ),
  )}
  return v_id;
end;
$$;
revoke execute on function ${self}(${idType}, text, text, text) from public, anon, authenticated;
grant execute on function ${self}(${idType}, text, text, text) to service_role;
`;
}

/**
 * The before trigger on one bound table. Choosing an item writes its level to
 * the level column; with `follow`, writing the level column picks the first
 * item at that level.
 */
export function levelTrigger(
  ctx: BlockSqlContext,
  names: OptionNames,
  binding: OptionBinding,
): string {
  const { t, c } = names;
  const subject = binding.subject;
  const level = sqlIdent(binding.column);
  const option = sqlIdent(binding.option);
  const tenant = `new.${subject.tenant ?? ""}`;

  const scope =
    binding.scope === undefined
      ? "null"
      : `new.${sqlIdent(binding.scope)}::text`;

  const name = `bsb_option_${subjectTypeIdent(binding.type)}_${binding.field}`;
  const i = (column: string): string => c("items", column);
  const s = (column: string): string => c("sets", column);

  const follow = binding.follow
    ? `
  elsif new.${level} is not null and (new.${option} is null or tg_op = 'UPDATE' and new.${level} is distinct from old.${level}) then
    if new.${option} is null or not exists (
      select 1 from ${t("items")} x where x.${i("id")} = new.${option} and x.${i("level")} = new.${level}
    ) then
      select x.${i("id")} into new.${option} from ${t("items")} x
      where x.${i("set")} = ${ctx.fn("default_option_set")}(${tenant}, ${sqlString(binding.type)}, ${sqlString(binding.field)}, ${scope})
        and x.${i("archivedAt")} is null and x.${i("level")} = new.${level}
      order by x.${i("rank")} collate "C", x.${i("id")}
      limit 1;
    end if;`
    : "";

  return `
create or replace function better_supabase.${name}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_level integer;
begin
  if tg_op = 'UPDATE' and new.${option} is not distinct from old.${option} and new.${level} is not distinct from old.${level} then
    return new;
  end if;
  if new.${option} is not null and (tg_op = 'INSERT' or new.${option} is distinct from old.${option}) then
    select x.${i("level")} into v_level
    from ${t("items")} x
    join ${t("sets")} y on y.${s("id")} = x.${i("set")}
    where x.${i("id")} = new.${option}
      and x.${i("archivedAt")} is null
      and y.${s("archivedAt")} is null
      and y.${s("tenant")}::text = ${tenant}::text
      and y.${s("subjectType")} = ${sqlString(binding.type)}
      and y.${s("field")} = ${sqlString(binding.field)}
      and y.${s("scope")} is not distinct from ${scope};
    if not found then
      ${fail("OPTION_SET_ITEM_INVALID", "the item is not an active item of this record's option set", "22023")}
    end if;
    new.${level} := v_level;${follow}
  end if;
  return new;
end;
$$;
drop trigger if exists ${name} on ${subject.qualified};
create trigger ${name} before insert or update of ${level}, ${option} on ${subject.qualified}
for each row execute function better_supabase.${name}();
`;
}

/** The column the chosen item lives in, added to a bound table. */
export function optionColumn(
  names: OptionNames,
  binding: OptionBinding,
): string {
  const option = sqlIdent(binding.option);

  const index = sqlIdent(
    `bsb_${subjectTypeIdent(binding.type)}_${binding.option}_idx`,
  );

  return `alter table ${binding.subject.qualified} add column if not exists ${option} uuid references ${names.t("items")} (${names.c("items", "id")}) on delete set null;
create index if not exists ${index} on ${binding.subject.qualified} (${option});`;
}

/** The SQL functions that edit and read option sets. */
export function setFunctions(
  ctx: BlockSqlContext,
  names: OptionNames,
  bindings: readonly OptionBinding[],
): string {
  const { t, c, idType } = names;
  const fn = (name: string): string => ctx.fn(name);
  const s = (column: string): string => c("sets", column);
  const i = (column: string): string => c("items", column);

  const guard = (
    tenant: string,
    permission: string,
    code: string,
    message: string,
  ): string => `if not (auth.role() = 'service_role' or ${ctx.scope.can(tenant, permission)}) then
    ${fail(code, message)}
  end if;`;

  const manage = (tenant: string): string =>
    guard(
      tenant,
      names.manage,
      "OPTION_SET_FORBIDDEN",
      "not allowed to manage option sets",
    );

  const unknownField = fail(
    "OPTION_SET_FIELD_UNKNOWN",
    "this field has no option set binding",
    "22023",
  );

  const configured = (
    type: string,
    payload: string,
    subject: string,
    tenant: string,
    target: string,
    recordId: string,
    summary: string,
  ): string =>
    ctx.record({
      type,
      payload,
      subject,
      tenant,
      audit: {
        category: "configuration",
        targetType: target,
        recordId,
        summary,
      },
    });

  const setJson = (alias: string, includeArchived: string): string =>
    `${ctx.rowJson("sets", alias)} || jsonb_build_object('items', coalesce((
      select jsonb_agg(${ctx.rowJson("items", "z")} order by z.${i("rank")} collate "C", z.${i("id")})
      from ${t("items")} z
      where z.${i("set")} = ${alias}.${s("id")} and (${includeArchived} or z.${i("archivedAt")} is null)
    ), '[]'::jsonb))`;

  const inUse = (itemSql: string): string =>
    byField(
      "v_type",
      "v_field",
      bindings,
      (
        binding,
      ) => `      perform 1 from ${binding.subject.qualified} r where r.${sqlIdent(binding.option)} = ${itemSql} limit 1;
      v_used := found;`,
      "v_used := false;",
    );

  const moveRecords = (from: string, to: string): string =>
    byField(
      "v_type",
      "v_field",
      bindings,
      (
        binding,
      ) => `      update ${binding.subject.qualified} r set ${sqlIdent(binding.option)} = ${to}
      where r.${sqlIdent(binding.option)} = ${from};`,
      "null;",
    );

  const bounds = byField(
    "v_type",
    "v_field",
    bindings,
    (binding) => `      v_min := ${String(binding.min)};
      v_max := ${String(binding.max)};`,
    unknownField,
  );

  const relevel = byField(
    "v_type",
    "v_field",
    bindings,
    (
      binding,
    ) => `      update ${binding.subject.qualified} r set ${sqlIdent(binding.column)} = save_option_set_item.level
      where r.${sqlIdent(binding.option)} = v_item;`,
    "null;",
  );

  return `
-- The option sets of a tenant with their active items, ordered by rank.
-- filters is { subjectType, field, scopeId, includeArchived }.
create or replace function ${fn("list_option_sets")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_filters jsonb := coalesce(list_option_sets.filters, '{}'::jsonb);
  v_archived boolean := coalesce((v_filters ->> 'includeArchived')::boolean, false);
begin
  ${guard("list_option_sets.tenant", names.read, "OPTION_SET_FORBIDDEN", "not allowed to read option sets")}
  return coalesce((
    select jsonb_agg(${setJson("y", "v_archived")} order by y.${s("isDefault")} desc, y.${s("createdAt")}, y.${s("id")})
    from ${t("sets")} y
    where y.${s("tenant")} = list_option_sets.tenant
      and (v_archived or y.${s("archivedAt")} is null)
      and (not v_filters ? 'subjectType' or y.${s("subjectType")} = v_filters ->> 'subjectType')
      and (not v_filters ? 'field' or y.${s("field")} = v_filters ->> 'field')
      and (not v_filters ? 'scopeId' or y.${s("scope")} is not distinct from (v_filters ->> 'scopeId'))
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_option_sets")}(${idType}, jsonb)`)}

-- The default option set of a field, created from its template on first use.
-- Returns it with its items.
create or replace function ${fn("ensure_option_set")}(tenant ${idType}, subject_type text, field text, scope_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_set uuid;
begin
  ${guard("ensure_option_set.tenant", names.read, "OPTION_SET_FORBIDDEN", "not allowed to read option sets")}
  v_set := ${fn("default_option_set")}(ensure_option_set.tenant, ensure_option_set.subject_type, ensure_option_set.field, ensure_option_set.scope_id);
  return (select ${setJson("y", "false")} from ${t("sets")} y where y.${s("id")} = v_set);
end;
$$;
${userGrant(`${fn("ensure_option_set")}(${idType}, text, text, text)`)}

-- Creates an option set (option_set null) or renames one. Returns it with its
-- items. A set made the default replaces the field's previous default.
create or replace function ${fn("save_option_set")}(tenant ${idType}, option_set uuid, subject_type text, field text, key text, name text, scope_id text default null, is_default boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_set uuid := save_option_set.option_set;
  v_tenant ${idType} := save_option_set.tenant;
  v_type text := save_option_set.subject_type;
  v_field text := save_option_set.field;
  v_created boolean := save_option_set.option_set is null;
begin
  ${manage("save_option_set.tenant")}
  if not (save_option_set.subject_type || '.' || save_option_set.field = any (${sqlString(`{${bindings.map((binding) => `${binding.type}.${binding.field}`).join(",")}}`)}::text[])) then
    ${unknownField}
  end if;
  if coalesce(save_option_set.is_default, false) then
    update ${t("sets")} x set ${s("isDefault")} = false
    where x.${s("tenant")} = save_option_set.tenant and x.${s("subjectType")} = save_option_set.subject_type
      and x.${s("field")} = save_option_set.field
      and x.${s("scope")} is not distinct from save_option_set.scope_id and x.${s("isDefault")}
      and x.${s("id")} is distinct from save_option_set.option_set;
  end if;
  begin
    if v_created then
      insert into ${t("sets")} (${s("tenant")}, ${s("subjectType")}, ${s("field")}, ${s("scope")}, ${s("key")}, ${s("name")}, ${s("isDefault")})
      values (save_option_set.tenant, save_option_set.subject_type, save_option_set.field, save_option_set.scope_id, save_option_set.key, save_option_set.name,
        coalesce(save_option_set.is_default, false) or not exists (
          select 1 from ${t("sets")} x where x.${s("tenant")} = save_option_set.tenant and x.${s("subjectType")} = save_option_set.subject_type
            and x.${s("field")} = save_option_set.field
            and x.${s("scope")} is not distinct from save_option_set.scope_id and x.${s("archivedAt")} is null))
      returning ${s("id")} into v_set;
    else
      update ${t("sets")} x set ${s("key")} = save_option_set.key, ${s("name")} = save_option_set.name,
        ${s("isDefault")} = coalesce(save_option_set.is_default, x.${s("isDefault")}), ${s("updatedAt")} = now()
      where x.${s("id")} = save_option_set.option_set and x.${s("tenant")} = save_option_set.tenant
        and x.${s("subjectType")} = save_option_set.subject_type and x.${s("field")} = save_option_set.field;
      if not found then
        ${fail("OPTION_SET_NOT_FOUND", "option set not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("OPTION_SET_KEY_TAKEN", "another option set of this field has this key", "23505")}
  end;
  ${createdOrUpdated("v_created", (verb) => configured(`option_set.${verb}`, "jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'subjectType', v_type, 'field', v_field, 'key', save_option_set.key)", "'option-sets/' || v_set::text", "v_tenant::text", "option_set", "v_set::text", `'${verb} option set ' || save_option_set.name`))}
  return (select ${setJson("y", "false")} from ${t("sets")} y where y.${s("id")} = v_set);
end;
$$;
${userGrant(`${fn("save_option_set")}(${idType}, uuid, text, text, text, text, text, boolean)`)}

-- Creates an item at the end of a set (item null) or changes one. The level
-- must lie within the bounds of the field's binding; records on the item take
-- the new level.
create or replace function ${fn("save_option_set_item")}(option_set uuid, item uuid, key text, label text, level integer, color text default null, icon text default null, description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType};
  v_type text;
  v_field text;
  v_min integer;
  v_max integer;
  v_set uuid := save_option_set_item.option_set;
  v_item uuid := save_option_set_item.item;
begin
  select x.${s("tenant")}, x.${s("subjectType")}, x.${s("field")} into v_tenant, v_type, v_field
  from ${t("sets")} x where x.${s("id")} = save_option_set_item.option_set and x.${s("archivedAt")} is null;
  if v_tenant is null then
    ${fail("OPTION_SET_NOT_FOUND", "option set not found", "P0002")}
  end if;
  ${manage("v_tenant")}
  ${bounds}
  if save_option_set_item.level is null or save_option_set_item.level < v_min or save_option_set_item.level > v_max then
    ${fail("OPTION_SET_LEVEL_INVALID", "the level is outside the bounds of this field", "22023")}
  end if;
  begin
    if v_item is null then
      insert into ${t("items")} (${i("tenant")}, ${i("set")}, ${i("key")}, ${i("label")}, ${i("level")}, ${i("color")}, ${i("icon")}, ${i("description")}, ${i("rank")})
      values (v_tenant, save_option_set_item.option_set, save_option_set_item.key, save_option_set_item.label, save_option_set_item.level,
        save_option_set_item.color, save_option_set_item.icon, save_option_set_item.description,
        ${rankAfter(`(select max(x.${i("rank")} collate "C") from ${t("items")} x where x.${i("set")} = save_option_set_item.option_set)`)})
      returning ${i("id")} into v_item;
    else
      update ${t("items")} x set ${i("key")} = save_option_set_item.key, ${i("label")} = save_option_set_item.label,
        ${i("level")} = save_option_set_item.level, ${i("color")} = save_option_set_item.color, ${i("icon")} = save_option_set_item.icon,
        ${i("description")} = save_option_set_item.description, ${i("updatedAt")} = now()
      where x.${i("id")} = v_item and x.${i("set")} = save_option_set_item.option_set;
      if not found then
        ${fail("OPTION_SET_ITEM_NOT_FOUND", "item not found", "P0002")}
      end if;
      ${relevel}
    end if;
  exception when unique_violation then
    ${fail("OPTION_SET_ITEM_KEY_TAKEN", "another item of this set has this key", "23505")}
  end;
  ${createdOrUpdated("save_option_set_item.item is null", (verb) => configured(`option_set_item.${verb}`, "jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item, 'key', save_option_set_item.key, 'level', save_option_set_item.level)", "'option-sets/' || v_set::text", "v_tenant::text", "option_set_item", "v_item::text", `'${verb} option set item ' || save_option_set_item.label`))}
  return (select ${ctx.rowJson("items", "x")} from ${t("items")} x where x.${i("id")} = v_item);
end;
$$;
${userGrant(`${fn("save_option_set_item")}(uuid, uuid, text, text, integer, text, text, text)`)}

-- Moves an item to a rank key the client computed with rankBetween.
create or replace function ${fn("rank_option_set_item")}(item uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType};
begin
  select x.${i("tenant")} into v_tenant from ${t("items")} x where x.${i("id")} = rank_option_set_item.item;
  if v_tenant is null then
    return false;
  end if;
  ${manage("v_tenant")}
  if rank_option_set_item.rank is null or rank_option_set_item.rank !~ ${RANK_KEY_PATTERN} then
    ${fail("OPTION_SET_RANK_INVALID", "not a rank key", "22023")}
  end if;
  update ${t("items")} x set ${i("rank")} = rank_option_set_item.rank, ${i("updatedAt")} = now()
  where x.${i("id")} = rank_option_set_item.item;
  return true;
end;
$$;
${userGrant(`${fn("rank_option_set_item")}(uuid, text)`)}

-- Archives an item. Records on it must move first: pass replacement, an active
-- item of the same set, to move them in the same call. A set keeps at least
-- one active item.
create or replace function ${fn("archive_option_set_item")}(item uuid, replacement uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType};
  v_set uuid;
  v_type text;
  v_field text;
  v_used boolean;
  v_item uuid := archive_option_set_item.item;
begin
  select x.${i("tenant")}, x.${i("set")}, y.${s("subjectType")}, y.${s("field")} into v_tenant, v_set, v_type, v_field
  from ${t("items")} x join ${t("sets")} y on y.${s("id")} = x.${i("set")}
  where x.${i("id")} = archive_option_set_item.item and x.${i("archivedAt")} is null;
  if v_tenant is null then
    return false;
  end if;
  ${manage("v_tenant")}
  if archive_option_set_item.replacement is not null and not exists (
    select 1 from ${t("items")} x
    where x.${i("id")} = archive_option_set_item.replacement and x.${i("set")} = v_set
      and x.${i("archivedAt")} is null and x.${i("id")} <> archive_option_set_item.item
  ) then
    ${fail("OPTION_SET_REPLACEMENT_INVALID", "the replacement must be another active item of the same set", "22023")}
  end if;
  if not exists (
    select 1 from ${t("items")} x
    where x.${i("set")} = v_set and x.${i("archivedAt")} is null and x.${i("id")} <> archive_option_set_item.item
  ) then
    ${fail("OPTION_SET_LAST_ITEM", "an option set keeps at least one item", "23514")}
  end if;
  ${inUse("archive_option_set_item.item")}
  if v_used then
    if archive_option_set_item.replacement is null then
      ${fail("OPTION_SET_ITEM_IN_USE", "records use this item; pass a replacement", "23503")}
    end if;
    ${moveRecords("archive_option_set_item.item", "archive_option_set_item.replacement")}
  end if;
  update ${t("items")} x set ${i("archivedAt")} = now(), ${i("updatedAt")} = now() where x.${i("id")} = archive_option_set_item.item;
  ${configured(
    "option_set_item.archived",
    "jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item)",
    "'option-sets/' || v_set::text",
    "v_tenant::text",
    "option_set_item",
    "v_item::text",
    "'archived an option set item'",
  )}
  return true;
end;
$$;
${userGrant(`${fn("archive_option_set_item")}(uuid, uuid)`)}

-- Restores an archived item. Records that moved to a replacement stay there.
create or replace function ${fn("restore_option_set_item")}(item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType};
  v_set uuid;
  v_item uuid := restore_option_set_item.item;
begin
  select x.${i("tenant")}, x.${i("set")} into v_tenant, v_set
  from ${t("items")} x
  where x.${i("id")} = restore_option_set_item.item and x.${i("archivedAt")} is not null;
  if v_tenant is null then
    return false;
  end if;
  ${manage("v_tenant")}
  update ${t("items")} x set ${i("archivedAt")} = null, ${i("updatedAt")} = now() where x.${i("id")} = restore_option_set_item.item;
  ${configured(
    "option_set_item.restored",
    "jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item)",
    "'option-sets/' || v_set::text",
    "v_tenant::text",
    "option_set_item",
    "v_item::text",
    "'restored an option set item'",
  )}
  return true;
end;
$$;
${userGrant(`${fn("restore_option_set_item")}(uuid)`)}
`;
}
