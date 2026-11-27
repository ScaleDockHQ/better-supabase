-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- notifications: version 11 to 12. A recipient can be snoozed until a time. Snoozed rows leave the inbox and the unread count until that time.
alter table "centrakit"."notification_recipients" add column if not exists "snoozed_until" timestamptz;
