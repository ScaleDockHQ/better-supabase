create type public.note_kind as enum ('call', 'meeting', 'email');

create type rbac.app_role as enum ('admin', 'member');

create type rbac.app_permission as enum (
  'customers.read',
  'customers.write',
  'reports.read',
  'users.manage',
  'billing.manage',
  'audit.read',
  'settings.manage'
);
