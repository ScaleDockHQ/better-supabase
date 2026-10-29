import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  activeMembership,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  SERVICE_CALLER,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";
import {
  evidenceAttachments,
  holderTypes,
  holdingStatus,
  optionalField,
  QUALIFICATION_RESERVED,
  sqlList,
  TARGET_TYPES,
} from "./qualifications-shared.ts";

/** The blocks a requirement target reads, when it reads one. */
const TARGET_BLOCKS: Readonly<Record<string, string>> = {
  team: "teams",
  job_title: "employees",
  asset_kind: "assets",
  segment: "segments",
};

/** The blocks a holder type reads its holders from. */
const HOLDER_BLOCKS: Readonly<Record<string, string>> = {
  company: "contacts",
  asset: "assets",
};

/** The JSON of a qualification type row. */
function typeJson(ctx: BlockSqlContext, row: string): string {
  const t = (column: string): string => `${row}.${ctx.col("types", column)}`;

  const field = (column: string): string =>
    optionalField(ctx, "types", row, column);

  return `jsonb_build_object('id', ${t("id")}, 'organizationId', ${t("tenant")}, 'key', ${t("key")}, 'name', ${t("name")}, 'description', ${field("description")}, 'holderTypes', to_jsonb(${t("holderTypes")}), 'validForMonths', ${t("validForMonths")}, 'evidenceRequired', ${t("evidenceRequired")}, 'courseId', ${field("course")}, 'archivedAt', ${t("archivedAt")}, 'createdAt', ${field("createdAt")}, 'updatedAt', ${field("updatedAt")})`;
}

/** The JSON of holding `row` of type `type` (a types row). */
function holdingJson(ctx: BlockSqlContext, row: string, type: string): string {
  const q = (column: string): string =>
    `${row}.${ctx.col("qualifications", column)}`;

  const field = (column: string): string =>
    optionalField(ctx, "qualifications", row, column);

  const extras = ctx.extraColumns("qualifications", QUALIFICATION_RESERVED);

  return `jsonb_build_object('id', ${q("id")}, 'organizationId', ${q("tenant")}, 'qualificationTypeId', ${q("type")}, 'typeKey', ${type}.${ctx.col("types", "key")}, 'typeName', ${type}.${ctx.col("types", "name")}, 'holderType', ${q("holderType")}, 'holderId', ${q("holderId")}, 'grantedOn', ${q("grantedOn")}, 'expiresOn', ${q("expiresOn")}, 'revokedAt', ${q("revokedAt")}, 'revokeReason', ${field("revokeReason")}, 'evidenceAttachmentId', ${q("evidenceAttachment")}, 'evidenceNote', ${field("evidenceNote")}, 'source', ${q("source")}, 'sourceId', ${q("sourceId")}, 'grantedBy', ${field("grantedBy")}, 'status', ${holdingStatus(ctx, row)}, 'createdAt', ${field("createdAt")}, 'updatedAt', ${field("updatedAt")}${extraFieldsJson(row, extras)})`;
}

/**
 * The `qualification.granted` or `.revoked` record of holding `row` of type
 * `type`, with `extra` (`, 'key', value` pairs) after the shared keys.
 */
export function holdingRecord(
  ctx: BlockSqlContext,
  options: {
    readonly event: string;
    readonly row: string;
    readonly type: string;
    readonly extra: string;
    readonly summary: string;
    readonly audit?: boolean;
  },
): string {
  const q = (column: string): string =>
    `${options.row}.${ctx.col("qualifications", column)}`;

  const key = `${options.type}.${ctx.col("types", "key")}`;

  return ctx.record({
    type: options.event,
    payload: `jsonb_build_object('organizationId', ${q("tenant")}, 'qualificationId', ${q("id")}, 'qualificationTypeId', ${q("type")}, 'typeKey', ${key}, 'holderType', ${q("holderType")}, 'holderId', ${q("holderId")}${options.extra})`,
    subject: `'qualifications/' || ${q("id")}::text`,
    tenant: q("tenant"),
    audit:
      options.audit === false
        ? false
        : {
            category: "data",
            targetType: "qualification",
            recordId: `${q("id")}::text`,
            targetLabel: `${options.type}.${ctx.col("types", "name")}`,
            summary: options.summary,
          },
  });
}

