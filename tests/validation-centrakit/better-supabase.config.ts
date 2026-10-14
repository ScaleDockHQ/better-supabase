import { defineConfig } from "better-supabase/config";

// The module config CentraKit adopts better-supabase with: every module runs on
// its existing tables (`adopt`), its permission catalog and its names. Only
// support sessions and the realtime registry are new tables. CentraKit keeps its tables in `public`;
// the fixture puts them in `centrakit`.
export default defineConfig({
  sql: {
    modules: {
      access: {
        model: "catalog",
        tables: {
          roles: "centrakit.roles",
          permissions: "centrakit.permissions",
          rolePermissions: "centrakit.role_permissions",
          overrides: "centrakit.organization_permission_overrides",
          platformAssignments: "centrakit.user_roles",
        },
        columns: {
          roles: { scope: "scope" },
          overrides: { tenant: "organization_id" },
        },
        options: {
          tenantRoleScope: "organization",
          platformRoleScope: "system",
        },
        disabled: {
          tenant: "centrakit.organizations.disabled_at",
          user: "centrakit.profiles.disabled_at",
          userKey: "user_id",
        },
        activeTenant: {
          profileColumn: "centrakit.profiles.active_organization_id",
          key: "user_id",
        },
        mode: "adopt",
      },
      tenant: {
        mode: "adopt",
        tables: { memberships: "centrakit.organization_users" },
        columns: {
          memberships: { tenant: "organization_id", role: "role_id" },
        },
      },
      organizations: {
        mode: "adopt",
        tables: { organizations: "centrakit.organizations" },
        columns: { organizations: { createdBy: null, deletedAt: null } },
        permissions: {
          update: "organization.settings.manage",
          delete: "organization.delete",
          removeMember: "organization.members.remove",
          updateRole: "organization.members.manage",
          transferOwnership: "organization.ownership.transfer",
        },
        hooks: {
          schema: "centrakit",
          functions: { after_organization_create: "seed_organization" },
        },
        options: {
          attributes: ["website", "logo_path", "default_currency"],
          reservedSlugs: ["app", "admin"],
        },
      },
      invitations: {
        mode: "adopt",
        tables: {
          invitations: "centrakit.organization_invitations",
          platformInvitations: "centrakit.organization_invitations",
        },
        columns: {
          invitations: {
            tenant: "organization_id",
            role: "role_id",
            tokenHash: "token",
            acceptedBy: null,
            revokedAt: null,
          },
        },
        permissions: {
          invite: "organization.members.invite",
          revoke: "organization.members.invite",
          view: "organization.members.invite",
        },
        options: { tokenStorage: "plain" },
      },
      profiles: {
        mode: "adopt",
        tables: { profiles: "centrakit.profiles" },
        columns: {
          profiles: {
            key: "user_id",
            fullName: null,
            avatar: "avatar_path",
            activeTenant: "active_organization_id",
            onboarding: null,
          },
        },
        hooks: {
          schema: "centrakit",
          functions: { after_profile_sync: "create_contact_profile" },
        },
        options: {
          syncTrigger: false,
          usernameMaxLength: 30,
          metadata: { first_name: "first_name", last_name: "last_name" },
        },
      },
      "support-sessions": {
        permissions: {
          start: "system.users.manage",
          view: "system.users.manage",
        },
        options: { auditCategory: "security" },
      },
      audit: {
        mode: "adopt",
        tables: {
          log: "centrakit.audit_logs",
          restricted: "centrakit.audit_log_restricted_details",
        },
        columns: {
          log: {
            table: null,
            record: "target_id",
            op: null,
            old: null,
            new: null,
            changed: null,
            actorRole: null,
            tenant: "organization_id",
            occurredAt: "occurred_at",
            impersonatedBy: null,
            impersonationReason: null,
            supportSession: null,
            metadata: "safe_metadata",
          },
          restricted: {
            entry: "event_id",
            old: null,
            new: null,
            metadata: "restricted_metadata",
          },
        },
        permissions: { view: "audit.view", viewAll: "system.users.manage" },
        options: {
          eventSource: "saas",
          eventCategory: "data",
          readPolicy: true,
          // CentraKit's category check names the shared categories its own way.
          values: {
            category: {
              membership: "users",
              access: "permissions",
              configuration: "settings",
              integration: "integrations",
              ai: "system",
            },
          },
        },
      },
      outbox: {
        mode: "adopt",
        tables: { events: "centrakit.workflow_events" },
        columns: {
          events: {
            position: "position",
            type: "kind",
            tenant: "organization_id",
            key: "idempotency_key",
            subject: null,
            actor: null,
            xid: null,
          },
        },
        idType: "uuid",
        options: {
          defaultSource: "domain",
          blockSource: "domain",
        },
      },
      notifications: {
        mode: "adopt",
        schema: "better_supabase",
        tables: {
          events: "centrakit.notification_events",
          recipients: "centrakit.notification_recipients",
          deliveries: "centrakit.notification_deliveries",
          subscriptions: "centrakit.notification_subscriptions",
          preferences: "centrakit.notification_preferences",
        },
        columns: {
          events: { key: null, actor: "actor_user_id", data: "metadata" },
          recipients: { user: "recipient_user_id" },
          deliveries: { attempts: null, nextAttemptAt: null },
          subscriptions: { updatedAt: null },
          preferences: { updatedAt: null },
        },
        idType: "uuid",
        options: {
          topic: "organization:{tenantId}:notifications:{userId}",
          channels: ["in_app", "email"],
        },
      },
      "webhooks-out": {
        mode: "adopt",
        tables: {
          endpoints: "centrakit.webhook_destinations",
          secrets: "centrakit.webhook_destination_secrets",
          deliveries: "centrakit.webhook_deliveries",
        },
        columns: {
          endpoints: {
            eventTypes: "event_kinds",
            failingSince: null,
            disabledAt: null,
            disabledReason: null,
          },
          secrets: {
            endpoint: "destination_id",
            vaultId: null,
            expiresAt: null,
          },
          deliveries: {
            endpoint: "destination_id",
            type: "event_kind",
            run: "workflow_run_id",
          },
        },
        permissions: {
          manage: "organization.webhooks.manage",
          view: "organization.webhooks.view",
        },
        options: {
          secretStorage: "column",
          eventIdType: "uuid",
          runIdType: "uuid",
          statuses: {
            delivering: "processing",
            succeeded: "completed",
            retrying: "failed",
            dead: "dead_lettered",
          },
        },
      },
      credentials: {
        mode: "adopt",
        tables: { secrets: "centrakit.integration_credentials" },
        columns: {
          secrets: {
            name: "key",
            tenant: "organization_id",
            scope: null,
            vaultId: "vault_secret_id",
            secret: null,
          },
        },
      },
      "webhooks-in": {
        mode: "adopt",
        tables: { endpoints: "centrakit.inbound_webhooks" },
        columns: {
          endpoints: {
            tenant: "organization_id",
            tokenHash: "token_digest",
            verify: "verification",
            secret: null,
            secretId: "vault_secret_id",
            previousSecret: null,
            previousSecretId: null,
            previousSecretExpiresAt: null,
            maxBodyBytes: null,
            receiveCount: null,
            lastReceivedAt: null,
            lastStatus: null,
            metadata: "settings",
            subjectType: null,
            subjectId: null,
          },
        },
        permissions: {
          create: "organization.webhooks.manage",
          update: "organization.webhooks.manage",
          delete: "organization.webhooks.manage",
          view: "organization.webhooks.view",
        },
      },
      "webhook-inbox": {
        mode: "adopt",
        tables: { messages: "centrakit.inbound_webhook_events" },
        columns: {
          messages: {
            messageId: "external_id",
            eventType: "event_kind",
            tenant: "organization_id",
            headers: null,
            maxAttempts: null,
            checkpoint: null,
          },
        },
      },
      "number-sequences": {
        mode: "adopt",
        tables: { sequences: "centrakit.organization_number_sequences" },
      },
      teams: {
        mode: "adopt",
        tables: {
          teams: "centrakit.teams",
          members: "centrakit.team_members",
        },
      },
      tags: {
        mode: "adopt",
        tables: { tags: "centrakit.organization_tags", taggings: null },
        // CentraKit orders tags by an integer position, not rank keys.
        columns: { tags: { rank: null } },
        options: {
          subjects: {
            task: {
              table: "centrakit.tasks",
              kinds: ["task"],
              links: {
                table: "centrakit.task_tags",
                subject: "task_id",
                tag: "tag_id",
              },
            },
          },
        },
      },
      "state-machine": {
        mode: "adopt",
        tables: { history: "centrakit.status_history" },
      },
      "custom-fields": {
        mode: "adopt",
        tables: {
          definitions: "centrakit.field_definitions",
          options: "centrakit.field_options",
          values: "centrakit.field_values",
        },
        columns: { definitions: { rank: null }, options: { rank: null } },
      },
      "share-links": {
        mode: "adopt",
        tables: {
          links: "centrakit.share_links",
          views: "centrakit.subject_views",
          state: "centrakit.subject_user_state",
        },
      },
      reminders: {
        mode: "adopt",
        tables: {
          rules: "centrakit.recurrence_rules",
          reminders: "centrakit.reminders",
          deliveries: "centrakit.reminder_deliveries",
        },
      },
      imports: {
        mode: "adopt",
        tables: { runs: "centrakit.import_runs" },
      },
      // CentraKit keeps no attachment rows, sort keys or soft deletes on its
      // tree, so the drive adopts the tree and grants and leaves uploads to it.
      drive: {
        mode: "adopt",
        tables: {
          nodes: "centrakit.file_node",
          grants: "centrakit.file_node_grant",
        },
        columns: {
          nodes: {
            tenant: "organization_id",
            attachment: null,
            path: null,
            rank: null,
            deletedAt: null,
          },
          grants: {
            tenant: "organization_id",
            node: "file_node_id",
            principalType: null,
            principalId: null,
            expiresAt: null,
            createdBy: null,
          },
        },
        options: { roles: ["viewer", "commenter", "editor"] },
      },
      "realtime-tables": {},
    },
  },
});
