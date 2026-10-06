-- better-supabase module: invitations
-- Owners and admins invite by email; the invitee accepts with a one-time token and becomes a member.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists better_supabase.invitations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  email text not null,
  role text not null default 'member',
  token_hash text not null unique,
  invited_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_by uuid references auth.users (id) on delete set null
);
create unique index if not exists invitations_open_idx
  on better_supabase.invitations (org_id, lower(email)) where accepted_at is null;
create index if not exists invitations_invited_by_idx
  on better_supabase.invitations (invited_by);
create index if not exists invitations_accepted_by_idx
  on better_supabase.invitations (accepted_by);

alter table better_supabase.invitations drop constraint if exists invitations_role_check;
alter table better_supabase.invitations
  add constraint invitations_role_check check (role in ('owner', 'admin', 'member', 'viewer'));

alter table better_supabase.invitations enable row level security;
revoke all on better_supabase.invitations from anon, authenticated;
grant select on better_supabase.invitations to authenticated;
grant all on better_supabase.invitations to service_role;

drop policy if exists bs_invitations_read on better_supabase.invitations;
create policy bs_invitations_read on better_supabase.invitations
  for select to authenticated
  using (org_id in (select better_supabase.member_org_ids('{owner,admin}')));

-- Returns the token to send; only its hash is stored.
create or replace function better_supabase.create_invitation(
  org uuid,
  invitee_email text,
  invitee_role text default 'member',
  valid_for interval default '7 days'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  privileged boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role';
begin
  if not privileged and not better_supabase.has_org_role(org, '{owner,admin}') then
    raise exception 'Only owners and admins can invite' using errcode = '42501';
  end if;
  -- Admins invite admins and below; only an owner hands out ownership.
  if invitee_role = 'owner' and not privileged and not better_supabase.has_org_role(org, '{owner}') then
    raise exception 'Only owners can invite an owner' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  delete from better_supabase.invitations i
  where i.org_id = org and lower(i.email) = lower(invitee_email) and i.accepted_at is null;
  insert into better_supabase.invitations (org_id, email, role, token_hash, invited_by, expires_at)
  values (
    org,
    invitee_email,
    invitee_role,
    encode(extensions.digest(token, 'sha256'), 'hex'),
    auth.uid(),
    now() + valid_for
  );
  return token;
end;
$$;

create or replace function better_supabase.accept_invitation(token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  invite better_supabase.invitations;
begin
  if auth.uid() is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501';
  end if;
  select * into invite
  from better_supabase.invitations i
  where i.token_hash = encode(extensions.digest(token, 'sha256'), 'hex')
  for update;
  if invite.id is null or invite.accepted_at is not null or invite.expires_at < now() then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if lower(invite.email) <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = auth.uid() and u.email_confirmed_at is not null and lower(u.email) = lower(invite.email)
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  insert into better_supabase.memberships (org_id, user_id, role)
  values (invite.org_id, auth.uid(), invite.role)
  on conflict (org_id, user_id) do update set role = excluded.role;
  update better_supabase.invitations
  set accepted_at = now(), accepted_by = auth.uid()
  where id = invite.id;
  return invite.org_id;
end;
$$;

revoke execute on function better_supabase.create_invitation(uuid, text, text, interval) from public, anon;
revoke execute on function better_supabase.accept_invitation(text) from public, anon;
grant execute on function better_supabase.create_invitation(uuid, text, text, interval) to authenticated, service_role;
grant execute on function better_supabase.accept_invitation(text) to authenticated;
