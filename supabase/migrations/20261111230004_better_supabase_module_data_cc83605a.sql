-- better-supabase add --adopt: the rows and settings of reserved-slugs, idempotency, webhook-inbox, webhooks-in, security-events, domains, option-sets that no data migration holds yet.

set lock_timeout = '5s';

-- reserved-slugs
insert into "better_supabase"."reserved_slugs" ("slug", "reason")
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict ("slug") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reserved-slugs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- idempotency
insert into better_supabase.blocks (name, version, mode)
values ('idempotency', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- webhook-inbox
insert into better_supabase.blocks (name, version, mode)
values ('webhook-inbox', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- webhooks-in
insert into better_supabase.blocks (name, version, mode)
values ('webhooks-in', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- security-events
insert into better_supabase.blocks (name, version, mode)
values ('security-events', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- domains
insert into better_supabase.blocks (name, version, mode)
values ('domains', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- option-sets
insert into better_supabase.blocks (name, version, mode)
values ('option-sets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
