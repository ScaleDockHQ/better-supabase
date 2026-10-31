import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  fail,
  raise,
  SERVICE_CALLER,
  triggerGrant,
  userGrant,
} from "../shared.ts";
import {
  DOCUMENT_BODY_MAX,
  DOCUMENT_CONTRACT_VERSION,
  DOCUMENT_FILTERS,
  DOCUMENT_LANGUAGE_PATTERN,
  DOCUMENT_TEXT_KEY_PATTERN,
  DOCUMENT_TYPES,
  DOCUMENT_VARIABLES,
} from "./document-templates-values.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The pattern of a template name, the slot a document type can hold several of. */
const NAME_PATTERN = "^[a-z][a-z0-9_-]{0,63}$";

/**
 * The contract as the JSON `document_template_contract` returns: paths and
 * types.
 */
function contractLiteral(): string {
  const all = Object.fromEntries(
    DOCUMENT_TYPES.map((type) => [
      type,
      {
        version: DOCUMENT_CONTRACT_VERSION,
        documentType: type,
        variables: DOCUMENT_VARIABLES[type].map(({ path, type: kind }) => ({
          path,
          type: kind,
        })),
      },
    ]),
  );

  return sqlString(JSON.stringify(all));
}

const FILTERS_SQL = DOCUMENT_FILTERS.map((name) => sqlString(name)).join(", ");
const FILTERS_TEXT = DOCUMENT_FILTERS.join(" or ");

/**
 * The text key pattern without its anchors, for a regular expression inside
 * another.
 */
const TEXT_KEY = DOCUMENT_TEXT_KEY_PATTERN.slice(1, -1);

/** The path of a variable, as the template grammar writes it. */
const PATH = "[A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*";

/**
 * The variable contract, the template validator, the template and text block
 * writers and readers, the fallback chain, `render_document` and the snapshots
 * (ADR 0145). The validator mirrors `template.ts`: a template the database
 * accepts is one the TypeScript renderer accepts.
 */
