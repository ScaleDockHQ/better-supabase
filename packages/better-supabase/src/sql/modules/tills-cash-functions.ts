import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { booksAccounting } from "../accounting-sources-sql.ts";
import { userGrant } from "../shared.ts";
import { tillsSql } from "./tills-sql.ts";
import { TILL_MOVEMENT_KINDS } from "./tills-values.ts";

export function tillsCashFunctions(ctx: BlockSqlContext): string {
  const sql = tillsSql(ctx);

  const { fn, t, s, m, c, d, tills, sessions, movements, counts, deposits } =
    sql;

  // Books a document in the same transaction and keeps the entry's id.
  const post = (source: string, id: string, target: string): string =>
    booksAccounting(ctx)
      ? `if not ${ctx.importing()} then
    ${target} := ${ctx.of("accounting").fn("accounting_post_source")}(${sqlString(source)}, ${id}::text);
  end if;`
      : "";

  const kinds = TILL_MOVEMENT_KINDS.map((kind) => sqlString(kind)).join(", ");

  const matchTransaction =
    sql.banking === undefined || sql.accounting === undefined
      ? sql.invalid("reconciling needs the banking and accounting blocks")
      : `if v_row.${d("entry")} is null then
    ${sql.invalid("this deposit has no accounting entry to match; give the till a cash account")}
  end if;
  perform ${sql.banking.fn("match_bank_transaction")}(
    reconcile_till_deposit.bank_transaction_id,
    jsonb_build_array(jsonb_build_object('targetType', 'accounting_entry', 'targetId', v_row.${d("entry")}, 'amount', v_row.${d("amount")}::text)));`;

  return `
-- Records cash that went into or out of the drawer of an open session. kind is
-- cash_sale or cash_in (adds) or cash_refund or cash_out (removes); amount is
-- above zero, in minor units. Needs tills.write.
create or replace function ${fn("record_till_movement")}(session_id uuid, kind text, amount bigint, reason text default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_session ${sessions};
  v_till ${tills};
  v_row ${movements};
begin
  select * into v_session from ${sessions} x where x.${s("id")} = record_till_movement.session_id for update;
  if not found or not ${sql.allowed(`v_session.${s("tenant")}`, sql.read)} then
    ${sql.sessionMissing}
  end if;
  if not ${sql.allowed(`v_session.${s("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to record cash movements")}
  end if;
  if v_session.${s("status")} <> 'open' then
    ${sql.status("cash can only be recorded on an open session")}
  end if;
  if record_till_movement.kind is null or record_till_movement.kind not in (${kinds}) then
    ${sql.invalid(`kind is one of ${TILL_MOVEMENT_KINDS.join(", ")}`)}
  end if;
  if record_till_movement.amount is null or record_till_movement.amount <= 0 then
    ${sql.invalid("the amount is above zero")}
  end if;
  if record_till_movement.kind in ('cash_refund', 'cash_out') and record_till_movement.amount > ${sql.expected("v_session")} then
    ${sql.invalid("the drawer does not hold that much cash")}
  end if;
  begin
    insert into ${movements} (${m("tenant")}, ${m("session")}, ${m("kind")}, ${m("amount")}, ${m("reason")}, ${m("reference")}, ${m("createdBy")})
    values (v_session.${s("tenant")}, v_session.${s("id")}, record_till_movement.kind, record_till_movement.amount,
      nullif(trim(record_till_movement.reason), ''), nullif(trim(record_till_movement.reference), ''), auth.uid())
    returning * into v_row;
  exception when check_violation then
    ${sql.invalid("a reason is up to 500 and a reference up to 200 characters")}
  end;
  select * into v_till from ${tills} x where x.${t("id")} = v_session.${s("till")};
  ${sql.recordMovement("v_row", "v_till")}
  return ${sql.movementJson("v_row")};
end;
$$;
${userGrant(`${fn("record_till_movement")}(uuid, text, bigint, text, text)`)}

-- Ends a session with the end-of-day count. input is { denominations, amount,
-- notes }: denominations maps a note or coin value in minor units to how many
-- there are ({ "500": 3, "100": 12 }) and the count is their sum; without it,
-- amount is the counted total in minor units. The difference to the expected
-- cash is kept and, when the till has a cash account, booked in accounting.
-- Needs tills.write.
create or replace function ${fn("close_till_session")}(session_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(close_till_session.input, '{}'::jsonb);
  v_session ${sessions};
  v_till ${tills};
  v_count ${counts};
  v_expected bigint;
  v_counted bigint;
  v_entry uuid;
  v_entry_value record;
begin
  select * into v_session from ${sessions} x where x.${s("id")} = close_till_session.session_id for update;
  if not found or not ${sql.allowed(`v_session.${s("tenant")}`, sql.read)} then
    ${sql.sessionMissing}
  end if;
  if not ${sql.allowed(`v_session.${s("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to close till sessions")}
  end if;
  if v_session.${s("status")} <> 'open' then
    ${sql.status("only an open session can be closed")}
  end if;
  if jsonb_typeof(v_input -> 'denominations') = 'object' then
    for v_entry_value in select key, value from jsonb_each(v_input -> 'denominations') loop
      if v_entry_value.key !~ '^[0-9]{1,12}$' or jsonb_typeof(v_entry_value.value) is distinct from 'number'
        or v_entry_value.value::text !~ '^[0-9]{1,9}$' then
        ${sql.invalid("denominations maps a value in minor units to a whole count")}
      end if;
    end loop;
    select coalesce(sum(key::bigint * (value::text)::bigint), 0) into v_counted from jsonb_each(v_input -> 'denominations');
  elsif coalesce(v_input ->> 'amount', '') ~ '^[0-9]{1,18}$' then
    v_counted := (v_input ->> 'amount')::bigint;
  else
    ${sql.invalid("give the counted denominations or a counted amount in minor units")}
  end if;
  select * into v_till from ${tills} x where x.${t("id")} = v_session.${s("till")};
  v_expected := ${sql.expected("v_session")};
  ${ctx.hook("before_till_session_close", [
    ["uuid", `v_session.${s("id")}`],
    ["bigint", "v_counted"],
  ])}
  begin
    insert into ${counts} (${c("tenant")}, ${c("session")}, ${c("denominations")}, ${c("expected")}, ${c("counted")}, ${c("variance")}, ${c("countedBy")}, ${c("notes")})
    values (v_session.${s("tenant")}, v_session.${s("id")},
      case when jsonb_typeof(v_input -> 'denominations') = 'object' then v_input -> 'denominations' end,
      v_expected, v_counted, v_counted - v_expected, auth.uid(), nullif(trim(v_input ->> 'notes'), ''))
    returning * into v_count;
  exception when check_violation then
    ${sql.invalid("notes are up to 2000 characters")}
  end;
  update ${sessions} x set ${s("status")} = 'closed', ${s("closedAt")} = now(), ${s("closedBy")} = auth.uid()
  where x.${s("id")} = v_session.${s("id")} returning * into v_session;
  if v_count.${c("variance")} <> 0 then
    ${post("till_count", `v_count.${c("id")}`, "v_entry")}
    if v_entry is not null then
      update ${counts} x set ${c("entry")} = v_entry where x.${c("id")} = v_count.${c("id")};
    end if;
  end if;
  ${sql.recordSession("till_session.closed", "v_session", "v_till", "till session closed")}
  ${ctx.hook("after_till_session_close", [["uuid", `v_session.${s("id")}`]])}
  select * into v_session from ${sessions} x where x.${s("id")} = v_session.${s("id")};
  return ${sql.sessionDetail("v_session")};
end;
$$;
${userGrant(`${fn("close_till_session")}(uuid, jsonb)`)}

-- Takes counted cash to the bank from a closed session. input is { amount,
-- depositedOn, reference }; the deposits of a session never exceed its count.
-- With accounting and a cash account on the till, the deposit is booked as bank
-- against cash. It stays pending until it is reconciled. Needs tills.manage.
create or replace function ${fn("deposit_till_cash")}(session_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(deposit_till_cash.input, '{}'::jsonb);
  v_session ${sessions};
  v_till ${tills};
  v_count ${counts};
  v_amount bigint;
  v_on date;
  v_entry uuid;
  v_row ${deposits};
begin
  select * into v_session from ${sessions} x where x.${s("id")} = deposit_till_cash.session_id for update;
  if not found or not ${sql.allowed(`v_session.${s("tenant")}`, sql.read)} then
    ${sql.sessionMissing}
  end if;
  if not ${sql.allowed(`v_session.${s("tenant")}`, sql.manage)} then
    ${sql.forbidden("not allowed to deposit till cash")}
  end if;
  select * into v_count from ${counts} x where x.${c("session")} = v_session.${s("id")};
  if v_session.${s("status")} <> 'closed' or v_count.${c("id")} is null then
    ${sql.status("cash can only be deposited from a closed, counted session")}
  end if;
  if coalesce(v_input ->> 'amount', '') !~ '^[0-9]{1,18}$' or (v_input ->> 'amount')::bigint = 0 then
    ${sql.invalid("amount is above zero, in minor units")}
  end if;
  v_amount := (v_input ->> 'amount')::bigint;
  if coalesce(v_input ->> 'depositedOn', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    v_on := (v_input ->> 'depositedOn')::date;
  elsif nullif(v_input ->> 'depositedOn', '') is null then
    v_on := (now() at time zone 'UTC')::date;
  else
    ${sql.invalid("depositedOn is a date such as 2026-10-31")}
  end if;
  if v_amount + coalesce((select sum(y.${d("amount")}) from ${deposits} y where y.${d("session")} = v_session.${s("id")}), 0) > v_count.${c("counted")} then
    ${sql.invalid("the deposits would exceed the counted cash of the session")}
  end if;
  select * into v_till from ${tills} x where x.${t("id")} = v_session.${s("till")};
  ${ctx.hook("before_till_deposit", [
    ["uuid", `v_session.${s("id")}`],
    ["bigint", "v_amount"],
  ])}
  begin
    insert into ${deposits} (${d("tenant")}, ${d("session")}, ${d("amount")}, ${d("depositedOn")}, ${d("reference")}, ${d("createdBy")})
    values (v_session.${s("tenant")}, v_session.${s("id")}, v_amount, v_on, nullif(trim(v_input ->> 'reference'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation then
    ${sql.invalid("a reference is up to 200 characters")}
  end;
  ${post("till_deposit", `v_row.${d("id")}`, "v_entry")}
  if v_entry is not null then
    update ${deposits} x set ${d("entry")} = v_entry where x.${d("id")} = v_row.${d("id")} returning * into v_row;
  end if;
  ${sql.recordDeposit("till_deposit.recorded", "v_row", "v_till", "cash deposit recorded")}
  ${ctx.hook("after_till_deposit", [["uuid", `v_row.${d("id")}`]])}
  return ${sql.depositJson("v_row")};
end;
$$;
${userGrant(`${fn("deposit_till_cash")}(uuid, jsonb)`)}

-- Matches a pending deposit to the bank transaction that shows it, through the
-- banking block, and marks it reconciled. The transaction's amount must equal
-- the deposit's. Needs tills.manage.
create or replace function ${fn("reconcile_till_deposit")}(deposit_id uuid, bank_transaction_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${deposits};
  v_till ${tills};
begin
  select * into v_row from ${deposits} x where x.${d("id")} = reconcile_till_deposit.deposit_id for update;
  if not found or not ${sql.allowed(`v_row.${d("tenant")}`, sql.read)} then
    ${sql.depositMissing}
  end if;
  if not ${sql.allowed(`v_row.${d("tenant")}`, sql.manage)} then
    ${sql.forbidden("not allowed to reconcile cash deposits")}
  end if;
  if v_row.${d("status")} <> 'pending' then
    ${sql.status("this deposit is already reconciled")}
  end if;
  ${matchTransaction}
  update ${deposits} x set ${d("status")} = 'reconciled', ${d("bankTransaction")} = reconcile_till_deposit.bank_transaction_id, ${d("reconciledAt")} = now()
  where x.${d("id")} = v_row.${d("id")} returning * into v_row;
  select y.* into v_till from ${tills} y join ${sessions} z on z.${s("till")} = y.${t("id")} where z.${s("id")} = v_row.${d("session")};
  ${sql.recordDeposit("till_deposit.reconciled", "v_row", "v_till", "cash deposit reconciled")}
  return ${sql.depositJson("v_row")};
end;
$$;
${userGrant(`${fn("reconcile_till_deposit")}(uuid, uuid)`)}
`;
}
