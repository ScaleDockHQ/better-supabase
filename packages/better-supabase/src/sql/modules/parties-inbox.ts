import type { ModuleContext } from "../context.ts";
import type { PartyNames } from "./parties-functions.ts";

import { fail, lockTable, userGrant } from "../shared.ts";

/**
 * With the inbox installed: which person an inbox contact is, so a
 * conversation shows the person's company, deals and history. One person
 * has many contacts (an email, a WhatsApp number); a contact has one person.
 */
export function partiesInboxSql(ctx: ModuleContext, names: PartyNames): string {
  if (!ctx.installed("inbox")) return "";
  const inbox = ctx.of("inbox");
  const { t, c, fn } = names;
  const pc = (column: string): string => c("personContacts", column);
  const pe = (column: string): string => c("people", column);
  const ic = (column: string): string => inbox.col("contacts", column);
  const contacts = inbox.table("contacts");
  const guard = (
    tenant: string,
  ): string => `if not (auth.role() = 'service_role' or ${ctx.scope.can(tenant, names.write)}) then
    ${fail("PARTY_FORBIDDEN", "not allowed to change companies and people")}
  end if;`;
  const table = ctx.manages
    ? `
create table if not exists ${t("personContacts")} (
  ${pc("tenant")} ${ctx.idType} not null,
  ${pc("person")} uuid not null references ${t("people")} (${pe("id")}) on delete cascade,
  ${pc("contact")} uuid not null unique references ${contacts} (${ic("id")}) on delete cascade,
  ${pc("createdAt")} timestamptz not null default now(),
  primary key (${pc("person")}, ${pc("contact")})
);
${lockTable(t("personContacts"), { read: true })}
drop policy if exists person_inbox_contacts_read on ${t("personContacts")};
create policy person_inbox_contacts_read on ${t("personContacts")} for select to authenticated
using (${ctx.scope.check(pc("tenant"), names.read)});
`
    : "";
  return `${table}
-- Links an inbox contact to a person in the same organization; a contact
-- linked to someone else moves.
create or replace function ${fn("link_inbox_contact")}(person uuid, contact uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select p.${pe("tenant")} into v_tenant from ${t("people")} p
  join ${contacts} k on k.${ic("id")} = link_inbox_contact.contact and k.${ic("tenant")}::text = p.${pe("tenant")}::text
  where p.${pe("id")} = link_inbox_contact.person;
  if v_tenant is null then
    ${fail("PARTY_NOT_FOUND", "person or contact not found in one organization", "P0002")}
  end if;
  ${guard("v_tenant")}
  insert into ${t("personContacts")} (${pc("tenant")}, ${pc("person")}, ${pc("contact")})
  values (v_tenant, link_inbox_contact.person, link_inbox_contact.contact)
  on conflict (${pc("contact")}) do update set ${pc("person")} = excluded.${pc("person")};
  return true;
end;
$$;
${userGrant(`${fn("link_inbox_contact")}(uuid, uuid)`)}

create or replace function ${fn("unlink_inbox_contact")}(contact uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${pc("tenant")} into v_tenant from ${t("personContacts")} x where x.${pc("contact")} = unlink_inbox_contact.contact;
  if v_tenant is null then
    return false;
  end if;
  ${guard("v_tenant")}
  delete from ${t("personContacts")} x where x.${pc("contact")} = unlink_inbox_contact.contact;
  return true;
end;
$$;
${userGrant(`${fn("unlink_inbox_contact")}(uuid)`)}

-- The person an inbox contact is linked to. Without a link, the active
-- person with the contact's email is linked first; with create, a contact
-- with a name and no match becomes a new lead.
create or replace function ${fn("person_for_inbox_contact")}(contact uuid, "create" boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contact ${contacts};
  v_person uuid;
begin
  select * into v_contact from ${contacts} k where k.${ic("id")} = person_for_inbox_contact.contact;
  if v_contact.${ic("id")} is null then
    ${fail("PARTY_NOT_FOUND", "contact not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can(`v_contact.${ic("tenant")}`, names.read)}) then
    ${fail("PARTY_FORBIDDEN", "not allowed to read people")}
  end if;
  select x.${pc("person")} into v_person from ${t("personContacts")} x where x.${pc("contact")} = v_contact.${ic("id")};
  if v_person is null and v_contact.${ic("email")} is not null then
    select p.${pe("id")} into v_person from ${t("people")} p
    where p.${pe("tenant")}::text = v_contact.${ic("tenant")}::text and p.${pe("email")} = lower(v_contact.${ic("email")}) and p.${pe("archivedAt")} is null;
  end if;
  if v_person is null and person_for_inbox_contact."create" and nullif(trim(v_contact.${ic("name")}), '') is not null then
    if not (auth.role() = 'service_role' or ${ctx.scope.can(`v_contact.${ic("tenant")}`, names.write)}) then
      ${fail("PARTY_FORBIDDEN", "not allowed to change companies and people")}
    end if;
    v_person := (${fn("save_person")}(v_contact.${ic("tenant")}, null, jsonb_strip_nulls(jsonb_build_object(
      'name', v_contact.${ic("name")}, 'email', v_contact.${ic("email")}, 'phone', v_contact.${ic("phone")}))) ->> 'id')::uuid;
  end if;
  if v_person is null then
    return null;
  end if;
  insert into ${t("personContacts")} (${pc("tenant")}, ${pc("person")}, ${pc("contact")})
  select p.${pe("tenant")}, v_person, v_contact.${ic("id")} from ${t("people")} p where p.${pe("id")} = v_person
  on conflict do nothing;
  return (select to_jsonb(p) from ${t("people")} p where p.${pe("id")} = v_person);
end;
$$;
${userGrant(`${fn("person_for_inbox_contact")}(uuid, boolean)`)}
`;
}
