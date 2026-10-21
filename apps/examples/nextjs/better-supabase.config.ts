import { catalogSubjects } from "better-supabase/blocks/catalog";
import { dealsSubjects } from "better-supabase/blocks/deals";
import { driveSubject } from "better-supabase/blocks/drive";
import { employeesSubjects } from "better-supabase/blocks/employees";
import { partiesSubjects } from "better-supabase/blocks/parties";
import { workItemsSubjects } from "better-supabase/blocks/work-items";
import { defineConfig } from "better-supabase/config";

import { gettingStarted } from "./src/features/onboarding/checklist.ts";
import { metrics } from "./src/metrics.ts";

const crud = ["select", "insert", "update", "delete"] as const;

const WORK_STATES = [
  "triage",
  "backlog",
  "unstarted",
  "started",
  "completed",
  "canceled",
];

export default defineConfig({
  source: { snapshot: "../../../supabase/snapshot.json" },
  casing: "camel",
  codecs: { int8: "bigint" },
  seed: { perTenant: "src/features/onboarding/tenant-seed.ts" },
  output: "src/lib/supabase/generated.ts",
  expose: {
    customers: crud,
    contacts: crud,
    locations: crud,
    notes: crud,
    tags: crud,
    customer_tags: crud,
    organizations: ["select"],
    plans: ["select"],
    plan_features: ["select"],
    subscriptions: ["select"],
  },
  // Plan features come from the fixture's plan catalog
  // (supabase/schemas/public/tables/plans.sql), not from Stripe.
  entitlements: {
    source: {
      plans: {
        subscriptions: {
          table: "public.subscriptions",
          tenant: "organization_id",
          plan: "plan_key",
          status: "status",
        },
        features: {
          table: "public.plan_features",
          plan: "plan_key",
          feature: "feature_key",
          included: "included",
          value: "value",
        },
      },
    },
  },
  plugins: { tenant: { column: "organization_id" } },
  buckets: {
    customerLogos: {
      path: "{organizationId}/{customerId}/logo/{version}.webp",
      public: true,
      policy: "tenant",
      fileSizeLimit: "5MiB",
      allowedMimeTypes: ["image/png", "image/jpeg", "image/webp"],
    },
    // Profile pictures, with the settings of `avatarBucket()`.
    avatars: {
      path: "{userId}/avatar-{version}.{ext}",
      public: true,
      policy: "owner",
      fileSizeLimit: "2MiB",
      allowedMimeTypes: [
        "image/png",
        "image/jpeg",
        "image/webp",
        "image/gif",
        "image/avif",
      ],
    },
  },
  // Rows store the object path; URLs are built when rendering.
  storagePaths: { "customers.logo_path": "customerLogos" },
  readSets: ["src/lib/read-sets.ts"],
  // Rows the search index, comments and other subject-aware modules point at.
  subjects: {
    customer: {
      table: "public.customers",
      idType: "uuid",
      title: "name",
      url: "/customers/{id}",
      deletedAt: "archived_at",
      permissions: { read: "customers.read", write: "customers.write" },
      search: {},
    },
    ...partiesSubjects({
      url: { company: "/crm/contacts/{id}", person: "/crm/contacts/{id}" },
    }),
    ...dealsSubjects({ url: "/crm/deals" }),
    ...workItemsSubjects({ url: "/work" }),
    ...employeesSubjects({ url: "/people" }),
    ...catalogSubjects({ productUrl: "/shop" }),
    drive_node: driveSubject(),
    application: {
      table: "better_supabase.applications",
      idType: "uuid",
      tenant: "tenant_id",
      url: "/people/hiring",
      permissions: { read: "hiring.read", write: "hiring.write" },
      rank: { column: "rank", group: "stage_id" },
    },
  },
  // `search_notes(query, k)` for `db.$search('notes', …)`.
  vectorSearch: { notes: "embedding" },
  // Tables only this app has. `sql sync` writes them with the organization
  // column (or `user_id`), row level security and a pgTAP test.
  appTables: {
    projects: {
      columns: {
        name: { type: "text", nullable: false },
        budget_minor: { type: "bigint", nullable: false, default: "0" },
        currency: { type: "text", nullable: false, default: "'EUR'" },
        lead_id: {
          type: "uuid",
          references: { table: "auth.users", onDelete: "set null" },
        },
        label_id: {
          type: "uuid",
          references: { block: "tags", table: "tags", onDelete: "set null" },
        },
        // Signed-in members can't select or write it; server code with the
        // service role reads it by name (ADR 0051).
        internal_notes: { type: "text", access: "server" },
      },
      // Comments, attachments, tags, versions and search reach projects.
      // Each change to the name, budget or currency keeps a version, which
      // the record history restores field by field.
      subject: {
        type: "project",
        title: "name",
        url: "/projects/{id}",
        search: {},
        softDelete: true,
        versions: { columns: ["name", "budget_minor", "currency"] },
      },
      // Read through `public.projects_view`, with the caller's row level
      // security on projects and tasks.
      rollups: {
        open_tasks: {
          table: "tasks",
          via: "project_id",
          aggregate: "count",
          where: { column: "status", equals: "todo" },
        },
        done_tasks: {
          table: "tasks",
          via: "project_id",
          aggregate: "count",
          where: { column: "status", equals: "done" },
        },
        next_due_on: {
          table: "tasks",
          via: "project_id",
          aggregate: "min",
          column: "due_on",
        },
      },
    },
    tasks: {
      columns: {
        title: { type: "text", nullable: false, max: 200 },
        status: {
          type: "text",
          nullable: false,
          default: "'todo'",
          options: ["todo", "doing", "done"],
        },
        starts_on: { type: "date" },
        due_on: { type: "date" },
        assignee_id: {
          type: "uuid",
          references: { table: "auth.users", onDelete: "set null" },
        },
        project_id: {
          type: "uuid",
          nullable: false,
          references: { table: "projects", onDelete: "cascade" },
        },
      },
      // The board orders tasks within each status column.
      subject: {
        type: "task",
        title: "title",
        url: "/projects/{project_id}",
        rank: { group: "status" },
      },
      lookups: { project_name: { via: "project_id", column: "name" } },
      // The task import updates the task with the same title in a project.
      unique: [["project_id", "title"]],
      // task.created, task.updated and task.deleted go to the outbox, where
      // /api/outbox runs the rules whose trigger is the event (ADR 0048).
      events: { include: ["status", "project_id"] },
    },
    saved_views: {
      scope: "user",
      columns: {
        name: { type: "text", nullable: false },
        filters: { type: "jsonb", nullable: false, default: "'{}'" },
      },
    },
  },
  // The block files live in the repo's fixture, so the stack runs them.
  sql: {
    dir: "../../../supabase/schemas/_better_supabase",
    testsDir: "../../../supabase/tests/database",
    // Every module writes its Data API wrappers to `api`, except those
    // that set `api: false` (helpers with no client entry points).
    api: "api",
  },
  blocks: {
    "updated-at": { api: false },
    "read-sets": { api: false },
    "realtime-tables": { api: false },
    "rate-limit": { api: false },
    "vector-search": { api: false },
    // The fixture writes the memberships table and the access contract
    // itself (supabase/schemas/better_supabase/functions), so tokens that
    // carry only a tenant claim keep working for the integration suite.
    tenant: {
      mode: "custom",
      api: false,
      tables: { memberships: "public.memberships" },
    },
    // switch_organization writes app_metadata.tenant_id; the token hook
    // copies it into the access token. In custom mode only the role names
    // count: they are the roles invitations and member updates accept.
    // Their permissions live in
    // supabase/schemas/better_supabase/functions/role_permissions.sql.
    access: {
      mode: "custom",
      api: false,
      activeTenant: "claim",
      roles: { owner: [], admin: [], member: [] },
    },
    // The fixture audits none of its CRM tables (doctor BS315). Members with
    // `audit.read` read their organization's log, and the app's actions
    // record events as the signed-in user.
    audit: {
      options: {
        exempt: [
          {
            table: "public.*",
            reason:
              "the fixture CRM tables are demo data with no audit requirement",
          },
        ],
        readPolicy: true,
        eventRoles: ["authenticated", "service_role"],
      },
    },
    "api-keys": {},
    settings: {},
    comments: {},
    // Tags on customers, edited with the tag input on the customer page. The
    // fixture's `public.tags` and `customer_tags` tables are separate seed
    // data that no example renders.
    tags: {},
    organizations: {
      mode: "adopt",
      tables: { organizations: "public.organizations" },
      columns: {
        organizations: { createdBy: null, deletedAt: null, disabledAt: null },
      },
    },
    invitations: {},
    profiles: {},
    flags: {},
    announcements: {},
    onboarding: { options: { checklists: [gettingStarted] } },
    entitlements: {},
    usage: {},
    // Cmd+K over customers, and the customers card on the dashboard.
    search: {},
    metrics: { options: { metrics } },
    // In-app notifications behind the unread badge and /notifications,
    // on the recipient's private topic `notifications:<user id>`.
    notifications: {},
    // Durable workflow runs behind /workflows, run by the Workflow SDK on
    // the Supabase World (`WORKFLOW_TARGET_WORLD`), which polls in dev.
    workflows: {},
    "workflow-sdk-world": { api: false },
    // Workflows tenants build on a canvas at /workflows/builder.
    "workflow-builder": {},
    // Tenant rules for expenses, edited with the rule builder at /rules.
    rules: {},
    // Vault-backed secrets behind the builder's credential references.
    credentials: {},
    // The support inbox behind /inbox and the Help sheet: jobs carry bot
    // turns and channel replies, streams hold the bot's resumable output.
    jobs: { api: false },
    streams: {},
    inbox: {},
    "chat-sdk-state": { api: false },
    // The /assistant sample: chats in `ai-chat` on private Realtime topics,
    // resumable answers in `streams` and attachments in `ai-files`.
    // /knowledge ingests documents into `knowledge` for the assistant's
    // search tool, and `memory` keeps what it remembers. /agents builds and
    // installs assistants (`agents`), `connectors` holds the MCP servers they
    // call and `ai-tasks` their schedules.
    "ai-chat": {},
    "ai-files": {},
    knowledge: {},
    memory: {},
    agents: {},
    connectors: {},
    "ai-tasks": {},
    // Device push tokens for the Expo example's push registration.
    push: {},
    // The assistant answers with each organization's own provider keys
    // (`ai-providers`), and `ai-cache` keeps repeated model calls.
    "ai-cache": {},
    "ai-providers": {},
    // The blocks behind the remaining UI recipes (`/recipes`), one page or
    // card each in the app.
    // Ending a session on /settings/sessions cuts its access at once: every
    // app table gets the restrictive session_active() policy.
    sessions: { options: { policies: true } },
    sso: {},
    approvals: {
      options: {
        policies: {
          customer: {
            discount: {
              steps: [
                { approvers: { permission: "approvals.manage" }, required: 1 },
              ],
              selfApproval: true,
            },
          },
        },
      },
    },
    "access-requests": {},
    grants: {},
    subjects: {},
    reactions: {},
    "share-links": {},
    // The example runs no malware scanner, so uploads are readable at once.
    attachments: { options: { requireScan: false } },
    waitlist: {},
    teams: {},
    parties: {},
    pipelines: {},
    deals: {},
    engagements: {},
    quotes: {},
    targets: {},
    "state-machine": {
      options: {
        machines: {
          // Any state may follow any other, as the board allows; the machine
          // adds the history and the status.changed events.
          work_item: {
            column: "state",
            initial: "backlog",
            transitions: Object.fromEntries(
              WORK_STATES.map((from) => [
                from,
                WORK_STATES.filter((to) => to !== from),
              ]),
            ),
            order: ["triage", "backlog", "unstarted", "started", "completed"],
          },
        },
      },
    },
    rank: {},
    // The app already has `projects` and `saved_views` tables (appTables).
    "work-items": { tables: { projects: "work_projects" } },
    "saved-views": { tables: { views: "shared_views" } },
    sla: {},
    "custom-fields": {},
    bulk: {},
    trash: {},
    relations: {},
    employees: {},
    hiring: {},
    "time-tracking": {},
    invoices: {},
    catalog: {},
    inventory: {},
    orders: {},
    promotions: {},
    calendar: {},
    bookings: {},
    reminders: {},
    "drive-files": {},
    drive: {},
    versions: {
      options: { subjects: { customer: { columns: ["name", "kvk"] } } },
    },
    "jsonb-schemas": {},
    forms: {},
    imports: {},
    templates: {},
    documents: {},
    "webhooks-out": {},
    outbox: {},
    "service-principals": {},
    "signing-keys": {},
    // Exports leave out token, hash and secret columns (doctor BS341).
    "data-lifecycle": { options: { omitPattern: true } },
  },
});
