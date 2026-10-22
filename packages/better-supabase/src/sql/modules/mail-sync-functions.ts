import type { ModuleContext } from "../context.ts";
import type { MailNames } from "./mail-sync.ts";

import { sqlString } from "../../core/template.ts";
import {
  fail,
  pageSize,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { tenantRefGuard } from "./credentials.ts";

/** At most this many messages go into one `ingest_mail` call. */
const BATCH = 500;

const internal = (signature: string): string =>
  `revoke execute on function ${signature} from public, anon, authenticated;`;

/**
 * Links a thread to the people whose address is on one of its messages, the
 * companies they work at and, with `matchDomains`, companies by domain.
 */
function matchSql(ctx: ModuleContext, n: MailNames): string {
  const { fn, t, a, h, m, l } = n;
  const parties = ctx.of("parties");
  const person = parties.naming.rename("person");
  const company = parties.naming.rename("company");
  const pe = (column: string): string => parties.col("people", column);
  const co = (column: string): string => parties.col("companies", column);
  const cp = (column: string): string => parties.col("links", column);
  const people = parties.table("people");
  const companies = parties.table("companies");
  const companyPeople = parties.table("links");

  const insert = (
    select: string,
  ): string => `insert into ${t("links")} (${l("tenant")}, ${l("thread")}, ${l("subjectType")}, ${l("subjectId")})
  ${select}
  on conflict do nothing;`;

  const domains = n.matchDomains
    ? `
  ${insert(`select v_tenant, v_thread, ${sqlString(company)}, c.${co("id")}::text
  from ${companies} c
  where c.${co("tenant")} = v_tenant and c.${co("archivedAt")} is null
    and c.${co("domain")} is not null
    and lower(c.${co("domain")}) = any (select split_part(x, '@', 2) from unnest(v_addresses) x)`)}`
    : "";

  return `
-- Links a thread to the parties its addresses name; manual links stay.
create or replace function ${fn("match_mail_thread")}(thread uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_thread uuid := match_mail_thread.thread;
  v_tenant ${ctx.idType};
  v_own text;
  v_addresses text[];
begin
  select x.${h("tenant")}, k.${a("address")} into v_tenant, v_own
  from ${t("threads")} x join ${t("accounts")} k on k.${a("id")} = x.${h("account")}
  where x.${h("id")} = v_thread;
  select coalesce(array_agg(distinct v.address), '{}') into v_addresses
  from ${t("messages")} y
  cross join lateral unnest(array[y.${m("fromAddress")}] || y.${m("to")} || y.${m("cc")}) as v(address)
  where y.${m("thread")} = v_thread and v.address is not null and v.address <> v_own;
  ${insert(`select v_tenant, v_thread, ${sqlString(person)}, p.${pe("id")}::text
  from ${people} p
  where p.${pe("tenant")} = v_tenant and p.${pe("archivedAt")} is null
    and lower(p.${pe("email")}) = any (v_addresses)`)}
  ${insert(`select v_tenant, v_thread, ${sqlString(company)}, cp.${cp("company")}::text
  from ${companyPeople} cp
  join ${people} p on p.${pe("id")} = cp.${cp("person")}
  where p.${pe("tenant")} = v_tenant and p.${pe("archivedAt")} is null
    and lower(p.${pe("email")}) = any (v_addresses)`)}${domains}
end;
$$;
${internal(`${fn("match_mail_thread")}(uuid)`)}
`;
}

/**
 * Logs a thread of a mailbox that shares with records as one engagement on its
 * records, updated in place as messages arrive.
 */
function engagementSql(ctx: ModuleContext, n: MailNames): string {
  const { fn, t, a, h, l } = n;
  const log = ctx.of("engagements").fn("log_engagement");

  return `
-- Logs or updates the thread's engagement; private mailboxes log none.
create or replace function ${fn("log_mail_thread")}(thread uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_subjects jsonb;
  v_result jsonb;
  v_claims text;
begin
  select x.${h("id")} as id, x.${h("tenant")} as tenant, x.${h("subject")} as subject, x.${h("snippet")} as snippet,
    x.${h("lastMessageAt")} as at, k.${a("user")} as owner, k.${a("share")} as share
  into v_row
  from ${t("threads")} x join ${t("accounts")} k on k.${a("id")} = x.${h("account")}
  where x.${h("id")} = log_mail_thread.thread;
  if v_row.id is null or v_row.share <> 'records' then
    return;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('type', s.${l("subjectType")}, 'id', s.${l("subjectId")}) order by s.${l("createdAt")}, s.${l("subjectType")}, s.${l("subjectId")}), '[]'::jsonb)
  into v_subjects
  from ${t("links")} s where s.${l("thread")} = v_row.id;
  if jsonb_array_length(v_subjects) = 0 then
    return;
  end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  v_result := ${log}(v_row.tenant, jsonb_build_object(
    'type', ${sqlString(n.engagementType)},
    'title', coalesce(nullif(trim(v_row.subject), ''), '(no subject)'),
    'body', v_row.snippet,
    'ownerId', v_row.owner,
    'doneAt', v_row.at,
    'externalRef', 'mail:' || v_row.id::text
  ), v_subjects);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  update ${t("threads")} x set ${h("engagement")} = (v_result ->> 'id')::uuid
  where x.${h("id")} = v_row.id;
end;
$$;
${internal(`${fn("log_mail_thread")}(uuid)`)}
`;
}

/** Stores one message on its thread, deduplicated by provider and RFC id. */
function storeSql(n: MailNames): string {
  const { fn, t, a, h, m } = n;

  const field = (key: string): string =>
    `nullif(trim(store_mail_message.message ->> ${sqlString(key)}), '')`;

  const addresses = (key: string): string =>
    `coalesce((select array_agg(lower(trim(coalesce(e.value ->> 'address', e.value #>> '{}')))) from jsonb_array_elements(case when jsonb_typeof(store_mail_message.message -> ${sqlString(key)}) = 'array' then store_mail_message.message -> ${sqlString(key)} else '[]'::jsonb end) e where coalesce(e.value ->> 'address', e.value #>> '{}') like '%@%'), '{}')`;

  return `
-- Stores a message on its account: message is { externalId, threadId,
-- messageId, direction, from: { address, name }, to, cc, subject, snippet,
-- text, html, sentAt }. Returns { id, threadId, created, direction }.
create or replace function ${fn("store_mail_message")}(account uuid, message jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account record;
  v_external text := ${field("externalId")};
  v_thread_ref text := coalesce(${field("threadId")}, ${field("externalId")});
  v_rfc text := ${field("messageId")};
  v_from text := lower(coalesce(nullif(trim(store_mail_message.message -> 'from' ->> 'address'), ''), case when jsonb_typeof(store_mail_message.message -> 'from') = 'string' then nullif(trim(store_mail_message.message ->> 'from'), '') end));
  v_direction text := ${field("direction")};
  v_sent timestamptz;
  v_thread uuid;
  v_id uuid;
begin
  select k.${a("id")} as id, k.${a("tenant")} as tenant, k.${a("address")} as address into v_account
  from ${t("accounts")} k where k.${a("id")} = store_mail_message.account;
  if jsonb_typeof(store_mail_message.message) <> 'object' or v_external is null or ${field("sentAt")} is null then
    ${fail("MAIL_MESSAGE_INVALID", "a message needs an externalId and a sentAt", "22023")}
  end if;
  v_sent := (${field("sentAt")})::timestamptz;
  v_direction := coalesce(v_direction, case when v_from = v_account.address then 'outbound' else 'inbound' end);
  if v_direction not in ('inbound', 'outbound') then
    ${fail("MAIL_MESSAGE_INVALID", "direction is inbound or outbound", "22023")}
  end if;
  insert into ${t("threads")} (${h("tenant")}, ${h("account")}, ${h("externalId")})
  values (v_account.tenant, v_account.id, v_thread_ref)
  on conflict (${h("account")}, ${h("externalId")}) do update set ${h("updatedAt")} = now()
  returning ${h("id")} into v_thread;
  select y.${m("id")} into v_id from ${t("messages")} y
  where y.${m("account")} = v_account.id
    and (y.${m("externalId")} = v_external or (v_rfc is not null and y.${m("rfcId")} = v_rfc))
  order by y.${m("externalId")} = v_external desc
  limit 1;
  if v_id is not null then
    update ${t("messages")} y set ${m("externalId")} = v_external, ${m("rfcId")} = coalesce(v_rfc, y.${m("rfcId")})
    where y.${m("id")} = v_id
      and not exists (select 1 from ${t("messages")} z where z.${m("account")} = v_account.id and z.${m("externalId")} = v_external and z.${m("id")} <> v_id);
    return jsonb_build_object('id', v_id, 'threadId', (select y.${m("thread")} from ${t("messages")} y where y.${m("id")} = v_id), 'created', false, 'direction', v_direction);
  end if;
  insert into ${t("messages")} (${m("tenant")}, ${m("account")}, ${m("thread")}, ${m("externalId")}, ${m("rfcId")}, ${m("direction")},
    ${m("fromAddress")}, ${m("fromName")}, ${m("to")}, ${m("cc")}, ${m("subject")}, ${m("snippet")}, ${m("bodyText")}, ${m("bodyHtml")}, ${m("sentAt")})
  values (v_account.tenant, v_account.id, v_thread, v_external, v_rfc, v_direction,
    v_from, nullif(trim(store_mail_message.message -> 'from' ->> 'name'), ''), ${addresses("to")}, ${addresses("cc")},
    ${field("subject")}, left(${field("snippet")}, 500), store_mail_message.message ->> 'text', store_mail_message.message ->> 'html', v_sent)
  returning ${m("id")} into v_id;
  update ${t("threads")} x set
    ${h("subject")} = coalesce(x.${h("subject")}, ${field("subject")}),
    ${h("snippet")} = case when x.${h("lastMessageAt")} is null or v_sent >= x.${h("lastMessageAt")} then left(${field("snippet")}, 500) else x.${h("snippet")} end,
    ${h("lastMessageAt")} = greatest(x.${h("lastMessageAt")}, v_sent),
    ${h("messageCount")} = x.${h("messageCount")} + 1,
    ${h("updatedAt")} = now()
  where x.${h("id")} = v_thread;
  return jsonb_build_object('id', v_id, 'threadId', v_thread, 'created', true, 'direction', v_direction);
end;
$$;
${internal(`${fn("store_mail_message")}(uuid, jsonb)`)}
`;
}

function accountSql(ctx: ModuleContext, n: MailNames): string {
  const { fn, t, a } = n;

  const record = (event: string, row: string): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', ${row}.${a("tenant")}, 'accountId', ${row}.${a("id")}, 'userId', ${row}.${a("user")}, 'provider', ${row}.${a("provider")}, 'address', ${row}.${a("address")})`,
      subject: `'mail-accounts/' || ${row}.${a("id")}::text`,
      tenant: `${row}.${a("tenant")}::text`,
      audit: {
        category: "integration",
        targetType: "mail_account",
        recordId: `${row}.${a("id")}::text`,
        targetLabel: `${row}.${a("address")}`,
      },
    });

  return `
-- Connects the caller's mailbox: credential_ref names the OAuth grant the
-- app stored for them. share is records (members who can read a linked
-- record see its threads) or private. Connecting again updates the grant.
create or replace function ${fn("connect_mail_account")}(tenant ${ctx.idType}, provider text, address text, credential_ref jsonb, share text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t("accounts")};
  v_address text := lower(trim(connect_mail_account.address));
begin
  if auth.uid() is null or not ${ctx.scope.can("connect_mail_account.tenant", n.connect)} then
    ${fail("MAIL_FORBIDDEN", "not allowed to connect a mailbox")}
  end if;
  if connect_mail_account.provider is null or connect_mail_account.provider !~ '^[a-z][a-z0-9-]{0,39}$' then
    ${fail("MAIL_PROVIDER_INVALID", "provider is a lowercase name", "22023")}
  end if;
  if v_address is null or v_address !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    ${fail("MAIL_ADDRESS_INVALID", "address is an email address", "22023")}
  end if;
  if coalesce(connect_mail_account.share, 'records') not in ('records', 'private') then
    ${fail("MAIL_SHARE_INVALID", "share is records or private", "22023")}
  end if;
  if jsonb_typeof(connect_mail_account.credential_ref) is distinct from 'object' then
    ${fail("MAIL_CREDENTIAL_INVALID", "credential_ref is a credential reference", "22023")}
  end if;
  ${tenantRefGuard("connect_mail_account.credential_ref", "connect_mail_account.tenant")}
  insert into ${t("accounts")} as x (${a("tenant")}, ${a("user")}, ${a("provider")}, ${a("address")}, ${a("credentialRef")}, ${a("share")})
  values (connect_mail_account.tenant, auth.uid(), connect_mail_account.provider, v_address, connect_mail_account.credential_ref, coalesce(connect_mail_account.share, 'records'))
  on conflict (${a("tenant")}, ${a("user")}, ${a("address")}) do update set
    ${a("provider")} = excluded.${a("provider")},
    ${a("credentialRef")} = excluded.${a("credentialRef")},
    ${a("share")} = excluded.${a("share")},
    ${a("status")} = 'active',
    ${a("cursor")} = case when x.${a("provider")} = excluded.${a("provider")} then x.${a("cursor")} end,
    ${a("lastError")} = null,
    ${a("updatedAt")} = now()
  returning * into v_row;
  ${record("mail_account.connected", "v_row")}
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${fn("connect_mail_account")}(${ctx.idType}, text, text, jsonb, text)`)}

