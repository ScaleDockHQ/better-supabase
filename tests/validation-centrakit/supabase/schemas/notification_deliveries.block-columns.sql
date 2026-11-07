-- Columns the blocks add to centrakit.notification_deliveries, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."notification_deliveries" add column if not exists "provider_status" text check ("provider_status" in ('delayed', 'delivered', 'opened', 'clicked', 'bounced', 'complained'));
alter table "centrakit"."notification_deliveries" add column if not exists "provider_status_at" timestamptz;
alter table "centrakit"."notification_deliveries" add column if not exists "template_key" text;
