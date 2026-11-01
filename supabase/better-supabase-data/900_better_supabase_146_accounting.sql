-- better-supabase module: accounting
-- @bsb-block-data accounting
-- @bsb-hash sha256:3d0316c5150b15b7a730b48a3cfcdff523aed3c83484e2dcd5f88163b806f9eb
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Adds the disposal gain and loss accounts to existing charts of accounts.
insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable")
select s."tenant_id", c.code, c.name, c.type, c.subtype, false
from "better_supabase"."accounting_settings" s
cross join (values ('disposal_gain', '4910', 'Gains on asset disposals', 'income', 'other_income'), ('disposal_loss', '6910', 'Losses on asset disposals', 'expense', 'other_expense')) c (role, code, name, type, subtype)
where exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = s."tenant_id")
  and not exists (select 1 from "better_supabase"."accounting_account_roles" z where z."tenant_id" = s."tenant_id" and z."role" = c.role)
  and not exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = s."tenant_id" and y."code" = c.code);
insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
select s."tenant_id", c.role, y."id"
from "better_supabase"."accounting_settings" s
cross join (values ('disposal_gain', '4910', 'Gains on asset disposals'), ('disposal_loss', '6910', 'Losses on asset disposals')) c (role, code, name)
join "better_supabase"."accounting_accounts" y on y."tenant_id" = s."tenant_id" and y."code" = c.code and y."name" = c.name
where not exists (select 1 from "better_supabase"."accounting_account_roles" z where z."tenant_id" = s."tenant_id" and z."role" = c.role)
on conflict ("tenant_id", "role") do nothing;

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.accounting_accounts', target_type => 'accounting_account', event_prefix => 'accounting_account', deferred => true);
select better_supabase.audit('better_supabase.accounting_journals', target_type => 'accounting_journal', event_prefix => 'accounting_journal', deferred => true);
select better_supabase.audit('better_supabase.accounting_periods', target_type => 'accounting_period', event_prefix => 'accounting_period', deferred => true);
select better_supabase.audit('better_supabase.accounting_entries', target_type => 'accounting_entry', event_prefix => 'accounting_entry', deferred => true);
select better_supabase.audit('better_supabase.accounting_dimensions', target_type => 'accounting_dimension', event_prefix => 'accounting_dimension', deferred => true);
select better_supabase.audit('better_supabase.accounting_budgets', target_type => 'accounting_budget', event_prefix => 'accounting_budget', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('accounting', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
