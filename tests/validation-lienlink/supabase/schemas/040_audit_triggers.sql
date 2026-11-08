-- Row audit for jobs. The ignore list keeps bookkeeping columns out of the log.
create function public.jobs_audit() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  ignored text[] := array['updated_at'];
  changed jsonb := '{}';
begin
  if tg_op = 'UPDATE' then
    select coalesce(jsonb_object_agg(n.key, n.value), '{}') into changed
    from jsonb_each(to_jsonb(new)) n
    where to_jsonb(old) -> n.key is distinct from n.value
      and n.key <> all (ignored);

    if changed = '{}' then
      return new;
    end if;
  end if;

  insert into public.job_audit (job_id, organization_id, action, changed)
  values (new.id, new.organization_id, lower(tg_op), changed);

  return new;
end;
$$;

revoke all on function public.jobs_audit() from public, anon, authenticated;

create trigger jobs_audit
  after insert or update on public.jobs
  for each row execute function public.jobs_audit();
