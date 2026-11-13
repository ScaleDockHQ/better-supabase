-- better-supabase add --adopt: the rows and settings of webhooks, incoming-webhooks that no data migration holds yet.

set lock_timeout = '5s';

-- webhooks
delete from better_supabase.blocks
  where name = 'webhooks-out'
    and exists (select 1 from better_supabase.blocks where name = 'webhooks');

update better_supabase.blocks set name = 'webhooks'
  where name = 'webhooks-out'
    and not exists (select 1 from better_supabase.blocks where name = 'webhooks');

insert into better_supabase.blocks (name, version, mode)
values ('webhooks', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- incoming-webhooks
delete from better_supabase.blocks
  where name = 'webhooks-in'
    and exists (select 1 from better_supabase.blocks where name = 'incoming-webhooks');

update better_supabase.blocks set name = 'incoming-webhooks'
  where name = 'webhooks-in'
    and not exists (select 1 from better_supabase.blocks where name = 'incoming-webhooks');

insert into better_supabase.blocks (name, version, mode)
values ('incoming-webhooks', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
