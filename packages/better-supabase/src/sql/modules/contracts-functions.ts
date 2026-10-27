import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  extraFieldsArg,
  extraFieldsJson,
  fail,
  pageSize,
  SERVICE_CALLER,
  serviceGrant,
  triggerGrant,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { CONTRACT_RESERVED, keepsContract } from "./contracts-shared.ts";
import { asText } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

/**
 * `options.reminderDays`: how many days before the notice deadline the owner
 * hears.
 */
function reminderDays(ctx: BlockSqlContext): number {
  const days = ctx.number("reminderDays", 14);

  if (!Number.isInteger(days) || days < 0 || days > 365) {
    throw new TypeError(
      "blocks.contracts.options.reminderDays must be a whole number from 0 to 365",
    );
  }

  return days;
}

/** The contract and obligation functions of the `contracts` module. */
export function contractsFunctions(ctx: BlockSqlContext): string {
  const contracts = ctx.table("contracts");
  const obligations = ctx.table("obligations");
  const c = (column: string): string => ctx.col("contracts", column);
  const o = (column: string): string => ctx.col("obligations", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("contracts");
  const write = ctx.permission("write", permissions.write);
  const manage = ctx.permission("manage", permissions.manage);
  const members = ctx.of("memberships");
  const versions = ctx.of("versions");
  const signatures = ctx.of("signatures");
  const sr = signatures.table("requests");
  const s = (column: string): string => signatures.col("requests", column);
  const reminders = ctx.of("reminders");
  const rules = reminders.table("rules");
  const ru = (column: string): string => reminders.col("rules", column);
  const rem = reminders.table("reminders");
  const re = (column: string): string => reminders.col("reminders", column);
  const subjectType = sqlString(ctx.resolved.entityNaming.rename("contract"));
  const offset = String(reminderDays(ctx) * 1440);
  const extras = ctx.extraColumns("contracts", CONTRACT_RESERVED);
  const extra = extraFieldsArg(extras);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("CONTRACT_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("CONTRACT_INVALID", message, "22023");

  const notFound = fail("CONTRACT_NOT_FOUND", "contract not found", "P0002");

  const keeps = (column: string): boolean => keepsContract(ctx, column);

  const obligationKeeps = (column: string): boolean =>
    ctx.has("obligations", column);

  const counterparty = keeps("counterpartyType");

  // Column `column` of row `row`, or `missing` when the app's table lacks it.
  const contractValue = (
    row: string,
    column: string,
    missing = "null",
  ): string => (keeps(column) ? `${row}.${c(column)}` : missing);

  const obligationValue = (
    row: string,
    column: string,
    missing = "null",
  ): string => (obligationKeeps(column) ? `${row}.${o(column)}` : missing);

  const contractStatus = (row: string): string =>
    asText(ctx, "contracts", `${row}.${c("status")}`);

  // `column = value` assignments for the columns the contracts table keeps.
  const sets = (
    pairs: readonly (readonly [column: string, value: string])[],
  ): string[] =>
    pairs
      .filter(([column]) => keeps(column))
      .map(([column, value]) => `${c(column)} = ${value}`);

  const touched = keeps("updatedAt") ? `, ${c("updatedAt")} = now()` : "";

  const isMember = (tenant: string, user: string): string =>
    `exists (select 1 from ${members.table("memberships")} m where m.${members.col("memberships", "tenant")} = ${tenant} and m.${members.col("memberships", "user")} = ${user})`;

  const deadline = (row: string): string =>
    `case when ${row}.${c("endsOn")} is null then null else ${row}.${c("endsOn")} - ${row}.${c("noticeDays")} end`;

  const contractJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'title', ${row}.${c("title")}, 'description', ${contractValue(row, "description")}, 'counterpartyType', ${contractValue(row, "counterpartyType")}, 'counterpartyId', ${contractValue(row, "counterpartyId")}, 'ownerId', ${row}.${c("owner")}, 'status', ${row}.${c("status")}, 'value', ${contractValue(row, "value")}::text, 'currency', ${contractValue(row, "currency")}, 'startsOn', ${row}.${c("startsOn")}, 'endsOn', ${row}.${c("endsOn")}, 'autoRenew', ${row}.${c("autoRenew")}, 'renewalMonths', ${row}.${c("renewalMonths")}, 'noticeDays', ${row}.${c("noticeDays")}, 'noticeDeadline', ${deadline(row)}, 'renewedCount', ${contractValue(row, "renewedCount", "0")}, 'signatureRequestId', ${row}.${c("signatureRequest")}, 'signedAt', ${contractValue(row, "signedAt")}, 'terminatedAt', ${contractValue(row, "terminatedAt")}, 'terminationReason', ${contractValue(row, "terminationReason")}, 'createdBy', ${contractValue(row, "createdBy")}, 'createdAt', ${row}.${c("createdAt")}, 'updatedAt', ${contractValue(row, "updatedAt", `${row}.${c("createdAt")}`)}${extraFieldsJson(row, extras)})`;

  const obligationJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${o("id")}, 'organizationId', ${row}.${o("tenant")}, 'contractId', ${row}.${o("contract")}, 'title', ${row}.${o("title")}, 'description', ${obligationValue(row, "description")}, 'dueOn', ${row}.${o("dueOn")}, 'ownerId', ${row}.${o("owner")}, 'status', ${row}.${o("status")}, 'overdue', (${row}.${o("status")} = 'open' and ${row}.${o("dueOn")} < current_date), 'completedAt', ${obligationValue(row, "completedAt")}, 'completedBy', ${obligationValue(row, "completedBy")}, 'createdAt', ${row}.${o("createdAt")}, 'updatedAt', ${obligationValue(row, "updatedAt", `${row}.${o("createdAt")}`)})`;

  const contractRecord = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${c("tenant")}, 'contractId', ${row}.${c("id")}, 'title', ${row}.${c("title")}, 'status', ${row}.${c("status")})`,
      subject: `'contracts/' || ${row}.${c("id")}::text`,
      tenant: `${row}.${c("tenant")}`,
      audit: {
        category: "data",
        targetType: "contract",
        recordId: `${row}.${c("id")}::text`,
        summary: `${sqlString(summary)} || ' ' || ${row}.${c("title")}`,
      },
    });

  const obligationRecord = (
    type: string,
    row: string,
    summary: string,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${o("tenant")}, 'obligationId', ${row}.${o("id")}, 'contractId', ${row}.${o("contract")}, 'status', ${row}.${o("status")})`,
      subject: `'obligations/' || ${row}.${o("id")}::text`,
      tenant: `${row}.${o("tenant")}`,
      audit: {
        category: "data",
        targetType: "obligation",
        recordId: `${row}.${o("id")}::text`,
        summary: `${sqlString(summary)} || ' ' || ${row}.${o("title")}`,
      },
    });

  const savedObligation = (
    [
      ["tenant", `v_contract.${c("tenant")}`],
      ["contract", `v_contract.${c("id")}`],
      ["title", "trim(save_obligation.title)"],
      ["description", "nullif(trim(save_obligation.description), '')"],
      ["dueOn", "save_obligation.due_on"],
      ["owner", "save_obligation.owner_id"],
    ] as const
  ).filter(([column]) => obligationKeeps(column));

  // The checks create_contract and update_contract share, over v_row.
  const termsCheck = `${
    counterparty
      ? `if v_row.${c("counterpartyType")} is not null and not ${subjectInTenant(ctx, `v_row.${c("counterpartyType")}`, `v_row.${c("counterpartyId")}`, `v_row.${c("tenant")}`)} then
    ${invalid("the counterparty is unknown or not in this organization")}
  end if;
  `
      : ""
  }if v_row.${c("owner")} is not null and not ${isMember(`v_row.${c("tenant")}`, `v_row.${c("owner")}`)} then
    ${invalid("the owner must be a member of the organization")}
  end if;`;

  const created = (
    [
      ["tenant", `v_row.${c("tenant")}`],
      ["title", `v_row.${c("title")}`],
      ["description", contractValue("v_row", "description")],
      ["counterpartyType", contractValue("v_row", "counterpartyType")],
      ["counterpartyId", contractValue("v_row", "counterpartyId")],
      ["owner", `v_row.${c("owner")}`],
      ["value", contractValue("v_row", "value")],
      ["currency", `upper(${contractValue("v_row", "currency")})`],
      ["startsOn", `v_row.${c("startsOn")}`],
      ["endsOn", `v_row.${c("endsOn")}`],
      ["autoRenew", `coalesce(v_row.${c("autoRenew")}, false)`],
      ["renewalMonths", `coalesce(v_row.${c("renewalMonths")}, 12)`],
      ["noticeDays", `coalesce(v_row.${c("noticeDays")}, 30)`],
      ["createdBy", "auth.uid()"],
    ] as const
  ).filter(([column]) => keeps(column));

  // attrs (jsonb) over the current row, for create (v_row empty) and update.
  const assign = (column: string, key: string, cast: string): string =>
    `v_row.${c(column)} := case when attrs ? '${key}' then (attrs ->> '${key}')::${cast} else v_row.${c(column)} end;`;

  const attributes = [
    ["title", "title", "text"],
    ["description", "description", "text"],
    ["counterpartyType", "counterpartyType", "text"],
    ["counterpartyId", "counterpartyId", "text"],
    ["owner", "ownerId", "uuid"],
    ["value", "value", "bigint"],
    ["currency", "currency", "text"],
    ["startsOn", "startsOn", "date"],
    ["endsOn", "endsOn", "date"],
    ["autoRenew", "autoRenew", "boolean"],
    ["renewalMonths", "renewalMonths", "integer"],
    ["noticeDays", "noticeDays", "integer"],
  ] as const;

  const dropped = attributes
    .filter(([column]) => !keeps(column))
    .map(([, key]) => sqlString(key));

  // An attrs key for a column the app's contracts table doesn't keep fails
  // instead of being dropped.
  const applyAttrs = (attrs: string): string =>
    [
      ...(dropped.length === 0
        ? []
        : [
            `if attrs ?| array[${dropped.join(", ")}] then
    ${fail("CONTRACT_FIELD_UNSUPPORTED", "this contracts table doesn't keep every attribute passed", "0A000")}
  end if;`,
          ]),
      ...attributes
        .filter(([column]) => keeps(column))
        .map(([column, key, cast]) => assign(column, key, cast)),
    ]
      .map((line) => line.replaceAll("attrs", attrs))
      .join("\n  ");

  return `
-- Keeps the contract's renewal reminder in step with its terms: while it is
-- active with an end date, the reminders block holds one occurrence at the
-- notice deadline and the owner a reminder before it (options.reminderDays).
create or replace function ${fn("contract_schedule_renewal")}(contract_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${contracts}%rowtype;
begin
  select * into v_row from ${contracts} x where x.${c("id")} = contract_schedule_renewal.contract_id;
  if not found then
    return;
  end if;
  if v_row.${c("status")} <> 'active' or v_row.${c("endsOn")} is null then
    delete from ${rem} x where x.${re("tenant")} = v_row.${c("tenant")} and x.${re("subjectType")} = ${subjectType} and x.${re("subjectId")} = v_row.${c("id")}::text;
    delete from ${rules} x where x.${ru("tenant")} = v_row.${c("tenant")} and x.${ru("subjectType")} = ${subjectType} and x.${ru("subjectId")} = v_row.${c("id")}::text;
    return;
  end if;
  insert into ${rules} (${ru("tenant")}, ${ru("subjectType")}, ${ru("subjectId")}, ${ru("dtstart")}, ${ru("tzid")})
  values (v_row.${c("tenant")}, ${subjectType}, v_row.${c("id")}::text, ((${deadline("v_row")})::timestamp + interval '9 hours') at time zone 'UTC', 'UTC')
  on conflict (${ru("tenant")}, ${ru("subjectType")}, ${ru("subjectId")}) do update
    set ${ru("dtstart")} = excluded.${ru("dtstart")}, ${ru("tzid")} = excluded.${ru("tzid")};
  if v_row.${c("owner")} is not null and not exists (
    select 1 from ${rem} x
    where x.${re("tenant")} = v_row.${c("tenant")} and x.${re("subjectType")} = ${subjectType}
      and x.${re("subjectId")} = v_row.${c("id")}::text and x.${re("user")} = v_row.${c("owner")}
  ) then
    insert into ${rem} (${re("tenant")}, ${re("subjectType")}, ${re("subjectId")}, ${re("user")}, ${re("offsetMinutes")})
    values (v_row.${c("tenant")}, ${subjectType}, v_row.${c("id")}::text, v_row.${c("owner")}, ${offset});
  end if;
end;
$$;
${serviceGrant(`${fn("contract_schedule_renewal")}(uuid)`)}

-- Moves a contract to a status, stamps the timestamps the status carries and
-- records contract.status_changed. Callers check permissions and transitions.
create or replace function ${fn("contract_apply_status")}(contract_id uuid, status text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${contracts}%rowtype;
  v_from text;
begin
  select * into v_row from ${contracts} x where x.${c("id")} = contract_apply_status.contract_id for update;
  if not found then
    ${notFound}
  end if;
  v_from := ${contractStatus("v_row")};
  if v_from = contract_apply_status.status then
    return ${contractJson("v_row")};
  end if;
  update ${contracts} x set
    ${sets([
      [
        "status",
        ctx.cast("contracts", "status", "contract_apply_status.status"),
      ],
      [
        "startsOn",
        `case when contract_apply_status.status = 'active' then coalesce(x.${c("startsOn")}, current_date) else x.${c("startsOn")} end`,
      ],
      [
        "signedAt",
        `case when contract_apply_status.status = 'active' and x.${c("signatureRequest")} is not null then now() else ${contractValue("x", "signedAt")} end`,
      ],
      [
        "signatureRequest",
        `case when contract_apply_status.status in ('draft', 'in_review') then null else x.${c("signatureRequest")} end`,
      ],
      [
        "terminatedAt",
        `case when contract_apply_status.status = 'terminated' then now() else ${contractValue("x", "terminatedAt")} end`,
      ],
      [
        "terminationReason",
        `case when contract_apply_status.status = 'terminated' then nullif(trim(contract_apply_status.reason), '') else ${contractValue("x", "terminationReason")} end`,
      ],
      ["updatedAt", "now()"],
    ]).join(",\n    ")}
    where x.${c("id")} = v_row.${c("id")}
    returning * into v_row;
  perform ${fn("contract_schedule_renewal")}(v_row.${c("id")});
  ${ctx.record({
    type: "contract.status_changed",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'contractId', v_row.${c("id")}, 'status', v_row.${c("status")}, 'previousStatus', v_from)`,
    subject: `'contracts/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: {
      category: "data",
      targetType: "contract",
      recordId: `v_row.${c("id")}::text`,
      summary: `'moved contract ' || v_row.${c("title")} || ' from ' || v_from || ' to ' || ${contractStatus("v_row")}`,
    },
  })}
  return ${contractJson("v_row")};
end;
$$;
${serviceGrant(`${fn("contract_apply_status")}(uuid, text, text)`)}

-- Creates a draft contract. attrs: title (required), description,
-- counterpartyType and counterpartyId (a registered subject), ownerId, value
-- (minor units as text) and currency, startsOn, endsOn, autoRenew,
-- renewalMonths and noticeDays. fields: the extra columns to set.
${extra.drop(fn("create_contract"), `${idType}, jsonb`)}
create or replace function ${fn("create_contract")}(tenant ${idType}, attrs jsonb${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${contracts}%rowtype;
begin
  if not ${allowed("create_contract.tenant", write)} then
    ${forbidden("not allowed to create contracts")}
  end if;
  if jsonb_typeof(create_contract.attrs) is distinct from 'object' then
    ${invalid("attrs must be an object")}
  end if;
  v_row.${c("tenant")} := create_contract.tenant;
  v_row.${c("autoRenew")} := false;
  v_row.${c("renewalMonths")} := 12;
  v_row.${c("noticeDays")} := 30;
  v_row.${c("owner")} := auth.uid();
  ${applyAttrs("create_contract.attrs")}
  v_row.${c("title")} := nullif(trim(v_row.${c("title")}), '');
  if v_row.${c("title")} is null then
    ${invalid("a contract needs a title")}
  end if;
  ${termsCheck}
  insert into ${contracts} (${created.map(([column]) => c(column)).join(", ")})
  values (${created.map(([, value]) => value).join(", ")})
  returning * into v_row;${writeExtraColumns(contracts, extras, "create_contract.fields", `x.${c("id")} = v_row.${c("id")}`, "v_row")}
  ${contractRecord("contract.created", "v_row", "created contract")}
  return ${contractJson("v_row")};
end;
$$;
${userGrant(`${fn("create_contract")}(${idType}, jsonb${extra.type})`)}

-- Changes a contract's terms while it is a draft or in review. An active
-- contract takes changes to its owner, description and renewal terms only,
-- and its renewal reminder moves with them.
${extra.drop(fn("update_contract"), "uuid, jsonb")}
create or replace function ${fn("update_contract")}(contract_id uuid, attrs jsonb${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${contracts}%rowtype;
  v_owner uuid;
begin
  select * into v_row from ${contracts} x where x.${c("id")} = update_contract.contract_id for update;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`, write)} then
    ${forbidden("not allowed to change contracts")}
  end if;
  if jsonb_typeof(update_contract.attrs) is distinct from 'object' then
    ${invalid("attrs must be an object")}
  end if;
  if v_row.${c("status")} not in ('draft', 'in_review', 'active') then
    ${fail("CONTRACT_LOCKED", "this contract can no longer change", "55000")}
  end if;
  if v_row.${c("status")} = 'active' and exists (
    select 1 from jsonb_object_keys(update_contract.attrs) k
    where k not in ('description', 'ownerId', 'autoRenew', 'renewalMonths', 'noticeDays')
  ) then
    ${fail("CONTRACT_LOCKED", "an active contract changes only its owner, description and renewal terms", "55000")}
  end if;
  v_owner := v_row.${c("owner")};
  ${applyAttrs("update_contract.attrs")}
  v_row.${c("title")} := nullif(trim(v_row.${c("title")}), '');
  if v_row.${c("title")} is null then
    ${invalid("a contract needs a title")}
  end if;
  ${termsCheck}
  update ${contracts} x set
    ${
      created.length === 14 && keeps("updatedAt")
        ? `${c("title")} = v_row.${c("title")}, ${c("description")} = v_row.${c("description")},
    ${c("counterpartyType")} = v_row.${c("counterpartyType")}, ${c("counterpartyId")} = v_row.${c("counterpartyId")},
    ${c("owner")} = v_row.${c("owner")}, ${c("value")} = v_row.${c("value")}, ${c("currency")} = upper(v_row.${c("currency")}),
    ${c("startsOn")} = v_row.${c("startsOn")}, ${c("endsOn")} = v_row.${c("endsOn")},
    ${c("autoRenew")} = coalesce(v_row.${c("autoRenew")}, false), ${c("renewalMonths")} = coalesce(v_row.${c("renewalMonths")}, 12),
    ${c("noticeDays")} = coalesce(v_row.${c("noticeDays")}, 30), ${c("updatedAt")} = now()`
        : sets([
            ...created.filter(
              ([column]) => column !== "tenant" && column !== "createdBy",
            ),
            ["updatedAt", "now()"],
          ]).join(",\n    ")
    }
    where x.${c("id")} = v_row.${c("id")}
    returning * into v_row;${writeExtraColumns(contracts, extras, "update_contract.fields", `x.${c("id")} = v_row.${c("id")}`, "v_row")}
  if v_owner is distinct from v_row.${c("owner")} and v_row.${c("owner")} is not null then
    update ${rem} x set ${re("user")} = v_row.${c("owner")}
      where x.${re("tenant")} = v_row.${c("tenant")} and x.${re("subjectType")} = ${subjectType}
        and x.${re("subjectId")} = v_row.${c("id")}::text and x.${re("user")} = v_owner
        and x.${re("offsetMinutes")} = ${offset};
  end if;
  perform ${fn("contract_schedule_renewal")}(v_row.${c("id")});
  ${contractRecord("contract.updated", "v_row", "updated contract")}
  return ${contractJson("v_row")};
