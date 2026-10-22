import type { ModuleContext, ModuleContractFunction } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, lockTable, SERVICE_CALLER, userGrant } from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import { MOVING_REASON } from "./bookings-series.ts";

/** The table `options.credits` adds, for the module's names. */
export const CREDIT_TABLES = {
  credits: {
    name: "pass_credit_entries",
    columns: {
      id: "id",
      tenant: "tenant_id",
      pass: "pass_id",
      booking: "booking_id",
      delta: "delta",
      reason: "reason",
      createdBy: "created_by",
      createdAt: "created_at",
    },
  },
} as const;

/** Whether `blocks.passes.options.credits` is on; it needs bookings. */
export const creditsOn = (ctx: ModuleContext): boolean =>
  ctx.manages && ctx.installed("bookings") && ctx.flag("credits", false);

/**
 * Class credits: a pass with a number of uses pays for bookings, one use each,
 * and gives the use back when the booking is cancelled early enough. Every
 * movement is a row in the credit ledger; `passes.uses` is its running total.
 */
export function creditsSql(ctx: ModuleContext): string {
  const passes = ctx.table("passes");
  const credits = ctx.table("credits");
  const p = (column: string): string => ctx.col("passes", column);
  const c = (column: string): string => ctx.col("credits", column);
  const fn = (name: string): string => ctx.fn(name);
  const bookings = ctx.of("bookings");
  const b = (column: string): string => bookings.col("bookings", column);
  const s = (column: string): string => bookings.col("services", column);
  const keys = moduleOperations("passes");
  const read = ctx.permission("read", keys.read);
  const manage = ctx.permission("manage", keys.manage);
  const refundBefore = sqlString(ctx.text("creditRefundBefore", "12 hours"));
  const name = ctx.tableName("credits").name;

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const entryJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}::text, 'passId', ${row}.${c("pass")}, 'bookingId', ${row}.${c("booking")}, 'delta', ${row}.${c("delta")}, 'reason', ${row}.${c("reason")}, 'createdBy', ${row}.${c("createdBy")}, 'createdAt', ${row}.${c("createdAt")})`;

  const creditRecord = (
    type: "pass.credit_used" | "pass.credit_refunded",
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_entry.${c("tenant")}::text, 'id', v_entry.${c("pass")}, 'entryId', v_entry.${c("id")}, 'bookingId', v_entry.${c("booking")})`,
      subject: `'passes/' || v_entry.${c("pass")}::text`,
      tenant: `v_entry.${c("tenant")}`,
      audit: {
        category: "access",
        targetType: "pass",
        recordId: `v_entry.${c("pass")}::text`,
        summary: `'${type === "pass.credit_used" ? "booked with a credit of" : "refunded a credit to"} pass'`,
      },
    });

  return `
-- The class-credit ledger: -1 when a pass pays for a booking, +1 when the
-- booking is cancelled before the refund window closes. One of each per
-- booking at most.
create table if not exists ${credits} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("pass")} uuid not null references ${passes} (${p("id")}) on delete cascade,
  ${c("booking")} uuid references ${bookings.table("bookings")} (${b("id")}) on delete set null,
  ${c("delta")} integer not null check (${c("delta")} in (-1, 1)),
  ${c("reason")} text not null check (${c("reason")} in ('booking', 'refund')),
  ${c("createdBy")} uuid,
  ${c("createdAt")} timestamptz not null default clock_timestamp(),
  check ((${c("reason")} = 'booking') = (${c("delta")} = -1))
);
create index if not exists ${sqlIdent(`${name}_pass_idx`)} on ${credits} (${c("pass")}, ${c("createdAt")} desc);
create index if not exists ${sqlIdent(`${name}_booking_idx`)} on ${credits} (${c("booking")});
create unique index if not exists ${sqlIdent(`${name}_once_idx`)} on ${credits} (${c("booking")}, ${c("reason")});
${lockTable(credits)}

-- Books a class with one credit of a pass: the holder, or a passes manager
-- for the holder. The pass must be active, valid when the class starts, for
-- that resource (or any) and have a use left. The booking is confirmed.
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
  v_entry ${credits}%rowtype;
begin
  select * into v_pass from ${passes} x where x.${p("id")} = book_with_credit.pass_id for update;
  if not found or not (v_pass.${p("holderUser")} = auth.uid() or ${allowed(`v_pass.${p("tenant")}`, manage)}) then
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
    coalesce(book_with_credit.customer, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('userId', v_pass.${p("holderUser")}, 'name', v_pass.${p("holderName")}, 'email', v_pass.${p("holderEmail")})), true);
  insert into ${credits} (${c("tenant")}, ${c("pass")}, ${c("booking")}, ${c("delta")}, ${c("reason")}, ${c("createdBy")})
  values (v_pass.${p("tenant")}, v_pass.${p("id")}, (v_booking ->> 'id')::uuid, -1, 'booking', auth.uid())
  returning * into v_entry;
  update ${passes} x set ${p("uses")} = x.${p("uses")} + 1, ${p("updatedAt")} = now()
  where x.${p("id")} = v_pass.${p("id")};
  ${creditRecord("pass.credit_used")}
  return (v_booking - 'accessToken') || jsonb_build_object('passId', v_pass.${p("id")}, 'creditsLeft', v_pass.${p("usesAllowed")} - v_pass.${p("uses")} - 1);
end;
$$;
${userGrant(`${fn("book_with_credit")}(uuid, uuid, uuid, timestamptz, jsonb)`)}

-- Gives the credit back when a credit booking is cancelled at least
-- ${ctx.text("creditRefundBefore", "12 hours")} before it starts; later, the credit is spent. A booking
-- that moves (cancel reason ${MOVING_REASON}) keeps its credit.
create or replace function ${fn("refund_pass_credit")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry ${credits}%rowtype;
begin
  if new.${b("status")} <> 'cancelled' or old.${b("status")} = 'cancelled'
    or new.${b("cancelReason")} is not distinct from '${MOVING_REASON}'
    or now() > lower(new.${b("during")}) - ${refundBefore}::interval then
    return null;
  end if;
  for v_entry in
    insert into ${credits} (${c("tenant")}, ${c("pass")}, ${c("booking")}, ${c("delta")}, ${c("reason")}, ${c("createdBy")})
    select spent.${c("tenant")}, spent.${c("pass")}, spent.${c("booking")}, 1, 'refund', auth.uid()
    from ${credits} spent
    where spent.${c("booking")} = new.${b("id")} and spent.${c("reason")} = 'booking'
    on conflict (${c("booking")}, ${c("reason")}) do nothing
    returning *
  loop
    update ${passes} x set ${p("uses")} = greatest(x.${p("uses")} - 1, 0), ${p("updatedAt")} = now()
    where x.${p("id")} = v_entry.${c("pass")};
    ${creditRecord("pass.credit_refunded")}
  end loop;
  return null;
end;
$$;
revoke all on function ${fn("refund_pass_credit")}() from public, anon, authenticated;
drop trigger if exists ${sqlIdent(`${name}_refund`)} on ${bookings.table("bookings")};
create trigger ${sqlIdent(`${name}_refund`)}
after update of ${b("status")} on ${bookings.table("bookings")}
for each row execute function ${fn("refund_pass_credit")}();

-- A pass's credit ledger, newest first: its holder, or a passes reader.
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
  if not found or not (v_pass.${p("holderUser")} = auth.uid() or ${allowed(`v_pass.${p("tenant")}`, read)}) then
    ${fail("PASS_NOT_FOUND", "pass not found", "P0002")}
  end if;
  return coalesce((
    select jsonb_agg(${entryJson("e")} order by e.${c("createdAt")} desc, e.${c("id")})
    from ${credits} e where e.${c("pass")} = v_pass.${p("id")}
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_pass_credits")}(uuid)`)}
`;
}

export function creditsContract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "book_with_credit",
      args: ["uuid", "uuid", "uuid", "timestamptz", "jsonb"],
      returns: "jsonb",
    },
    { name: "list_pass_credits", args: ["uuid"], returns: "jsonb" },
  ];
}