/** The type, requirement and holding functions. */
export function qualificationFunctions(ctx: BlockSqlContext): string {
  const types = ctx.table("types");
  const requirements = ctx.table("requirements");
  const holdings = ctx.table("qualifications");
  const t = (column: string): string => ctx.col("types", column);
  const r = (column: string): string => ctx.col("requirements", column);
  const q = (column: string): string => ctx.col("qualifications", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("qualifications");
  const manage = ctx.permission("manage", permissions.manage);
  const grant = ctx.permission("grant", permissions.grant);
  const members = ctx.of("memberships");
  const m = (column: string): string => members.col("memberships", column);
  const attachments = evidenceAttachments(ctx);
  const allowedHolders = holderTypes(ctx);
  const extras = ctx.extraColumns("qualifications", QUALIFICATION_RESERVED);
  const extra = extraFieldsArg(extras);

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const insertCol = (table: string, column: string): string =>
    has(table, column) ? `, ${ctx.col(table, column)}` : "";

  const insertVal = (table: string, column: string, value: string): string =>
    has(table, column) ? `, ${value}` : "";

  const touch = (table: string): string =>
    has(table, "updatedAt") ? `, ${ctx.col(table, "updatedAt")} = now()` : "";

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("QUALIFICATION_FORBIDDEN", message);

  const typeInvalid = (message: string): string =>
    fail("QUALIFICATION_TYPE_INVALID", message, "22023");

  const requirementInvalid = (message: string): string =>
    fail("QUALIFICATION_REQUIREMENT_INVALID", message, "22023");

  const holderInvalid = (message: string): string =>
    fail("QUALIFICATION_HOLDER_INVALID", message, "22023");

  const typeNotFound = fail(
    "QUALIFICATION_TYPE_NOT_FOUND",
    "qualification type not found",
    "P0002",
  );

  const typeRecord = (
    event: string,
    row: string,
    payload: string,
    summary: string,
  ): string =>
    ctx.record({
      type: event,
      payload,
      subject: `'qualification-types/' || ${row}.${t("id")}::text`,
      tenant: `${row}.${t("tenant")}`,
      audit: {
        category: "configuration",
        targetType: "qualification_type",
        recordId: `${row}.${t("id")}::text`,
        targetLabel: `${row}.${t("name")}`,
        summary: `'${summary}'`,
      },
    });

  const savedPayload = `jsonb_build_object('organizationId', v_row.${t("tenant")}, 'qualificationTypeId', v_row.${t("id")}, 'key', v_row.${t("key")}, 'name', v_row.${t("name")})`;

  const courses = ctx.installed("courses") ? ctx.of("courses") : undefined;

  const courseCheck = has("types", "course")
    ? courses === undefined
      ? `if save_qualification_type.course_id is not null then
    ${typeInvalid("course_id needs the courses block")}
  end if;`
      : `if save_qualification_type.course_id is not null and not exists (
    select 1 from ${courses.table("courses")} c
    where c.${courses.col("courses", "id")} = save_qualification_type.course_id
      and c.${courses.col("courses", "tenant")} = save_qualification_type.tenant
  ) then
    ${typeInvalid("the course isn't in this organization")}
  end if;`
    : `if save_qualification_type.course_id is not null then
    ${typeInvalid("the qualification types table has no course column")}
  end if;`;

  const typeSets = [
    `${t("name")} = v_name`,
    has("types", "description")
      ? `${t("description")} = nullif(trim(save_qualification_type.description), '')`
      : "",
    `${t("holderTypes")} = v_holders`,
    `${t("validForMonths")} = save_qualification_type.valid_for_months`,
    `${t("evidenceRequired")} = coalesce(save_qualification_type.evidence_required, false)`,
    has("types", "course")
      ? `${t("course")} = save_qualification_type.course_id`
      : "",
    `${t("archivedAt")} = null`,
    has("types", "updatedAt") ? `${t("updatedAt")} = now()` : "",
  ]
    .filter((set) => set !== "")
    .join(",\n      ");

  const holderModules = allowedHolders
    .filter((type) => {
      const block = HOLDER_BLOCKS[type];

      return block !== undefined && !ctx.installed(block);
    })
    .map(
      (type) => `if ${sqlString(type)} = any(v_holders) then
    ${typeInvalid(`${type} holders need the ${HOLDER_BLOCKS[type] ?? ""} block`)}
  end if;`,
    )
    .join("\n  ");

  // A requirement target applies to one holder type and may need its block.
  const targetChecks = Object.entries(TARGET_TYPES)
    .map(([target, holder]) => {
      const block = TARGET_BLOCKS[target];

      const missing =
        block !== undefined && !ctx.installed(block)
          ? `
    ${requirementInvalid(`${target} requirements need the ${block} block`)}`
          : "";

      const wrongHolder =
        holder === undefined
          ? ""
          : `
    if not (${sqlString(holder)} = any(v_type.${t("holderTypes")})) then
      ${requirementInvalid(`${target} requirements apply to ${holder} holders`)}
    end if;`;

      const exists = targetExists(ctx, target);

      return missing === "" && wrongHolder === "" && exists === ""
        ? ""
        : `if add_qualification_requirement.target_type = ${sqlString(target)} then${missing}${wrongHolder}${exists}
  end if;`;
    })
    .filter((check) => check !== "")
    .join("\n  ");

  const holderExists = `case grant_qualification.holder_type
      when 'member' then exists (select 1 from ${members.table("memberships")} m where m.${m("tenant")} = v_type.${t("tenant")} and m.${m("user")}::text = grant_qualification.holder_id${activeMembership(members, "m")})${allowedHolders
        .filter((type) => type !== "member")
        .map((type) => {
          const condition = holderCondition(
            ctx,
            type,
            `v_type.${t("tenant")}`,
            "grant_qualification.holder_id",
          );

          return condition === undefined
            ? ""
            : `\n      when ${sqlString(type)} then ${condition}`;
        })
        .join("")}
      else false
    end`;

  const attachmentCheck =
    attachments === undefined
      ? `if grant_qualification.evidence_attachment_id is not null then
    ${fail("QUALIFICATION_INVALID", "evidence files need the attachments block", "22023")}
  end if;`
      : `if grant_qualification.evidence_attachment_id is not null and not exists (
    select 1 from ${attachments.table("attachments")} a
    where a.${attachments.col("attachments", "id")} = grant_qualification.evidence_attachment_id
      and a.${attachments.col("attachments", "tenant")} = v_type.${t("tenant")}
  ) then
    ${fail("QUALIFICATION_INVALID", "the attachment isn't a file in this organization", "22023")}
  end if;`;

  const evidenceNote = has("qualifications", "evidenceNote")
    ? " and nullif(trim(grant_qualification.evidence_note), '') is null"
    : "";

  return `
-- Creates a qualification type, or changes one (type_id). Without type_id,
-- a type with the same key is updated (and unarchived). valid_for_months
-- sets how long a holding lasts (null: it never expires); course_id grants
-- the type when a member earns that course's certificate.
create or replace function ${fn("save_qualification_type")}(tenant ${idType}, key text, name text, holder_types text[], valid_for_months integer default null, evidence_required boolean default false, course_id uuid default null, description text default null, type_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${types}%rowtype;
  v_new boolean;
  v_name text := nullif(trim(save_qualification_type.name), '');
  v_holders text[] := array(select distinct h from unnest(save_qualification_type.holder_types) h where h is not null order by h);
begin
  if not ${allowed("save_qualification_type.tenant", manage)} then
    ${forbidden("not allowed to manage qualifications")}
  end if;
  if save_qualification_type.key is null or save_qualification_type.key !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    ${typeInvalid("the key takes lowercase letters, digits, dots, dashes and underscores")}
  end if;
  if v_name is null or length(v_name) > 200 then
    ${typeInvalid("a qualification type needs a name of at most 200 characters")}
  end if;
  if cardinality(v_holders) = 0 or not (v_holders <@ array[${allowedHolders.map((type) => sqlString(type)).join(", ")}]::text[]) then
    ${typeInvalid(`holder_types takes ${allowedHolders.join(", ")}`)}
  end if;
  ${holderModules}
  if save_qualification_type.valid_for_months is not null and save_qualification_type.valid_for_months not between 1 and 240 then
    ${typeInvalid("valid_for_months is between 1 and 240")}
  end if;
  ${courseCheck}
  ${ctx.hook("before_qualification_type_save", [
    [idType, "save_qualification_type.tenant"],
    ["text", "save_qualification_type.key"],
  ])}
  if save_qualification_type.type_id is null then
    v_new := not exists (select 1 from ${types} x where x.${t("tenant")} = save_qualification_type.tenant and x.${t("key")} = save_qualification_type.key);
    insert into ${types} (${t("tenant")}, ${t("key")}, ${t("name")}${insertCol("types", "description")}, ${t("holderTypes")}, ${t("validForMonths")}, ${t("evidenceRequired")}${insertCol("types", "course")})
    values (save_qualification_type.tenant, save_qualification_type.key, v_name${insertVal("types", "description", "nullif(trim(save_qualification_type.description), '')")}, v_holders, save_qualification_type.valid_for_months, coalesce(save_qualification_type.evidence_required, false)${insertVal("types", "course", "save_qualification_type.course_id")})
    on conflict (${t("tenant")}, ${t("key")}) do update set
      ${typeSets}
    returning * into v_row;
  else
    v_new := false;
    update ${types} x set
      ${t("key")} = save_qualification_type.key,
      ${typeSets}
    where x.${t("id")} = save_qualification_type.type_id and x.${t("tenant")} = save_qualification_type.tenant
    returning x.* into v_row;
    if not found then
      ${typeNotFound}
    end if;
  end if;
  if v_new then
    ${typeRecord("qualification_type.created", "v_row", savedPayload, "Qualification type created")}
  else
    ${typeRecord("qualification_type.updated", "v_row", savedPayload, "Qualification type updated")}
  end if;
  ${ctx.hook("after_qualification_type_save", [["uuid", `v_row.${t("id")}`]])}
  return ${typeJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("save_qualification_type")}(${idType}, text, text, text[], integer, boolean, uuid, text, uuid)`)}

