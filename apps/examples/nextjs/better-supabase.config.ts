import { defineConfig } from "better-supabase/config";

import { gettingStarted } from "./src/features/onboarding/checklist.ts";

const crud = ["select", "insert", "update", "delete"] as const;

export default defineConfig({
  source: {
    snapshot: "../../../supabase/snapshot.json",
    // The repo's `supabase start` stack, for `doctor --explain` and `--stats`.
    dbUrl: "postgresql://postgres:postgres@127.0.0.1:55422/postgres",
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
    notifications: crud,
    organizations: ["select"],
    plans: ["select"],
    plan_features: ["select"],
    subscriptions: ["select"],
  },
  // Plan features come from the fixture's plan catalog
  // (supabase/schemas/030_crm/090_plans.sql), not from Stripe.
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
  // Tenant tables broadcast per organization; notifications per user
  // (`bs:t:public.notifications:u:<user id>`).
  plugins: { tenant: { column: "organization_id" } },
  realtime: {
    tables: ["notifications"],
    users: { notifications: "user_id" },
  },
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
  // `search_notes(query, k)` for `db.$search('notes', …)`.
  vectorSearch: { notes: "embedding" },
  // The block files live in the repo's fixture, so the stack runs them.
  sql: {
    dir: "../../../supabase/schemas",
    modules: {
      "updated-at": {},
      "read-sets": {},
      "realtime-tables": {},
      "rate-limit": {},
      "vector-search": {},
      // The fixture writes the memberships table and the access contract
      // itself (supabase/schemas/045_access_contract.sql), so tokens that
      // carry only a tenant claim keep working for the integration suite.
      tenant: { mode: "custom", tables: { memberships: "public.memberships" } },
      // switch_organization writes app_metadata.tenant_id; the token hook
      // copies it into the access token. In custom mode only the role names
      // count: they are the roles invitations and member updates accept.
      // Their permissions live in supabase/schemas/045_access_contract.sql.
      access: {
        mode: "custom",
        activeTenant: "claim",
        roles: { owner: [], admin: [], member: [] },
      },
      // The fixture audits none of its CRM tables (doctor BS315). Members with
      // `audit.read` read their organization's log, and the app's actions
      // record events as the signed-in user.
      audit: {
        api: "api",
        options: {
          exempt: ["public.*"],
          readPolicy: true,
          eventRoles: ["authenticated", "service_role"],
        },
      },
      "api-keys": { api: "api" },
      settings: { api: "api" },
      comments: { api: "api" },
      organizations: {
        api: "api",
        mode: "adopt",
        tables: { organizations: "public.organizations" },
        columns: {
          organizations: { createdBy: null, deletedAt: null, disabledAt: null },
        },
      },
      invitations: { api: "api" },
      profiles: { api: "api" },
      flags: { api: "api" },
      announcements: { api: "api" },
      onboarding: { api: "api", options: { checklists: [gettingStarted] } },
      entitlements: { api: "api" },
      usage: { api: "api" },
    },
  },
});
