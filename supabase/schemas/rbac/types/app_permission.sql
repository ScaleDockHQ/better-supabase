create type rbac.app_permission as enum (
  'customers.read',
  'customers.write',
  'reports.read',
  'users.manage',
  'billing.manage',
  'audit.read',
  'settings.manage'
);