-- Archives a type: it takes no new holdings and leaves the gap report, and
-- its holdings stay.
create or replace function ${fn("archive_qualification_type")}(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${types}%rowtype;
begin
  select * into v_row from ${types} x where x.${t("id")} = archive_qualification_type.type_id;
  if not found then
    ${typeNotFound}
  end if;
  if not ${allowed(`v_row.${t("tenant")}`, manage)} then
    ${forbidden("not allowed to manage qualifications")}
  end if;
  if v_row.${t("archivedAt")} is null then
    update ${types} x set ${t("archivedAt")} = now()${touch("types")}
    where x.${t("id")} = v_row.${t("id")}
    returning x.* into v_row;
    ${typeRecord("qualification_type.archived", "v_row", `jsonb_build_object('organizationId', v_row.${t("tenant")}, 'qualificationTypeId', v_row.${t("id")}, 'key', v_row.${t("key")})`, "Qualification type archived")}
  end if;
  return ${typeJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("archive_qualification_type")}(uuid)`)}

create or replace function ${fn("list_qualification_types")}(tenant ${idType}, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${typeJson(ctx, "x")} order by x.${t("name")}, x.${t("key")}), '[]'::jsonb)
  from ${types} x
  where x.${t("tenant")} = list_qualification_types.tenant
    and (coalesce(list_qualification_types.include_archived, false) or x.${t("archivedAt")} is null)
$$;
${userGrant(`${fn("list_qualification_types")}(${idType}, boolean)`)}

-- Says who must hold a type: target_type role (a membership role), team (a
-- team id), job_title (an employee job title, any case), asset_kind (an
-- asset kind), segment (a segment of companies) or holder (one holder id).
create or replace function ${fn("add_qualification_requirement")}(type_id uuid, target_type text, target_value text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_type ${types}%rowtype;
  v_row ${requirements}%rowtype;
  v_value text := nullif(trim(add_qualification_requirement.target_value), '');
begin
  select * into v_type from ${types} x where x.${t("id")} = add_qualification_requirement.type_id;
  if not found then
    ${typeNotFound}
  end if;
  if not ${allowed(`v_type.${t("tenant")}`, manage)} then
    ${forbidden("not allowed to manage qualifications")}
  end if;
  if add_qualification_requirement.target_type is null or add_qualification_requirement.target_type not in ${sqlList(Object.keys(TARGET_TYPES))} then
    ${requirementInvalid(`target_type is one of ${Object.keys(TARGET_TYPES).join(", ")}`)}
  end if;
  if v_value is null or length(v_value) > 200 then
    ${requirementInvalid("a requirement needs a target value of at most 200 characters")}
  end if;
  ${targetChecks}
  insert into ${requirements} (${r("tenant")}, ${r("type")}, ${r("targetType")}, ${r("targetValue")})
  values (v_type.${t("tenant")}, v_type.${t("id")}, add_qualification_requirement.target_type, v_value)
  on conflict (${r("type")}, ${r("targetType")}, ${r("targetValue")}) do nothing;
  select * into v_row from ${requirements} x
  where x.${r("type")} = v_type.${t("id")} and x.${r("targetType")} = add_qualification_requirement.target_type and x.${r("targetValue")} = v_value;
  return ${requirementJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("add_qualification_requirement")}(uuid, text, text)`)}

