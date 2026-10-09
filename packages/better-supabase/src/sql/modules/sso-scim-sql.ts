/** The SCIM storage functions of the sso module, for the SCIM handler. */

export interface ScimSqlNames {
  /** The tenant id type. */
  readonly id: string;
  readonly fn: (name: string) => string;
  readonly users: string;
  readonly groups: string;
  readonly members: string;
  readonly cu: (column: string) => string;
  readonly cg: (column: string) => string;
  readonly cm: (column: string) => string;
  /** Raises unless the caller is the service role. */
  readonly serviceOnly: (what: string) => string;
  /** Whether the email's domain is verified for the tenant. */
  readonly verifiedFor: (tenant: string, email: string) => string;
  /** Records a SCIM write: `ctx.record` with the tenant and the row's id. */
  readonly record: (type: string, tenant: string, id: string) => string;
}

export function scimSql(names: ScimSqlNames): string {
  const { id, fn, cu, cg, cm, serviceOnly, verifiedFor, record } = names;
  const u = names.users;
  const g = names.groups;
  const gm = names.members;
  const userJson = (alias: string): string =>
    `to_jsonb(${alias}.*) || jsonb_build_object('groups', (
      select coalesce(jsonb_agg(jsonb_build_object('value', sg.${cg("id")}, 'display', sg.${cg("displayName")}) order by sg.${cg("displayName")}), '[]'::jsonb)
      from ${gm} sm join ${g} sg on sg.${cg("id")} = sm.${cm("group")}
      where sm.${cm("member")} = ${alias}.${cu("id")}
    ))`;
  const groupJson = (alias: string): string =>
    `to_jsonb(${alias}.*) || jsonb_build_object('members', (
      select coalesce(jsonb_agg(jsonb_build_object('value', su.${cu("id")}, 'display', coalesce(su.${cu("displayName")}, su.${cu("userName")})) order by su.${cu("userName")}), '[]'::jsonb)
      from ${gm} sm join ${u} su on su.${cu("id")} = sm.${cm("member")}
      where sm.${cm("group")} = ${alias}.${cg("id")}
    ))`;
  return `-- SCIM storage for the SCIM handler (service role). Rows come back as
-- jsonb; users carry their groups and groups their members.
create or replace function ${fn("scim_list_users")}(tenant ${id})
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${serviceOnly("serves SCIM")}
  return (
    select coalesce(jsonb_agg(${userJson("x")} order by x.${cu("createdAt")}, x.${cu("id")}), '[]'::jsonb)
    from ${u} x where x.${cu("tenant")} = scim_list_users.tenant
  );
end;
$$;

create or replace function ${fn("scim_get_user")}(tenant ${id}, id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${serviceOnly("serves SCIM")}
  return (
    select ${userJson("x")} from ${u} x
    where x.${cu("tenant")} = scim_get_user.tenant and x.${cu("id")} = scim_get_user.id
  );
end;
$$;

-- Creates (id null) or replaces a SCIM user. \`version\`, when set, must
-- match (If-Match). data: { userName, externalId, displayName, givenName,
-- familyName, emails, active }.
create or replace function ${fn("scim_save_user")}(tenant ${id}, id uuid, data jsonb, version integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${u};
  v_emails jsonb := coalesce(scim_save_user.data -> 'emails', '[]'::jsonb);
  v_name text := scim_save_user.data ->> 'userName';
  v_email text;
  v_user uuid;
begin
  ${serviceOnly("serves SCIM")}
  if v_name is null or length(trim(v_name)) = 0 then
    raise exception 'userName is required' using errcode = '22023', hint = 'SCIM_INVALID';
  end if;
  if jsonb_typeof(v_emails) <> 'array' then
    raise exception 'emails must be an array' using errcode = '22023', hint = 'SCIM_INVALID';
  end if;
  v_email := lower(coalesce(
    (select e ->> 'value' from jsonb_array_elements(v_emails) e where (e ->> 'primary')::boolean limit 1),
    v_emails -> 0 ->> 'value',
    case when v_name like '%@%' then v_name end
  ));
  if scim_save_user.id is null then
    insert into ${u} (${cu("tenant")}, ${cu("externalId")}, ${cu("userName")}, ${cu("displayName")}, ${cu("givenName")}, ${cu("familyName")}, ${cu("email")}, ${cu("emails")}, ${cu("active")})
    values (scim_save_user.tenant, scim_save_user.data ->> 'externalId', v_name, scim_save_user.data ->> 'displayName',
      scim_save_user.data ->> 'givenName', scim_save_user.data ->> 'familyName', v_email, v_emails,
      coalesce((scim_save_user.data ->> 'active')::boolean, true))
    returning * into v_row;
  else
    select * into v_row from ${u} x where x.${cu("tenant")} = scim_save_user.tenant and x.${cu("id")} = scim_save_user.id for update;
    if v_row.${cu("id")} is null then
      raise exception 'No SCIM user has this id' using errcode = 'P0002', hint = 'SCIM_NOT_FOUND';
    end if;
    if scim_save_user.version is not null and scim_save_user.version <> v_row.${cu("version")} then
      raise exception 'The user changed since version %', scim_save_user.version using errcode = 'P0001', hint = 'SCIM_PRECONDITION';
    end if;
    update ${u} x set
      ${cu("externalId")} = scim_save_user.data ->> 'externalId',
      ${cu("userName")} = v_name,
      ${cu("displayName")} = scim_save_user.data ->> 'displayName',
      ${cu("givenName")} = scim_save_user.data ->> 'givenName',
      ${cu("familyName")} = scim_save_user.data ->> 'familyName',
      ${cu("email")} = v_email,
      ${cu("emails")} = v_emails,
      ${cu("active")} = coalesce((scim_save_user.data ->> 'active')::boolean, true),
      ${cu("version")} = x.${cu("version")} + 1,
      ${cu("updatedAt")} = now()
    where x.${cu("id")} = v_row.${cu("id")}
    returning * into v_row;
  end if;
  if v_row.${cu("user")} is null and v_email is not null and ${verifiedFor("scim_save_user.tenant", "v_email")} then
    select au.id into v_user from auth.users au
    where lower(au.email) = v_email and au.email_confirmed_at is not null
      and not exists (select 1 from ${u} y where y.${cu("tenant")} = scim_save_user.tenant and y.${cu("user")} = au.id)
    limit 1;
    if v_user is not null then
      update ${u} x set ${cu("user")} = v_user where x.${cu("id")} = v_row.${cu("id")} returning * into v_row;
    end if;
  end if;
  perform ${fn("scim_sync_member")}(v_row.${cu("id")});
  ${record("scim_user.saved", "scim_save_user.tenant", `v_row.${cu("id")}`)}
  return (select ${userJson("x")} from ${u} x where x.${cu("id")} = v_row.${cu("id")});
end;
$$;

-- Deprovisions (removes the membership) and deletes a SCIM user.
create or replace function ${fn("scim_delete_user")}(tenant ${id}, id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  ${serviceOnly("serves SCIM")}
  update ${u} x set ${cu("active")} = false
  where x.${cu("tenant")} = scim_delete_user.tenant and x.${cu("id")} = scim_delete_user.id
  returning x.${cu("id")} into v_id;
  if v_id is null then
    return false;
  end if;
  perform ${fn("scim_sync_member")}(v_id);
  delete from ${u} x where x.${cu("id")} = v_id;
  ${record("scim_user.deleted", "scim_delete_user.tenant", "v_id")}
  return true;
end;
$$;

create or replace function ${fn("scim_list_groups")}(tenant ${id})
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${serviceOnly("serves SCIM")}
  return (
    select coalesce(jsonb_agg(${groupJson("x")} order by x.${cg("createdAt")}, x.${cg("id")}), '[]'::jsonb)
    from ${g} x where x.${cg("tenant")} = scim_list_groups.tenant
  );
end;
$$;

create or replace function ${fn("scim_get_group")}(tenant ${id}, id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${serviceOnly("serves SCIM")}
  return (
    select ${groupJson("x")} from ${g} x
    where x.${cg("tenant")} = scim_get_group.tenant and x.${cg("id")} = scim_get_group.id
  );
end;
$$;

-- Creates (id null) or replaces a group and its members, then syncs the
-- roles of everyone who joined or left. data: { displayName, externalId,
-- members: [scim user id] }.
create or replace function ${fn("scim_save_group")}(tenant ${id}, id uuid, data jsonb, version integer default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${g};
  v_name text := scim_save_group.data ->> 'displayName';
  v_members uuid[];
  v_before uuid[] := '{}';
  v_member uuid;
begin
  ${serviceOnly("serves SCIM")}
  if v_name is null or length(trim(v_name)) = 0 then
    raise exception 'displayName is required' using errcode = '22023', hint = 'SCIM_INVALID';
  end if;
  begin
    select coalesce(array_agg(distinct (w.value)::uuid), '{}') into v_members
    from jsonb_array_elements_text(coalesce(scim_save_group.data -> 'members', '[]'::jsonb)) w;
  exception when invalid_text_representation then
    raise exception 'members must be SCIM user ids' using errcode = '22023', hint = 'SCIM_INVALID';
  end;
  if exists (
    select 1 from unnest(v_members) w(member)
    where not exists (select 1 from ${u} x where x.${cu("tenant")} = scim_save_group.tenant and x.${cu("id")} = w.member)
  ) then
    raise exception 'members must be SCIM users of the organization' using errcode = '22023', hint = 'SCIM_INVALID';
  end if;
  if scim_save_group.id is null then
    insert into ${g} (${cg("tenant")}, ${cg("displayName")}, ${cg("externalId")}, ${cg("role")})
    values (scim_save_group.tenant, v_name, scim_save_group.data ->> 'externalId', ${fn("scim_group_role")}(v_name))
    returning * into v_row;
  else
    select * into v_row from ${g} x where x.${cg("tenant")} = scim_save_group.tenant and x.${cg("id")} = scim_save_group.id for update;
    if v_row.${cg("id")} is null then
      raise exception 'No SCIM group has this id' using errcode = 'P0002', hint = 'SCIM_NOT_FOUND';
    end if;
    if scim_save_group.version is not null and scim_save_group.version <> v_row.${cg("version")} then
      raise exception 'The group changed since version %', scim_save_group.version using errcode = 'P0001', hint = 'SCIM_PRECONDITION';
    end if;
    select coalesce(array_agg(sm.${cm("member")}), '{}') into v_before from ${gm} sm where sm.${cm("group")} = v_row.${cg("id")};
    update ${g} x set
      ${cg("displayName")} = v_name,
      ${cg("externalId")} = scim_save_group.data ->> 'externalId',
      ${cg("role")} = ${fn("scim_group_role")}(v_name),
      ${cg("version")} = x.${cg("version")} + 1,
      ${cg("updatedAt")} = now()
    where x.${cg("id")} = v_row.${cg("id")}
    returning * into v_row;
    delete from ${gm} sm where sm.${cm("group")} = v_row.${cg("id")} and not (sm.${cm("member")} = any (v_members));
  end if;
  insert into ${gm} (${cm("group")}, ${cm("member")})
  select v_row.${cg("id")}, w.member from unnest(v_members) w(member)
  on conflict do nothing;
  for v_member in select distinct w.member from unnest(v_before || v_members) w(member) loop
    perform ${fn("scim_sync_member")}(v_member);
  end loop;
  ${record("scim_group.saved", "scim_save_group.tenant", `v_row.${cg("id")}`)}
  return (select ${groupJson("x")} from ${g} x where x.${cg("id")} = v_row.${cg("id")});
end;
$$;

create or replace function ${fn("scim_delete_group")}(tenant ${id}, id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_members uuid[];
  v_member uuid;
begin
  ${serviceOnly("serves SCIM")}
  select coalesce(array_agg(sm.${cm("member")}), '{}') into v_members
  from ${gm} sm join ${g} x on x.${cg("id")} = sm.${cm("group")}
  where x.${cg("tenant")} = scim_delete_group.tenant and x.${cg("id")} = scim_delete_group.id;
  delete from ${g} x where x.${cg("tenant")} = scim_delete_group.tenant and x.${cg("id")} = scim_delete_group.id;
  if not found then
    return false;
  end if;
  foreach v_member in array v_members loop
    perform ${fn("scim_sync_member")}(v_member);
  end loop;
  ${record("scim_group.deleted", "scim_delete_group.tenant", "scim_delete_group.id")}
  return true;
end;
$$;`;
}
