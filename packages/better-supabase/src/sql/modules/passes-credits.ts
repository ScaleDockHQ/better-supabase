import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { MOVING_REASON } from "./bookings-series.ts";
import { ledgerRebalance, ledgerTables } from "./ledger.ts";
import { moduleOperations } from "./permissions-model.ts";

/**
 * Whether `blocks['passes'].options.credits` is on; it needs bookings, and adds
 * the ledger to what the block requires.
 */
export const creditsOn = (ctx: BlockSqlContext): boolean =>
  ctx.manages && ctx.installed("bookings") && ctx.flag("credits", false);

/** The ledger key of a credit movement, unique per booking and reason. */
const creditKey = (booking: string, reason: "booking" | "refund"): string =>
  `'pass-credit:' || ${booking}::text || ':${reason}'`;

/** The code of a pass's credit account. */
const passCode = (pass: string): string => `'pass:' || ${pass}::text`;

const POOL_CODE = "'pass-credits:pool'";

/** SQL fragments the credit functions and the upgrade share. */
function creditLedger(ctx: BlockSqlContext) {
  const ledger = ctx.of("ledger");
  const la = (column: string): string => ledger.col("accounts", column);

  const read = ctx.permission("read", moduleOperations("passes").read);

  /** A pass's credit account, opened on first use. */
  const passAccount = (tenant: string, pass: string, holder: string): string =>
    `${ledger.fn("ledger_account_for")}(${tenant}, 'pass_credits', ${passCode(pass)}, 'Pass credits', 'credit', 0::smallint,
    'passes', ${pass}::text, ${holder}, true, ${read}, 'passes', jsonb_build_object('passId', ${pass}))`;

  /** The organization's pool the credits come from and go back to. */
  const poolAccount = (tenant: string): string =>
    `${ledger.fn("ledger_account_for")}(${tenant}, 'pass_credits_pool', ${POOL_CODE}, 'Pass credits pool', 'credit', 0::smallint,
    null, null, null, true, ${read}, 'passes', null)`;

  return { ledger, la, read, passAccount, poolAccount };
}

/**
 * Class credits: a pass with a number of uses pays for bookings, one use each,
 * and gives the use back when the booking is cancelled early enough. Every
 * movement is a ledger transaction on the pass's credit account against the
 * organization's pool; `passes.uses` is its running total.
 */
