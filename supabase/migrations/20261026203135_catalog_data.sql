-- The fixture's permission catalog: every key the example and the installed
-- blocks check, and the keys each tenant role holds. The catalog matches keys
-- exactly (no `*`), so owners hold every key; admins everything but deleting
-- and handing over the organization and a few owner-only areas; members read,
-- comment and do the everyday writes. The roles themselves are in the
-- catalog_access migration. Overrides per organization are rows admins write
-- from the roles page, so none are seeded.
insert into better_supabase.permissions (key) values
  ('access_requests.create'), ('access_requests.manage'), ('access_requests.read'), ('activity.read'),
  ('ai.admin'), ('ai.create'), ('ai.moderate'), ('ai.read'),
  ('ai.share'), ('ai_chat.admin'), ('ai_chat.create'), ('ai_chat.moderate'),
  ('ai_chat.read'), ('ai_chat.share'), ('announcements.manage'), ('api_keys.manage'),
  ('api_keys.own'), ('approvals.manage'), ('approvals.read'), ('approvals.request'),
  ('assets.assign'), ('assets.manage'), ('assets.read'), ('assignment.assign'),
  ('assignment.manage'), ('assignment.read'), ('attachments.manage'), ('attachments.read'),
  ('attachments.upload'), ('audit.read'), ('audit.revert'), ('billable_time.invoice'),
  ('billable_time.manage'), ('billable_time.read'), ('billing.manage'), ('billing.read'),
  ('bookings.create'), ('bookings.manage'), ('bookings.read'), ('bulk.run'),
  ('calendar.manage'), ('calendar.read'), ('calendar.write'), ('catalog.manage'),
  ('catalog.read'), ('channels.create'), ('channels.manage'), ('comments.create'),
  ('comments.moderate'), ('comments.read'), ('content.publish'), ('content.read'),
  ('content.write'), ('contracts.manage'), ('contracts.read'), ('contracts.write'),
  ('controls.acknowledge'), ('controls.collect'), ('controls.manage'), ('controls.read'),
  ('courses.enroll'), ('courses.manage'), ('courses.read'), ('custom_fields.manage'),
  ('custom_fields.read'), ('custom_fields.sensitive.read'), ('customers.read'), ('customers.write'),
  ('deals.manage'), ('deals.read'), ('deals.write'), ('dispatch.manage'),
  ('dispatch.read'), ('dispatch.work'), ('documents.manage'), ('documents.read'),
  ('documents.suggest'), ('documents.write'), ('donations.manage'), ('donations.read'),
  ('drive.create'), ('drive.manage'), ('drive.read'), ('employees.read'),
  ('employees.view_sensitive'), ('employees.write'), ('engagements.manage'), ('engagements.read'),
  ('engagements.write'), ('enrichment.read'), ('enrichment.run'), ('enrollments.enroll'),
  ('enrollments.manage'), ('enrollments.read'), ('expenses.approve'), ('expenses.manage'),
  ('expenses.read'), ('expenses.submit'), ('flags.manage'), ('forecasts.read'),
  ('forecasts.snapshot'), ('forms.manage'), ('forms.read'), ('forms.review'),
  ('forms.submit'), ('guests.manage'), ('guests.read'), ('hiring.manage'),
  ('hiring.read'), ('hiring.write'), ('history.read'), ('imports.manage'),
  ('inbox.assign'), ('inbox.manage'), ('inbox.read'), ('inbox.reply'),
  ('incidents.manage'), ('incidents.read'), ('incidents.write'), ('inventory.manage'),
  ('inventory.purchase'), ('inventory.read'), ('inventory.reserve'), ('invoices.manage'),
  ('invoices.read'), ('invoices.write'), ('leases.maintain'), ('leases.manage'),
  ('leases.read'), ('ledger.manage'), ('ledger.post'), ('ledger.read'),
  ('mail.connect'), ('mail.manage'), ('mail.read'), ('mail.send'),
  ('members.invite'), ('members.read'), ('members.remove'), ('members.update_role'),
  ('messages.moderate'), ('messages.read'), ('messages.send'), ('metrics.manage'),
  ('metrics.read'), ('moderation.ban'), ('moderation.manage'), ('moderation.read'),
  ('moderation.report'), ('notifications.read'), ('notifications.send'), ('number_sequences.assign'),
  ('onboarding.complete'), ('onboarding.read'), ('orders.manage'), ('orders.prepare'),
  ('orders.read'), ('organization.delete'), ('organization.export'), ('organization.read'),
  ('organization.transfer_ownership'), ('organization.update'), ('parties.manage'), ('parties.read'),
  ('parties.write'), ('passes.check_in'), ('passes.manage'), ('passes.read'),
  ('pipelines.manage'), ('pipelines.read'), ('posts.manage'), ('posts.moderate'),
  ('posts.read'), ('posts.write'), ('promotions.manage'), ('promotions.read'),
  ('quotes.manage'), ('quotes.read'), ('quotes.write'), ('reactions.create'),
  ('reactions.manage'), ('reactions.read'), ('relations.manage'), ('relations.read'),
  ('reminders.manage'), ('reminders.read'), ('reports.read'), ('roles.manage'),
  ('rules.admin'), ('rules.edit'), ('rules.publish'), ('rules.read'),
  ('scores.compute'), ('scores.manage'), ('scores.read'), ('search.read'),
  ('segments.edit'), ('segments.read'), ('sequences.enroll'), ('sequences.manage'),
  ('sequences.read'), ('service_principals.manage'), ('service_principals.read'), ('settings.manage'),
  ('settings.read'), ('settings.update'), ('share_links.create'), ('share_links.read'),
  ('shipments.manage'), ('shipments.read'), ('signatures.manage'), ('signatures.read'),
  ('signatures.request'), ('sla.manage'), ('sla.read'), ('sso.manage'),
  ('tags.apply'), ('tags.manage'), ('tags.read'), ('targets.manage'),
  ('targets.read'), ('teams.manage'), ('teams.read'), ('templates.apply'),
  ('templates.manage'), ('templates.read'), ('time_tracking.approve'), ('time_tracking.manage'),
  ('time_tracking.read'), ('time_tracking.track'), ('trash.create'), ('trash.manage'),
  ('trash.read'), ('trash.restore'), ('usage.read'), ('usage.record'),
  ('versions.create'), ('versions.manage'), ('versions.read'), ('versions.restore'),
  ('views.read'), ('views.share'), ('waitlist.manage'), ('webhooks.manage'),
  ('webhooks.read'), ('work_items.manage'), ('work_items.read'), ('work_items.write'),
  ('workflow.admin'), ('workflow.edit'), ('workflow.publish'), ('workflow.read'),
  ('workflow.run')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
