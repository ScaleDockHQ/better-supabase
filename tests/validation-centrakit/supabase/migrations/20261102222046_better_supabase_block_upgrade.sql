-- better-supabase upgrade: steps that run before the schema diff.

-- notifications: version 9 to 10. Preferences gain a cadence (immediate, daily, weekly or off); a daily or weekly delivery is held, run_notification_digests (the digest_run job) folds held deliveries into notification_digests, and claim_notification_digests and complete_notification_digest are the sender's pair. set_notification_cadence is new. A notification may name a consent_purpose that the consents block checks.
alter table "centrakit"."notification_preferences" add column if not exists "cadence" text not null default 'immediate' check ("cadence" in ('immediate', 'daily', 'weekly', 'off'));
do $digest$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = '"centrakit"."notification_deliveries"'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%''skipped''%' and pg_get_constraintdef(oid) not like '%''held''%'
  loop
    execute format('alter table "centrakit"."notification_deliveries" drop constraint %I', c.conname);
  end loop;
  alter table "centrakit"."notification_deliveries" add constraint notification_deliveries_status_held_check
    check ("status" in ('pending', 'sent', 'failed', 'skipped', 'held', 'digested'));
exception when duplicate_object then null;
end
$digest$;
