-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- approvals: version 5 to 6. consume_approval moves a request to the new consumed status. Requests used before keep consumed_at with status approved; the upgrade sets them to consumed and adds a check that consumed_at is set exactly when the status is consumed.
alter table "better_supabase"."approval_requests" drop constraint if exists "approval_requests_status_check";
alter table "better_supabase"."approval_requests" drop constraint if exists "bsb_approval_requests_status_check";
alter table "better_supabase"."approval_requests" add constraint "bsb_approval_requests_status_check" check ("status" in ('pending', 'approved', 'rejected', 'cancelled', 'expired', 'consumed'));
update "better_supabase"."approval_requests" set "status" = 'consumed' where "consumed_at" is not null and "status" = 'approved';
set constraints all immediate;
alter table "better_supabase"."approval_requests" drop constraint if exists "bsb_approval_requests_consumed_check";
alter table "better_supabase"."approval_requests" add constraint "bsb_approval_requests_consumed_check" check (("status" = 'consumed') = ("consumed_at" is not null));
