SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.permission_bitset (
  all_keys text[],
  held     text[]
)
  RETURNS text
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  width integer := ceil(coalesce(cardinality(all_keys), 0) / 8.0);
  bytes bytea;
  i integer;
  slot integer;
  value integer;
begin
  if width < 1 then
    return '';
  end if;
  bytes := decode(repeat('00', width), 'hex');
  if held is null then
    return translate(rtrim(encode(bytes, 'base64'), '='), '+/', '-_');
  end if;
  for i in 1 .. coalesce(cardinality(all_keys), 0) loop
    if all_keys[i] = any (held) then
      slot := (i - 1) / 8;
      value := get_byte(bytes, slot) | (1 << ((i - 1) % 8));
      bytes := set_byte(bytes, slot, value);
    end if;
  end loop;
  return translate(rtrim(encode(bytes, 'base64'), '='), '+/', '-_');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.role_permissions (
  role text
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case role
    when 'owner' then array['*']::text[]
    when 'admin' then array['organization.read', 'organization.update', 'members.*', 'audit.read', 'audit.revert', 'webhooks.*', 'notifications.*', 'billing.*', 'api_keys.*', 'settings.*', 'usage.*', 'timeline.read', 'attachments.*', 'data_lifecycle.export', 'onboarding.*', 'inbox.*', 'ai_chat.*', 'agents.*', 'ai_files.*', 'ai_keys.*', 'ai_schedules.*', 'connectors.*', 'knowledge.*', 'memory.*', 'tags.*', 'teams.*', 'subjects.*', 'custom_fields.*', 'share_links.*', 'reminders.*', 'imports.*', 'saved_views.*', 'relations.*', 'bulk_actions.*', 'search.*', 'metrics.*', 'calendar.*', 'bookings.*', 'versions.*', 'trash.*', 'reactions.*', 'approvals.*', 'access_requests.*', 'documents.*', 'drive.*', 'forms.*', 'signatures.*', 'templates.*', 'time_entries.*', 'service_accounts.*', 'pipelines.*', 'option_sets.*', 'contacts.*', 'activities.*', 'deals.*', 'tasks.*', 'quotes.*', 'invoices.*', 'sla.*', 'goals.*', 'hiring.*', 'employees.*', 'collections.*', 'messages.*', 'channels.*', 'mail_sync.*', 'legal_entities.*', 'document_templates.*', 'segments.*', 'assignment.*', 'enrichment.*', 'forecasts.*', 'field_history.*', 'domains.*', 'automations.*', 'reviews.*', 'leave.*', 'ledger.*', 'assets.*', 'scores.*', 'moderation.*', 'enrollments.*', 'guests.*', 'passes.*', 'billable_time.*', 'leases.*', 'expenses.*', 'donations.*', 'dispatch.*', 'shipments.*', 'contracts.*', 'compliance.*', 'acknowledgements.*', 'incidents.*', 'courses.*', 'sequences.*', 'posts.*', 'content.*', 'qualifications.*', 'risks.*', 'advisories.*', 'shifts.*', 'consents.*', 'waitlist.invite', 'accounting.*', 'observations.*', 'medications.*', 'care_plans.*', 'cases.*', 'inspections.*', 'meetings.*', 'maintenance.*', 'dam.*', 'lims.*', 'appraisals.*', 'warehouse.*', 'rfqs.*', 'tills.*', 'periods.*', 'deadlines.*', 'commissions.*', 'referrals.*', 'agent_checkout.*', 'clinical_decision_support.*', 'e_prescribing.*', 'manufacturing.*', 'banking.*', 'tax.*', 'funding.*', 'payroll_export.*', 'warranty.*']::text[]
    when 'member' then array['organization.read', 'members.read', 'notifications.read', 'api_keys.own', 'settings.read', 'timeline.read', 'attachments.read', 'attachments.upload', 'onboarding.read', 'inbox.read', 'inbox.reply', 'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'agents.read', 'agents.write', 'agents.publish', 'ai_files.upload', 'ai_keys.use', 'ai_schedules.write', 'connectors.read', 'connectors.use', 'knowledge.read', 'knowledge.write', 'memory.read', 'custom_fields.read', 'teams.read', 'tags.read', 'tags.apply', 'share_links.read', 'reminders.read', 'saved_views.read', 'relations.read', 'bulk_actions.run', 'search.read', 'metrics.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'versions.restore', 'trash.read', 'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read', 'approvals.request', 'access_requests.create', 'documents.read', 'documents.write', 'documents.suggest', 'drive.read', 'drive.create', 'forms.read', 'forms.submit', 'signatures.read', 'signatures.request', 'templates.read', 'templates.apply', 'time_entries.track', 'leave.request', 'pipelines.read', 'option_sets.read', 'contacts.read', 'contacts.write', 'activities.read', 'activities.write', 'deals.read', 'deals.write', 'tasks.read', 'tasks.write', 'quotes.read', 'quotes.write', 'invoices.read', 'sla.read', 'goals.read', 'employees.read', 'collections.read', 'collections.write', 'domains.read', 'automations.read', 'assets.read', 'scores.read', 'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit', 'dispatch.read', 'dispatch.work', 'shipments.read', 'contracts.read', 'contracts.write', 'compliance.read', 'compliance.collect', 'acknowledgements.acknowledge', 'incidents.read', 'incidents.write', 'courses.read', 'sequences.read', 'sequences.enroll', 'posts.read', 'posts.write', 'content.read', 'content.write', 'shifts.read', 'shifts.request', 'messages.read', 'messages.send', 'channels.create', 'mail_sync.read', 'legal_entities.read', 'document_templates.read', 'mail_sync.connect', 'mail_sync.send', 'segments.read', 'assignment.read', 'enrichment.read', 'forecasts.read', 'field_history.read', 'risks.read', 'advisories.read', 'observations.read', 'observations.record', 'care_plans.read', 'cases.read', 'cases.create', 'manufacturing.read', 'manufacturing.produce', 'banking.read', 'banking.reconcile', 'tax.read', 'funding.read', 'funding.register', 'warranty.read', 'warranty.write']::text[]
    when 'viewer' then array['organization.read']::text[]
    else '{}'::text[]
  end
$function$;