export function creditsSql(ctx: BlockSqlContext): string {
  const passes = ctx.table("passes");
  const p = (column: string): string => ctx.col("passes", column);

  const touched = ctx.has("passes", "updatedAt")
    ? `, ${p("updatedAt")} = now()`
    : "";

  const fn = (name: string): string => ctx.fn(name);
  const bookings = ctx.of("bookings");
  const b = (column: string): string => bookings.col("bookings", column);
  const s = (column: string): string => bookings.col("services", column);
  const { ledger, la, read, passAccount, poolAccount } = creditLedger(ctx);
  const lt = (column: string): string => ledger.col("transactions", column);
  const le = (column: string): string => ledger.col("entries", column);
  const transactions = ledger.table("transactions");

  const manage = ctx.permission("manage", moduleOperations("passes").manage);

  const refundBefore = sqlString(ctx.text("creditRefundBefore", "12 hours"));
  const trigger = sqlIdent(`${ctx.tableName("passes").name}_credit_refund`);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const entryJson = `jsonb_build_object('id', r.${lt("id")}, 'organizationId', r.${lt("tenant")}::text, 'passId', (x.${la("metadata")} ->> 'passId')::uuid,
      'bookingId', r.${lt("referenceId")}::uuid, 'delta', y.${le("amount")},
      'reason', case when r.${lt("kind")} = 'pass.credit_used' then 'booking' else 'refund' end,
      'createdBy', r.${lt("actor")}, 'createdAt', r.${lt("createdAt")})`;

  const creditRecord = (
    type: "pass.credit_used" | "pass.credit_refunded",
    tenant: string,
    pass: string,
    entry: string,
    booking: string,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${tenant}::text, 'id', ${pass}, 'entryId', ${entry}, 'bookingId', ${booking})`,
      subject: `'passes/' || ${pass}::text`,
      tenant,
      audit: {
        category: "access",
        targetType: "pass",
        recordId: `${pass}::text`,
        summary: `'${type === "pass.credit_used" ? "booked with a credit of" : "refunded a credit to"} pass'`,
      },
    });

  /** Posts one credit movement between the pass's account and the pool. */
  const post = (
    tenant: string,
    pass: string,
    holder: string,
    booking: string,
    reason: "booking" | "refund",
  ): string => {
    const amount = reason === "booking" ? -1 : 1;

    return `${ledger.fn("ledger_post")}(${tenant}, '${reason === "booking" ? "pass.credit_used" : "pass.credit_refunded"}',
      jsonb_build_array(
        jsonb_build_object('account', ${passAccount(tenant, pass, holder)}, 'amount', ${amount}),
        jsonb_build_object('account', ${poolAccount(tenant)}, 'amount', ${-amount})),
      'bookings', ${booking}::text, null, ${creditKey(booking, reason)}, clock_timestamp(),
      jsonb_build_object('passId', ${pass}, 'reason', '${reason}'))`;
  };

  return `
-- Books a class with one credit of a pass: the holder, or a passes manager
-- for the holder. The pass must be active, valid when the class starts, for
-- that resource (or any) and have a use left. The booking is confirmed, and
-- the credit moves from the pass's ledger account to the pool.
create or replace function ${fn("book_with_credit")}(pass_id uuid, service uuid, resource uuid, starts_at timestamptz, customer jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pass ${passes}%rowtype;
  v_tenant ${ctx.idType};
  v_booking jsonb;
  v_entry uuid;
begin
  select * into v_pass from ${passes} x where x.${p("id")} = book_with_credit.pass_id for update;
  if not found or not (coalesce(v_pass.${p("holderUser")} = auth.uid(), false) or ${allowed(`v_pass.${p("tenant")}`, manage)}) then
    ${fail("PASS_NOT_FOUND", "pass not found", "P0002")}
  end if;
  if v_pass.${p("status")} <> 'active' then
    ${fail("PASS_REVOKED", "the pass is revoked", "55000")}
  end if;
  if v_pass.${p("usesAllowed")} is null or v_pass.${p("booking")} is not null then
    ${fail("PASS_NOT_CREDITS", "only a pass with a number of uses and no booking of its own pays for bookings", "22023")}
  end if;
  if v_pass.${p("resource")} is not null and v_pass.${p("resource")} <> book_with_credit.resource then
    ${fail("PASS_WRONG_RESOURCE", "the pass is for another resource", "22023")}
  end if;
  if book_with_credit.starts_at < v_pass.${p("validFrom")} or (v_pass.${p("validUntil")} is not null and book_with_credit.starts_at >= v_pass.${p("validUntil")}) then
    ${fail("PASS_NOT_VALID", "the pass is not valid when the class starts", "22023")}
  end if;
  if v_pass.${p("uses")} >= v_pass.${p("usesAllowed")} then
    ${fail("PASS_CREDITS_USED_UP", "the pass has no credits left", "55000")}
  end if;
  select sv.${s("tenant")} into v_tenant from ${bookings.table("services")} sv where sv.${s("id")} = book_with_credit.service;
  if v_tenant is distinct from v_pass.${p("tenant")} then
    ${fail("PASS_BOOKING_NOT_FOUND", "the service does not exist in the pass's organization", "P0002")}
  end if;
  v_booking := ${bookings.fn("hold_booking")}(book_with_credit.service, book_with_credit.resource, book_with_credit.starts_at,
    coalesce(book_with_credit.customer, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('userId', v_pass.${p("holderUser")}, 'name', ${ctx.has("passes", "holderName") ? `v_pass.${p("holderName")}` : "null"}, 'email', ${ctx.has("passes", "holderEmail") ? `v_pass.${p("holderEmail")}` : "null"})), true);
  v_entry := ${post(`v_pass.${p("tenant")}`, `v_pass.${p("id")}`, `v_pass.${p("holderUser")}`, "(v_booking ->> 'id')::uuid", "booking")};
  update ${passes} x set ${p("uses")} = x.${p("uses")} + 1${touched}
  where x.${p("id")} = v_pass.${p("id")};
  ${creditRecord("pass.credit_used", `v_pass.${p("tenant")}`, `v_pass.${p("id")}`, "v_entry", "(v_booking ->> 'id')::uuid")}
  return (v_booking - 'accessToken') || jsonb_build_object('passId', v_pass.${p("id")}, 'creditsLeft', v_pass.${p("usesAllowed")} - v_pass.${p("uses")} - 1);
end;
$$;
${userGrant(`${fn("book_with_credit")}(uuid, uuid, uuid, timestamptz, jsonb)`)}

-- Gives the credit back when a credit booking is cancelled at least
-- ${ctx.text("creditRefundBefore", "12 hours")} before it starts; later, the credit is spent. A booking
-- that moves (cancel reason ${MOVING_REASON}) keeps its credit. The ledger key
-- refunds a booking once.
create or replace function ${fn("refund_pass_credit")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_spent record;
  v_entry uuid;
begin
  if new.${b("status")} <> 'cancelled' or old.${b("status")} = 'cancelled'
    or new.${b("cancelReason")} is not distinct from '${MOVING_REASON}'
    or now() > lower(new.${b("during")}) - ${refundBefore}::interval then
    return null;
  end if;
  for v_spent in
    select r.${lt("tenant")} as tenant, (r.${lt("metadata")} ->> 'passId')::uuid as pass, x.${p("holderUser")} as holder
    from ${transactions} r
    join ${passes} x on x.${p("id")} = (r.${lt("metadata")} ->> 'passId')::uuid
    where r.${lt("tenant")} = new.${b("tenant")} and r.${lt("key")} = ${creditKey(`new.${b("id")}`, "booking")}
      and not exists (select 1 from ${transactions} d where d.${lt("tenant")} = r.${lt("tenant")} and d.${lt("key")} = ${creditKey(`new.${b("id")}`, "refund")})
  loop
    v_entry := ${post("v_spent.tenant", "v_spent.pass", "v_spent.holder", `new.${b("id")}`, "refund")};
    update ${passes} x set ${p("uses")} = greatest(x.${p("uses")} - 1, 0)${touched}
    where x.${p("id")} = v_spent.pass;
    ${creditRecord("pass.credit_refunded", "v_spent.tenant", "v_spent.pass", "v_entry", `new.${b("id")}`)}
  end loop;
  return null;
end;
$$;
revoke all on function ${fn("refund_pass_credit")}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${bookings.table("bookings")};
create trigger ${trigger}
after update of ${b("status")} on ${bookings.table("bookings")}
for each row execute function ${fn("refund_pass_credit")}();

-- A pass's credit movements on the ledger, newest first: its holder, or a
-- passes reader.
create or replace function ${fn("list_pass_credits")}(pass_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pass ${passes}%rowtype;
begin
  select * into v_pass from ${passes} x where x.${p("id")} = list_pass_credits.pass_id;
  if not found or not (coalesce(v_pass.${p("holderUser")} = auth.uid(), false) or ${allowed(`v_pass.${p("tenant")}`, read)}) then
    ${fail("PASS_NOT_FOUND", "pass not found", "P0002")}
  end if;
  return coalesce((
    select jsonb_agg(${entryJson} order by r.${lt("effectiveAt")} desc, r.${lt("createdAt")} desc, r.${lt("id")})
    from ${ledger.table("accounts")} x
    join ${ledger.table("entries")} y on y.${le("account")} = x.${la("id")}
    join ${transactions} r on r.${lt("id")} = y.${le("transaction")}
    where x.${la("tenant")} = v_pass.${p("tenant")} and x.${la("code")} = ${passCode(`v_pass.${p("id")}`)}
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_pass_credits")}(uuid)`)}
`;
}

/** Copies `pass_credit_entries` onto the ledger, keeping each row's id. */
export function creditsUpgrade(ctx: BlockSqlContext): string {
  if (!creditsOn(ctx)) {
    return "";
  }

  const { ledger, la, read } = creditLedger(ctx);
  const accounts = ledger.table("accounts");
  const lt = (column: string): string => ledger.col("transactions", column);
  const le = (column: string): string => ledger.col("entries", column);
  const passes = ctx.table("passes");
  const p = (column: string): string => ctx.col("passes", column);
  const old = `${ctx.schema}.pass_credit_entries`;
  // The old table took the tenant column the block names on its other tables.
  const mt = ctx.col("passes", "tenant");
  const bookings = ctx.of("bookings").table("bookings");

  return `${ledgerTables(ledger)}
do $upgrade$
begin
  if to_regclass('${ctx.schemaName}.pass_credit_entries') is null then
    return;
  end if;
  insert into ${accounts} (${la("tenant")}, ${la("kind")}, ${la("code")}, ${la("name")}, ${la("unit")}, ${la("scale")}, ${la("holderType")}, ${la("holderId")}, ${la("owner")}, ${la("allowNegative")}, ${la("readPermission")}, ${la("managedBy")}, ${la("metadata")})
  select distinct m.${mt}, 'pass_credits', ${passCode("m.pass_id")}, 'Pass credits', 'credit', 0, 'passes', m.pass_id::text, x.${p("holderUser")}, true, ${read}, 'passes',
    jsonb_build_object('passId', m.pass_id)
  from ${old} m join ${passes} x on x.${p("id")} = m.pass_id
  on conflict do nothing;
  insert into ${accounts} (${la("tenant")}, ${la("kind")}, ${la("code")}, ${la("name")}, ${la("unit")}, ${la("scale")}, ${la("allowNegative")}, ${la("readPermission")}, ${la("managedBy")})
  select distinct m.${mt}, 'pass_credits_pool', ${POOL_CODE}, 'Pass credits pool', 'credit', 0, true, ${read}, 'passes'
  from ${old} m
  on conflict do nothing;
  insert into ${ledger.table("transactions")} (${lt("id")}, ${lt("tenant")}, ${lt("kind")}, ${lt("referenceType")}, ${lt("referenceId")}, ${lt("key")}, ${lt("metadata")}, ${lt("effectiveAt")}, ${lt("actor")}, ${lt("createdAt")})
  select m.id, m.${mt}, case when m.reason = 'booking' then 'pass.credit_used' else 'pass.credit_refunded' end,
    case when m.booking_id is not null then 'bookings' end, m.booking_id::text,
    case when m.booking_id is not null then 'pass-credit:' || m.booking_id::text || ':' || m.reason end,
    jsonb_build_object('passId', m.pass_id, 'reason', m.reason), m.created_at, m.created_by, m.created_at
  from ${old} m
  on conflict do nothing;
  insert into ${ledger.table("entries")} (${le("tenant")}, ${le("transaction")}, ${le("account")}, ${le("amount")}, ${le("unit")}, ${le("createdAt")})
  select m.${mt}, m.id, x.${la("id")}, m.delta, 'credit', m.created_at
  from ${old} m join ${accounts} x on x.${la("tenant")} = m.${mt} and x.${la("code")} = ${passCode("m.pass_id")}
  union all
  select m.${mt}, m.id, x.${la("id")}, -m.delta, 'credit', m.created_at
  from ${old} m join ${accounts} x on x.${la("tenant")} = m.${mt} and x.${la("code")} = ${POOL_CODE};
  ${ledgerRebalance(ledger)}
  drop trigger if exists pass_credit_entries_refund on ${bookings};
  drop table ${old};
end;
$upgrade$;`;
}

export function creditsContract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "book_with_credit",
      args: ["uuid", "uuid", "uuid", "timestamptz", "jsonb"],
      returns: "jsonb",
    },
    { name: "list_pass_credits", args: ["uuid"], returns: "jsonb" },
  ];
}
