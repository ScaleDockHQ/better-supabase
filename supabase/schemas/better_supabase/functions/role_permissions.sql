-- The access contract for the SQL modules, which run with `tenant` and
-- `access` in custom mode (`apps/examples/nextjs/better-supabase.config.ts`).
-- A user can belong to several organizations (public.memberships);
-- the active one is the `tenant_id` claim that switch_organization writes.
-- Owners hold every permission, admins everything but deleting and handing
-- over the organization, members read, comment, keep their own API keys,
-- read the settings, answer inbox conversations and use the assistant.
-- Assigning conversations and managing inboxes is for admins. There are no
-- platform roles, and nobody is disabled.
-- `rolePermissions` in apps/examples/nextjs/src/features/user/user-permissions.ts
-- mirrors the lists for the UI.
create or replace function better_supabase.role_permissions(role text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case role
    when 'owner' then array['*']
    when 'admin' then array[
      'customers.read', 'customers.write', 'reports.read',
      'organization.read', 'organization.update',
      'members.read', 'members.invite', 'members.remove', 'members.update_role',
      'billing.read', 'billing.manage', 'audit.read',
      'settings.read', 'settings.update', 'settings.manage',
      'api_keys.manage', 'api_keys.own',
      'comments.read', 'comments.create', 'comments.moderate', 'activity.read',
      'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record',
      'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'workflow.edit', 'workflow.publish', 'workflow.admin',
      'inbox.read', 'inbox.reply', 'inbox.assign', 'inbox.manage',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_chat.admin',
      'ai.read', 'ai.create', 'ai.share', 'ai.admin'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'onboarding.read', 'usage.read', 'usage.record', 'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'inbox.read', 'inbox.reply',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share',
      'ai.read', 'ai.create', 'ai.share'
    ]
    else array[]::text[]
  end
$$;

revoke execute on function better_supabase.role_permissions(text) from public, anon;

grant execute on function better_supabase.role_permissions(text) to authenticated, service_role;
