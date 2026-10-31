import type { BlockSqlContext } from "../context.ts";
import type { RfqsSql } from "./rfqs-sql.ts";

import { assignNumberSql } from "../numbering-sql.ts";
import { pageSize, userGrant } from "../shared.ts";
import { rfqsSql } from "./rfqs-sql.ts";

/** The SQL that checks and stores the requested lines of rfq `rfq` from `lines`. */
function lineWrites(
  q: RfqsSql,
  lines: string,
  tenant: string,
  rfq: string,
  fnName: string,
): { readonly check: string; readonly insert: string } {
  const { l } = q;

  return {
    check: `if jsonb_typeof(${lines}) is distinct from 'array'
    or exists (select 1 from jsonb_array_elements(${lines}) e where jsonb_typeof(e) is distinct from 'object') then
    ${q.invalid(`${fnName}: lines must be a list of objects`)}
  end if;`,
    insert: `insert into ${q.lines} (${l("tenant")}, ${l("rfq")}, ${l("ordinal")}, ${l("description")}, ${l("variant")}, ${l("quantity")}, ${l("unit")})
    select ${tenant}, ${rfq}, t.ord::integer, trim(t.e ->> 'description'), (t.e ->> 'variantId')::uuid,
      (t.e ->> 'quantity')::numeric, nullif(trim(t.e ->> 'unit'), '')
    from jsonb_array_elements(${lines}) with ordinality as t(e, ord);`,
  };
}

const LINE_ERROR =
  "a line needs a description of 1 to 500 characters, a quantity above zero and, when given, a variantId that is a uuid";