-- Changes who sees a mailbox's threads (share) and pauses or resumes its
-- sync; null leaves a setting as it is. Only the mailbox's member may.
create or replace function ${fn("update_mail_account")}(account uuid, share text, paused boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("accounts")};
begin
  if update_mail_account.share is not null and update_mail_account.share not in ('records', 'private') then
    ${fail("MAIL_SHARE_INVALID", "share is records or private", "22023")}
  end if;
  update ${t("accounts")} x set
    ${a("share")} = coalesce(update_mail_account.share, x.${a("share")}),
    ${a("status")} = case
      when update_mail_account.paused then 'paused'
      when update_mail_account.paused = false and x.${a("status")} = 'paused' then 'active'
      else x.${a("status")} end,
    ${a("updatedAt")} = now()
  where x.${a("id")} = update_mail_account.account and x.${a("user")} = auth.uid() and x.${a("status")} <> 'disconnected'
  returning * into v_row;
  if v_row.${a("id")} is null then
    ${fail("MAIL_ACCOUNT_NOT_FOUND", "no such mailbox of yours", "P0002")}
  end if;
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${fn("update_mail_account")}(uuid, text, boolean)`)}

-- Stops syncing a mailbox. Its member or a member with mail.manage may.
-- purge deletes the mailbox with its threads and messages.
create or replace function ${fn("disconnect_mail_account")}(account uuid, purge boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("accounts")};
begin
  select * into v_row from ${t("accounts")} x
  where x.${a("id")} = disconnect_mail_account.account
    and (x.${a("user")} = auth.uid() or ${ctx.scope.can(`x.${a("tenant")}`, n.manage)});
  if v_row.${a("id")} is null then
    return false;
  end if;
  if coalesce(disconnect_mail_account.purge, false) then
    delete from ${t("accounts")} x where x.${a("id")} = v_row.${a("id")};
  else
    update ${t("accounts")} x set ${a("status")} = 'disconnected', ${a("cursor")} = null, ${a("updatedAt")} = now()
    where x.${a("id")} = v_row.${a("id")};
  end if;
  ${record("mail_account.disconnected", "v_row")}
  return true;
end;
$$;
${userGrant(`${fn("disconnect_mail_account")}(uuid, boolean)`)}

-- The caller's mailboxes in a tenant; with mail.manage, every member's.
create or replace function ${fn("mail_accounts_of")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.${a("createdAt")}, x.${a("id")}), '[]'::jsonb)
  from ${t("accounts")} x
  where x.${a("tenant")} = mail_accounts_of.tenant
$$;
${userGrant(`${fn("mail_accounts_of")}(${ctx.idType})`)}

-- One mailbox the caller can see, or null.
create or replace function ${fn("get_mail_account")}(account uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) from ${t("accounts")} x where x.${a("id")} = get_mail_account.account
$$;
${userGrant(`${fn("get_mail_account")}(uuid)`)}

-- For the sync job: active mailboxes not synced within stale_after, the
-- longest waiting first, with their grant and cursor.
create or replace function ${fn("due_mail_accounts")}(max_count integer, stale_after interval)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER}) then
    ${fail("MAIL_FORBIDDEN", "only the service role syncs mailboxes")}
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(p) order by p.${a("lastSyncedAt")} nulls first, p.${a("id")}), '[]'::jsonb)
    from (
      select * from ${t("accounts")} x
      where x.${a("status")} = 'active'
        and (x.${a("lastSyncedAt")} is null or x.${a("lastSyncedAt")} < now() - coalesce(due_mail_accounts.stale_after, interval '5 minutes'))
      order by x.${a("lastSyncedAt")} nulls first, x.${a("id")}
      limit ${pageSize("due_mail_accounts.max_count", 25, 500)}
    ) p
  );
end;
$$;
${serviceGrant(`${fn("due_mail_accounts")}(integer, interval)`)}

-- For the sync job: marks a mailbox active, paused or failed with an error
-- (a failed one waits for its member to connect it again).
create or replace function ${fn("set_mail_account_status")}(account uuid, status text, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER}) then
    ${fail("MAIL_FORBIDDEN", "only the service role syncs mailboxes")}
  end if;
  if set_mail_account_status.status not in ('active', 'paused', 'error') then
    ${fail("MAIL_STATUS_INVALID", "status is active, paused or error", "22023")}
  end if;
  update ${t("accounts")} x set
    ${a("status")} = set_mail_account_status.status,
    ${a("lastError")} = left(set_mail_account_status.error, 1000),
    ${a("lastSyncedAt")} = now(),
    ${a("updatedAt")} = now()
  where x.${a("id")} = set_mail_account_status.account and x.${a("status")} <> 'disconnected';
  return found;
end;
$$;
${serviceGrant(`${fn("set_mail_account_status")}(uuid, text, text)`)}
`;
}

