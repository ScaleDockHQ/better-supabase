-- Role settings a schema diff skips (docs/agents/database.md). A Data API
-- client that leaves a transaction open holds its locks until this ends it
-- (doctor BS224). Supabase sets statement_timeout on both roles already; the
-- block keeps that value and sets one only where it is missing.

alter role anon set idle_in_transaction_session_timeout = '60s';
alter role authenticated set idle_in_transaction_session_timeout = '60s';

do $$
declare
  r record;
begin
  for r in
    select rolname, case rolname when 'anon' then '3s' else '8s' end as timeout
    from pg_roles
    where rolname in ('anon', 'authenticated')
      and not exists (
        select 1 from unnest(coalesce(rolconfig, '{}')) setting
        where setting like 'statement\_timeout=%'
      )
  loop
    execute format('alter role %I set statement_timeout = %L', r.rolname, r.timeout);
  end loop;
end;
$$;

notify pgrst, 'reload config';
