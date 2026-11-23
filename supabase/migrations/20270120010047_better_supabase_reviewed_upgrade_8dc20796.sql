-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- tasks: version 6 to 7. delegate_task takes to_profile and reserves the task for that profile of the user (ADR 1183). delegate_profile held the delegator's label at version 6, so its values are cleared.
update "better_supabase"."work_items" set "delegate_profile" = null where "delegate_profile" is not null and not ("delegate_profile" ? 'userId');

-- facilities: version 6 to 7. delegate_task takes to_profile and reserves the task for that profile of the user (ADR 1183). delegate_profile held the delegator's label at version 6, so its values are cleared.
update "better_supabase"."maintenance_requests" set "delegate_profile" = null where "delegate_profile" is not null and not ("delegate_profile" ? 'userId');
