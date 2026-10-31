import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { fail, serviceGrant } from "../shared.ts";

/** An import target names its functions as `schema.function`, without quotes. */
const plain = (qualified: string): string => qualified.replaceAll('"', "");

/**
 * The import targets of templates and text blocks (ADR 0141): one template per
 * (document type, name, legal entity, language) slot and one text block per
 * (key, legal entity, language), written through `save_document_template` and
 * `save_document_text_block` so the same checks apply. A legal entity is named
 * by its `legalEntityId` or its `legalEntity` code.
 */
export function documentTemplateImportFunctions(ctx: BlockSqlContext): string {
  const templates = ctx.table("templates");
  const blocks = ctx.table("textBlocks");
  const x = (column: string): string => ctx.col("templates", column);
  const y = (column: string): string => ctx.col("textBlocks", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const legal = ctx.of("legal-entities");
  const entities = legal.table("entities");
  const e = (column: string): string => legal.col("entities", column);

  const invalid = (message: string): string =>
    fail("IMPORT_ITEM_INVALID", message, "22023");

  const entityLookup = `
  if nullif(v_data ->> 'legalEntityId', '') is not null then
    v_entity := (v_data ->> 'legalEntityId')::uuid;
  elsif nullif(v_data ->> 'legalEntity', '') is not null then
    select x.${e("id")} into v_entity from ${entities} x
      where x.${e("tenant")} = v_tenant and x.${e("code")} = v_data ->> 'legalEntity';
    if v_entity is null then
      ${invalid("the legal entity code is unknown")}
    end if;
  end if;`;

  return `
-- item.data is { documentType, body, name?, language?, legalEntityId? or
-- legalEntity? (a code), active? }. The slot is the document type, name, legal
-- entity and language; importing it again changes the body and raises the version.
create or replace function ${fn("import_document_template")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType} := (import_document_template.item ->> 'tenant')::${idType};
  v_data jsonb := import_document_template.item -> 'data';
  v_entity uuid;
  v_saved jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    ${invalid("a template item is an object")}
  end if;${entityLookup}
  v_saved := ${fn("save_document_template")}(v_tenant, v_data ->> 'documentType', v_data ->> 'body', v_data ->> 'language',
    coalesce(nullif(v_data ->> 'name', ''), 'default'), v_entity, coalesce((v_data ->> 'active')::boolean, true));
  return jsonb_build_object('subjectId', v_saved ->> 'id', 'updatedAt', v_saved -> 'updatedAt');
end;
$$;
${serviceGrant(`${fn("import_document_template")}(uuid, jsonb, text)`)}

-- item.data is { key, body, language?, legalEntityId? or legalEntity? }.
create or replace function ${fn("import_document_text_block")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType} := (import_document_text_block.item ->> 'tenant')::${idType};
  v_data jsonb := import_document_text_block.item -> 'data';
  v_entity uuid;
  v_saved jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    ${invalid("a text block item is an object")}
  end if;${entityLookup}
  v_saved := ${fn("save_document_text_block")}(v_tenant, v_data ->> 'key', v_data ->> 'body', v_data ->> 'language', v_entity);
  return jsonb_build_object('subjectId', v_saved ->> 'id', 'updatedAt', v_saved -> 'updatedAt');
end;
$$;
${serviceGrant(`${fn("import_document_text_block")}(uuid, jsonb, text)`)}

-- When a template or text block last changed, for the conflict check of imports.
create or replace function ${fn("document_template_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select t.${x("updatedAt")} from ${templates} t where t.${x("id")} = $1::uuid
$$;
${serviceGrant(`${fn("document_template_updated_at")}(text)`)}

create or replace function ${fn("document_text_block_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select b.${y("updatedAt")} from ${blocks} b where b.${y("id")} = $1::uuid
$$;
${serviceGrant(`${fn("document_text_block_updated_at")}(text)`)}
`;
}

/** The entities `import_upsert_batch` takes for this block. */
export function documentTemplateImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return [
    {
      entity: "document_template",
      subjectType: "document_template",
      write: plain(own.fn("import_document_template")),
      updatedAt: plain(own.fn("document_template_updated_at")),
    },
    {
      entity: "document_text_block",
      subjectType: "document_text_block",
      write: plain(own.fn("import_document_text_block")),
      updatedAt: plain(own.fn("document_text_block_updated_at")),
    },
  ];
}