export function documentTemplateFunctions(ctx: BlockSqlContext): string {
  const templates = ctx.table("templates");
  const blocks = ctx.table("textBlocks");
  const snapshots = ctx.table("snapshots");
  const x = (column: string): string => ctx.col("templates", column);
  const y = (column: string): string => ctx.col("textBlocks", column);
  const z = (column: string): string => ctx.col("snapshots", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("document-templates");
  const manage = ctx.permission("manage", permissions.manage);
  const legal = ctx.of("legal-entities");

  const allowed = (tenant: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, manage)})`;

  const forbidden = fail(
    "DOCUMENT_TEMPLATE_FORBIDDEN",
    "not allowed to manage document templates",
  );

  const invalid = (message: string): string =>
    fail("DOCUMENT_TEMPLATE_INVALID", message, "22023");

  const typeInvalid = fail(
    "DOCUMENT_TYPE_INVALID",
    `the document type is ${DOCUMENT_TYPES.join(", ")}`,
    "22023",
  );

  const templateMissing = fail(
    "DOCUMENT_TEMPLATE_NOT_FOUND",
    "document template not found",
    "P0002",
  );

  const types = DOCUMENT_TYPES.map((type) => sqlString(type)).join(", ");

  const lock = (key: string): string =>
    `perform pg_advisory_xact_lock(hashtextextended(${key}, 0));`;

  const templateJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${x("id")}, 'organizationId', ${row}.${x("tenant")}, 'legalEntityId', ${row}.${x("legalEntity")}, 'documentType', ${row}.${x("documentType")}, 'language', ${row}.${x("language")}, 'name', ${row}.${x("name")}, 'body', ${row}.${x("body")}, 'version', ${row}.${x("version")}, 'active', ${row}.${x("active")}, 'createdAt', ${row}.${x("createdAt")}, 'updatedAt', ${row}.${x("updatedAt")})`;

  const blockJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${y("id")}, 'organizationId', ${row}.${y("tenant")}, 'legalEntityId', ${row}.${y("legalEntity")}, 'key', ${row}.${y("key")}, 'language', ${row}.${y("language")}, 'body', ${row}.${y("body")}, 'version', ${row}.${y("version")}, 'createdAt', ${row}.${y("createdAt")}, 'updatedAt', ${row}.${y("updatedAt")})`;

  const templateRecord = (verb: "created" | "updated", row: string): string =>
    ctx.record({
      type: `document_template.${verb}`,
      payload: `jsonb_build_object('organizationId', ${row}.${x("tenant")}, 'templateId', ${row}.${x("id")}, 'documentType', ${row}.${x("documentType")}, 'legalEntityId', ${row}.${x("legalEntity")}, 'language', ${row}.${x("language")}, 'name', ${row}.${x("name")}, 'version', ${row}.${x("version")})`,
      subject: `'document-templates/' || ${row}.${x("id")}::text`,
      tenant: `${row}.${x("tenant")}`,
      audit: {
        category: "data",
        targetType: "document_template",
        recordId: `${row}.${x("id")}::text`,
        summary: `'${verb} ' || ${row}.${x("documentType")} || ' template ' || ${row}.${x("name")} || ' (version ' || ${row}.${x("version")}::text || ')'`,
      },
    });

  const blockRecord = (verb: "created" | "updated", row: string): string =>
    ctx.record({
      type: `document_text_block.${verb}`,
      payload: `jsonb_build_object('organizationId', ${row}.${y("tenant")}, 'textBlockId', ${row}.${y("id")}, 'key', ${row}.${y("key")}, 'legalEntityId', ${row}.${y("legalEntity")}, 'language', ${row}.${y("language")}, 'version', ${row}.${y("version")})`,
      subject: `'document-templates/' || ${row}.${y("id")}::text`,
      tenant: `${row}.${y("tenant")}`,
      audit: {
        category: "data",
        targetType: "document_text_block",
        recordId: `${row}.${y("id")}::text`,
        summary: `'${verb} text block ' || ${row}.${y("key")} || ' (version ' || ${row}.${y("version")}::text || ')'`,
      },
    });

  const snapshotRecord = (row: string): string =>
    ctx.record({
      type: "document_snapshot.created",
      payload: `jsonb_build_object('organizationId', ${row}.${z("tenant")}, 'snapshotId', ${row}.${z("id")}, 'documentType', ${row}.${z("documentType")}, 'documentId', ${row}.${z("documentId")}, 'templateVersion', ${row}.${z("templateVersion")})`,
      subject: `'document-templates/' || ${row}.${z("id")}::text`,
      tenant: `${row}.${z("tenant")}`,
      audit: {
        category: "data",
        targetType: "document_snapshot",
        recordId: `${row}.${z("id")}::text`,
        summary: `'froze ' || ${row}.${z("documentType")} || ' ' || ${row}.${z("documentId")}::text`,
      },
    });

  const snapshotJson = (row: string): string =>
    `jsonb_build_object('contractVersion', ${row}.${z("contractVersion")}, 'documentType', ${row}.${z("documentType")}, 'documentId', ${row}.${z("documentId")}, 'legalEntityId', ${row}.${z("legalEntity")}, 'language', ${row}.${z("language")}, 'variables', ${row}.${z("variables")}, 'template', ${row}.${z("template")}, 'blocks', ${row}.${z("blocks")}, 'frozen', true, 'frozenAt', ${row}.${z("createdAt")}, 'snapshotId', ${row}.${z("id")})`;

  // The issue a template can have, as the raise that carries its hint code.
  const issueRaise = (code: string): string =>
    raise("%", "22023", code, "v_message");

  return `
-- The variable contract of a document type: its version and the paths and
-- types a template can read. Null names every type. A text block reads any of
-- them. The TypeScript type DocumentVariables and the JSON Schema in
-- schemas/document-template-variables-v1.json state the same contract.
create or replace function ${fn("document_template_contract")}(document_type text default null)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_all constant jsonb := ${contractLiteral()}::jsonb;
begin
  if document_template_contract.document_type is null then
    return v_all;
  end if;
  if not v_all ? document_template_contract.document_type then
    ${typeInvalid}
  end if;
  return v_all -> document_template_contract.document_type;
end;
$$;
${userGrant(`${fn("document_template_contract")}(text)`)}

-- The problems of a template body, first to last, as [{ code, message, tag }].
-- Empty when the body is valid. A text block (text_block) may read the
-- variables of any document type and has no texts.<key>. An unknown variable,
-- an unknown filter and a block that is not closed each have a hint code.
create or replace function ${fn("validate_document_template")}(document_type text, body text, text_block boolean default false)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_known jsonb := '{}'::jsonb;
  v_contract jsonb;
  v_item jsonb;
  v_parse jsonb := '[]'::jsonb;
  v_check jsonb := '[]'::jsonb;
  v_stack jsonb := '[]'::jsonb;
  v_scope jsonb := '{}'::jsonb;
  v_piece text;
  v_tag text;
  v_match text[];
  v_top jsonb;
  v_path text;
  v_kind text;
  v_head text;
  v_list text;
  v_each text[];
  v_if text[];
  v_value text[];
  v_filter text;
  v_text boolean := not coalesce(validate_document_template.text_block, false);
