-- better-supabase upgrade: steps that run before the schema diff.

-- profiles: version 2 to 3. The email mirror and sign-up sync store the email lowercased; existing emails are lowercased unless that would duplicate another profile's. Managed profiles get a locale column the user may update, which notification deliveries render in.
update "better_supabase"."profiles" p set "email" = lower(p."email")
where p."email" <> lower(p."email")
  and not exists (select 1 from "better_supabase"."profiles" o where o."email" = lower(p."email"));

-- notifications: version 8 to 9. Events get actions (an array of { key, label, operation, payload } that send_notification validates) and recipients a resolution that resolve_notifications stores; claim_notification_deliveries returns the recipient's profile locale.
drop function if exists "better_supabase"."resolve_notifications"(text, text, text, uuid);
