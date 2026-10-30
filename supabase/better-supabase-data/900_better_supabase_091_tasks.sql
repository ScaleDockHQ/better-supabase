-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:bb57c9034af66f66293881209e508086def69e2f6a5a8bf87d6fb5e5b9dfc32b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."notification_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."notification_events" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
update "better_supabase"."notification_subscriptions" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."guest_grants" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."attachments" set "subject_type" = 'task' where "subject_type" = 'work_item';
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."data_exports"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."data_exports" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
update "better_supabase"."enrollments" set "subject_type" = 'task' where "subject_type" = 'work_item';
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_runs"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_runs" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_start_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_start_requests" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."knowledge_documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."knowledge_documents" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."memories"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."memories" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
update "better_supabase"."taggings" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."status_history" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."status_stages" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."subject_lifecycles" set "subject_type" = 'task' where "subject_type" = 'work_item';
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."field_values"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."field_values" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
update "better_supabase"."share_links" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."subject_views" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."subject_user_state" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."recurrence_rules" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."reminders" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."subject_members" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."relations" set "source_type" = 'task' where "source_type" = 'work_item';
update "better_supabase"."relations" set "target_type" = 'task' where "target_type" = 'work_item';
update "better_supabase"."bulk_runs" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."search_documents" set "subject_type" = 'task' where "subject_type" = 'work_item';
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_events" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_attendees"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_attendees" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
update "better_supabase"."versions" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."trash_items" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."reactions" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."reaction_scores" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."approval_requests" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."approval_policies" set "subject_type" = 'task' where "subject_type" = 'work_item';
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."access_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."access_requests" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
update "better_supabase"."documents" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."form_submissions" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."signature_requests" set "subject_type" = 'task' where "subject_type" = 'work_item';
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."time_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."time_entries" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
update "better_supabase"."template_applications" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."pipelines" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."pipeline_stage_history" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."engagement_subjects" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."sla_policies" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."sla_clocks" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."moderation_items" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."rules" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."rule_defaults" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."rule_evaluations" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."rule_fields" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."score_models" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."scores" set "subject_type" = 'task' where "subject_type" = 'work_item';
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."passes"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."passes" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
update "better_supabase"."work_orders" set "subject_type" = 'task' where "subject_type" = 'work_item';
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."shipments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."shipments" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
update "better_supabase"."conversations" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."message_record_mentions" set "subject_type" = 'task' where "subject_type" = 'work_item';
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."channels"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."channels" set "subject_type" = 'task' where "subject_type" = 'work_item'; end if; end $$;
update "better_supabase"."activity_entries" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."mail_thread_subjects" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."segments" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."assignment_queues" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."assignments" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."field_changes" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."sequence_enrollments" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."lead_score_checks" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."qualification_requirements" set "target_type" = 'task' where "target_type" = 'work_item';
update "better_supabase"."acknowledgement_assignments" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."acknowledgements" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."acknowledgement_notices" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."consents" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."observations" set "subject_type" = 'task' where "subject_type" = 'work_item';
update "better_supabase"."medication_orders" set "subject_type" = 'task' where "subject_type" = 'work_item';

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