begin
  if validate_document_template.body is null then
    ${invalid("a template needs a body")}
  end if;
  if coalesce(validate_document_template.text_block, false) then
    for v_contract in select c.value from jsonb_each(${fn("document_template_contract")}(null)) c loop
      for v_item in select e.value from jsonb_array_elements(v_contract -> 'variables') e loop
        v_known := v_known || jsonb_build_object(v_item ->> 'path', v_item ->> 'type');
      end loop;
    end loop;
  else
    for v_item in select e.value from jsonb_array_elements(${fn("document_template_contract")}(validate_document_template.document_type) -> 'variables') e loop
      v_known := v_known || jsonb_build_object(v_item ->> 'path', v_item ->> 'type');
    end loop;
  end if;

  -- Text between the tags holds no brace pair.
  for v_piece in select p from regexp_split_to_table(validate_document_template.body, '\\{\\{[\\s\\S]*?\\}\\}') p loop
    if v_piece ~ '\\{\\{|\\}\\}' then
      v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'a brace pair is not closed or not opened', 'tag', btrim(v_piece)));
    end if;
  end loop;

  for v_match in select m from regexp_matches(validate_document_template.body, '\\{\\{([\\s\\S]*?)\\}\\}', 'g') m loop
    v_tag := btrim(v_match[1]);
    v_top := case when jsonb_array_length(v_stack) = 0 then null else v_stack -> (jsonb_array_length(v_stack) - 1) end;

    if v_tag in ('/each', '/if') then
      if v_top is null or v_top ->> 'kind' <> substr(v_tag, 2) then
        v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', v_tag || ' closes nothing', 'tag', v_tag));
      else
        v_stack := v_stack - (jsonb_array_length(v_stack) - 1);
        if v_top ->> 'kind' = 'each' then
          v_scope := v_scope - (v_top ->> 'alias');
        end if;
      end if;
    elsif v_tag = 'else' then
      if v_top is null or v_top ->> 'kind' <> 'if' or (v_top ->> 'else')::boolean then
        v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'else belongs inside one #if', 'tag', v_tag));
      else
        v_stack := jsonb_set(v_stack, array[(jsonb_array_length(v_stack) - 1)::text, 'else'], 'true'::jsonb);
      end if;
    else
      v_each := regexp_match(v_tag, '^#each\\s+(${PATH})\\s+as\\s+([a-z][A-Za-z0-9_]*)$');
      v_if := regexp_match(v_tag, '^#if\\s+(${PATH})$');
      if v_each is not null then
        if coalesce(v_known ->> v_each[1], '') <> 'list' or v_scope ? v_each[1] then
          v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_each[1] || ' is not a list of this document', 'tag', v_each[1]));
        end if;
        if v_known ? v_each[2] or v_scope ? v_each[2] then
          v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', v_each[2] || ' is already a variable', 'tag', v_each[2]));
        end if;
        v_stack := v_stack || jsonb_build_array(jsonb_build_object('kind', 'each', 'alias', v_each[2], 'else', false));
        v_scope := v_scope || jsonb_build_object(v_each[2], v_each[1]);
      elsif v_if is not null then
        v_path := v_if[1];
        v_kind := null;
        v_head := split_part(v_path, '.', 1);
        if v_scope ? v_head then
          v_kind := case when position('.' in v_path) = 0 then null else v_known ->> ((v_scope ->> v_head) || '[]' || substr(v_path, length(v_head) + 1)) end;
        elsif v_path ~ '^texts\\.${TEXT_KEY}$' then
          v_kind := case when v_text then 'string' else null end;
        else
          v_kind := v_known ->> v_path;
        end if;
        if v_kind is null then
          v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_path || ' is not a variable of this document', 'tag', v_path));
        end if;
        v_stack := v_stack || jsonb_build_array(jsonb_build_object('kind', 'if', 'else', false));
      elsif left(v_tag, 1) in ('#', '/') then
        v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'unknown block tag', 'tag', v_tag));
      else
        v_value := regexp_match(v_tag, '^(${PATH})(?:\\s*\\|\\s*([A-Za-z_]+))?$');
        if v_value is null then
          v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'a placeholder is a path with an optional filter', 'tag', v_tag));
        else
          v_filter := v_value[2];
          if v_filter is not null and v_filter not in (${FILTERS_SQL}) then
            v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_FILTER', 'message', 'unknown filter ' || v_filter || '; use ${FILTERS_TEXT}', 'tag', v_tag));
          else
            v_path := v_value[1];
            v_kind := null;
            v_head := split_part(v_path, '.', 1);
            if v_scope ? v_head then
              v_kind := case when position('.' in v_path) = 0 then null else v_known ->> ((v_scope ->> v_head) || '[]' || substr(v_path, length(v_head) + 1)) end;
            elsif v_path ~ '^texts\\.${TEXT_KEY}$' then
              v_kind := case when v_text then 'string' else null end;
            else
              v_kind := v_known ->> v_path;
            end if;
            if v_kind is null then
              v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_path || ' is not a variable of this document', 'tag', v_path));
            elsif v_kind in ('object', 'list') then
              v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_path || ' is not a single value', 'tag', v_path));
            end if;
          end if;
        end if;
      end if;
    end if;
  end loop;

  for v_item in select s.value from jsonb_array_elements(v_stack) s loop
    v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', '#' || (v_item ->> 'kind') || ' is not closed', 'tag', '#' || (v_item ->> 'kind')));
  end loop;

  return v_parse || v_check;
