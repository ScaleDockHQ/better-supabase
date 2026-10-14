create table rbac.role_permissions (
  role rbac.app_role not null,
  permission rbac.app_permission not null,
  primary key (role, permission)
);

alter table rbac.role_permissions enable row level security;
