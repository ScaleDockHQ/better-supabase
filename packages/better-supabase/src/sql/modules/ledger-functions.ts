import type { BlockSqlContext } from "../context.ts";

import {
  fail,
  pageSize,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./access-model.ts";

/** The ledger's functions: the internal posting core and the public API. */
export function ledgerFunctions(ctx: BlockSqlContext): string {
  const accounts = ctx.table("accounts");
  const transactions = ctx.table("transactions");
  const entries = ctx.table("entries");
  const balances = ctx.table("balances");
  const holds = ctx.table("holds");
  const a = (column: string): string => ctx.col("accounts", column);
  const t = (column: string): string => ctx.col("transactions", column);
  const e = (column: string): string => ctx.col("entries", column);
  const b = (column: string): string => ctx.col("balances", column);
  const h = (column: string): string => ctx.col("holds", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("ledger");
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const post = ctx.permission("post", permissions.post);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const visible = (row: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", `${row}.${a("tenant")}`, read)} or ${row}.${a("owner")} = auth.uid() or (${row}.${a("readPermission")} is not null and ${ctx.can("tenant", `${row}.${a("tenant")}`, `${row}.${a("readPermission")}`)}))`;

  const forbidden = (message: string): string =>
    fail("LEDGER_FORBIDDEN", message);

  const invalid = (code: string, message: string): string =>
    fail(code, message, "22023");

  const accountJson = (row: string, balance: string): string =>
    `jsonb_build_object('id', ${row}.${a("id")}, 'organizationId', ${row}.${a("tenant")}, 'kind', ${row}.${a("kind")}, 'code', ${row}.${a("code")}, 'name', ${row}.${a("name")}, 'unit', ${row}.${a("unit")}, 'scale', ${row}.${a("scale")}, 'holderType', ${row}.${a("holderType")}, 'holderId', ${row}.${a("holderId")}, 'ownerId', ${row}.${a("owner")}, 'allowNegative', ${row}.${a("allowNegative")}, 'readPermission', ${row}.${a("readPermission")}, 'managedBy', ${row}.${a("managedBy")}, 'metadata', ${row}.${a("metadata")}, 'closedAt', ${row}.${a("closedAt")}, 'createdAt', ${row}.${a("createdAt")}, 'balance', coalesce(${balance}.${b("balance")}, 0)::text, 'held', coalesce(${balance}.${b("held")}, 0)::text, 'available', coalesce(${balance}.${b("balance")} - ${balance}.${b("held")}, 0)::text)`;

  const entriesOf = (transaction: string): string =>
    `coalesce((select jsonb_agg(jsonb_build_object('id', y.${e("id")}, 'accountId', y.${e("account")}, 'amount', y.${e("amount")}::text, 'unit', y.${e("unit")}) order by y.${e("createdAt")}, y.${e("id")}) from ${entries} y where y.${e("transaction")} = ${transaction}), '[]'::jsonb)`;

  const transactionJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${t("id")}, 'organizationId', ${row}.${t("tenant")}, 'kind', ${row}.${t("kind")}, 'referenceType', ${row}.${t("referenceType")}, 'referenceId', ${row}.${t("referenceId")}, 'memo', ${row}.${t("memo")}, 'idempotencyKey', ${row}.${t("key")}, 'reverses', ${row}.${t("reverses")}, 'metadata', ${row}.${t("metadata")}, 'effectiveAt', ${row}.${t("effectiveAt")}, 'actorId', ${row}.${t("actor")}, 'createdAt', ${row}.${t("createdAt")}, 'entries', ${entriesOf(`${row}.${t("id")}`)})`;

  const holdJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${h("id")}, 'organizationId', ${row}.${h("tenant")}, 'accountId', ${row}.${h("account")}, 'amount', ${row}.${h("amount")}::text, 'status', ${row}.${h("status")}, 'referenceType', ${row}.${h("referenceType")}, 'referenceId', ${row}.${h("referenceId")}, 'expiresAt', ${row}.${h("expiresAt")}, 'transactionId', ${row}.${h("transaction")}, 'createdBy', ${row}.${h("createdBy")}, 'createdAt', ${row}.${h("createdAt")}, 'updatedAt', ${row}.${h("updatedAt")})`;

  const accountRecord = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${a("tenant")}, 'id', ${row}.${a("id")}, 'kind', ${row}.${a("kind")}, 'code', ${row}.${a("code")}, 'unit', ${row}.${a("unit")}, 'holderType', ${row}.${a("holderType")}, 'holderId', ${row}.${a("holderId")})`,
      subject: `'ledger-accounts/' || ${row}.${a("id")}::text`,
      tenant: `${row}.${a("tenant")}`,
      audit: {
        category: "billing",
        targetType: "ledger_account",
        recordId: `${row}.${a("id")}::text`,
        targetLabel: `${row}.${a("name")}`,
        summary: `'${summary} ' || ${row}.${a("code")}`,
      },
    });

  const transactionPayload = (row: string): string =>
    `jsonb_build_object('organizationId', ${row}.${t("tenant")}, 'id', ${row}.${t("id")}, 'kind', ${row}.${t("kind")}, 'referenceType', ${row}.${t("referenceType")}, 'referenceId', ${row}.${t("referenceId")}, 'reverses', ${row}.${t("reverses")}, 'entries', (select count(*)::integer from ${entries} y where y.${e("transaction")} = ${row}.${t("id")}))`;

  const holdRecord = (type: string, row: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${h("tenant")}, 'id', ${row}.${h("id")}, 'accountId', ${row}.${h("account")}, 'amount', ${row}.${h("amount")}::text, 'status', ${row}.${h("status")}, 'transactionId', ${row}.${h("transaction")})`,
      subject: `'ledger-holds/' || ${row}.${h("id")}::text`,
      tenant: `${row}.${h("tenant")}`,
      audit: false,
    });

  const postArgs = `${idType}, text, jsonb, text, text, text, text, timestamptz, jsonb, uuid`;
  const accountArgs = `${idType}, text, text, text, text, smallint, text, text, uuid, boolean, text, text, jsonb`;

  return `-- The account with code, opened with the rest when it doesn't exist yet.
-- Modules that post to the ledger call it; it isn't granted to anyone.
create or replace function ${fn("ledger_account_for")}(tenant ${idType}, kind text, code text, name text, unit text, scale smallint default 0, holder_type text default null, holder_id text default null, owner_id uuid default null, allow_negative boolean default false, read_permission text default null, managed_by text default null, metadata jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  select x.${a("id")} into v_id from ${accounts} x
    where x.${a("tenant")} = ledger_account_for.tenant and x.${a("code")} = ledger_account_for.code;
  if found then
    return v_id;
  end if;
  insert into ${accounts} (${a("tenant")}, ${a("kind")}, ${a("code")}, ${a("name")}, ${a("unit")}, ${a("scale")}, ${a("holderType")}, ${a("holderId")}, ${a("owner")}, ${a("allowNegative")}, ${a("readPermission")}, ${a("managedBy")}, ${a("metadata")})
  values (ledger_account_for.tenant, ledger_account_for.kind, ledger_account_for.code, ledger_account_for.name, ledger_account_for.unit,
    coalesce(ledger_account_for.scale, 0), ledger_account_for.holder_type, ledger_account_for.holder_id, ledger_account_for.owner_id,
    coalesce(ledger_account_for.allow_negative, false), ledger_account_for.read_permission, ledger_account_for.managed_by,
    coalesce(ledger_account_for.metadata, '{}'::jsonb))
  on conflict (${a("tenant")}, ${a("code")}) do nothing
  returning ${a("id")} into v_id;
  if v_id is null then
    select x.${a("id")} into v_id from ${accounts} x
      where x.${a("tenant")} = ledger_account_for.tenant and x.${a("code")} = ledger_account_for.code;
  end if;
  return v_id;
end;
$$;
revoke execute on function ${fn("ledger_account_for")}(${accountArgs}) from public, anon, authenticated;

-- Posts a balanced transaction: lines is an array of {account, amount} with
-- signed integer amounts in each account's unit, summing to zero per unit.
-- With idempotency_key a second call returns the first transaction. Modules
-- that post to the ledger call it; it isn't granted to anyone.
create or replace function ${fn("ledger_post")}(tenant ${idType}, kind text, lines jsonb, reference_type text default null, reference_id text default null, memo text default null, idempotency_key text default null, effective_at timestamptz default null, metadata jsonb default null, reverses uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row ${transactions}%rowtype;
begin
  if ledger_post.idempotency_key is not null then
    select x.${t("id")} into v_id from ${transactions} x
      where x.${t("tenant")} = ledger_post.tenant and x.${t("key")} = ledger_post.idempotency_key;
    if found then
      return v_id;
    end if;
  end if;
  if ledger_post.kind is null or ledger_post.kind !~ '^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$' then
    ${invalid("LEDGER_KIND_INVALID", "kind must be lowercase words joined by dots, such as credit.grant")}
  end if;
  if jsonb_typeof(ledger_post.lines) is distinct from 'array' or jsonb_array_length(ledger_post.lines) < 2 then
    ${invalid("LEDGER_LINES_INVALID", "a transaction needs at least two lines")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    where jsonb_typeof(l.value) is distinct from 'object'
      or coalesce(l.value ->> 'account', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(l.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$'
      or (l.value ->> 'amount')::bigint = 0
  ) then
    ${invalid("LEDGER_LINES_INVALID", "every line needs an account id and a non-zero integer amount")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    left join ${accounts} x on x.${a("id")} = (l.value ->> 'account')::uuid
      and x.${a("tenant")} = ledger_post.tenant and x.${a("closedAt")} is null
    where x.${a("id")} is null
  ) then
    ${fail("LEDGER_ACCOUNT_NOT_FOUND", "an account of the transaction doesn't exist here or is closed", "P0002")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    join ${accounts} x on x.${a("id")} = (l.value ->> 'account')::uuid
    group by x.${a("unit")} having sum((l.value ->> 'amount')::bigint) <> 0
  ) then
    ${fail("LEDGER_UNBALANCED", "the lines of a ledger transaction must sum to zero per unit", "23514")}
  end if;
  ${ctx.hook("before_ledger_transaction_post", [
    [idType, "ledger_post.tenant"],
    ["text", "ledger_post.kind"],
    ["jsonb", "ledger_post.lines"],
  ])}
  insert into ${transactions} (${t("tenant")}, ${t("kind")}, ${t("referenceType")}, ${t("referenceId")}, ${t("memo")}, ${t("key")}, ${t("reverses")}, ${t("metadata")}, ${t("effectiveAt")}, ${t("actor")})
  values (ledger_post.tenant, ledger_post.kind, ledger_post.reference_type, ledger_post.reference_id, nullif(trim(ledger_post.memo), ''),
    ledger_post.idempotency_key, ledger_post.reverses, coalesce(ledger_post.metadata, '{}'::jsonb), coalesce(ledger_post.effective_at, now()), auth.uid())
  returning * into v_row;
  insert into ${entries} (${e("tenant")}, ${e("transaction")}, ${e("account")}, ${e("amount")}, ${e("unit")})
  select ledger_post.tenant, v_row.${t("id")}, x.${a("id")}, (l.value ->> 'amount')::bigint, x.${a("unit")}
  from jsonb_array_elements(ledger_post.lines) with ordinality as l(value, n)
  join ${accounts} x on x.${a("id")} = (l.value ->> 'account')::uuid
  order by l.n;
  ${ctx.record({
    type: "ledger_transaction.posted",
    payload: transactionPayload("v_row"),
    subject: `'ledger-transactions/' || v_row.${t("id")}::text`,
    tenant: `v_row.${t("tenant")}`,
    audit: false,
  })}
  ${ctx.hook("after_ledger_transaction_post", [["uuid", `v_row.${t("id")}`]])}
  return v_row.${t("id")};
end;
$$;
revoke execute on function ${fn("ledger_post")}(${postArgs}) from public, anon, authenticated;

-- Opens an account for the app's own use (credits, loyalty points, gift
-- cards, trust balances). code is unique per organization.
create or replace function ${fn("open_ledger_account")}(tenant ${idType}, kind text, code text, name text, unit text, scale smallint default 0, holder_type text default null, holder_id text default null, owner_id uuid default null, allow_negative boolean default false, read_permission text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${accounts}%rowtype;
  v_balance ${balances}%rowtype;
begin
  if not ${allowed("open_ledger_account.tenant", manage)} then
    ${forbidden("not allowed to manage ledger accounts")}
  end if;
  if exists (select 1 from ${accounts} x where x.${a("tenant")} = open_ledger_account.tenant and x.${a("code")} = open_ledger_account.code) then
    ${fail("LEDGER_ACCOUNT_CODE_TAKEN", "an account with this code already exists", "23505")}
  end if;
  insert into ${accounts} (${a("tenant")}, ${a("kind")}, ${a("code")}, ${a("name")}, ${a("unit")}, ${a("scale")}, ${a("holderType")}, ${a("holderId")}, ${a("owner")}, ${a("allowNegative")}, ${a("readPermission")}, ${a("metadata")})
  values (open_ledger_account.tenant, open_ledger_account.kind, open_ledger_account.code, open_ledger_account.name, open_ledger_account.unit,
    coalesce(open_ledger_account.scale, 0), open_ledger_account.holder_type, open_ledger_account.holder_id, open_ledger_account.owner_id,
    coalesce(open_ledger_account.allow_negative, false), open_ledger_account.read_permission, coalesce(open_ledger_account.metadata, '{}'::jsonb))
  returning * into v_row;
  ${accountRecord("ledger_account.opened", "v_row", "opened ledger account")}
  return ${accountJson("v_row", "v_balance")};
end;
$$;
${userGrant(`${fn("open_ledger_account")}(${idType}, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb)`)}

-- Closes an account with a zero balance and no active holds.
create or replace function ${fn("close_ledger_account")}(account_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${accounts}%rowtype;
  v_balance ${balances}%rowtype;
begin
  select * into v_row from ${accounts} x where x.${a("id")} = close_ledger_account.account_id for update;
  if not found or not ${visible("v_row")} then
    ${fail("LEDGER_ACCOUNT_NOT_FOUND", "ledger account not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${a("tenant")}`, manage)} then
    ${forbidden("not allowed to manage ledger accounts")}
  end if;
  if v_row.${a("managedBy")} is not null and not ${SERVICE_CALLER} then
    ${fail("LEDGER_ACCOUNT_MANAGED", "this account belongs to another block", "55000")}
  end if;
  select * into v_balance from ${balances} x where x.${b("account")} = v_row.${a("id")} for update;
  if coalesce(v_balance.${b("balance")}, 0) <> 0 or coalesce(v_balance.${b("held")}, 0) <> 0 then
    ${fail("LEDGER_ACCOUNT_NOT_EMPTY", "only an account with a zero balance and no holds can be closed", "55000")}
  end if;
  if v_row.${a("closedAt")} is null then
    update ${accounts} x set ${a("closedAt")} = now(), ${a("updatedAt")} = now()
      where x.${a("id")} = v_row.${a("id")}
      returning * into v_row;
    ${accountRecord("ledger_account.closed", "v_row", "closed ledger account")}
  end if;
  return ${accountJson("v_row", "v_balance")};
