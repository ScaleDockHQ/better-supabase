-- The access token hook's 2048 byte budget for the permission claim (EX-1108).
-- The owner and admin catalog sets fold to `resource.*` and fit; the member
-- set does not, so its token carries `permissions_truncated`. A catalog that
-- grows past the budget fails the first two assertions, which is the moment to
-- fold keys further or raise the budget on purpose.
begin;
select plan(3);

-- The hook's own measure: jsonb prints a space after each comma and colon that
-- the token's JSON does not have.
create function pg_temp.token_bytes(role_key text)
returns integer
language sql
as $$
  select octet_length(
    replace(replace(
      jsonb_build_object(
        '00000000-0000-4000-8000-000000000001',
        to_jsonb(rbac.compact_permission_keys(array(
          select p.key
          from better_supabase.role_permissions rp
          join better_supabase.roles r on r.id = rp.role_id
          join better_supabase.permissions p on p.id = rp.permission_id
          where r.key = role_key
        )))
      )::text,
      '", "', '","'), '": [', '":[')
  )
$$;

select cmp_ok(pg_temp.token_bytes('owner'), '<=', 2048, 'an owner''s claim fits the budget');
select cmp_ok(pg_temp.token_bytes('admin'), '<=', 2048, 'an admin''s claim fits the budget');
select cmp_ok(pg_temp.token_bytes('member'), '>', 2048, 'a member''s claim stays truncated and reads my_permissions()');

select * from finish();
rollback;
