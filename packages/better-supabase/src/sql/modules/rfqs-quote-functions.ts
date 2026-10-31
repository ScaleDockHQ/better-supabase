import type { BlockSqlContext } from "../context.ts";

import { userGrant } from "../shared.ts";
import { rfqsSql } from "./rfqs-sql.ts";

export function rfqsQuoteFunctions(ctx: BlockSqlContext): string {
  const sql = rfqsSql(ctx);
  const { fn, q, l, s, k, u, rfqs, lines, suppliers, quotes, quoteLines } = sql;

  // The award creates a draft purchase order when a location is given.
  const purchaseOrder =
    sql.inventory === undefined
      ? `if award_rfq.location is not null then
    ${sql.invalid("a location needs the inventory block to create a purchase order")}
  end if;`
      : `if award_rfq.location is not null then
    if exists (select 1 from ${lines} y where y.${l("rfq")} = v_row.${q("id")} and y.${l("variant")} is null) then
      ${sql.invalid("every line needs a variantId to create a purchase order")}
    end if;
    v_order := (${sql.inventory.fn("save_purchase_order")}(
      v_row.${q("tenant")}, null, award_rfq.location, v_invitation.${s("supplierType")}, v_invitation.${s("supplierId")},
      v_row.${q("currency")},
      case when v_quote.${k("leadTimeDays")} is null then null else now() + make_interval(days => v_quote.${k("leadTimeDays")}) end,
      (select jsonb_agg(jsonb_build_object('variantId', y.${l("variant")}, 'quantity', y.${l("quantity")}, 'unitCost', z.${u("unitAmount")}::text) order by y.${l("ordinal")})
        from ${lines} y join ${quoteLines} z on z.${u("line")} = y.${l("id")} and z.${u("quote")} = v_quote.${k("id")}
        where y.${l("rfq")} = v_row.${q("id")}),
      v_row.${q("number")}
    ) ->> 'id')::uuid;
  end if;`;

  return `
-- Records a supplier's quote, or replaces its earlier one (the revision goes
-- up). input is { leadTimeDays, validUntil, notes }; lines is [{ lineId,
-- unitAmount, leadTimeDays }] with unitAmount in minor units of the request's
-- currency. The request must be open and the supplier invited. The total is
-- the sum of unit amount times quantity. Needs rfqs.write.
create or replace function ${fn("record_rfq_quote")}(rfq_id uuid, invitation_id uuid, input jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rfqs};
  v_invitation ${suppliers};
  v_quote ${quotes};
  v_input jsonb := coalesce(record_rfq_quote.input, '{}'::jsonb);
begin
  select * into v_row from ${rfqs} x where x.${q("id")} = record_rfq_quote.rfq_id for update;
  if not found or not ${sql.allowed(`v_row.${q("tenant")}`, sql.read)} then
    ${sql.rfqMissing}
  end if;
  if not ${sql.allowed(`v_row.${q("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to record quotes")}
  end if;
  if v_row.${q("status")} <> 'open' then
    ${sql.status("quotes can only be recorded on an open request")}
  end if;
  select * into v_invitation from ${suppliers} y
  where y.${s("id")} = record_rfq_quote.invitation_id and y.${s("rfq")} = v_row.${q("id")} for update;
  if not found then
    ${sql.invitationMissing}
  end if;
  if v_invitation.${s("status")} = 'declined' then
    ${sql.status("this supplier declined to quote")}
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    ${sql.invalid("input must be an object")}
  end if;
  if jsonb_typeof(record_rfq_quote.lines) is distinct from 'array' or jsonb_array_length(record_rfq_quote.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(record_rfq_quote.lines) e
      where jsonb_typeof(e) is distinct from 'object'
        or coalesce(e ->> 'lineId', '') !~ '^[0-9a-fA-F-]{36}$'
        or coalesce(e ->> 'unitAmount', '') !~ '^[0-9]{1,18}$'
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(record_rfq_quote.lines) e) <> jsonb_array_length(record_rfq_quote.lines) then
    ${sql.invalid("lines must be a non-empty list with a unique lineId and a unitAmount in minor units each")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(record_rfq_quote.lines) e
    where not exists (select 1 from ${lines} y where y.${l("id")} = (e ->> 'lineId')::uuid and y.${l("rfq")} = v_row.${q("id")})
  ) then
    ${sql.invalid("a lineId is not a line of this request")}
  end if;
  ${ctx.hook("before_rfq_quote_record", [
    ["uuid", "record_rfq_quote.rfq_id"],
    ["jsonb", "record_rfq_quote.input"],
  ])}
  begin
    select * into v_quote from ${quotes} y
    where y.${k("rfq")} = v_row.${q("id")} and y.${k("invitation")} = v_invitation.${s("id")} for update;
    if found then
      delete from ${quoteLines} z where z.${u("quote")} = v_quote.${k("id")};
      update ${quotes} y set ${k("status")} = 'submitted', ${k("total")} = 0,
        ${k("leadTimeDays")} = (v_input ->> 'leadTimeDays')::integer, ${k("validUntil")} = (v_input ->> 'validUntil')::date,
        ${k("notes")} = nullif(trim(v_input ->> 'notes'), ''), ${k("revision")} = y.${k("revision")} + 1,
        ${k("submittedBy")} = auth.uid(), ${k("submittedAt")} = now(), ${k("updatedAt")} = now()
      where y.${k("id")} = v_quote.${k("id")} returning * into v_quote;
    else
      insert into ${quotes} (${k("tenant")}, ${k("rfq")}, ${k("invitation")}, ${k("total")}, ${k("leadTimeDays")}, ${k("validUntil")}, ${k("notes")}, ${k("submittedBy")})
      values (v_row.${q("tenant")}, v_row.${q("id")}, v_invitation.${s("id")}, 0, (v_input ->> 'leadTimeDays')::integer,
        (v_input ->> 'validUntil')::date, nullif(trim(v_input ->> 'notes'), ''), auth.uid())
      returning * into v_quote;
    end if;
    insert into ${quoteLines} (${u("tenant")}, ${u("quote")}, ${u("line")}, ${u("unitAmount")}, ${u("leadTimeDays")})
    select v_row.${q("tenant")}, v_quote.${k("id")}, (e ->> 'lineId')::uuid, (e ->> 'unitAmount')::bigint, (e ->> 'leadTimeDays')::integer
    from jsonb_array_elements(record_rfq_quote.lines) e;
    update ${quotes} y set ${k("total")} = coalesce((
      select round(sum(z.${u("unitAmount")} * ln.${l("quantity")}))::bigint
      from ${quoteLines} z join ${lines} ln on ln.${l("id")} = z.${u("line")} where z.${u("quote")} = y.${k("id")}
    ), 0)
    where y.${k("id")} = v_quote.${k("id")} returning * into v_quote;
  exception when check_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    ${sql.invalid("a quote needs a leadTimeDays of zero or more, a valid validUntil, notes of up to 4000 and unit amounts in minor units")}
  end;
  update ${suppliers} y set ${s("status")} = 'quoted', ${s("respondedAt")} = now() where y.${s("id")} = v_invitation.${s("id")};
  ${sql.recordQuote("rfq_quote.submitted", "v_quote", "v_row", "quote recorded")}
  ${ctx.hook("after_rfq_quote_record", [["uuid", `v_quote.${k("id")}`]])}
  return ${sql.quoteJson("v_quote")} || jsonb_build_object('lines', coalesce((
    select jsonb_agg(${sql.quoteLineJson("z")} order by z.${u("id")}) from ${quoteLines} z where z.${u("quote")} = v_quote.${k("id")}
  ), '[]'::jsonb));
end;
$$;
${userGrant(`${fn("record_rfq_quote")}(uuid, uuid, jsonb, jsonb)`)}

-- Withdraws a submitted quote of an open request; the supplier can quote
-- again. Needs rfqs.write.
create or replace function ${fn("withdraw_rfq_quote")}(quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_quote ${quotes};
  v_row ${rfqs};
begin
  select * into v_quote from ${quotes} y where y.${k("id")} = withdraw_rfq_quote.quote_id for update;
  if not found or not ${sql.allowed(`v_quote.${k("tenant")}`, sql.read)} then
    ${sql.quoteMissing}
  end if;
  if not ${sql.allowed(`v_quote.${k("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to withdraw quotes")}
  end if;
  select * into v_row from ${rfqs} x where x.${q("id")} = v_quote.${k("rfq")};
  if v_row.${q("status")} <> 'open' or v_quote.${k("status")} <> 'submitted' then
    ${sql.status("only a submitted quote of an open request can be withdrawn")}
  end if;
  update ${quotes} y set ${k("status")} = 'withdrawn', ${k("updatedAt")} = now()
  where y.${k("id")} = v_quote.${k("id")} returning * into v_quote;
  update ${suppliers} y set ${s("status")} = 'invited' where y.${s("id")} = v_quote.${k("invitation")};
  ${sql.recordQuote("rfq_quote.withdrawn", "v_quote", "v_row", "quote withdrawn")}
  return ${sql.quoteJson("v_quote")};
end;
$$;
${userGrant(`${fn("withdraw_rfq_quote")}(uuid)`)}

-- The quotes side by side. lines has one entry per requested line with every
-- live quote's unit price and line total (lowest marks the best price); quotes
-- has one entry per live quote with its total, whether it prices every line
-- (complete) and whether it is the lowest complete total. Amounts are minor
-- units as text.
create or replace function ${fn("compare_rfq")}(rfq_id uuid)
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
  select * into v_row from ${rfqs} x where x.${q("id")} = compare_rfq.rfq_id;
  if not found or not ${sql.allowed(`v_row.${q("tenant")}`, sql.read)} then
    ${sql.rfqMissing}
  end if;
  return jsonb_build_object(
    'rfqId', v_row.${q("id")},
    'currency', v_row.${q("currency")},
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lineId', ln.${l("id")}, 'ordinal', ln.${l("ordinal")}, 'description', ln.${l("description")}, 'quantity', ln.${l("quantity")},
        'offers', coalesce((
          select jsonb_agg(jsonb_build_object(
            'quoteId', y.${k("id")}, 'invitationId', y.${k("invitation")}, 'unitAmount', z.${u("unitAmount")}::text,
            'lineTotal', round(z.${u("unitAmount")} * ln.${l("quantity")})::bigint::text,
            'leadTimeDays', coalesce(z.${u("leadTimeDays")}, y.${k("leadTimeDays")}),
            'lowest', z.${u("unitAmount")} = (
              select min(z2.${u("unitAmount")}) from ${quoteLines} z2 join ${quotes} y2 on y2.${k("id")} = z2.${u("quote")}
              where z2.${u("line")} = ln.${l("id")} and y2.${k("status")} in ('submitted', 'awarded')
            )
          ) order by z.${u("unitAmount")}, y.${k("submittedAt")}, y.${k("id")})
          from ${quoteLines} z join ${quotes} y on y.${k("id")} = z.${u("quote")}
          where z.${u("line")} = ln.${l("id")} and y.${k("status")} in ('submitted', 'awarded')
        ), '[]'::jsonb)
      ) order by ln.${l("ordinal")})
      from ${lines} ln where ln.${l("rfq")} = v_row.${q("id")}
    ), '[]'::jsonb),
    'quotes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'quoteId', c.id, 'invitationId', c.invitation_id, 'supplierType', c.supplier_type, 'supplierId', c.supplier_id,
        'status', c.status, 'total', c.total::text, 'leadTimeDays', c.lead_time_days, 'validUntil', c.valid_until,
        'complete', c.complete,
        'lowest', c.complete and c.total = c.best
      ) order by c.total, c.submitted_at, c.id)
      from (
        select d.*, min(d.total) filter (where d.complete) over () as best
        from (
        select y.${k("id")} as id, y.${k("invitation")} as invitation_id, i.${s("supplierType")} as supplier_type,
          i.${s("supplierId")} as supplier_id, y.${k("status")} as status, y.${k("total")} as total,
          y.${k("leadTimeDays")} as lead_time_days, y.${k("validUntil")} as valid_until, y.${k("submittedAt")} as submitted_at,
          (select count(*) from ${quoteLines} z where z.${u("quote")} = y.${k("id")})
            = (select count(*) from ${lines} ln where ln.${l("rfq")} = v_row.${q("id")}) as complete
        from ${quotes} y join ${suppliers} i on i.${s("id")} = y.${k("invitation")}
        where y.${k("rfq")} = v_row.${q("id")} and y.${k("status")} in ('submitted', 'awarded')
        ) d
      ) c
    ), '[]'::jsonb)
  );
end;
$$;
${userGrant(`${fn("compare_rfq")}(uuid)`)}

-- Awards a closed or open request to one complete quote: the quote becomes
-- awarded, the other live quotes rejected and the request awarded. With a
-- location (and the inventory block) a draft purchase order for the quote's
-- supplier and prices is created and its id kept on the request; every line
-- then needs a variantId. Needs rfqs.manage and, for the purchase order, the
-- inventory purchase permission.
create or replace function ${fn("award_rfq")}(rfq_id uuid, quote_id uuid, location uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rfqs};
  v_quote ${quotes};
  v_invitation ${suppliers};
  v_order uuid;
begin
  select * into v_row from ${rfqs} x where x.${q("id")} = award_rfq.rfq_id for update;
  if not found or not ${sql.allowed(`v_row.${q("tenant")}`, sql.read)} then
    ${sql.rfqMissing}
  end if;
  if not ${sql.allowed(`v_row.${q("tenant")}`, sql.manage)} then
    ${sql.forbidden("not allowed to award requests for quotation")}
  end if;
  if v_row.${q("status")} not in ('open', 'closed') then
    ${sql.status("only an open or closed request can be awarded")}
  end if;
  select * into v_quote from ${quotes} y where y.${k("id")} = award_rfq.quote_id and y.${k("rfq")} = v_row.${q("id")} for update;
  if not found then
    ${sql.quoteMissing}
  end if;
  if v_quote.${k("status")} <> 'submitted' then
    ${sql.status("only a submitted quote can be awarded")}
  end if;
  if (select count(*) from ${quoteLines} z where z.${u("quote")} = v_quote.${k("id")})
    <> (select count(*) from ${lines} ln where ln.${l("rfq")} = v_row.${q("id")}) then
    ${sql.invalid("only a quote that prices every line can be awarded")}
  end if;
  ${ctx.hook("before_rfq_award", [
    ["uuid", "award_rfq.rfq_id"],
    ["uuid", "award_rfq.quote_id"],
  ])}
  select * into v_invitation from ${suppliers} i where i.${s("id")} = v_quote.${k("invitation")};
  ${purchaseOrder}
  update ${quotes} y set ${k("status")} = case when y.${k("id")} = v_quote.${k("id")} then 'awarded' else 'rejected' end, ${k("updatedAt")} = now()
  where y.${k("rfq")} = v_row.${q("id")} and y.${k("status")} = 'submitted';
  update ${rfqs} x set ${q("status")} = 'awarded', ${q("awardedQuote")} = v_quote.${k("id")}, ${q("purchaseOrder")} = v_order,
    ${q("awardedAt")} = now(), ${q("closedAt")} = coalesce(x.${q("closedAt")}, now()), ${q("updatedAt")} = now()
  where x.${q("id")} = v_row.${q("id")} returning * into v_row;
  ${sql.recordRfq("rfq.awarded", "v_row", "request for quotation awarded")}
  ${ctx.hook("after_rfq_award", [["uuid", `v_row.${q("id")}`]])}
  return ${sql.rfqJson("v_row")};
end;
$$;
${userGrant(`${fn("award_rfq")}(uuid, uuid, uuid)`)}
`;
}