create or replace function ${fn("remove_qualification_requirement")}(requirement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${requirements}%rowtype;
begin
  select * into v_row from ${requirements} x where x.${r("id")} = remove_qualification_requirement.requirement_id;
  if not found then
    ${fail("QUALIFICATION_REQUIREMENT_NOT_FOUND", "requirement not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${r("tenant")}`, manage)} then
    ${forbidden("not allowed to manage qualifications")}
  end if;
  delete from ${requirements} x where x.${r("id")} = v_row.${r("id")};
  return ${requirementJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("remove_qualification_requirement")}(uuid)`)}

create or replace function ${fn("list_qualification_requirements")}(type_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${requirementJson(ctx, "x")} order by x.${r("targetType")}, x.${r("targetValue")}), '[]'::jsonb)
  from ${requirements} x
  where x.${r("type")} = list_qualification_requirements.type_id
$$;
${userGrant(`${fn("list_qualification_requirements")}(uuid)`)}

-- Grants a qualification to a holder (a member's user id, a company id or
-- an asset id). The holding expires valid_for_months after granted_on;
-- earlier holdings of the same type stay as history.
${extra.drop(fn("grant_qualification"), `${idType}, text, text, text, date, uuid, text`)}
create or replace function ${fn("grant_qualification")}(tenant ${idType}, type_key text, holder_type text, holder_id text, granted_on date default current_date, evidence_attachment_id uuid default null, evidence_note text default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_type ${types}%rowtype;
  v_row ${holdings}%rowtype;
begin
  if not ${allowed("grant_qualification.tenant", grant)} then
    ${forbidden("not allowed to grant qualifications")}
  end if;
  select * into v_type from ${types} x
  where x.${t("tenant")} = grant_qualification.tenant and x.${t("key")} = grant_qualification.type_key and x.${t("archivedAt")} is null;
  if not found then
    ${typeNotFound}
  end if;
  if grant_qualification.holder_type is null or not (grant_qualification.holder_type = any(v_type.${t("holderTypes")})) then
    ${holderInvalid("the type doesn't apply to this holder type")}
  end if;
  if grant_qualification.holder_id is null or not (${holderExists}) then
    ${holderInvalid("the holder isn't in this organization")}
  end if;
  if grant_qualification.granted_on is null then
    ${fail("QUALIFICATION_INVALID", "granted_on is required", "22023")}
  end if;
  if v_type.${t("evidenceRequired")} and grant_qualification.evidence_attachment_id is null${evidenceNote} then
    ${fail("QUALIFICATION_EVIDENCE_REQUIRED", "this qualification type needs evidence", "22023")}
  end if;
  ${attachmentCheck}
  ${ctx.hook("before_qualification_grant", [
    ["uuid", `v_type.${t("id")}`],
    ["text", "grant_qualification.holder_type"],
    ["text", "grant_qualification.holder_id"],
  ])}
  insert into ${holdings} (${q("tenant")}, ${q("type")}, ${q("holderType")}, ${q("holderId")}, ${q("grantedOn")}, ${q("expiresOn")}, ${q("evidenceAttachment")}${insertCol("qualifications", "evidenceNote")}, ${q("source")}${insertCol("qualifications", "grantedBy")})
  values (v_type.${t("tenant")}, v_type.${t("id")}, grant_qualification.holder_type, grant_qualification.holder_id, grant_qualification.granted_on, ${expiry(`v_type.${t("validForMonths")}`, "grant_qualification.granted_on")}, grant_qualification.evidence_attachment_id${insertVal("qualifications", "evidenceNote", "nullif(trim(grant_qualification.evidence_note), '')")}, 'manual'${insertVal("qualifications", "grantedBy", "(select auth.uid())")})
  returning * into v_row;${writeExtraColumns(holdings, extras, "grant_qualification.fields", `x.${q("id")} = v_row.${q("id")}`, "v_row")}
  ${holdingRecord(ctx, {
    event: "qualification.granted",
    row: "v_row",
    type: "v_type",
    extra: `, 'grantedOn', v_row.${q("grantedOn")}, 'expiresOn', v_row.${q("expiresOn")}, 'source', v_row.${q("source")}`,
    summary: "'Qualification granted'",
  })}
  ${ctx.hook("after_qualification_grant", [["uuid", `v_row.${q("id")}`]])}
  return ${holdingJson(ctx, "v_row", "v_type")};
end;
$$;
${userGrant(`${fn("grant_qualification")}(${idType}, text, text, text, date, uuid, text${extra.type})`)}

-- Revokes a holding. Revoking one already revoked changes nothing.
create or replace function ${fn("revoke_qualification")}(qualification_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${holdings}%rowtype;
  v_type ${types}%rowtype;
begin
  select * into v_row from ${holdings} x where x.${q("id")} = revoke_qualification.qualification_id;
  if not found then
    ${fail("QUALIFICATION_NOT_FOUND", "qualification not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${q("tenant")}`, grant)} then
    ${forbidden("not allowed to revoke qualifications")}
  end if;
  select * into v_type from ${types} x where x.${t("id")} = v_row.${q("type")};
  if v_row.${q("revokedAt")} is null then
    ${ctx.hook("before_qualification_revoke", [["uuid", `v_row.${q("id")}`]])}
    update ${holdings} x set ${q("revokedAt")} = now()${has("qualifications", "revokeReason") ? `, ${q("revokeReason")} = left(nullif(trim(revoke_qualification.reason), ''), 2000)` : ""}${touch("qualifications")}
    where x.${q("id")} = v_row.${q("id")}
    returning x.* into v_row;
    ${holdingRecord(ctx, {
      event: "qualification.revoked",
      row: "v_row",
      type: "v_type",
      extra: `, 'reason', nullif(trim(revoke_qualification.reason), '')`,
      summary: "'Qualification revoked'",
    })}
    ${ctx.hook("after_qualification_revoke", [["uuid", `v_row.${q("id")}`]])}
  end if;
  return ${holdingJson(ctx, "v_row", "v_type")};
end;
$$;
${userGrant(`${fn("revoke_qualification")}(uuid, text)`)}

-- The holdings of one holder the caller may read, newest first, with each
-- one's status: valid, expiring, expired or revoked.
create or replace function ${fn("qualifications_of")}(holder_type text, holder_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${holdingJson(ctx, "x", "y")} order by x.${q("grantedOn")} desc, y.${t("name")}), '[]'::jsonb)
  from ${holdings} x
  join ${types} y on y.${t("id")} = x.${q("type")}
  where x.${q("holderType")} = qualifications_of.holder_type and x.${q("holderId")} = qualifications_of.holder_id
