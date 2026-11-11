-- better-supabase add --adopt: the rows and settings of prompts, ai-evals, ai-guardrails that no data migration holds yet.

set lock_timeout = '5s';

-- prompts
insert into better_supabase.blocks (name, version, mode)
values ('prompts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ai-evals
insert into better_supabase.blocks (name, version, mode)
values ('ai-evals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ai-guardrails
insert into better_supabase.blocks (name, version, mode)
values ('ai-guardrails', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