end;
$$;
${userGrant(`${fn("validate_document_template")}(text, text, boolean)`)}

-- Raises with the hint code of the first problem of a template body.
create or replace function ${fn("assert_document_template")}(document_type text, body text, text_block boolean default false)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_issues jsonb;
  v_code text;
  v_message text;
begin
  v_issues := ${fn("validate_document_template")}(assert_document_template.document_type, assert_document_template.body, assert_document_template.text_block);
  if jsonb_array_length(v_issues) = 0 then
    return;
  end if;
  v_code := v_issues -> 0 ->> 'code';
  v_message := v_issues -> 0 ->> 'message';
  if v_code = 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE' then
    ${issueRaise("DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE")}
  elsif v_code = 'DOCUMENT_TEMPLATE_UNKNOWN_FILTER' then
    ${issueRaise("DOCUMENT_TEMPLATE_UNKNOWN_FILTER")}
  end if;
  ${issueRaise("DOCUMENT_TEMPLATE_SYNTAX")}
end;
$$;
revoke execute on function ${fn("assert_document_template")}(text, text, boolean) from public, anon, authenticated;

-- How well a template or text block fits a request, lower first: its own
-- entity before the organization's, and inside each its exact language, its
-- base language (nl for nl-nl), then no language, then any other language.
create or replace function ${fn("document_slot_rank")}(entity uuid, wanted_entity uuid, language text, wanted_language text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when document_slot_rank.entity is not distinct from document_slot_rank.wanted_entity and document_slot_rank.entity is not null then 0 else 3 end
    + case
      when document_slot_rank.wanted_language is not null and document_slot_rank.language = document_slot_rank.wanted_language then 0
      when document_slot_rank.wanted_language is not null and document_slot_rank.language = split_part(document_slot_rank.wanted_language, '-', 1) then 1
      when document_slot_rank.language is null then 2
      else 6
    end
$$;
${userGrant(`${fn("document_slot_rank")}(uuid, uuid, text, text)`)}

-- Saves the template of a slot: a document type, a name, a legal entity (null
-- for the organization) and a language (null for any). Saving a changed body
-- raises the version by one; the same body and state change nothing. Raises
-- with a hint code when the body names an unknown variable.
create or replace function ${fn("save_document_template")}(tenant ${idType}, document_type text, body text, language text default null, name text default 'default', legal_entity_id uuid default null, active boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${templates}%rowtype;
  v_language text := lower(nullif(btrim(save_document_template.language), ''));
  v_name text := coalesce(nullif(btrim(save_document_template.name), ''), 'default');
  v_active boolean := coalesce(save_document_template.active, true);
  v_changed boolean;
begin
  if not ${allowed("save_document_template.tenant")} then
    ${forbidden}
  end if;
  if save_document_template.document_type is null or save_document_template.document_type not in (${types}) then
    ${typeInvalid}
  end if;
  if v_name !~ '${NAME_PATTERN}' then
    ${invalid("a template name is lower case letters, digits, _ and -, from a letter, up to 64 characters")}
  end if;
  if v_language is not null and v_language !~ '${DOCUMENT_LANGUAGE_PATTERN}' then
    ${invalid("a language is a code such as nl or nl-NL")}
  end if;
  if save_document_template.body is null or length(btrim(save_document_template.body)) = 0 or length(save_document_template.body) > ${String(DOCUMENT_BODY_MAX)} then
    ${invalid(`a template body is 1 to ${String(DOCUMENT_BODY_MAX)} characters`)}
  end if;
  if save_document_template.legal_entity_id is not null then
    perform ${legal.fn("legal_entity_of")}(save_document_template.tenant, save_document_template.legal_entity_id);
  end if;
  perform ${fn("assert_document_template")}(save_document_template.document_type, save_document_template.body);
  ${ctx.hook("before_document_template_save", [
    [idType, "save_document_template.tenant"],
    ["text", "save_document_template.document_type"],
  ])}
  ${lock(`'document_templates:' || save_document_template.tenant::text`)}
  select * into v_row from ${templates} t
    where t.${x("tenant")} = save_document_template.tenant
      and t.${x("documentType")} = save_document_template.document_type
      and t.${x("name")} = v_name
      and t.${x("legalEntity")} is not distinct from save_document_template.legal_entity_id
      and t.${x("language")} is not distinct from v_language;
  if found then
    v_changed := v_row.${x("body")} <> save_document_template.body;
    if not v_changed and v_row.${x("active")} = v_active then
      return ${templateJson("v_row")};
    end if;
    update ${templates} t set
      ${x("body")} = save_document_template.body,
      ${x("version")} = t.${x("version")} + case when v_changed then 1 else 0 end,
      ${x("active")} = v_active,
      ${x("updatedAt")} = now()
    where t.${x("id")} = v_row.${x("id")}
    returning * into v_row;
    ${templateRecord("updated", "v_row")}
  else
    insert into ${templates} (${x("tenant")}, ${x("legalEntity")}, ${x("documentType")}, ${x("language")}, ${x("name")}, ${x("body")}, ${x("active")})
    values (save_document_template.tenant, save_document_template.legal_entity_id, save_document_template.document_type, v_language, v_name, save_document_template.body, v_active)
    returning * into v_row;
    ${templateRecord("created", "v_row")}
  end if;
  ${ctx.hook("after_document_template_save", [["uuid", `v_row.${x("id")}`]])}
  return ${templateJson("v_row")};
end;
$$;
${userGrant(`${fn("save_document_template")}(${idType}, text, text, text, text, uuid, boolean)`)}

-- Turns a template on or off. An inactive template drops out of the fallback
-- chain; documents already frozen keep the copy they froze.
create or replace function ${fn("set_document_template_active")}(template_id uuid, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${templates}%rowtype;
begin
  select * into v_row from ${templates} t where t.${x("id")} = set_document_template_active.template_id;
  if not found then
    ${templateMissing}
  end if;
  if not ${allowed(`v_row.${x("tenant")}`)} then
    ${forbidden}
  end if;
  if v_row.${x("active")} is distinct from coalesce(set_document_template_active.active, true) then
    update ${templates} t set ${x("active")} = coalesce(set_document_template_active.active, true), ${x("updatedAt")} = now()
    where t.${x("id")} = v_row.${x("id")}
    returning * into v_row;
    ${templateRecord("updated", "v_row")}
  end if;
  return ${templateJson("v_row")};
end;
$$;
${userGrant(`${fn("set_document_template_active")}(uuid, boolean)`)}

create or replace function ${fn("get_document_template")}(template_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row ${templates}%rowtype;
begin
  select * into v_row from ${templates} t where t.${x("id")} = get_document_template.template_id;
  if not found then
    ${templateMissing}
  end if;
  return ${templateJson("v_row")};
end;
$$;
${userGrant(`${fn("get_document_template")}(uuid)`)}

-- The templates of an organization by document type, name, entity (the
-- organization's first) and language.
create or replace function ${fn("list_document_templates")}(tenant ${idType}, document_type text default null, legal_entity_id uuid default null, active_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${templateJson("t")} order by t.${x("documentType")}, t.${x("name")}, t.${x("legalEntity")} nulls first, t.${x("language")} nulls first), '[]'::jsonb)
  from ${templates} t
  where t.${x("tenant")} = list_document_templates.tenant
    and (list_document_templates.document_type is null or t.${x("documentType")} = list_document_templates.document_type)
    and (list_document_templates.legal_entity_id is null or t.${x("legalEntity")} = list_document_templates.legal_entity_id)
    and (not coalesce(list_document_templates.active_only, false) or t.${x("active")})
$$;
${userGrant(`${fn("list_document_templates")}(${idType}, text, uuid, boolean)`)}

-- Saves a reusable text, read in a template as texts.<key>: a payment terms
-- sentence, a dunning text, a footer, a legal line. The text may hold the same
-- placeholders a template does, of any document type. An entity text beats the
-- organization's, and an exact language beats a text with no language.
create or replace function ${fn("save_document_text_block")}(tenant ${idType}, key text, body text, language text default null, legal_entity_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${blocks}%rowtype;
  v_language text := lower(nullif(btrim(save_document_text_block.language), ''));
begin
  if not ${allowed("save_document_text_block.tenant")} then
    ${forbidden}
  end if;
  if save_document_text_block.key is null or save_document_text_block.key !~ '${DOCUMENT_TEXT_KEY_PATTERN}' then
    ${invalid("a text key is lower case letters, digits and _, from a letter, up to 64 characters")}
  end if;
  if v_language is not null and v_language !~ '${DOCUMENT_LANGUAGE_PATTERN}' then
    ${invalid("a language is a code such as nl or nl-NL")}
  end if;
  if save_document_text_block.body is null or length(btrim(save_document_text_block.body)) = 0 or length(save_document_text_block.body) > ${String(DOCUMENT_BODY_MAX)} then
    ${invalid(`a text block body is 1 to ${String(DOCUMENT_BODY_MAX)} characters`)}
  end if;
  if save_document_text_block.legal_entity_id is not null then
    perform ${legal.fn("legal_entity_of")}(save_document_text_block.tenant, save_document_text_block.legal_entity_id);
  end if;
  perform ${fn("assert_document_template")}(null, save_document_text_block.body, true);
  ${ctx.hook("before_document_text_block_save", [
    [idType, "save_document_text_block.tenant"],
    ["text", "save_document_text_block.key"],
  ])}
  ${lock(`'document_text_blocks:' || save_document_text_block.tenant::text`)}
  select * into v_row from ${blocks} b
    where b.${y("tenant")} = save_document_text_block.tenant
      and b.${y("key")} = save_document_text_block.key
      and b.${y("legalEntity")} is not distinct from save_document_text_block.legal_entity_id
      and b.${y("language")} is not distinct from v_language;
  if found then
    if v_row.${y("body")} = save_document_text_block.body then
      return ${blockJson("v_row")};
    end if;
    update ${blocks} b set ${y("body")} = save_document_text_block.body, ${y("version")} = b.${y("version")} + 1, ${y("updatedAt")} = now()
    where b.${y("id")} = v_row.${y("id")}
    returning * into v_row;
    ${blockRecord("updated", "v_row")}
  else
    insert into ${blocks} (${y("tenant")}, ${y("legalEntity")}, ${y("key")}, ${y("language")}, ${y("body")})
    values (save_document_text_block.tenant, save_document_text_block.legal_entity_id, save_document_text_block.key, v_language, save_document_text_block.body)
    returning * into v_row;
    ${blockRecord("created", "v_row")}
  end if;
  ${ctx.hook("after_document_text_block_save", [["uuid", `v_row.${y("id")}`]])}
  return ${blockJson("v_row")};
end;
$$;
${userGrant(`${fn("save_document_text_block")}(${idType}, text, text, text, uuid)`)}

create or replace function ${fn("list_document_text_blocks")}(tenant ${idType}, key text default null, legal_entity_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${blockJson("b")} order by b.${y("key")}, b.${y("legalEntity")} nulls first, b.${y("language")} nulls first), '[]'::jsonb)
  from ${blocks} b
  where b.${y("tenant")} = list_document_text_blocks.tenant
    and (list_document_text_blocks.key is null or b.${y("key")} = list_document_text_blocks.key)
    and (list_document_text_blocks.legal_entity_id is null or b.${y("legalEntity")} = list_document_text_blocks.legal_entity_id)
$$;
${userGrant(`${fn("list_document_text_blocks")}(${idType}, text, uuid)`)}

-- The template a document gets: the legal entity's template in the document's
-- language, the entity's template for any language, the organization's in the
-- language, then the organization's for any language. Legal entity null means
-- the default entity. A language also matches by its base (nl for nl-nl), and a
-- template in another language is the last resort. Null when nothing fits.
create or replace function ${fn("resolve_document_template")}(tenant ${idType}, document_type text, legal_entity_id uuid default null, language text default null, name text default 'default')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_entity uuid;
  v_language text := lower(nullif(btrim(resolve_document_template.language), ''));
  v_row ${templates}%rowtype;
  v_rank integer;
begin
  v_entity := ${legal.fn("legal_entity_of")}(resolve_document_template.tenant, resolve_document_template.legal_entity_id);
  select * into v_row
  from ${templates} t
  where t.${x("tenant")} = resolve_document_template.tenant
    and t.${x("documentType")} = resolve_document_template.document_type
    and t.${x("name")} = coalesce(resolve_document_template.name, 'default')
    and t.${x("active")}
    and (t.${x("legalEntity")} is null or t.${x("legalEntity")} = v_entity)
  order by ${fn("document_slot_rank")}(t.${x("legalEntity")}, v_entity, t.${x("language")}, v_language), t.${x("updatedAt")} desc
  limit 1;
  if not found then
    return null;
  end if;
  v_rank := ${fn("document_slot_rank")}(v_row.${x("legalEntity")}, v_entity, v_row.${x("language")}, v_language);
  return jsonb_build_object(
    'id', v_row.${x("id")},
    'name', v_row.${x("name")},
    'documentType', v_row.${x("documentType")},
    'legalEntityId', v_row.${x("legalEntity")},
    'language', v_row.${x("language")},
    'version', v_row.${x("version")},
    'body', v_row.${x("body")},
    'source', case v_rank
      when 0 then 'entity_language'
      when 1 then 'entity_language'
      when 2 then 'entity'
      when 3 then 'organization_language'
      when 4 then 'organization_language'
      when 5 then 'organization'
      when 6 then 'entity_other_language'
      else 'organization_other_language' end
  );
end;
$$;
${userGrant(`${fn("resolve_document_template")}(${idType}, text, uuid, text, text)`)}

-- The text blocks for these keys, as an object of key to body, each chosen by
-- the same chain as a template. A key with no block is left out.
create or replace function ${fn("resolve_document_blocks")}(tenant ${idType}, keys text[], legal_entity_id uuid default null, language text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_entity uuid;
  v_language text := lower(nullif(btrim(resolve_document_blocks.language), ''));
  v_result jsonb;
begin
  v_entity := ${legal.fn("legal_entity_of")}(resolve_document_blocks.tenant, resolve_document_blocks.legal_entity_id);
  select coalesce(jsonb_object_agg(f.key, f.body), '{}'::jsonb) into v_result
  from (
    select distinct on (b.${y("key")}) b.${y("key")} as key, b.${y("body")} as body
    from ${blocks} b
    where b.${y("tenant")} = resolve_document_blocks.tenant
      and b.${y("key")} = any (coalesce(resolve_document_blocks.keys, '{}'::text[]))
      and (b.${y("legalEntity")} is null or b.${y("legalEntity")} = v_entity)
    order by b.${y("key")}, ${fn("document_slot_rank")}(b.${y("legalEntity")}, v_entity, b.${y("language")}, v_language), b.${y("updatedAt")} desc
  ) f;
  return v_result;
end;
$$;
${userGrant(`${fn("resolve_document_blocks")}(${idType}, text[], uuid, text)`)}

-- The variables, the chosen template and its text blocks for a document as it
-- stands now. The language is the one asked for, else the buyer's.
create or replace function ${fn("document_render_live")}(tenant ${idType}, document_type text, document_id uuid, language text default null, template_name text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_vars jsonb;
  v_entity uuid;
  v_language text;
  v_template jsonb;
  v_keys text[] := '{}'::text[];
  v_text_key text;
  v_blocks jsonb := '{}'::jsonb;
begin
  v_language := lower(nullif(btrim(document_render_live.language), ''));
  if v_language is not null and v_language !~ '${DOCUMENT_LANGUAGE_PATTERN}' then
    ${invalid("a language is a code such as nl or nl-NL")}
  end if;
  v_vars := ${fn("document_variables")}(document_render_live.tenant, document_render_live.document_type, document_render_live.document_id);
  v_entity := nullif(v_vars #>> '{entity,id}', '')::uuid;
  v_language := coalesce(v_language, lower(nullif(btrim(v_vars #>> '{buyer,language}'), '')));
  if v_language is not null and v_language !~ '${DOCUMENT_LANGUAGE_PATTERN}' then
    v_language := null;
  end if;
  v_template := ${fn("resolve_document_template")}(document_render_live.tenant, document_render_live.document_type, v_entity, v_language, coalesce(document_render_live.template_name, 'default'));
  if v_template is not null then
    select coalesce(array_agg(distinct m[1]), '{}'::text[]) into v_keys
    from regexp_matches(v_template ->> 'body', 'texts\\.(${TEXT_KEY})', 'g') m;
    v_text_key := nullif(v_vars #>> '{document,textKey}', '');
    if v_text_key is not null and v_text_key ~ '${DOCUMENT_TEXT_KEY_PATTERN}' and not v_text_key = any (v_keys) then
      v_keys := v_keys || v_text_key;
    end if;
    v_blocks := ${fn("resolve_document_blocks")}(document_render_live.tenant, v_keys, v_entity, v_language);
    if v_text_key is not null and v_blocks ? v_text_key then
      v_blocks := v_blocks || jsonb_build_object('dunning', v_blocks -> v_text_key);
    end if;
  end if;
  v_vars := jsonb_set(v_vars, '{document,language}', coalesce(to_jsonb(v_language), 'null'::jsonb));
  return jsonb_build_object(
    'contractVersion', ${String(DOCUMENT_CONTRACT_VERSION)},
    'documentType', document_render_live.document_type,
    'documentId', document_render_live.document_id,
    'legalEntityId', v_entity,
    'language', v_language,
    'variables', v_vars,
    'template', v_template,
    'blocks', v_blocks,
    'frozen', false,
    'frozenAt', null,
    'snapshotId', null
  );
end;
$$;
${userGrant(`${fn("document_render_live")}(${idType}, text, uuid, text, text)`)}

-- Everything a renderer needs for one document: the variable payload, the
-- chosen template and the text blocks it reads. A document that was frozen
-- (an issued invoice or credit note, or after freeze_document) returns the
-- copy it froze, so editing a template later never changes it; fresh = true
-- renders the document as it stands now with today's templates instead.
create or replace function ${fn("render_document")}(tenant ${idType}, document_type text, document_id uuid, language text default null, fresh boolean default false, template_name text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${snapshots}%rowtype;
begin
  if render_document.document_type is null or render_document.document_type not in (${types}) then
    ${typeInvalid}
  end if;
  if not coalesce(render_document.fresh, false) then
    select * into v_row from ${snapshots} s
      where s.${z("tenant")} = render_document.tenant
        and s.${z("documentType")} = render_document.document_type
        and s.${z("documentId")} = render_document.document_id;
    if found then
      return ${snapshotJson("v_row")};
    end if;
  end if;
  return ${fn("document_render_live")}(render_document.tenant, render_document.document_type, render_document.document_id, render_document.language, render_document.template_name);
end;
$$;
${userGrant(`${fn("render_document")}(${idType}, text, uuid, text, boolean, text)`)}

-- Freezes a document: stores the variables, the template and the text blocks
-- as they are now. A frozen document returns its snapshot unchanged.
create or replace function ${fn("document_freeze")}(tenant ${idType}, document_type text, document_id uuid, language text default null, template_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${snapshots}%rowtype;
  v_live jsonb;
begin
  ${lock(`'rendered_documents:' || document_freeze.tenant::text || ':' || document_freeze.document_id::text`)}
  select * into v_row from ${snapshots} s
    where s.${z("tenant")} = document_freeze.tenant
      and s.${z("documentType")} = document_freeze.document_type
      and s.${z("documentId")} = document_freeze.document_id;
  if found then
    return ${snapshotJson("v_row")};
  end if;
  v_live := ${fn("document_render_live")}(document_freeze.tenant, document_freeze.document_type, document_freeze.document_id, document_freeze.language, document_freeze.template_name);
  insert into ${snapshots} (${z("tenant")}, ${z("documentType")}, ${z("documentId")}, ${z("language")}, ${z("legalEntity")}, ${z("contractVersion")}, ${z("templateId")}, ${z("templateVersion")}, ${z("template")}, ${z("blocks")}, ${z("variables")})
  values (
    document_freeze.tenant, document_freeze.document_type, document_freeze.document_id,
    v_live ->> 'language', nullif(v_live ->> 'legalEntityId', '')::uuid, (v_live ->> 'contractVersion')::integer,
    nullif(v_live #>> '{template,id}', '')::uuid, nullif(v_live #>> '{template,version}', '')::integer,
    v_live -> 'template', v_live -> 'blocks', v_live -> 'variables')
  returning * into v_row;
  ${snapshotRecord("v_row")}
  return ${snapshotJson("v_row")};
end;
$$;
revoke execute on function ${fn("document_freeze")}(${idType}, text, uuid, text, text) from public, anon, authenticated;

-- Freezes a document on request. An invoice and a credit note freeze when they
-- are issued; call this for the other documents when you send them.
create or replace function ${fn("freeze_document")}(tenant ${idType}, document_type text, document_id uuid, language text default null, template_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${allowed("freeze_document.tenant")} then
    ${forbidden}
  end if;
  if freeze_document.document_type is null or freeze_document.document_type not in (${types}) then
    ${typeInvalid}
  end if;
  return ${fn("document_freeze")}(freeze_document.tenant, freeze_document.document_type, freeze_document.document_id, freeze_document.language, freeze_document.template_name);
end;
$$;
${userGrant(`${fn("freeze_document")}(${idType}, text, uuid, text, text)`)}

-- A snapshot never changes; to freeze again, delete it first.
create or replace function ${fn("document_snapshot_immutable")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  ${fail("DOCUMENT_SNAPSHOT_IMMUTABLE", "a frozen document never changes", "23000")}
end;
$$;
${triggerGrant(`${fn("document_snapshot_immutable")}()`)}
drop trigger if exists bsb_frozen_render_guard on ${snapshots};
create trigger bsb_frozen_render_guard
  before update on ${snapshots}
  for each row execute function ${fn("document_snapshot_immutable")}();
`;
}