function messageSql(ctx: ModuleContext, n: MailNames): string {
  const { fn, t, a, h, l } = n;

  const subjects = (thread: string): string =>
    `coalesce((select jsonb_agg(jsonb_build_object('type', s.${l("subjectType")}, 'id', s.${l("subjectId")}) order by s.${l("createdAt")}, s.${l("subjectType")}, s.${l("subjectId")}) from ${t("links")} s where s.${l("thread")} = ${thread}), '[]'::jsonb)`;

  const match = ctx.installed("parties")
    ? `perform ${fn("match_mail_thread")}(v_thread);`
    : "";

  const log = ctx.installed("engagements")
    ? `perform ${fn("log_mail_thread")}(v_thread);`
    : "";

  const record = (event: string, stored: string, account: string): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', ${account}.tenant, 'accountId', ${account}.id, 'userId', ${account}.owner, 'threadId', ${stored} ->> 'threadId', 'messageId', ${stored} ->> 'id', 'direction', ${stored} ->> 'direction', 'fromAddress', ${stored} ->> 'fromAddress', 'subjects', ${subjects(`(${stored} ->> 'threadId')::uuid`)})`,
      subject: `'mail-messages/' || (${stored} ->> 'id')`,
      tenant: `${account}.tenant::text`,
      key: `'mail_message:' || (${stored} ->> 'id')`,
      audit: false,
    });

  const announce = (
    stored: string,
    account: string,
  ): string => `if ${stored} ->> 'direction' = 'outbound' then
      ${record("mail_message.sent", stored, account)}
    else
      ${record("mail_message.received", stored, account)}
    end if;`;

  return `
-- For the sync job: stores up to ${String(BATCH)} provider messages on a mailbox,
-- links their threads to records and logs them, then saves the cursor the
-- next sync starts from. Returns { stored, threads }.
create or replace function ${fn("ingest_mail")}(account uuid, messages jsonb, next_cursor text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
  v_item jsonb;
  v_stored jsonb;
  v_new jsonb := '[]'::jsonb;
  v_threads uuid[] := '{}';
  v_thread uuid;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("MAIL_FORBIDDEN", "only the service role syncs mailboxes")}
  end if;
  select k.${a("id")} as id, k.${a("tenant")} as tenant, k.${a("user")} as owner into v_account
  from ${t("accounts")} k where k.${a("id")} = ingest_mail.account and k.${a("status")} <> 'disconnected';
  if v_account.id is null then
    ${fail("MAIL_ACCOUNT_NOT_FOUND", "no such connected mailbox", "P0002")}
  end if;
  if jsonb_typeof(coalesce(ingest_mail.messages, '[]')) <> 'array' then
    ${fail("MAIL_MESSAGE_INVALID", "messages is a list", "22023")}
  end if;
  if jsonb_array_length(coalesce(ingest_mail.messages, '[]')) > ${String(BATCH)} then
    ${fail("MAIL_BATCH_TOO_LARGE", `at most ${String(BATCH)} messages per call`, "22023")}
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(ingest_mail.messages, '[]')) loop
    v_stored := ${fn("store_mail_message")}(v_account.id, v_item);
    if not ((v_stored ->> 'threadId')::uuid = any (v_threads)) then
      v_threads := v_threads || (v_stored ->> 'threadId')::uuid;
    end if;
    if (v_stored ->> 'created')::boolean then
      v_new := v_new || jsonb_build_array(v_stored || jsonb_build_object('fromAddress', lower(coalesce(v_item -> 'from' ->> 'address', v_item ->> 'from'))));
    end if;
  end loop;
  foreach v_thread in array v_threads loop
    ${match || "null;"}
    ${log || "null;"}
  end loop;
  for v_stored in select value from jsonb_array_elements(v_new) loop
    ${announce("v_stored", "v_account")}
  end loop;
  update ${t("accounts")} x set
    ${a("cursor")} = coalesce(ingest_mail.next_cursor, x.${a("cursor")}),
    ${a("lastSyncedAt")} = now(),
    ${a("status")} = case when x.${a("status")} = 'error' then 'active' else x.${a("status")} end,
    ${a("lastError")} = null,
    ${a("updatedAt")} = now()
  where x.${a("id")} = v_account.id;
  return jsonb_build_object('stored', jsonb_array_length(v_new), 'threads', coalesce(array_length(v_threads, 1), 0));
end;
$$;
${serviceGrant(`${fn("ingest_mail")}(uuid, jsonb, text)`)}

-- Records a message the caller sent from their mailbox through the provider
-- (the block's send does both), so it shows on the thread before the next
-- sync. Returns the stored message.
create or replace function ${fn("record_sent_mail")}(account uuid, message jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
  v_stored jsonb;
  v_thread uuid;
begin
  select k.${a("id")} as id, k.${a("tenant")} as tenant, k.${a("user")} as owner into v_account
  from ${t("accounts")} k
  where k.${a("id")} = record_sent_mail.account and k.${a("user")} = auth.uid() and k.${a("status")} <> 'disconnected';
  if v_account.id is null then
    ${fail("MAIL_ACCOUNT_NOT_FOUND", "no such mailbox of yours", "P0002")}
  end if;
  if not ${ctx.scope.can("v_account.tenant", n.send)} then
    ${fail("MAIL_FORBIDDEN", "not allowed to send mail")}
  end if;
  v_stored := ${fn("store_mail_message")}(v_account.id, coalesce(record_sent_mail.message, '{}'::jsonb) || '{"direction": "outbound"}'::jsonb);
  v_thread := (v_stored ->> 'threadId')::uuid;
  ${match}
  ${log}
  if (v_stored ->> 'created')::boolean then
    v_stored := v_stored || jsonb_build_object('fromAddress', (select k.${a("address")} from ${t("accounts")} k where k.${a("id")} = v_account.id));
    ${record("mail_message.sent", "v_stored", "v_account")}
  end if;
  return (select to_jsonb(y) from ${t("messages")} y where y.${n.m("id")} = (v_stored ->> 'id')::uuid);
end;
$$;
${userGrant(`${fn("record_sent_mail")}(uuid, jsonb)`)}

-- Links a thread of the caller's mailbox to records ([{ type, id }]) by
-- hand, for senders no person matches, and logs it on them.
create or replace function ${fn("link_mail_thread")}(thread uuid, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_thread uuid := link_mail_thread.thread;
  v_tenant ${ctx.idType};
  v_item jsonb;
begin
  select x.${h("tenant")} into v_tenant
  from ${t("threads")} x join ${t("accounts")} k on k.${a("id")} = x.${h("account")}
  where x.${h("id")} = v_thread and k.${a("user")} = auth.uid();
  if v_tenant is null then
    ${fail("MAIL_THREAD_NOT_FOUND", "no such thread in your mailbox", "P0002")}
  end if;
  if jsonb_typeof(coalesce(link_mail_thread.subjects, '[]')) <> 'array' then
    ${fail("MAIL_SUBJECTS_INVALID", "subjects must be a list of { type, id }", "22023")}
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(link_mail_thread.subjects, '[]')) loop
    if not ${subjectInTenant(ctx, "(v_item ->> 'type')", "(v_item ->> 'id')", "v_tenant")} then
      ${fail("MAIL_SUBJECT_FORBIDDEN", "a subject is unknown or not readable in this organization", "42501")}
    end if;
    insert into ${t("links")} (${l("tenant")}, ${l("thread")}, ${l("subjectType")}, ${l("subjectId")}, ${l("source")})
    values (v_tenant, v_thread, v_item ->> 'type', v_item ->> 'id', 'manual')
    on conflict (${l("thread")}, ${l("subjectType")}, ${l("subjectId")}) do update set ${l("source")} = 'manual';
  end loop;
  ${log}
  return (select to_jsonb(x) || jsonb_build_object('subjects', ${subjects(`x.${h("id")}`)}) from ${t("threads")} x where x.${h("id")} = v_thread);
end;
$$;
${userGrant(`${fn("link_mail_thread")}(uuid, jsonb)`)}

-- Removes a record from a thread of the caller's mailbox.
create or replace function ${fn("unlink_mail_thread")}(thread uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from ${t("links")} s
  using ${t("threads")} x, ${t("accounts")} k
  where s.${l("thread")} = unlink_mail_thread.thread
    and s.${l("subjectType")} = unlink_mail_thread.subject_type and s.${l("subjectId")} = unlink_mail_thread.subject_id
    and x.${h("id")} = s.${l("thread")} and k.${a("id")} = x.${h("account")} and k.${a("user")} = auth.uid();
  return found;
end;
$$;
${userGrant(`${fn("unlink_mail_thread")}(uuid, text, text)`)}
`;
}

