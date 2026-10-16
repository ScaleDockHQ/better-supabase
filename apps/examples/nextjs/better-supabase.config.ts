import { defineConfig } from "better-supabase/config";

import { gettingStarted } from "./src/features/onboarding/checklist.ts";
import { metrics } from "./src/metrics.ts";

const crud = ["select", "insert", "update", "delete"] as const;

export default defineConfig({
  source: {
    snapshot: "../../../supabase/snapshot.json",
  },
  casing: "camel",
  codecs: { int8: "bigint" },
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
      permissions: { read: "customers.read" },
      search: {},
    },
  },
  // `search_notes(query, k)` for `db.$search('notes', …)`.
  vectorSearch: { notes: "embedding" },
  // The block files live in the repo's fixture, so the stack runs them.
  sql: {
    dir: "../../../supabase/schemas/_better_supabase",
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
        exempt: ["public.*"],
        readPolicy: true,
        eventRoles: ["authenticated", "service_role"],
      },
    },
    "api-keys": {},
    settings: {},
    comments: {},
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
  },
});