end;
$$;
${userGrant(`${fn("close_ledger_account")}(uuid)`)}

-- Posts a balanced transaction to the app's own accounts. Accounts a block
-- manages (stock, leave, receivables) only move through that block.
create or replace function ${fn("post_ledger_transaction")}(tenant ${idType}, kind text, lines jsonb, reference_type text default null, reference_id text default null, memo text default null, idempotency_key text default null, effective_at timestamptz default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row ${transactions}%rowtype;
begin
  if not ${allowed("post_ledger_transaction.tenant", post)} then
    ${forbidden("not allowed to post ledger transactions")}
  end if;
  if jsonb_typeof(post_ledger_transaction.lines) = 'array' and exists (
    select 1 from jsonb_array_elements(post_ledger_transaction.lines) l
    join ${accounts} x on x.${a("id")}::text = l.value ->> 'account'
    where x.${a("managedBy")} is not null
  ) then
    ${fail("LEDGER_ACCOUNT_MANAGED", "an account of the transaction belongs to another block", "55000")}
  end if;
  v_id := ${fn("ledger_post")}(post_ledger_transaction.tenant, post_ledger_transaction.kind, post_ledger_transaction.lines,
    post_ledger_transaction.reference_type, post_ledger_transaction.reference_id, post_ledger_transaction.memo,
    post_ledger_transaction.idempotency_key, post_ledger_transaction.effective_at, post_ledger_transaction.metadata);
  select * into v_row from ${transactions} x where x.${t("id")} = v_id;
  return ${transactionJson("v_row")};
end;
$$;
${userGrant(`${fn("post_ledger_transaction")}(${idType}, text, jsonb, text, text, text, text, timestamptz, jsonb)`)}

-- Posts the opposite of a transaction. A transaction is reversed at most
-- once, and a reversal can't be reversed.
create or replace function ${fn("reverse_ledger_transaction")}(transaction_id uuid, memo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old ${transactions}%rowtype;
  v_row ${transactions}%rowtype;
  v_id uuid;
begin
  select * into v_old from ${transactions} x where x.${t("id")} = reverse_ledger_transaction.transaction_id;
  if not found then
    ${fail("LEDGER_TRANSACTION_NOT_FOUND", "ledger transaction not found", "P0002")}
  end if;
  if not ${allowed(`v_old.${t("tenant")}`, post)} then
    ${forbidden("not allowed to post ledger transactions")}
  end if;
  if exists (
    select 1 from ${entries} y join ${accounts} x on x.${a("id")} = y.${e("account")}
    where y.${e("transaction")} = v_old.${t("id")} and x.${a("managedBy")} is not null
  ) then
    ${fail("LEDGER_ACCOUNT_MANAGED", "an account of the transaction belongs to another block", "55000")}
  end if;
  if v_old.${t("reverses")} is not null
    or exists (select 1 from ${transactions} x where x.${t("reverses")} = v_old.${t("id")}) then
    ${fail("LEDGER_ALREADY_REVERSED", "this transaction is a reversal or is already reversed", "55000")}
  end if;
  v_id := ${fn("ledger_post")}(v_old.${t("tenant")}, v_old.${t("kind")},
    (select jsonb_agg(jsonb_build_object('account', y.${e("account")}, 'amount', (-y.${e("amount")})::text) order by y.${e("createdAt")}, y.${e("id")})
      from ${entries} y where y.${e("transaction")} = v_old.${t("id")}),
    v_old.${t("referenceType")}, v_old.${t("referenceId")}, coalesce(reverse_ledger_transaction.memo, v_old.${t("memo")}),
    null, null, v_old.${t("metadata")}, v_old.${t("id")});
  select * into v_row from ${transactions} x where x.${t("id")} = v_id;
  ${ctx.record({
    type: "ledger_transaction.reversed",
    payload: transactionPayload("v_row"),
    subject: `'ledger-transactions/' || v_row.${t("id")}::text`,
    tenant: `v_row.${t("tenant")}`,
    audit: {
      category: "billing",
      targetType: "ledger_transaction",
      recordId: `v_old.${t("id")}::text`,
      summary: `'reversed a ' || v_old.${t("kind")} || ' transaction'`,
    },
  })}
  return ${transactionJson("v_row")};
end;
$$;
${userGrant(`${fn("reverse_ledger_transaction")}(uuid, text)`)}

-- Sets aside part of an account's available balance until it is captured,
-- released or expires, without checking the caller. Modules that hold
-- amounts on their own accounts call it; it isn't granted to anyone.
create or replace function ${fn("ledger_hold")}(account_id uuid, amount bigint, reference_type text default null, reference_id text default null, expires_at timestamptz default null)
returns ${holds}
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account ${accounts}%rowtype;
  v_balance ${balances}%rowtype;
  v_row ${holds}%rowtype;
begin
  select * into v_account from ${accounts} x where x.${a("id")} = ledger_hold.account_id;
  if not found or v_account.${a("closedAt")} is not null then
    ${fail("LEDGER_ACCOUNT_NOT_FOUND", "ledger account not found", "P0002")}
  end if;
  if ledger_hold.amount is null or ledger_hold.amount <= 0 then
    ${invalid("LEDGER_LINES_INVALID", "a hold needs an amount greater than zero")}
  end if;
  insert into ${balances} (${b("account")}, ${b("tenant")}) values (v_account.${a("id")}, v_account.${a("tenant")})
    on conflict (${b("account")}) do nothing;
  select * into v_balance from ${balances} x where x.${b("account")} = v_account.${a("id")} for update;
  if not v_account.${a("allowNegative")} and v_balance.${b("balance")} - v_balance.${b("held")} < ledger_hold.amount then
    ${fail("LEDGER_INSUFFICIENT", "the account doesn't have enough available", "23514")}
  end if;
  update ${balances} x set ${b("held")} = x.${b("held")} + ledger_hold.amount, ${b("updatedAt")} = now()
    where x.${b("account")} = v_account.${a("id")};
  insert into ${holds} (${h("tenant")}, ${h("account")}, ${h("amount")}, ${h("referenceType")}, ${h("referenceId")}, ${h("expiresAt")}, ${h("createdBy")})
  values (v_account.${a("tenant")}, v_account.${a("id")}, ledger_hold.amount, ledger_hold.reference_type, ledger_hold.reference_id, ledger_hold.expires_at, auth.uid())
  returning * into v_row;
  ${holdRecord("ledger_hold.placed", "v_row")}
  return v_row;
end;
$$;
revoke execute on function ${fn("ledger_hold")}(uuid, bigint, text, text, timestamptz) from public, anon, authenticated;

create or replace function ${fn("place_ledger_hold")}(account_id uuid, amount bigint, reference_type text default null, reference_id text default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account ${accounts}%rowtype;
  v_row ${holds}%rowtype;
begin
  select * into v_account from ${accounts} x where x.${a("id")} = place_ledger_hold.account_id;
  if not found or v_account.${a("closedAt")} is not null then
    ${fail("LEDGER_ACCOUNT_NOT_FOUND", "ledger account not found", "P0002")}
  end if;
  if not ${allowed(`v_account.${a("tenant")}`, post)} then
    ${forbidden("not allowed to post ledger transactions")}
  end if;
  if v_account.${a("managedBy")} is not null and not ${SERVICE_CALLER} then
    ${fail("LEDGER_ACCOUNT_MANAGED", "this account belongs to another block", "55000")}
  end if;
  v_row := ${fn("ledger_hold")}(place_ledger_hold.account_id, place_ledger_hold.amount, place_ledger_hold.reference_type, place_ledger_hold.reference_id, place_ledger_hold.expires_at);
  return ${holdJson("v_row")};
end;
$$;
${userGrant(`${fn("place_ledger_hold")}(uuid, bigint, text, text, timestamptz)`)}

-- Frees an active hold: release by a caller, expire from expire_ledger_holds.
create or replace function ${fn("ledger_unhold")}(hold_id uuid, status text)
returns ${holds}
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${holds}%rowtype;
begin
  select * into v_row from ${holds} x where x.${h("id")} = ledger_unhold.hold_id for update;
  if not found then
    ${fail("LEDGER_HOLD_NOT_FOUND", "ledger hold not found", "P0002")}
  end if;
  if v_row.${h("status")} <> 'active' then
    ${fail("LEDGER_HOLD_CLOSED", "this hold is no longer active", "55000")}
  end if;
  update ${balances} x set ${b("held")} = x.${b("held")} - v_row.${h("amount")}, ${b("updatedAt")} = now()
    where x.${b("account")} = v_row.${h("account")};
  update ${holds} x set ${h("status")} = ledger_unhold.status, ${h("updatedAt")} = now()
    where x.${h("id")} = v_row.${h("id")}
    returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function ${fn("ledger_unhold")}(uuid, text) from public, anon, authenticated;

-- Captures a hold without checking the caller: frees it and posts amount
-- (default all of it) from the held account to to_account. Modules call it;
-- it isn't granted to anyone.
create or replace function ${fn("ledger_capture")}(hold_id uuid, to_account uuid, amount bigint default null, kind text default 'ledger.capture', memo text default null)
returns ${holds}
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${holds}%rowtype;
  v_amount bigint;
begin
  select * into v_row from ${holds} x where x.${h("id")} = ledger_capture.hold_id;
  if not found then
    ${fail("LEDGER_HOLD_NOT_FOUND", "ledger hold not found", "P0002")}
  end if;
  v_amount := coalesce(ledger_capture.amount, v_row.${h("amount")});
  if v_amount <= 0 or v_amount > v_row.${h("amount")} then
    ${invalid("LEDGER_LINES_INVALID", "a capture takes more than zero and at most the held amount")}
  end if;
  v_row := ${fn("ledger_unhold")}(v_row.${h("id")}, 'captured');
  update ${holds} x set ${h("transaction")} = ${fn("ledger_post")}(v_row.${h("tenant")}, coalesce(ledger_capture.kind, 'ledger.capture'),
      jsonb_build_array(
        jsonb_build_object('account', v_row.${h("account")}, 'amount', (-v_amount)::text),
        jsonb_build_object('account', ledger_capture.to_account, 'amount', v_amount::text)),
      v_row.${h("referenceType")}, v_row.${h("referenceId")}, ledger_capture.memo)
    where x.${h("id")} = v_row.${h("id")}
    returning * into v_row;
  ${holdRecord("ledger_hold.captured", "v_row")}
  return v_row;
end;
$$;
revoke execute on function ${fn("ledger_capture")}(uuid, uuid, bigint, text, text) from public, anon, authenticated;

create or replace function ${fn("capture_ledger_hold")}(hold_id uuid, to_account uuid, amount bigint default null, kind text default 'ledger.capture', memo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${holds}%rowtype;
begin
  select * into v_row from ${holds} x where x.${h("id")} = capture_ledger_hold.hold_id;
  if not found then
    ${fail("LEDGER_HOLD_NOT_FOUND", "ledger hold not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${h("tenant")}`, post)} then
    ${forbidden("not allowed to post ledger transactions")}
  end if;
  if exists (select 1 from ${accounts} x where x.${a("id")} = capture_ledger_hold.to_account and x.${a("managedBy")} is not null) and not ${SERVICE_CALLER} then
    ${fail("LEDGER_ACCOUNT_MANAGED", "this account belongs to another block", "55000")}
  end if;
  v_row := ${fn("ledger_capture")}(v_row.${h("id")}, capture_ledger_hold.to_account, capture_ledger_hold.amount, capture_ledger_hold.kind, capture_ledger_hold.memo);
  return ${holdJson("v_row")};
end;
$$;
${userGrant(`${fn("capture_ledger_hold")}(uuid, uuid, bigint, text, text)`)}

-- Releases an active hold without checking the caller. Modules call it; it
-- isn't granted to anyone.
create or replace function ${fn("ledger_release")}(hold_id uuid)
returns ${holds}
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${holds}%rowtype;
begin
  v_row := ${fn("ledger_unhold")}(ledger_release.hold_id, 'released');
  ${holdRecord("ledger_hold.released", "v_row")}
  return v_row;
end;
$$;
revoke execute on function ${fn("ledger_release")}(uuid) from public, anon, authenticated;

create or replace function ${fn("release_ledger_hold")}(hold_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${holds}%rowtype;
begin
  select * into v_row from ${holds} x where x.${h("id")} = release_ledger_hold.hold_id;
  if not found then
    ${fail("LEDGER_HOLD_NOT_FOUND", "ledger hold not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${h("tenant")}`, post)} then
    ${forbidden("not allowed to post ledger transactions")}
  end if;
  v_row := ${fn("ledger_release")}(v_row.${h("id")});
  return ${holdJson("v_row")};
end;
$$;
${userGrant(`${fn("release_ledger_hold")}(uuid)`)}

-- Releases the active holds past expires_at; a scheduled job runs it.
-- Returns how many it expired.
create or replace function ${fn("expire_ledger_holds")}(max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row ${holds}%rowtype;
  v_count integer := 0;
begin
  for v_id in
    select x.${h("id")} from ${holds} x
    where x.${h("status")} = 'active' and x.${h("expiresAt")} <= now()
    order by x.${h("expiresAt")}
    limit least(greatest(coalesce(expire_ledger_holds.max_rows, 500), 1), 5000)
    for update skip locked
  loop
    v_row := ${fn("ledger_unhold")}(v_id, 'expired');
    ${holdRecord("ledger_hold.released", "v_row")}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("expire_ledger_holds")}(integer)`)}

-- The accounts the caller can read, with their balances: every account with
-- the read permission, else the caller's own and those a read permission of
-- another block grants. Without a tenant it lists a holder's accounts in
-- every tenant the caller can read them in.
create or replace function ${fn("list_ledger_accounts")}(tenant ${idType}, kind text default null, holder_type text default null, holder_id text default null, page_size integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.code), '[]'::jsonb)
  from (
    select ${accountJson("x", "y")} as item, x.${a("code")} as code
    from ${accounts} x
    left join ${balances} y on y.${b("account")} = x.${a("id")}
    where (list_ledger_accounts.tenant is null or x.${a("tenant")} = list_ledger_accounts.tenant)
      and (list_ledger_accounts.kind is null or x.${a("kind")} = list_ledger_accounts.kind)
      and (list_ledger_accounts.holder_type is null or x.${a("holderType")} = list_ledger_accounts.holder_type)
      and (list_ledger_accounts.holder_id is null or x.${a("holderId")} = list_ledger_accounts.holder_id)
      and ${visible("x")}
    order by x.${a("code")}
    limit ${pageSize("list_ledger_accounts.page_size", 100, 1000)}
  ) z
$$;
${userGrant(`${fn("list_ledger_accounts")}(${idType}, text, text, text, integer)`)}

-- An account's entries, newest first, with the transaction each belongs to.
-- before pages back from an entry's created_at.
create or replace function ${fn("ledger_account_entries")}(account_id uuid, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account ${accounts}%rowtype;
  v_rows jsonb;
begin
  select * into v_account from ${accounts} x where x.${a("id")} = ledger_account_entries.account_id;
  if not found or not ${visible("v_account")} then
    ${fail("LEDGER_ACCOUNT_NOT_FOUND", "ledger account not found", "P0002")}
  end if;
  select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', y.${e("id")}, 'accountId', y.${e("account")}, 'amount', y.${e("amount")}::text, 'unit', y.${e("unit")},
        'transactionId', r.${t("id")}, 'kind', r.${t("kind")}, 'referenceType', r.${t("referenceType")}, 'referenceId', r.${t("referenceId")},
        'memo', r.${t("memo")}, 'reverses', r.${t("reverses")}, 'metadata', r.${t("metadata")}, 'effectiveAt', r.${t("effectiveAt")}, 'createdAt', y.${e("createdAt")}) as item,
      y.${e("createdAt")} as created, y.${e("id")} as id
    from ${entries} y
    join ${transactions} r on r.${t("id")} = y.${e("transaction")}
    where y.${e("account")} = v_account.${a("id")}
      and (ledger_account_entries.before is null or y.${e("createdAt")} < ledger_account_entries.before)
    order by y.${e("createdAt")} desc, y.${e("id")} desc
    limit ${pageSize("ledger_account_entries.page_size", 50, 500)}
  ) z;
  return v_rows;
end;
$$;
${userGrant(`${fn("ledger_account_entries")}(uuid, timestamptz, integer)`)}

-- One transaction with its entries, for a caller who can read one of its
-- accounts.
create or replace function ${fn("get_ledger_transaction")}(transaction_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${transactions}%rowtype;
begin
  select * into v_row from ${transactions} x where x.${t("id")} = get_ledger_transaction.transaction_id;
  if not found or not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${t("tenant")}`, read)} or exists (
    select 1 from ${entries} y join ${accounts} x on x.${a("id")} = y.${e("account")}
    where y.${e("transaction")} = v_row.${t("id")} and ${visible("x")}
  )) then
    ${fail("LEDGER_TRANSACTION_NOT_FOUND", "ledger transaction not found", "P0002")}
  end if;
  return ${transactionJson("v_row")};
end;
$$;
${userGrant(`${fn("get_ledger_transaction")}(uuid)`)}`;
}