cross join better_supabase.permissions p
where r.scope = 'tenant' and r.key = 'owner'
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join lateral unnest(case r.key
  when 'admin' then array[
    'customers.read', 'customers.write', 'reports.read', 'organization.read', 'organization.update', 'members.read',
    'members.invite', 'members.remove', 'members.update_role', 'billing.read', 'billing.manage', 'audit.read',
    'settings.read', 'settings.update', 'settings.manage', 'api_keys.manage', 'api_keys.own', 'comments.read',
    'comments.create', 'comments.moderate', 'activity.read', 'tags.read', 'tags.apply', 'tags.manage',
    'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record', 'search.read', 'metrics.read',
    'notifications.send', 'notifications.read', 'workflow.read', 'workflow.run', 'workflow.edit', 'workflow.publish',
    'workflow.admin', 'inbox.read', 'inbox.reply', 'inbox.assign', 'inbox.manage', 'ai_chat.read',
    'ai_chat.create', 'ai_chat.share', 'ai_chat.admin', 'ai.read', 'ai.create', 'ai.share',
    'ai.admin', 'attachments.read', 'attachments.upload', 'attachments.manage', 'sso.manage', 'waitlist.manage',
    'teams.read', 'teams.manage', 'catalog.read', 'catalog.manage', 'content.read', 'content.write',
    'content.publish', 'inventory.read', 'inventory.manage', 'inventory.reserve', 'inventory.purchase', 'orders.read',
    'orders.manage', 'orders.prepare', 'promotions.read', 'promotions.manage', 'custom_fields.read', 'custom_fields.manage',
    'custom_fields.sensitive.read', 'share_links.read', 'share_links.create', 'reminders.read', 'reminders.manage', 'imports.manage',
    'views.read', 'views.share', 'relations.read', 'relations.manage', 'bulk.run', 'calendar.read',
    'calendar.write', 'calendar.manage', 'bookings.read', 'bookings.create', 'bookings.manage', 'versions.read',
    'versions.create', 'versions.restore', 'versions.manage', 'trash.read', 'trash.create', 'trash.restore',
    'trash.manage', 'reactions.read', 'reactions.create', 'reactions.manage', 'approvals.read', 'approvals.request',
    'approvals.manage', 'access_requests.read', 'access_requests.create', 'access_requests.manage', 'documents.read', 'documents.write',
    'documents.suggest', 'documents.manage', 'drive.read', 'drive.create', 'drive.manage', 'forms.read',
    'forms.submit', 'forms.review', 'forms.manage', 'templates.read', 'templates.apply', 'templates.manage',
    'time_tracking.read', 'time_tracking.track', 'time_tracking.approve', 'time_tracking.manage', 'service_principals.read', 'service_principals.manage',
    'pipelines.read', 'pipelines.manage', 'parties.read', 'parties.write', 'parties.manage', 'engagements.read',
    'engagements.write', 'engagements.manage', 'deals.read', 'deals.write', 'deals.manage', 'work_items.read',
    'work_items.write', 'work_items.manage', 'quotes.read', 'quotes.write', 'quotes.manage', 'invoices.read',
    'invoices.write', 'invoices.manage', 'sla.read', 'sla.manage', 'targets.read', 'targets.manage',
    'hiring.read', 'hiring.write', 'hiring.manage', 'employees.read', 'employees.write', 'employees.view_sensitive',
    'webhooks.read', 'webhooks.manage', 'organization.export', 'rules.read', 'rules.edit', 'rules.publish',
    'rules.admin', 'assets.read', 'assets.manage', 'assets.assign', 'scores.read', 'scores.manage',
    'scores.compute', 'moderation.read', 'moderation.report', 'moderation.manage', 'moderation.ban', 'enrollments.read',
    'enrollments.enroll', 'enrollments.manage', 'dispatch.read', 'dispatch.manage', 'dispatch.work', 'shipments.read',
    'shipments.manage', 'signatures.read', 'signatures.request', 'signatures.manage', 'contracts.read', 'contracts.write',
    'contracts.manage', 'controls.read', 'controls.manage', 'controls.collect', 'controls.acknowledge', 'incidents.read',
    'incidents.write', 'incidents.manage', 'courses.read', 'courses.enroll', 'courses.manage', 'messages.read',
    'messages.send', 'messages.moderate', 'channels.create', 'channels.manage', 'mail.read', 'mail.connect',
    'mail.send', 'mail.manage', 'segments.read', 'segments.edit', 'assignment.read', 'assignment.manage',
    'assignment.assign', 'enrichment.read', 'enrichment.run', 'forecasts.read', 'forecasts.snapshot', 'history.read',
    'sequences.read', 'sequences.enroll', 'sequences.manage', 'posts.read', 'posts.write', 'posts.moderate',
    'posts.manage', 'roles.manage'
  ]
  when 'member' then array[
    'customers.read', 'organization.read', 'members.read', 'billing.read', 'settings.read', 'api_keys.own',
    'comments.read', 'comments.create', 'activity.read', 'tags.read', 'tags.apply', 'onboarding.read',
    'usage.read', 'usage.record', 'search.read', 'metrics.read', 'notifications.send', 'notifications.read',
    'workflow.read', 'workflow.run', 'inbox.read', 'inbox.reply', 'ai_chat.read', 'ai_chat.create',
    'ai_chat.share', 'ai.read', 'ai.create', 'ai.share', 'attachments.read', 'attachments.upload',
    'teams.read', 'catalog.read', 'inventory.read', 'content.read', 'content.write', 'orders.read',
    'orders.prepare', 'promotions.read', 'custom_fields.read', 'share_links.read', 'share_links.create', 'reminders.read',
    'reminders.manage', 'views.read', 'views.share', 'relations.read', 'relations.manage', 'calendar.read',
    'calendar.write', 'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'trash.read',
    'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read', 'approvals.request',
    'access_requests.read', 'access_requests.create', 'documents.read', 'documents.write', 'documents.suggest', 'drive.read',
    'drive.create', 'forms.read', 'forms.submit', 'templates.read', 'templates.apply', 'time_tracking.read',
    'time_tracking.track', 'pipelines.read', 'parties.read', 'parties.write', 'engagements.read', 'engagements.write',
    'deals.read', 'deals.write', 'work_items.read', 'work_items.write', 'quotes.read', 'quotes.write',
    'invoices.read', 'sla.read', 'targets.read', 'hiring.read', 'employees.read', 'rules.read',
    'assets.read', 'scores.read', 'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit',
    'dispatch.read', 'dispatch.work', 'shipments.read', 'signatures.read', 'contracts.read', 'contracts.write',
    'controls.read', 'controls.collect', 'controls.acknowledge', 'incidents.read', 'incidents.write', 'courses.read',
    'messages.read', 'messages.send', 'channels.create', 'mail.read', 'mail.connect', 'mail.send',
    'segments.read', 'assignment.read', 'enrichment.read', 'forecasts.read', 'history.read', 'sequences.read',
    'sequences.enroll', 'posts.read', 'posts.write'
  ]
end) as k(key) on true
join better_supabase.permissions p on p.key = k.key
where r.scope = 'tenant'
on conflict do nothing;
