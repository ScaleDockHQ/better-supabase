-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- tax: version 1 to 2. Adds a unique index on tax codes by id and tenant and a composite foreign key from tax rates, so a rate cannot point at another tenant's code. Run `select` over tax_rates and tax_codes first: a rate whose code has another tenant blocks the key.
create unique index if not exists "tax_codes_id_tenant_key" on "better_supabase"."tax_codes" ("id", "tenant_id");
do $upgrade$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tax_rates_tenant_code_fkey' and conrelid = 'better_supabase.tax_rates'::regclass
  ) then
    alter table "better_supabase"."tax_rates" add constraint "tax_rates_tenant_code_fkey" foreign key ("tax_code_id", "tenant_id") references "better_supabase"."tax_codes" ("id", "tenant_id") on delete cascade not valid;
  end if;
end
$upgrade$;