end;
$$;
${userGrant(`${fn("update_contract")}(uuid, jsonb${extra.type})`)}

-- Moves a contract through its lifecycle. action: submit (draft to review),
-- return (review to draft), activate (review to active, for a contract signed
-- elsewhere), recall (cancels the signature request, back to review) or
-- terminate (with an optional reason). Activate, recall and terminate need
-- the manage permission.
create or replace function ${fn("transition_contract")}(contract_id uuid, action text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${contracts}%rowtype;
  v_from text[];
  v_to text;
begin
  select * into v_row from ${contracts} x where x.${c("id")} = transition_contract.contract_id;
  if not found then
    ${notFound}
  end if;
  case transition_contract.action
    when 'submit' then v_from := array['draft']; v_to := 'in_review';
    when 'return' then v_from := array['in_review']; v_to := 'draft';
    when 'activate' then v_from := array['in_review']; v_to := 'active';
    when 'recall' then v_from := array['out_for_signature']; v_to := 'in_review';
    when 'terminate' then v_from := array['draft', 'in_review', 'out_for_signature', 'active']; v_to := 'terminated';
    else
      ${invalid("action must be submit, return, activate, recall or terminate")}
  end case;
  if not ${allowed(`v_row.${c("tenant")}`, `case when transition_contract.action in ('submit', 'return') then ${write} else ${manage} end`)} then
    ${forbidden("not allowed to move this contract")}
  end if;
  if not (${contractStatus("v_row")} = any (v_from)) then
    ${fail("CONTRACT_TRANSITION_INVALID", "the contract can't take this step from its status", "55000")}
  end if;
  if v_row.${c("status")} = 'out_for_signature' and v_row.${c("signatureRequest")} is not null then
    -- The signatures trigger moves a recalled contract back to review.
    perform ${signatures.fn("cancel_signature_request")}(v_row.${c("signatureRequest")});
    if transition_contract.action = 'recall' then
      return ${fn("get_contract")}(v_row.${c("id")});
    end if;
  end if;
  return ${fn("contract_apply_status")}(v_row.${c("id")}, v_to, transition_contract.reason);
end;
$$;
${userGrant(`${fn("transition_contract")}(uuid, text, text)`)}

-- Freezes the contract as a version and asks members to sign it
-- (signatures block). The caller also needs the signatures request
-- permission. Signing completes it to active; a decline or cancel returns it
-- to review.
create or replace function ${fn("send_contract_for_signature")}(contract_id uuid, signers uuid[], sign_order text default 'parallel', message text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${contracts}%rowtype;
  v_version uuid;
  v_request uuid;
begin
  select * into v_row from ${contracts} x where x.${c("id")} = send_contract_for_signature.contract_id for update;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`, manage)} then
    ${forbidden("not allowed to send contracts for signature")}
  end if;
  if v_row.${c("status")} <> 'in_review' then
    ${fail("CONTRACT_TRANSITION_INVALID", "only a contract in review goes out for signature", "55000")}
  end if;
  v_version := (${versions.fn("version_insert")}(
    v_row.${c("tenant")}, ${subjectType}, v_row.${c("id")}::text,
    ${contractJson("v_row")} - 'status' - 'updatedAt' - 'signatureRequestId' - 'renewedCount',
    null, 'Sent for signature', 'manual', true, auth.uid()
  ) ->> 'id')::uuid;
  v_request := (${signatures.fn("create_signature_request")}(
    v_row.${c("tenant")}, ${subjectType}, v_row.${c("id")}::text,
    send_contract_for_signature.signers, v_version,
    coalesce(send_contract_for_signature.sign_order, 'parallel'), null,
    send_contract_for_signature.message
  ) ->> 'id')::uuid;
  update ${contracts} x set ${c("signatureRequest")} = v_request${touched}
    where x.${c("id")} = v_row.${c("id")};
  return ${fn("contract_apply_status")}(v_row.${c("id")}, 'out_for_signature');
end;
$$;
${userGrant(`${fn("send_contract_for_signature")}(uuid, uuid[], text, text)`)}

-- A settled signature request settles the contract waiting on it.
create or replace function ${fn("contract_signature_settled")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  for v_id in
    select x.${c("id")} from ${contracts} x
    where x.${c("signatureRequest")} = new.${s("id")} and x.${c("status")} = 'out_for_signature'
  loop
    perform ${fn("contract_apply_status")}(v_id, case when new.${s("status")} = 'completed' then 'active' else 'in_review' end);
  end loop;
  return new;
end;
$$;
${triggerGrant(`${fn("contract_signature_settled")}()`)}
drop trigger if exists ${ctx.trigger("contracts_signature_settled")} on ${sr};
create trigger ${ctx.trigger("contracts_signature_settled")} after update of ${s("status")} on ${sr}
  for each row when (old.${s("status")} = 'pending' and new.${s("status")} <> 'pending')
  execute function ${fn("contract_signature_settled")}();

create or replace function ${fn("get_contract")}(contract_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row ${contracts}%rowtype;
begin
  select * into v_row from ${contracts} x where x.${c("id")} = get_contract.contract_id;
  if not found then
    ${notFound}
  end if;
  return ${contractJson("v_row")};
end;
$$;
${userGrant(`${fn("get_contract")}(uuid)`)}

-- The contracts the caller can read, the newest first. A null tenant reads
-- every organization the caller can (a counterparty's record page).
-- renewing_before: active contracts whose notice deadline falls on or
-- before the date.
create or replace function ${fn("list_contracts")}(tenant ${idType}, status text default null, counterparty_type text default null, counterparty_id text default null, owner_id uuid default null, renewing_before date default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${contractJson("x")} order by x.${c("createdAt")} desc, x.${c("id")} desc), '[]'::jsonb)
  from (
    select * from ${contracts} y
    where (list_contracts.tenant is null or y.${c("tenant")} = list_contracts.tenant)
      and (list_contracts.status is null or ${contractStatus("y")} = list_contracts.status)
      and (list_contracts.counterparty_type is null${counterparty ? ` or (y.${c("counterpartyType")} = list_contracts.counterparty_type and y.${c("counterpartyId")} = list_contracts.counterparty_id)` : ""})
      and (list_contracts.owner_id is null or y.${c("owner")} = list_contracts.owner_id)
      and (list_contracts.renewing_before is null or (y.${c("status")} = 'active' and ${deadline("y")} <= list_contracts.renewing_before))
      and (list_contracts.before is null or y.${c("createdAt")} < list_contracts.before)
    order by y.${c("createdAt")} desc, y.${c("id")} desc
    limit ${pageSize("list_contracts.page_size", 50, 200)}
  ) x
$$;
${userGrant(`${fn("list_contracts")}(${idType}, text, text, text, uuid, date, timestamptz, integer)`)}

-- Renews or expires the active contracts that reached their end date: an
-- auto-renewing contract moves ends_on by its renewal period, any other
-- expires. Run it daily from a job; it returns the counts.
create or replace function ${fn("run_contract_renewals")}(as_of date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := coalesce(run_contract_renewals.as_of, current_date);
  v_row ${contracts}%rowtype;
  v_renewed integer := 0;
  v_expired integer := 0;
begin
  for v_row in
    select * from ${contracts} x
    where x.${c("status")} = 'active' and x.${c("endsOn")} < v_today
    for update skip locked
  loop
    if v_row.${c("autoRenew")} then
      while v_row.${c("endsOn")} < v_today loop
        v_row.${c("endsOn")} := (v_row.${c("endsOn")} + make_interval(months => v_row.${c("renewalMonths")}))::date;
${
  keeps("renewedCount")
    ? `        v_row.${c("renewedCount")} := v_row.${c("renewedCount")} + 1;\n`
    : ""
}      end loop;
      update ${contracts} x set ${c("endsOn")} = v_row.${c("endsOn")}${keeps("renewedCount") ? `, ${c("renewedCount")} = v_row.${c("renewedCount")}` : ""}${touched}
        where x.${c("id")} = v_row.${c("id")};
      perform ${fn("contract_schedule_renewal")}(v_row.${c("id")});
      ${ctx.record({
        type: "contract.renewed",
        payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'contractId', v_row.${c("id")}, 'endsOn', v_row.${c("endsOn")}, 'renewedCount', ${contractValue("v_row", "renewedCount")})`,
        subject: `'contracts/' || v_row.${c("id")}::text`,
        tenant: `v_row.${c("tenant")}`,
        audit: {
          category: "data",
          targetType: "contract",
          recordId: `v_row.${c("id")}::text`,
          summary: `'renewed contract ' || v_row.${c("title")} || ' to ' || v_row.${c("endsOn")}::text`,
        },
      })}
      v_renewed := v_renewed + 1;
    else
      perform ${fn("contract_apply_status")}(v_row.${c("id")}, 'expired');
      v_expired := v_expired + 1;
    end if;
  end loop;
  return jsonb_build_object('renewed', v_renewed, 'expired', v_expired);
