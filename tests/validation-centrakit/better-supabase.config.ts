import { defineConfig } from "better-supabase/config";

import { centrakitProvider } from "./src/provider.ts";

// The module config CentraKit adopts better-supabase with: every module runs
// on its existing tables (`adopt`) and its names, and the permissions are
// CentraKit's authorization provider's, read from a frozen snapshot of its
// output (authorization-provider.json). Only support sessions, the realtime
// registry and the blocks CentraKit had no tables for are new. CentraKit keeps
// its tables in `public`; the fixture puts them in `centrakit`.
export default defineConfig({
  auth: { authorization: centrakitProvider() },
  // The records comments attach to.
  records: {
    task: { table: "centrakit.tasks", idType: "uuid" },
    project: { table: "centrakit.projects", idType: "uuid", scope: "project" },
    customer: { table: "centrakit.customers", idType: "bigint" },
  },
  blocks: {
    permissions: {
      model: "provider",
      activeTenant: {
        profileColumn: "centrakit.profiles.active_organization_id",
        key: "user_id",
      },
    },
    memberships: {
      ownership: "adopt",
      tables: { memberships: "centrakit.organization_users" },
      columns: { memberships: { tenant: "organization_id", role: "role_id" } },
      options: {
        // The roles table holds the system roles too.
        roleThrough: {
          table: "centrakit.roles",
          id: "id",
          column: "key",
          where: "{row}.scope = 'organization'",
        },
        sameTenant: [
          {
            table: "centrakit.tasks",
            column: "project_id",
            references: "centrakit.projects",
          },
          {
            table: "centrakit.customer_contacts",
            column: "customer_id",
            references: "centrakit.customers",
          },
          // A task's contact works at the task's customer.
          {
            table: "centrakit.tasks",
            column: "contact_id",
            references: "centrakit.customer_contacts",
            match: { customer_id: "customer_id" },
          },
          // A task's customer is its project's customer.
          {
            table: "centrakit.tasks",
            column: "customer_id",
            references: "centrakit.customers",
            match: { "project_id.customer_id": "id" },
            through: { project_id: "centrakit.projects" },
          },
          // Task labels are the organization's tags of kind task.
          {
            table: "centrakit.tasks",
            column: "label_id",
            references: {
              table: "centrakit.organization_tags",
              tenant: "tenant_id",
              where: "{row}.kind = 'task'",
            },
          },
          {
            table: "centrakit.file_node_grant",
            column: "team_id",
            references: { table: "centrakit.teams", tenant: "tenant_id" },
          },
          {
            table: "centrakit.employees",
            column: "department_team_id",
            references: { table: "centrakit.teams", tenant: "tenant_id" },
          },
          {
            table: "centrakit.webhook_deliveries",
            column: "destination_id",
            references: "centrakit.webhook_destinations",
          },
        ],
      },
    },
    organizations: {
      ownership: "adopt",
      tables: { organizations: "centrakit.organizations" },
      columns: { organizations: { createdBy: null, deletedAt: null } },
      callbacks: {
        schema: "centrakit",
        functions: { after_organization_create: "seed_organization" },
      },
      options: {
        attributes: ["website", "logo_path", "default_currency"],
        reservedSlugs: ["app", "admin"],
        // Deleting an organization runs the data-lifecycle purge.
        deleteMode: "lifecycle",
      },
    },
    invitations: {
      ownership: "adopt",
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
      options: {
        tokenStorage: "plain",
        platformRoles: {
          table: "centrakit.user_roles",
          user: "user_id",
          role: "role_id",
          through: {
            table: "centrakit.roles",
            id: "id",
            column: "key",
            where: "{row}.scope = 'system'",
          },
        },
      },
    },
    profiles: {
      ownership: "adopt",
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
      callbacks: {
        schema: "centrakit",
        functions: { after_profile_sync: "create_contact_profile" },
      },
      options: {
        syncTrigger: false,
        usernameMaxLength: 30,
        metadata: { first_name: "first_name", last_name: "last_name" },
      },
    },
    impersonation: {
      permissions: {
        start: "platform.users.manage",
        view: "platform.users.manage",
      },
      // CentraKit's support staff start sessions alone; it has no second approver.
      options: { auditCategory: "security", approval: "none" },
    },
    audit: {
      ownership: "adopt",
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
      permissions: { view: "audit.view", viewAll: "platform.users.manage" },
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
      ownership: "adopt",
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
      options: { defaultSource: "domain", blockSource: "domain" },
    },
    notifications: {
      ownership: "adopt",
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
      ownership: "adopt",
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
        secrets: { endpoint: "destination_id", vaultId: null, expiresAt: null },
        deliveries: {
          endpoint: "destination_id",
          type: "event_kind",
          run: "workflow_run_id",
        },
      },
      permissions: { manage: "webhook.manage", view: "webhook.view" },
      options: {
        secretStorage: "column",
        eventIdType: "uuid",
        runIdType: "uuid",
        defaultFormat: "cloudevents",
        statuses: {
          delivering: "processing",
          succeeded: "completed",
          retrying: "failed",
          dead: "dead_lettered",
        },
      },
    },
    credentials: {
      ownership: "adopt",
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
      ownership: "adopt",
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
        create: "webhook.manage",
        update: "webhook.manage",
        delete: "webhook.manage",
        view: "webhook.view",
      },
    },
    "webhook-inbox": {
      ownership: "adopt",
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
    numbering: {
      ownership: "adopt",
      tables: { sequences: "centrakit.organization_number_sequences" },
    },
    teams: {
      ownership: "adopt",
      tables: { teams: "centrakit.teams", members: "centrakit.team_members" },
    },
    tags: {
      ownership: "adopt",
      tables: { tags: "centrakit.organization_tags", taggings: null },
      // CentraKit orders tags by an integer position, not rank keys.
      columns: { tags: { rank: null } },
      // CentraKit's provider has no apply permission; tagging needs manage.
      permissions: { apply: "tags.manage" },
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
      ownership: "adopt",
      tables: { history: "centrakit.status_history" },
    },
    "custom-fields": {
      ownership: "adopt",
      tables: {
        definitions: "centrakit.field_definitions",
        options: "centrakit.field_options",
        values: "centrakit.field_values",
      },
      columns: { definitions: { rank: null }, options: { rank: null } },
    },
    "share-links": {
      ownership: "adopt",
      tables: {
        links: "centrakit.share_links",
        views: "centrakit.subject_views",
        state: "centrakit.subject_user_state",
      },
      columns: { links: { versionId: null } },
    },
    reminders: {
      ownership: "adopt",
      tables: {
        rules: "centrakit.recurrence_rules",
        reminders: "centrakit.reminders",
        deliveries: "centrakit.reminder_deliveries",
      },
    },
    imports: { ownership: "adopt", tables: { runs: "centrakit.import_runs" } },
    // CentraKit keeps no attachment rows, sort keys or soft deletes on its
    // tree, so the drive adopts the tree and grants and leaves uploads to it.
    drive: {
      ownership: "adopt",
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
    subjects: {},
    // Comments are messages on the messaging core; CentraKit's provider names
    // its comment permissions, so messaging checks those keys.
    messaging: {
      permissions: {
        read: "comments.read",
        send: "comments.create",
        moderate: "comments.moderate",
      },
    },
    comments: {
      permissions: {
        read: "comments.read",
        create: "comments.create",
        moderate: "comments.moderate",
      },
    },
    attachments: {
      options: {
        subjects: {
          task: { table: "centrakit.tasks", idType: "uuid", cascade: true },
          project: {
            table: "centrakit.projects",
            idType: "uuid",
            scope: "project",
          },
          // centrakit.customers checks crm.read, not tenant membership (BS345).
          customer: {
            table: "centrakit.customers",
            idType: "bigint",
            permissions: { read: "crm.read", upload: "crm.read" },
          },
        },
      },
    },
    "data-lifecycle": {
      options: {
        autoTables: {
          schemas: ["centrakit"],
          tenant: "organization_id",
          user: "created_by",
          exclude: [
            "centrakit.audit_*",
            "centrakit.roles",
            "centrakit.user_roles",
          ],
        },
        // Exports leave out token, secret and hash columns of the auto tables.
        omitPattern: true,
        anonymize: [
          {
            table: "centrakit.employees",
            after: "365 days",
            from: "archived_at",
            set: {
              first_name: "Anonymized",
              last_name: null,
              work_email: null,
              job_title: null,
            },
            markedBy: "anonymized_at",
          },
        ],
      },
    },
    "api-keys": { options: { scopes: "catalog" } },
    "session-revocation": {
      options: { policies: true, exclude: ["centrakit.roles"] },
    },
    "jsonb-schemas": {},
    settings: {
      options: {
        schemas: {
          user: {
            theme: { type: "string", enum: ["light", "dark", "system"] },
          },
          organization: {
            fiscal_year_start: { type: "integer", minimum: 1, maximum: 12 },
            default_currency: { type: "string", pattern: "^[A-Z]{3}$" },
          },
        },
      },
    },
  },
});
