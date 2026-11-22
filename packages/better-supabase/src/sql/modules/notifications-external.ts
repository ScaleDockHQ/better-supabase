import type { BlockSqlContext } from "../context.ts";
import type { NotifyNames } from "./notifications-sql.ts";

import { fail } from "../shared.ts";
import { addressSql } from "./notifications-address.ts";

const ADDRESS = "'^[^@[:space:]]+@[^@[:space:]]+$'";

const UUID = "'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'";

/**
 * Whether `options.externalRecipients` is on: a notification may name people
 * who are not members, by email address or by a contact the app resolves, and
 * the email channel reaches them. It needs the deliveries table and the two
 * recipient columns.
 */
export function externalOn(ctx: BlockSqlContext, n: NotifyNames): boolean {
  return (
    ctx.flag("externalRecipients", false) &&
    ctx.hasTable("deliveries") &&
    n.has("recipients", "address") &&
    n.has("recipients", "contact")
  );
}

/** The two recipient columns of the created table, and the target check. */
export function externalColumns(
  ctx: BlockSqlContext,
  n: NotifyNames,
): readonly string[] {
  if (!externalOn(ctx, n)) {
    return [];
  }

  const c = (logical: string) => n.col("recipients", logical);

  return [
    `${c("address")} text check (length(${c("address")}) <= 320)`,
    `${c("contact")} uuid`,
    `check (num_nonnulls(${c("user")}, ${c("address")}, ${c("contact")}) = 1)`,
  ];
}

/** The statements a table created before the option needs, and its indexes. */
export function externalAlter(ctx: BlockSqlContext, n: NotifyNames): string {
  if (!externalOn(ctx, n)) {
    return "";
  }

  const c = (logical: string) => n.col("recipients", logical);
  const table = n.table("recipients");

  return `
alter table ${table} add column if not exists ${c("address")} text check (length(${c("address")}) <= 320);
alter table ${table} add column if not exists ${c("contact")} uuid;
alter table ${table} alter column ${c("user")} drop not null;
do $external$
begin
  if not exists (select 1 from pg_constraint where conrelid = '${table}'::regclass and conname = 'notification_recipients_target_check') then
    alter table ${table} add constraint notification_recipients_target_check check (num_nonnulls(${c("user")}, ${c("address")}, ${c("contact")}) = 1);
  end if;
end
$external$;
create unique index if not exists notification_recipients_address_idx on ${table} (${c("event")}, ${c("address")}) where ${c("address")} is not null;
create unique index if not exists notification_recipients_contact_idx on ${table} (${c("event")}, ${c("contact")}) where ${c("contact")} is not null;`;
}

/** The declaration of the `notification.external` list in `send_notification`. */
export function externalDeclare(ctx: BlockSqlContext, n: NotifyNames): string {
  return externalOn(ctx, n)
    ? `
  v_external jsonb := case when jsonb_typeof(notification -> 'external') = 'array' then notification -> 'external' else '[]'::jsonb end;`
    : "";
}

/** Rejects an `external` entry that is not one `{ address }` or `{ contact }`. */
export function externalCheck(ctx: BlockSqlContext, n: NotifyNames): string {
  if (!externalOn(ctx, n)) {
    return "";
  }

  const contacts = ctx.option("resolveAddress") !== undefined;

  return `
  if exists (
    select 1 from jsonb_array_elements(v_external) x
    where jsonb_typeof(x) <> 'object'
      or num_nonnulls(x ->> 'address', x ->> 'contact') <> 1
      or (x ? 'address' and btrim(x ->> 'address') !~ ${ADDRESS})
      or (x ? 'contact' and (x ->> 'contact') !~* ${UUID})${contacts ? "" : "\n      or x ? 'contact'"}
  ) then
    ${fail("NOTIFICATION_EXTERNAL_INVALID", contacts ? "external recipients are { address } or { contact } objects" : "external recipients are { address } objects; contacts need options.resolveAddress", "22023")}
  end if;`;
}

/** The recipient rows and email deliveries of the `external` list. */
export function externalInsert(ctx: BlockSqlContext, n: NotifyNames): string {
  if (!externalOn(ctx, n)) {
    return "";
  }

  const r = (logical: string) => n.col("recipients", logical);
  const d = (logical: string) => n.col("deliveries", logical);
  const tenant = n.has("recipients", "tenant");
  const deliveryTenant = n.has("deliveries", "tenant");

  return `
  if jsonb_array_length(v_external) > 0 and 'email' = any(v_channels) then
    -- They have no inbox: dismissed at once, delivered by email only.
    with added as (
      insert into ${n.table("recipients")} (${[r("event"), ...(tenant ? [r("tenant")] : []), r("address"), r("contact"), r("dismissedAt"), r("createdAt")].join(", ")})
      select ${["v_event", ...(tenant ? ["v_tenant"] : []), `lower(btrim(x ->> 'address'))`, `(x ->> 'contact')::uuid`, "now()", "clock_timestamp()"].join(", ")}
      from jsonb_array_elements(v_external) x
      on conflict do nothing
      returning ${r("id")} as id
    )
    insert into ${n.table("deliveries")} (${[d("recipient"), ...(deliveryTenant ? [d("tenant")] : []), d("channel"), d("status")].join(", ")})
    select ${["a.id", ...(deliveryTenant ? ["v_tenant"] : []), "'email'", "'pending'"].join(", ")} from added a
    on conflict do nothing;
  end if;`;
}

/**
 * The address the claim returns: a member's, or for an external recipient the
 * address it names or the one `resolveAddress` finds for its contact.
 */
export function claimAddress(
  ctx: BlockSqlContext,
  n: NotifyNames,
  channel: string,
  memberAddress: string,
): string {
  if (!externalOn(ctx, n)) {
    return memberAddress;
  }

  const r = (logical: string) => `rc.${n.col("recipients", logical)}`;

  return `case when ${r("user")} is not null then ${memberAddress} else coalesce(${r("address")}, ${addressSql(ctx, r("contact"), channel, "null::text")}) end`;
}

/**
 * Columns later versions added, then the external-recipient ones, for tables
 * created before.
 */
export function addedColumns(ctx: BlockSqlContext, n: NotifyNames): string {
  const later = (
    [
      ["events", "actions"],
      ["recipients", "resolution"],
    ] as const
  )
    .filter(([table, logical]) => n.has(table, logical))
    .map(
      ([table, logical]) =>
        `alter table ${n.table(table)} add column if not exists ${n.col(table, logical)} jsonb;`,
    )
    .join("\n");

  return later + externalAlter(ctx, n);
}