$$;
${userGrant(`${fn("qualifications_of")}(text, text)`)}
`;
}

/** The expiry of a holding granted on `on` (a date) for `months` (an integer). */
export const expiry = (months: string, on: string): string =>
  `case when ${months} is null then null else (${on} + make_interval(months => ${months}))::date end`;

/** The JSON of a requirement row. */
function requirementJson(ctx: BlockSqlContext, row: string): string {
  const r = (column: string): string =>
    `${row}.${ctx.col("requirements", column)}`;

  return `jsonb_build_object('id', ${r("id")}, 'organizationId', ${r("tenant")}, 'qualificationTypeId', ${r("type")}, 'targetType', ${r("targetType")}, 'targetValue', ${r("targetValue")}, 'createdAt', ${optionalField(ctx, "requirements", row, "createdAt")})`;
}

/**
 * The check that a team or segment requirement names one of the organization's
 * teams or segments, or empty for the other targets.
 */
function targetExists(ctx: BlockSqlContext, target: string): string {
  const block =
    target === "team" ? "teams" : target === "segment" ? "segments" : undefined;

  if (block === undefined || !ctx.installed(block)) {
    return "";
  }

  const other = ctx.of(block);
  const logical = block;
  const col = (column: string): string => other.col(logical, column);

  return `
    if not exists (select 1 from ${other.table(logical)} o where o.${col("id")}::text = v_value and o.${col("tenant")} = v_type.${ctx.col("types", "tenant")}) then
      ${fail("QUALIFICATION_REQUIREMENT_INVALID", `the ${target} isn't in this organization`, "22023")}
    end if;`;
}

/**
 * Whether holder `id` (text) of `type` is one of tenant `tenant`'s companies or
 * assets, or undefined when its block isn't installed.
 */
export function holderCondition(
  ctx: BlockSqlContext,
  type: string,
  tenant: string,
  id: string,
): string | undefined {
  const block = HOLDER_BLOCKS[type];

  if (block === undefined || !ctx.installed(block)) {
    return undefined;
  }

  const other = ctx.of(block);

  if (type === "company") {
    const c = (column: string): string => other.col("companies", column);

    return `exists (select 1 from ${other.table("companies")} c where c.${c("tenant")} = ${tenant} and c.${c("id")}::text = ${id} and c.${c("archivedAt")} is null and c.${c("mergedInto")} is null)`;
  }

  const a = (column: string): string => other.col("assets", column);

  return `exists (select 1 from ${other.table("assets")} a where a.${a("tenant")} = ${tenant} and a.${a("id")}::text = ${id})`;
}