function readSql(ctx: ModuleContext, n: MailNames): string {
  const { fn, t, a, h, m, l } = n;

  const row = (alias: string): string =>
    `to_jsonb(${alias}) || jsonb_build_object('address', (select k.${a("address")} from ${t("accounts")} k where k.${a("id")} = ${alias}.${h("account")}), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s.${l("subjectType")}, 'id', s.${l("subjectId")}) order by s.${l("createdAt")}, s.${l("subjectType")}, s.${l("subjectId")}) from ${t("links")} s where s.${l("thread")} = ${alias}.${h("id")}), '[]'::jsonb))`;

  return `
-- A record's threads the caller can see, the latest message first. before
-- continues after the last thread of the previous page.
create or replace function ${fn("mail_threads_of")}(subject_type text, subject_id text, before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select ${row("x")} as value, x.${h("lastMessageAt")} as at, x.${h("id")} as id
    from ${t("threads")} x
    join ${t("links")} s on s.${l("thread")} = x.${h("id")}
    where s.${l("subjectType")} = mail_threads_of.subject_type and s.${l("subjectId")} = mail_threads_of.subject_id
      and (mail_threads_of.before is null or x.${h("lastMessageAt")} < mail_threads_of.before)
    order by x.${h("lastMessageAt")} desc, x.${h("id")} desc
    limit ${pageSize("mail_threads_of.page_size", 25, 100)}
  ) p
$$;
${userGrant(`${fn("mail_threads_of")}(text, text, timestamptz, integer)`)}

-- The threads the caller can see in a tenant, or in one mailbox, the
-- latest message first.
create or replace function ${fn("list_mail_threads")}(tenant ${ctx.idType}, account uuid, before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select ${row("x")} as value, x.${h("lastMessageAt")} as at, x.${h("id")} as id
    from ${t("threads")} x
    where x.${h("tenant")} = list_mail_threads.tenant
      and (list_mail_threads.account is null or x.${h("account")} = list_mail_threads.account)
      and (list_mail_threads.before is null or x.${h("lastMessageAt")} < list_mail_threads.before)
    order by x.${h("lastMessageAt")} desc, x.${h("id")} desc
    limit ${pageSize("list_mail_threads.page_size", 25, 100)}
  ) p
$$;
${userGrant(`${fn("list_mail_threads")}(${ctx.idType}, uuid, timestamptz, integer)`)}

-- A thread with its messages, oldest first; null when the caller can't see it.
create or replace function ${fn("get_mail_thread")}(thread uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${row("x")} || jsonb_build_object('messages', coalesce((
    select jsonb_agg(to_jsonb(y) order by y.${m("sentAt")}, y.${m("id")})
    from ${t("messages")} y where y.${m("thread")} = x.${h("id")}
  ), '[]'::jsonb))
  from ${t("threads")} x
  where x.${h("id")} = get_mail_thread.thread
$$;
${userGrant(`${fn("get_mail_thread")}(uuid)`)}
`;
}

/** The mail-sync module's functions, after its tables. */
export function mailSyncFunctions(ctx: ModuleContext, n: MailNames): string {
  return [
    storeSql(n),
    ctx.installed("parties") ? matchSql(ctx, n) : "",
    ctx.installed("engagements") ? engagementSql(ctx, n) : "",
    accountSql(ctx, n),
    messageSql(ctx, n),
    readSql(ctx, n),
  ].join("");
}