export function rfqsFunctions(ctx: BlockSqlContext): string {
  const sql = rfqsSql(ctx);
  const { fn, q, l, s, rfqs, lines, suppliers } = sql;
  const idType = ctx.idType;

  const numberAssign = assignNumberSql(
    ctx,
    ctx.naming.rename("rfq"),
    "create_rfq.tenant",
    { seq: "v_seq", identifier: "v_number" },
    { table: rfqs, seq: q("sequence"), tenant: q("tenant"), prefix: "RFQ-" },
  );

  const create = lineWrites(
    sql,
    "create_rfq.lines",
    "create_rfq.tenant",
    `v_row.${q("id")}`,
    "create_rfq",
  );

  const update = lineWrites(
    sql,
    "update_rfq.lines",
    `v_row.${q("tenant")}`,
    `v_row.${q("id")}`,
    "update_rfq",
  );

  // Loads the rfq `name`.rfq_id for update, hiding it from readers without access.
  const load = (
    name: string,
  ): string => `select * into v_row from ${rfqs} x where x.${q("id")} = ${name}.rfq_id for update;
  if not found or not ${sql.allowed(`v_row.${q("tenant")}`, sql.read)} then
    ${sql.rfqMissing}
  end if;`;

  const detail = (
    row: string,
  ): string => `${sql.rfqJson(row)} || jsonb_build_object(
    'lines', coalesce((select jsonb_agg(${sql.lineJson("y")} order by y.${l("ordinal")}) from ${lines} y where y.${l("rfq")} = ${row}.${q("id")}), '[]'::jsonb),
    'suppliers', coalesce((select jsonb_agg(${sql.supplierJson("y")} order by y.${s("invitedAt")}, y.${s("id")}) from ${suppliers} y where y.${s("rfq")} = ${row}.${q("id")}), '[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(${sql.quoteJson("y")} || jsonb_build_object('lines', coalesce((
        select jsonb_agg(${sql.quoteLineJson("z")} order by z.${sql.u("id")}) from ${sql.quoteLines} z where z.${sql.u("quote")} = y.${sql.k("id")}
      ), '[]'::jsonb)) order by y.${sql.k("submittedAt")}, y.${sql.k("id")}) from ${sql.quotes} y where y.${sql.k("rfq")} = ${row}.${q("id")}), '[]'::jsonb))`;

  return `
-- Creates a draft request for quotation and numbers it (RFQ-1, or the
-- numbering block's format for rfq). input is { title, currency, dueAt, notes };
-- currency is an ISO 4217 code. lines is [{ description, variantId, quantity,
-- unit }]; a variantId (inventory) is only needed to award into a purchase
-- order. Needs rfqs.write.
create or replace function ${fn("create_rfq")}(tenant ${idType}, input jsonb, lines jsonb default '[]')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rfqs};
  v_seq bigint;
  v_number text;
  v_input jsonb := coalesce(create_rfq.input, '{}'::jsonb);
begin
  if not ${sql.allowed("create_rfq.tenant", sql.write)} then
    ${sql.forbidden("not allowed to create requests for quotation")}
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    ${sql.invalid("input must be an object")}
  end if;
  ${ctx.hook("before_rfq_create", [
    [idType, "create_rfq.tenant"],
    ["jsonb", "create_rfq.input"],
  ])}
  ${numberAssign}
  begin
    insert into ${rfqs} (${q("tenant")}, ${q("number")}, ${q("sequence")}, ${q("title")}, ${q("currency")}, ${q("dueAt")}, ${q("notes")}, ${q("createdBy")})
    values (create_rfq.tenant, v_number, v_seq, trim(v_input ->> 'title'), upper(trim(v_input ->> 'currency')),
      (v_input ->> 'dueAt')::timestamptz, nullif(trim(v_input ->> 'notes'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    ${sql.invalid("a request needs a title of 1 to 200 characters, a three letter currency, a valid dueAt and notes of up to 4000")}
  end;
  ${create.check}
  begin
    ${create.insert}
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    ${sql.invalid(LINE_ERROR)}
  end;
  ${sql.recordRfq("rfq.created", "v_row", "request for quotation created")}
  ${ctx.hook("after_rfq_create", [["uuid", `v_row.${q("id")}`]])}
  return ${detail("v_row")};
end;
$$;
${userGrant(`${fn("create_rfq")}(${idType}, jsonb, jsonb)`)}

-- Changes a draft: input is the same object as create_rfq (omitted keys stay),
-- lines replaces every line when given. Needs rfqs.write.
create or replace function ${fn("update_rfq")}(rfq_id uuid, input jsonb, lines jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rfqs};
  v_input jsonb := coalesce(update_rfq.input, '{}'::jsonb);
begin
  ${load("update_rfq")}
  if not ${sql.allowed(`v_row.${q("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to change requests for quotation")}
  end if;
  if v_row.${q("status")} <> 'draft' then
    ${sql.status("only a draft request can change")}
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    ${sql.invalid("input must be an object")}
  end if;
  begin
    update ${rfqs} x set
      ${q("title")} = coalesce(trim(v_input ->> 'title'), x.${q("title")}),
      ${q("currency")} = coalesce(upper(trim(v_input ->> 'currency')), x.${q("currency")}),
      ${q("dueAt")} = case when v_input ? 'dueAt' then (v_input ->> 'dueAt')::timestamptz else x.${q("dueAt")} end,
      ${q("notes")} = case when v_input ? 'notes' then nullif(trim(v_input ->> 'notes'), '') else x.${q("notes")} end,
      ${q("updatedAt")} = now()
    where x.${q("id")} = v_row.${q("id")} returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    ${sql.invalid("a request needs a title of 1 to 200 characters, a three letter currency, a valid dueAt and notes of up to 4000")}
  end;
  if update_rfq.lines is not null then
    ${update.check}
    delete from ${lines} y where y.${l("rfq")} = v_row.${q("id")};
    begin
      ${update.insert}
    exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
      ${sql.invalid(LINE_ERROR)}
    end;
  end if;
  return ${detail("v_row")};
end;
$$;
${userGrant(`${fn("update_rfq")}(uuid, jsonb, jsonb)`)}

-- One request with its lines, invited suppliers and quotes (each with its
-- prices).
create or replace function ${fn("get_rfq")}(rfq_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rfqs};
begin
  select * into v_row from ${rfqs} x where x.${q("id")} = get_rfq.rfq_id;
  if not found or not ${sql.allowed(`v_row.${q("tenant")}`, sql.read)} then
    ${sql.rfqMissing}
  end if;
  return ${detail("v_row")};
end;
$$;
${userGrant(`${fn("get_rfq")}(uuid)`)}

-- Requests, newest first. filters is { status, limit, offset }.
create or replace function ${fn("list_rfqs")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_rfqs.filters, '{}'::jsonb);
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
begin
  if not ${sql.allowed("list_rfqs.tenant", sql.read)} then
    ${sql.forbidden("not allowed to read requests for quotation")}
  end if;
  return coalesce((
    select jsonb_agg(${sql.rfqJson("y")} order by y.${q("sequence")} desc)
    from (
      select * from ${rfqs} x
      where x.${q("tenant")} = list_rfqs.tenant
        and (not v_filters ? 'status' or x.${q("status")} = v_filters ->> 'status')
      order by x.${q("sequence")} desc
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_rfqs")}(${idType}, jsonb)`)}

-- Invites a supplier to quote on a draft or open request. With the contacts
-- block the supplier must be a company or person that holds the supplier role
-- and is not blocked. Needs rfqs.write.
create or replace function ${fn("invite_rfq_supplier")}(rfq_id uuid, supplier_type text, supplier_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rfqs};
  v_invitation ${suppliers};
begin
  ${load("invite_rfq_supplier")}
  if not ${sql.allowed(`v_row.${q("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to invite suppliers")}
  end if;
  if v_row.${q("status")} not in ('draft', 'open') then
    ${sql.status("suppliers can only be invited while the request is a draft or open")}
  end if;
  if coalesce(trim(invite_rfq_supplier.supplier_type), '') = '' or coalesce(trim(invite_rfq_supplier.supplier_id), '') = '' then
    ${sql.invalid("a supplier needs a type and an id")}
  end if;${sql.supplierCheck("invite_rfq_supplier.supplier_id", `v_row.${q("tenant")}`)}
  begin
    insert into ${suppliers} (${s("tenant")}, ${s("rfq")}, ${s("supplierType")}, ${s("supplierId")})
    values (v_row.${q("tenant")}, v_row.${q("id")}, trim(invite_rfq_supplier.supplier_type), trim(invite_rfq_supplier.supplier_id))
    returning * into v_invitation;
  exception when unique_violation then
    ${sql.invalid("this supplier is already invited")}
  when check_violation then
    ${sql.invalid("a supplier needs a type of up to 100 and an id of up to 200 characters")}
  end;
  return ${sql.supplierJson("v_invitation")};
end;
$$;
${userGrant(`${fn("invite_rfq_supplier")}(uuid, text, text)`)}

-- Records that an invited supplier will not quote. Needs rfqs.write.
create or replace function ${fn("decline_rfq_supplier")}(invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_invitation ${suppliers};
  v_status text;
begin
  select * into v_invitation from ${suppliers} x where x.${s("id")} = decline_rfq_supplier.invitation_id for update;
  if not found or not ${sql.allowed(`v_invitation.${s("tenant")}`, sql.read)} then
    ${sql.invitationMissing}
  end if;
  if not ${sql.allowed(`v_invitation.${s("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to change invited suppliers")}
  end if;
  select r.${q("status")} into v_status from ${rfqs} r where r.${q("id")} = v_invitation.${s("rfq")};
  if v_status not in ('draft', 'open') then
    ${sql.status("a supplier can only decline while the request is a draft or open")}
  end if;
  if v_invitation.${s("status")} <> 'invited' then
    ${sql.status("only a supplier that has not quoted can decline")}
  end if;
  update ${suppliers} x set ${s("status")} = 'declined', ${s("respondedAt")} = now()
  where x.${s("id")} = v_invitation.${s("id")} returning * into v_invitation;
  return ${sql.supplierJson("v_invitation")};
end;
$$;
${userGrant(`${fn("decline_rfq_supplier")}(uuid)`)}

-- Opens a draft for quotes. It needs at least one line and one invited
-- supplier. Needs rfqs.write.
create or replace function ${fn("open_rfq")}(rfq_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rfqs};
begin
  ${load("open_rfq")}
  if not ${sql.allowed(`v_row.${q("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to open requests for quotation")}
  end if;
  if v_row.${q("status")} <> 'draft' then
    ${sql.status("only a draft request can be opened")}
  end if;
  if not exists (select 1 from ${lines} y where y.${l("rfq")} = v_row.${q("id")})
    or not exists (select 1 from ${suppliers} y where y.${s("rfq")} = v_row.${q("id")}) then
    ${sql.invalid("a request needs a line and an invited supplier before it opens")}
  end if;
  update ${rfqs} x set ${q("status")} = 'open', ${q("openedAt")} = now(), ${q("updatedAt")} = now()
  where x.${q("id")} = v_row.${q("id")} returning * into v_row;
  ${sql.recordRfq("rfq.opened", "v_row", "request for quotation opened")}
  return ${sql.rfqJson("v_row")};
end;
$$;
${userGrant(`${fn("open_rfq")}(uuid)`)}

-- Stops taking quotes on an open request so the quotes can be compared and
-- one awarded. Needs rfqs.write.
create or replace function ${fn("close_rfq")}(rfq_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rfqs};
begin
  ${load("close_rfq")}
  if not ${sql.allowed(`v_row.${q("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to close requests for quotation")}
  end if;
  if v_row.${q("status")} <> 'open' then
    ${sql.status("only an open request can be closed")}
  end if;
  update ${rfqs} x set ${q("status")} = 'closed', ${q("closedAt")} = now(), ${q("updatedAt")} = now()
  where x.${q("id")} = v_row.${q("id")} returning * into v_row;
  ${sql.recordRfq("rfq.closed", "v_row", "request for quotation closed")}
  return ${sql.rfqJson("v_row")};
end;
$$;
${userGrant(`${fn("close_rfq")}(uuid)`)}

-- Cancels a request that is not awarded and says why. Needs rfqs.manage.
create or replace function ${fn("cancel_rfq")}(rfq_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rfqs};
begin
  ${load("cancel_rfq")}
  if not ${sql.allowed(`v_row.${q("tenant")}`, sql.manage)} then
    ${sql.forbidden("not allowed to cancel requests for quotation")}
  end if;
  if v_row.${q("status")} in ('awarded', 'cancelled') then
    ${sql.status("an awarded or cancelled request cannot be cancelled")}
  end if;
  if coalesce(trim(cancel_rfq.reason), '') = '' or length(cancel_rfq.reason) > 500 then
    ${sql.invalid("a reason of 1 to 500 characters is required")}
  end if;
  update ${rfqs} x set ${q("status")} = 'cancelled', ${q("cancelReason")} = trim(cancel_rfq.reason), ${q("updatedAt")} = now()
  where x.${q("id")} = v_row.${q("id")} returning * into v_row;
  ${sql.recordRfq("rfq.cancelled", "v_row", "request for quotation cancelled")}
  return ${sql.rfqJson("v_row")};
end;
$$;
${userGrant(`${fn("cancel_rfq")}(uuid, text)`)}
`;
}
