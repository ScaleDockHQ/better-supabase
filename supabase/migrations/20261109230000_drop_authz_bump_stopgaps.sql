-- The sessions module renders these statement triggers now (bsb_bump_*), so the fixture's own
-- copies would bump every member twice.
drop trigger if exists bsb_permission_overrides_bump_insert on better_supabase.permission_overrides;
drop trigger if exists bsb_permission_overrides_bump_update on better_supabase.permission_overrides;
drop trigger if exists bsb_permission_overrides_bump_delete on better_supabase.permission_overrides;
drop trigger if exists bsb_role_permissions_bump_insert on better_supabase.role_permissions;
drop trigger if exists bsb_role_permissions_bump_delete on better_supabase.role_permissions;
drop trigger if exists bsb_platform_roles_bump_insert on better_supabase.platform_roles;
drop trigger if exists bsb_platform_roles_bump_delete on better_supabase.platform_roles;
drop function if exists rbac.bump_override_authz_versions();
drop function if exists rbac.bump_role_permission_members();
drop function if exists rbac.bump_platform_role_members();
