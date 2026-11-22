set lock_timeout = '5s';

create index concurrently if not exists tax_rates_tenant_code_idx on better_supabase.tax_rates using btree (tax_code_id, tenant_id);