end;
$$;
${serviceGrant(`${fn("run_contract_renewals")}(date)`)}

-- Adds an obligation to a contract, or changes one (obligation_id).
create or replace function ${fn("save_obligation")}(contract_id uuid, title text, due_on date default null, owner_id uuid default null, description text default null, obligation_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_contract ${contracts}%rowtype;
  v_row ${obligations}%rowtype;
begin
  select * into v_contract from ${contracts} x where x.${c("id")} = save_obligation.contract_id;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_contract.${c("tenant")}`, write)} then
    ${forbidden("not allowed to change contract obligations")}
  end if;
  if nullif(trim(save_obligation.title), '') is null then
    ${invalid("an obligation needs a title")}
  end if;
${
  obligationKeeps("description")
    ? ""
    : `  if nullif(trim(save_obligation.description), '') is not null then
    ${fail("CONTRACT_FIELD_UNSUPPORTED", "this obligations table keeps no description", "0A000")}
  end if;
`
}  if save_obligation.owner_id is not null and not ${isMember(`v_contract.${c("tenant")}`, "save_obligation.owner_id")} then
    ${invalid("the owner must be a member of the organization")}
  end if;
  if save_obligation.obligation_id is null then
    insert into ${obligations} (${savedObligation.map(([column]) => o(column)).join(", ")})
    values (${savedObligation.map(([, value]) => value).join(", ")})
    returning * into v_row;
  else
    update ${obligations} x set ${
      obligationKeeps("description") && obligationKeeps("updatedAt")
        ? `${o("title")} = trim(save_obligation.title), ${o("description")} = nullif(trim(save_obligation.description), ''),
      ${o("dueOn")} = save_obligation.due_on, ${o("owner")} = save_obligation.owner_id, ${o("updatedAt")} = now()`
        : [
            ...savedObligation.filter(
              ([column]) => column !== "tenant" && column !== "contract",
            ),
            ...(obligationKeeps("updatedAt")
              ? [["updatedAt", "now()"] as const]
              : []),
          ]
            .map(([column, value]) => `${o(column)} = ${value}`)
            .join(", ")
    }
      where x.${o("id")} = save_obligation.obligation_id and x.${o("contract")} = v_contract.${c("id")}
      returning * into v_row;
    if not found then
      ${fail("OBLIGATION_NOT_FOUND", "obligation not found", "P0002")}
    end if;
  end if;
  ${obligationRecord("obligation.saved", "v_row", "saved obligation")}
  return ${obligationJson("v_row")};
end;
$$;
${userGrant(`${fn("save_obligation")}(uuid, text, date, uuid, text, uuid)`)}

-- Marks an obligation open, done or waived. Its owner may mark it too.
create or replace function ${fn("set_obligation_status")}(obligation_id uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${obligations}%rowtype;
begin
  select * into v_row from ${obligations} x where x.${o("id")} = set_obligation_status.obligation_id for update;
  if not found then
    ${fail("OBLIGATION_NOT_FOUND", "obligation not found", "P0002")}
  end if;
  if not (${allowed(`v_row.${o("tenant")}`, write)} or coalesce(v_row.${o("owner")} = auth.uid(), false)) then
    ${forbidden("not allowed to change this obligation")}
  end if;
  if set_obligation_status.status is null or set_obligation_status.status not in ('open', 'done', 'waived') then
    ${invalid("status must be open, done or waived")}
  end if;
  update ${obligations} x set ${[
    `${o("status")} = ${ctx.cast("obligations", "status", "set_obligation_status.status")}`,
    ...(
      [
        [
          "completedAt",
          "case when set_obligation_status.status = 'open' then null else now() end",
        ],
        [
          "completedBy",
          "case when set_obligation_status.status = 'open' then null else auth.uid() end",
        ],
        ["updatedAt", "now()"],
      ] as const
    )
      .filter(([column]) => obligationKeeps(column))
      .map(([column, value]) => `${o(column)} = ${value}`),
  ].join(",\n    ")}
    where x.${o("id")} = v_row.${o("id")}
    returning * into v_row;
  ${obligationRecord("obligation.status_changed", "v_row", "marked obligation")}
  return ${obligationJson("v_row")};
end;
$$;
${userGrant(`${fn("set_obligation_status")}(uuid, text)`)}

create or replace function ${fn("delete_obligation")}(obligation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${obligations}%rowtype;
begin
  select * into v_row from ${obligations} x where x.${o("id")} = delete_obligation.obligation_id;
  if not found then
    ${fail("OBLIGATION_NOT_FOUND", "obligation not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${o("tenant")}`, write)} then
    ${forbidden("not allowed to change contract obligations")}
  end if;
  delete from ${obligations} x where x.${o("id")} = v_row.${o("id")};
  return ${obligationJson("v_row")};
end;
$$;
${userGrant(`${fn("delete_obligation")}(uuid)`)}

-- The obligations the caller can read, the earliest due first.
create or replace function ${fn("list_obligations")}(tenant ${idType}, contract_id uuid default null, owner_id uuid default null, open_only boolean default false, due_before date default null, page_size integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${obligationJson("x")} order by x.${o("dueOn")} nulls last, x.${o("createdAt")}), '[]'::jsonb)
  from (
    select * from ${obligations} y
    where y.${o("tenant")} = list_obligations.tenant
      and (list_obligations.contract_id is null or y.${o("contract")} = list_obligations.contract_id)
      and (list_obligations.owner_id is null or y.${o("owner")} = list_obligations.owner_id)
      and (not coalesce(list_obligations.open_only, false) or y.${o("status")} = 'open')
      and (list_obligations.due_before is null or y.${o("dueOn")} <= list_obligations.due_before)
    order by y.${o("dueOn")} nulls last, y.${o("createdAt")}
    limit ${pageSize("list_obligations.page_size", 100, 500)}
  ) x
$$;
${userGrant(`${fn("list_obligations")}(${idType}, uuid, uuid, boolean, date, integer)`)}
`;
}
