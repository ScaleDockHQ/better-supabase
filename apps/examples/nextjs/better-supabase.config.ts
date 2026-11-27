import { driveSubject } from "better-supabase/blocks/drive";
import { defineConfig } from "better-supabase/config";
import { factories } from "better-supabase/generators/factories";
import { nuqs } from "better-supabase/generators/nuqs";
import { tags } from "better-supabase/generators/tags";
import { zod } from "better-supabase/generators/zod";
import { defineEntityPage, seedRef } from "better-supabase/list";

import {
  contractsSeed,
  customersSeed,
  inboxSeed,
  dealsSeed,
  pipelinesSeed,
  queuesSeed,
  scoresSeed,
  segmentsSeed,
} from "./crm-seeds.ts";
import { overviewPages } from "./overview-pages.ts";
import { gettingStarted } from "./src/features/onboarding/checklist.ts";
import { metrics } from "./src/metrics.ts";
import { TAG_DOMAINS } from "./tag-domains.ts";

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
  database: {
    source: { snapshot: "../../../supabase/snapshot.json" },
    seed: { perTenant: "src/features/onboarding/tenant-seed.ts" },
    expose: {
      customers: crud,
      contacts: crud,
      locations: crud,
      notes: crud,
      tags: crud,
      customer_tags: crud,
      organizations: ["select"],
      // The pricing page reads the plan catalog as a visitor.
      plans: { anon: ["select"], authenticated: ["select"] },
      plan_features: { anon: ["select"], authenticated: ["select"] },
      subscriptions: ["select"],
      // The bulk bar calls it over /rpc as the signed-in member.
      "work_bulk_state(uuid, text, text, jsonb)": {
        execute: ["authenticated"],
      },
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
    // `search_notes(query, k)` for `db.$search('notes', …)`.
    vectorSearch: { notes: "embedding" },
    // The block files live in the repo's fixture, so the stack runs them.
    sql: {
      dir: "../../../supabase/schemas/_better_supabase",
      testsDir: "../../../supabase/tests/database",
      // Every module writes its Data API wrappers to `api`, except those
      // that set `api: false` (helpers with no client entry points).
      api: "api",
    },
  },
  gen: {
    // The snapshot covers public and better_supabase only, so the api schema stays untyped:
    // its 2,529 wrappers would add about 342 KB of types to a 31 KB database.types.ts (EX-1612).
    // Pages call those functions through the typed block clients (db.impersonation and the rest).
    api: { types: false },
    casing: "camel",
    codecs: { int8: "bigint" },
    file: "src/lib/supabase/generated.ts",
    // Rows store the object path; URLs are built when rendering.
    storagePaths: { "customers.logo_path": "customerLogos" },
    readSets: ["src/lib/read-sets.ts"],
    hooks: "react",
    // Keys and default grants for every installed block, in a migration, so a new block's pages never answer 403 for the owner.
    permissionCatalog: true,
    // One descriptor per entity page: gen writes the list query, `/api/periods/list`,
    // the indexes of its sorts and facets, `scale_list_periods.test.sql` (ADR 0859), its columns and
    // its detail frame (ADR 0869), its nav item and route manifest (ADR 0879).
    entityPages: {
      pages: [
        defineEntityPage({
          entity: "periods.period",
          route: "/finance/periods",
          // The periods block names its list reads per entity.
          methods: { page: "periodPage", facets: "periodFacets" },
          // Columns and detail sections: gen writes `periods.columns.ts` and `periods.detail.ts`.
          columns: ["kind", "status", "startsOn", "endsOn"],
          sections: ["overview", "entries"],
          // Nav area: gen writes `periods.navigation.ts` and `routes.manifest.ts`.
          area: "finance",
          // Six fiscal months from the periods block's input schema. `kind` is a value no
          // generator can guess and the ranges may not overlap, so `seed.fields` declares
          // them (ADR 1032); `pnpm db:seed:pages` creates them through `create_period`.
          seed: {
            demo: 6,
            tiers: ["demo"],
            fields: {
              kind: "fiscal_month",
              startsOn: [
                "2026-06-01",
                "2026-07-01",
                "2026-08-01",
                "2026-09-01",
                "2026-10-01",
                "2026-11-01",
              ],
              endsOn: [
                "2026-06-30",
                "2026-07-31",
                "2026-08-31",
                "2026-09-30",
                "2026-10-31",
                "2026-11-30",
              ],
            },
          },
          // CSV download: gen writes `/api/periods/export` and lists it in `routes.manifest.ts` (ADR 0880).
          export: { filename: "periods.csv" },
        }),
        // The risk register (EX-1001). The block's `category` field takes one of the
        // block's configured categories, which a generated demo value cannot know, so
        // `seed.fields` lists the block's default categories and row `i` takes the one at `i`
        // (ADR 1032).
        defineEntityPage({
          entity: "risks.risk",
          route: "/risks",
          columns: ["title", "category", "status", "residualScore"],
          sections: ["overview", "assessments"],
          area: "quality",
          // The register sorts by score, then number (ADR 0896): `gen` writes the composite index
          // and BS636 asks for it. The block orders by the first term only, so the register reads its rows
          // through `features/risks/risk-reads.ts`, which orders by every term (ADR 0895).
          sortLists: [["residualScore", "number"]],
          seed: {
            demo: 8,
            tiers: ["demo"],
            fields: {
              category: [
                "quality",
                "safety",
                "environment",
                "security",
                "compliance",
                "operational",
                "financial",
                "strategic",
              ],
            },
          },
        }),
        // The dispatch board: the block's input schema asks only for a title, so the page
        // seeds five demo work orders (`work-orders.seed.ts`, applied by `pnpm db:seed:pages`).
        defineEntityPage({
          entity: "dispatch.work_order",
          route: "/field/dispatch",
          name: "work-orders",
          columns: ["title", "status", "priority", "startsAt"],
          area: "operations",
          seed: { demo: 5, tiers: ["demo"] },
        }),
        // The sales overviews of phase 6 (EX-607). Their blocks export no input schema that
        // fits (an accrual takes `source: { type, id }` and an attribution a code), so each page
        // declares its rows in `seed.rows` (ADR 1032). The commission plans and the referral
        // code stay in `example.sql`: the accruals and the attribution need them.
        defineEntityPage({
          entity: "commissions.commission",
          route: "/crm/commissions",
          name: "commissions",
          methods: { page: "commissionPage", facets: "commissionFacets" },
          columns: ["status", "seller", "amount", "occurredOn"],
          area: "sales",
          seed: {
            tiers: ["demo"],
            rows: [
              {
                seller_id: "00000000-0000-4000-8000-0000000000a1",
                source_type: "deal",
                source_id: seedRef("app.deals", "Globex add-on"),
                basis: 450_000,
                currency: "EUR",
                occurred_on: "2026-11-09",
              },
              {
                seller_id: "00000000-0000-4000-8000-0000000000a2",
                source_type: "deal",
                source_id: seedRef("app.deals", "Hooli pilot"),
                basis: 300_000,
                currency: "EUR",
                occurred_on: "2026-11-12",
              },
            ],
          },
        }),
        defineEntityPage({
          entity: "referrals.referral",
          route: "/crm/referrals",
          name: "referrals",
          methods: { page: "referralPage", facets: "referralFacets" },
          columns: ["status", "referrer", "createdAt"],
          area: "sales",
          seed: {
            tiers: ["demo"],
            rows: [
              { code: "ACMEFRIENDS", referred_email: "friend@initech.test" },
            ],
          },
        }),
        ...overviewPages,
        // The open invitations of an organization (ADR 0923, 0924): the organizations block
        // names its list reads per entity, and the members page is the nav area.
        defineEntityPage({
          entity: "organizations.invitation",
          route: "/members/invitations",
          // `db.organizations` is the table, so the block reads sit under `$blocks`.
          reads: "$blocks.organizations",
          methods: { page: "invitationsPage", facets: "invitationsFacets" },
          columns: ["email", "role", "expiresAt"],
          area: "team",
          // The organizations block declares no table for its invitations, so the page names
          // it. The open invitation with a known token stays in `seed.sql` (`/invite/seed-invitation-acme`).
          seed: {
            tiers: ["demo"],
            table: "better_supabase.invitations",
            tenant: "tenant_id",
            rows: [
              { email: "dana@acme.test", role: "member" },
              { email: "sam@acme.test", role: "member" },
              { email: "lee@acme.test", role: "admin" },
            ],
          },
        }),
        // The incident log (EX-001): every incidents call takes `organizationId`, which the
        // generated routes read from the route's `tenant` (ADR 0890). The block's input schema
        // asks for a title, so the page seeds three demo incidents through `open_incident`.
        defineEntityPage({
          entity: "incidents.incident",
          route: "/incidents",
          tenantOption: "organizationId",
          columns: ["title", "severity", "status", "startedAt"],
          area: "operations",
          seed: { demo: 3, tiers: ["demo"] },
        }),
        // The customers overview (EX-014, EX-001): an app table, so the entity is named
        // `app.customers` and its reads module answers `page` and `facets` over
        // `customerList` (ADR 0893). RLS decides the rows, so the table has a tenant column
        // for the indexes and the route passes no tenant.
        defineEntityPage({
          entity: "app.customers",
          route: "/customers",
          name: "customers",
          columns: ["name", "status", "createdAt"],
          area: "sales",
          seed: customersSeed,
          app: {
            surface: {
              sorts: ["name", "newest"],
              facets: ["status"],
              search: ["name"],
            },
            table: {
              name: "customers",
              tenant: "organization_id",
              columns: {
                name: "name",
                newest: "created_at",
                createdAt: "created_at",
                status: "status",
              },
            },
            reads: {
              module: "@/features/customers-list/customers-reads",
              export: "customersReads",
            },
            blocks: ["subjects", "saved-views", "search"],
          },
        }),
        // The inbox queue (EX-410): `conversations.list` declares no list surface, so the
        // queue is an app entity and `inboxReads` answers `page` and `facets` over it. The
        // list takes the tenant per call, which the generated route reads from the request.
        defineEntityPage({
          entity: "app.inbox",
          route: "/inbox",
          name: "inbox",
          tenantOption: "tenant",
          columns: ["subject", "status", "lastMessageAt"],
          area: "messaging",
          seed: inboxSeed,
          app: {
            surface: {
              sorts: ["lastMessageAt"],
              facets: ["status"],
              filters: ["status", "assignee", "channel"],
              search: true,
            },
            table: {
              schema: "better_supabase",
              name: "inbox_conversations",
              tenant: "tenant_id",
              columns: {
                subject: "subject",
                lastMessageAt: "last_message_at",
                status: "status",
                assignee: "assignee_id",
                channel: "inbox_id",
              },
            },
            reads: {
              module: "@/features/inbox/inbox-reads",
              export: "inboxReads",
            },
            blocks: ["inbox", "sla", "mail-sync"],
          },
        }),
        // The array lists of the CRM (EX-607): each block returns its rows as an array, so an
        // `arrayReads` module (ADR 0894) loads the array and answers `page` and `facets` with
        // the spec the overview uses. The table is the block's, for the indexes and scale test.
        defineEntityPage({
          entity: "app.deals",
          route: "/crm/deals",
          name: "deals",
          tenantOption: "tenant",
          columns: ["name", "stage", "closing"],
          area: "sales",
          seed: dealsSeed,
          app: {
            surface: {
              sorts: ["closing", "amount", "stale", "name"],
              facets: ["stage"],
              search: ["name"],
            },
            table: {
              schema: "better_supabase",
              name: "deals",
              tenant: "tenant_id",
              columns: {
                closing: "expected_close_on",
                amount: "amount",
                name: "name",
                stage: "stage_id",
              },
            },
            reads: {
              module: "@/features/sales/list-reads/deals-reads",
              export: "dealsReads",
            },
            blocks: ["pipelines", "deals"],
          },
        }),
        defineEntityPage({
          entity: "app.pipelines",
          route: "/crm/pipelines",
          name: "pipelines",
          tenantOption: "tenant",
          columns: ["name", "key"],
          area: "sales",
          seed: pipelinesSeed,
          app: {
            surface: { sorts: ["name"], search: ["name"] },
            table: {
              schema: "better_supabase",
              name: "pipelines",
              tenant: "tenant_id",
              columns: { name: "name", key: "key" },
            },
            reads: {
              module: "@/features/sales/list-reads/pipelines-reads",
              export: "pipelinesReads",
            },
            blocks: ["pipelines"],
          },
        }),
        defineEntityPage({
          entity: "app.segments",
          route: "/crm/segments",
          name: "segments",
          tenantOption: "tenant",
          columns: ["name", "subjectType", "members"],
          area: "sales",
          seed: segmentsSeed,
          app: {
            surface: {
              sorts: ["name", "members"],
              facets: ["subjectType"],
              search: ["name"],
            },
            table: {
              schema: "better_supabase",
              name: "segments",
              tenant: "tenant_id",
              columns: {
                name: "name",
                members: "member_count",
                subjectType: "subject_type",
              },
            },
            reads: {
              module: "@/features/sales/list-reads/segments-reads",
              export: "segmentsReads",
            },
            blocks: ["segments"],
          },
        }),
        defineEntityPage({
          entity: "app.queues",
          route: "/crm/queues",
          name: "assignment-queues",
          tenantOption: "tenant",
          columns: ["name", "strategy", "rank"],
          area: "sales",
          seed: queuesSeed,
          app: {
            surface: {
              sorts: ["rank", "name", "assigned"],
              facets: ["strategy"],
              search: ["name"],
            },
            table: {
              schema: "better_supabase",
              name: "assignment_queues",
              tenant: "tenant_id",
              columns: { rank: "rank", name: "name", strategy: "strategy" },
            },
            reads: {
              module: "@/features/sales/list-reads/queues-reads",
              export: "queuesReads",
            },
            blocks: ["assignment"],
          },
        }),
        defineEntityPage({
          entity: "app.scores",
          route: "/crm/scoring",
          name: "scores",
          tenantOption: "tenant",
          columns: ["name", "key", "subjectType"],
          area: "sales",
          seed: scoresSeed,
          app: {
            surface: {
              sorts: ["name"],
              // A filter, not a facet: the block's own `score_models_subject_idx` already serves
              // `(tenant_id, subject_type)`, and a facet would write an identical index.
              filters: ["subjectType"],
              search: ["name"],
            },
            table: {
              schema: "better_supabase",
              name: "score_models",
              tenant: "tenant_id",
              columns: {
                name: "name",
                key: "key",
                subjectType: "subject_type",
              },
            },
            reads: {
              module: "@/features/sales/list-reads/scores-reads",
              export: "scoreModelsReads",
            },
            blocks: ["scores"],
          },
        }),
        defineEntityPage({
          entity: "app.contracts",
          route: "/crm/contracts",
          name: "contracts",
          tenantOption: "tenant",
          columns: ["title", "status", "endsOn"],
          area: "sales",
          seed: contractsSeed,
          app: {
            surface: {
              sorts: ["ending", "notice", "title"],
              facets: ["status"],
              search: ["title"],
            },
            table: {
              schema: "better_supabase",
              name: "contracts",
              tenant: "tenant_id",
              columns: {
                ending: "ends_on",
                title: "title",
                status: "status",
                endsOn: "ends_on",
              },
            },
            reads: {
              module: "@/features/sales/list-reads/contracts-reads",
              export: "contractsReads",
            },
            blocks: ["contracts"],
          },
        }),
      ],
      server: { module: "@/lib/supabase/server", export: "bsb" },
      scaleDir: "../../../supabase/tests/scale",
    },
    // Tested consumers of the first-party generators: zod schemas (not wired
    // into the repositories, so no route bundles them), nuqs search params and test factories for the app's own tables.
    generators: [
      zod({ validators: false }),
      nuqs({ tables: ["tasks", "customers"] }),
      factories(),
      tags({ domains: TAG_DOMAINS }),
    ],
    // Routes that need no other block (sign-in, the customers API) build their
    // server from this set and bundle no other block (ADR 0542).
    serverBlocks: {
      core: ["permissions"],
      // `/api/v1` serves the app's tables next to the teams and permissions blocks.
      api: ["permissions", "teams"],
      shell: [
        "permissions",
        "organizations",
        "profiles",
        "usage",
        "onboarding",
        "audit",
        "notifications",
        "inbox",
      ],
    },
  },
  tooling: {
    doctor: {
      // The fixture installs every block, so its module SQL is far past the
      // 2 MB cache budget (BS244), and `client_notes_reveal` is a demo
      // function that embeds its masking table (BS243). Apps install fewer
      // blocks and keep data in tables. The commerce list migration
      // (20270102120003) drops the positional list_gifts, list_leases,
      // list_pledges and list_shipments signatures for one `filters jsonb`
      // argument (BS235, four findings); the client sends the new form.
      // `projects.sql` carries the search tag's `bsb_search_project_index`
      // trigger, which the search module file creates too (BS722, one finding).
      // The Vercel tag probe calls updateTag and revalidateTag on purpose, to
      // measure them, and the role actions expire a Next-only organization
      // snapshot tag, not a kept entry (BS648, three findings).
      ignore: ["BS235", "BS243", "BS244", "BS648", "BS722"],
    },
  },
  auth: {
    tenant: { column: "organization_id" },
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
  },
  // Rows the search index, comments and other subject-aware modules point at.
  // Installed blocks register their own entities (deals, work items, ...);
  // `blocks.<name>.entities` sets their pages.
  recordTypes: {
    customer: {
      table: "public.customers",
      idType: "uuid",
      title: "name",
      url: "/customers/{id}",
      deletedAt: "archived_at",
      permissions: { read: "customers.read", write: "customers.write" },
      // The account team on a customer reads and edits it without the keys.
      team: { actions: ["read", "write"] },
      // Every read through the blocks' read functions lands in the audit log.
      auditReads: true,
      // Statement triggers: import_customer_batch writes a batch in two
      // statements, and each indexes its rows in one call.
      search: { facets: ["status"], statement: true },
    },
    // Members ask for read access to a file or folder they cannot open.
    drive_node: driveSubject({ accessRequests: true }),
    // The tenant itself: its id is its tenant, so an organization accepts
    // agreements through consents for itself only.
    organization: {
      table: "public.organizations",
      idType: "uuid",
      tenant: "id",
      title: "name",
    },
    application: {
      table: "better_supabase.applications",
      idType: "uuid",
      tenant: "tenant_id",
      url: "/people/hiring",
      permissions: { read: "hiring.read", write: "hiring.write" },
      rank: { column: "rank", group: "stage_id" },
    },
  },
  blocks: [
    { block: "updated-at", api: false },
    "read-sets",
    { block: "realtime-tables", api: false },
    { block: "rate-limit", api: false },
    { block: "vector-search", api: false },
    // The block runs over the fixture's own `public.memberships` table
    // (ADR 0098); its `role` column references the catalog's roles.
    {
      block: "memberships",
      api: false,
      tables: { memberships: "public.memberships" },
    },
    // Roles, permission keys and their links are rows in the catalog tables
    // (seeded by a data migration), and admins override a role's keys per
    // organization in `permission_overrides`. switch_organization writes
    // app_metadata.tenant_id; the token hook copies it into the access token.
    { block: "permissions", model: "catalog", activeTenant: "claim" },
    // The fixture audits none of its CRM tables (doctor BS315). Members with
    // `audit.read` read their organization's log, and the app's actions
    // record events as the signed-in user.
    {
      block: "audit",
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
    "api-keys",
    "settings",
    "comments",
    // Conversations and messages under the channels block (ADR 0062).
    "messaging",
    "channels",
    // The record history the customer page shows, moved out of comments.
    "timeline",
    // Members' Gmail and Outlook mail, linked to parties and logged as
    // email activities.
    "mail-sync",
    // Saved filters over companies and deals, refreshed on a schedule.
    "segments",
    // Round robin and weighted queues that pick an owner for new records.
    "assignment",
    // Company and person data from an enrichment provider, one result each.
    "enrichment",
    // Tenant defaults (pipelines, calendars, tax codes) that new organizations receive.
    { block: "seeds", api: false },
    // The forecast call by period, snapshotted so a review compares weeks.
    "forecasts",
    // Old and new values of a deal's amount, stage, owner and close date,
    // and a company's owner and lifecycle stage.
    {
      block: "field-history",
      on: {
        deal: {
          fields: ["amount", "stage_id", "owner_id", "expected_close_on"],
        },
        company: { fields: ["owner_id", "lifecycle"] },
      },
    },
    // Tags on customers, edited with the tag input on the customer page. The
    // fixture's `public.tags` and `customer_tags` tables are separate seed
    // data that no example renders.
    "tags",
    {
      block: "organizations",
      tables: { organizations: "public.organizations" },
      columns: {
        organizations: { createdBy: null, deletedAt: null, disabledAt: null },
      },
    },
    "invitations",
    "profiles",
    "flags",
    "announcements",
    // Onboarding checklists run on enrollments (ADR 0077).
    "enrollments",
    // Courses behind /courses: each learner's progress is an enrollment.
    "courses",
    // Outreach sequences behind /crm/sequences: each recipient's run is an
    // enrollment, and email steps send through mail-sync (ADR 0091).
    "sequences",
    { block: "onboarding", options: { checklists: [gettingStarted] } },
    "entitlements",
    { block: "usage", options: { history: true } },
    // Cmd+K over customers, and the customers card on the dashboard.
    "search",
    { block: "metrics", options: { metrics } },
    // In-app notifications behind the unread badge and /notifications,
    // on the recipient's private topic `notifications:<user id>`.
    // Email goes to the work address `better_supabase.member_address` returns, and to
    // the sign-in email when it returns null.
    {
      block: "notifications",
      options: { resolveAddress: "better_supabase.member_address" },
    },
    // Durable workflow runs behind /workflows, run by the Workflow SDK on
    // the Supabase World (`WORKFLOW_TARGET_WORLD`), which polls in dev.
    "workflows",
    { block: "workflow-sdk", api: false },
    // Workflows tenants build on a canvas at /workflows/builder.
    "workflow-editor",
    // Tenant rules for expenses, edited with the rule builder at /rules.
    "automations",
    // Lead scoring and account health are score models over parties (ADR 0067).
    "scores",
    // People scored under the "lead" model, again when their segments, mail
    // or enrichment change.
    "lead-scoring",
    // Comment reports, the review queue and bans (ADR 0076).
    "moderation",
    // Vault-backed secrets behind the builder's credential references.
    "credentials",
    // The support inbox behind /inbox and the Help sheet: jobs carry bot
    // turns and channel replies, streams hold the bot's resumable output.
    { block: "queue", api: false },
    "streams",
    "inbox",
    { block: "chat-sdk-state", api: false },
    // The /assistant sample: chats in `ai-chat` on private Realtime topics,
    // resumable answers in `streams` and attachments in `ai-files`.
    // /knowledge ingests documents into `knowledge` for the assistant's
    // search tool, and `memory` keeps what it remembers. /agents builds and
    // installs assistants (`agents`), `connectors` holds the MCP servers they
    // call and `ai-schedules` their schedules.
    "ai-chat",
    "ai-files",
    "knowledge",
    "memory",
    "agents",
    "connectors",
    "ai-schedules",
    // Device push tokens for the Expo example's push registration.
    "push",
    // The assistant answers with each organization's own provider keys
    // (`ai-keys`), and `ai-cache` keeps repeated model calls.
    "ai-cache",
    "ai-keys",
    // /assistant/prompts keeps versioned prompt templates behind labels,
    // /assistant/evals runs datasets against a prompt version, and
    // /assistant/guardrails holds the per-agent policies and decision log.
    "prompts",
    "ai-evals",
    "ai-guardrails",
    // The blocks behind the remaining UI recipes (`/recipes`), one page or
    // card each in the app.
    // Ending a session on /settings/sessions cuts its access at once: every
    // app table gets the restrictive session_active() policy. A role change
    // bumps the user's authorization version, which SessionProvider hears on
    // authz:<uid> and refreshes the token for. `bootstrap` renders
    // better_supabase.bootstrap_islands, which /islands reads in one query.
    {
      block: "sessions",
      options: {
        policies: true,
        authzVersions: true,
        // The access token hook asks better_supabase.hook_plan(event) how
        // much to read: nothing for an OAuth client token, and no membership
        // reads for a refresh whose authz_ver is still current (ADR 0521).
        hook: { oauth: "slim" },
        bootstrap: {
          islands: {
            function: "public.island_counts",
            tables: ["customers", "notes", "contacts", "tags", "tasks"],
          },
          // The page shell in one call: organizations, profile, the pending
          // approvals count and the compact permissions (ADR 1232).
          shell: {
            function: "public.shell_bootstrap",
            tables: ["organizations", "memberships", "profiles", "approvals"],
          },
        },
      },
    },
    "sso",
    {
      block: "approvals",
      options: {
        // Organizations tighten these policies with their own (ADR 0119).
        tenantPolicies: true,
        policies: {
          // One floor for an action on every subject type that files it.
          "*": { "quote.send": { steps: [], effects: ["money-movement"] } },
          customer: {
            discount: {
              steps: [
                { approvers: { permission: "approvals.manage" }, required: 1 },
              ],
              selfApproval: true,
            },
            // A floor that asks for nothing until a tenant policy adds steps.
            refund: { steps: [] },
            // The requester confirms; their manager may approve as well.
            export: {
              mode: "confirm",
              steps: [{ approvers: { manager: true } }],
            },
          },
          // A floor that asks for nothing until a tenant policy adds steps: a
          // case then can't close before a request to close is approved.
          case: { close: { steps: [] } },
          // Sign-off on one version of a drive file, from the file's menu.
          drive_node: {
            approve: {
              steps: [
                { approvers: { permission: "approvals.manage" }, required: 1 },
              ],
              selfApproval: true,
            },
            // Two approvers release a controlled document's new version.
            release: {
              steps: [
                { approvers: { permission: "approvals.manage" }, required: 2 },
              ],
            },
          },
          // Tool calls of the eve example's agent (`approvalPolicy`), one action
          // per tool; the request's subject is the call id.
          eve_tool_call: {
            add_note: {
              steps: [
                { approvers: { permission: "approvals.manage" }, required: 1 },
              ],
            },
          },
          // Approval nodes of a builder graph; the request's subject is the run key.
          workflow_run: {
            approve: {
              steps: [
                { approvers: { permission: "approvals.manage" }, required: 1 },
              ],
              selfApproval: true,
            },
          },
        },
      },
    },
    "access-requests",
    "grants",
    "subjects",
    "reactions",
    // Forum and feedback boards behind /community (ADR 0092).
    "posts",
    "share-links",
    // The example runs no malware scanner, so uploads are readable at once.
    { block: "attachments", options: { requireScan: false } },
    "waitlist",
    // Teams can be renamed and restored from the trash in the app.
    { block: "teams", options: { patch: true, restore: true } },
    {
      block: "contacts",
      names: {
        // Search finds a company by its website as well as its domain, and a
        // person by phone as well as email (EX-101).
        company: {
          url: "/crm/contacts/{id}",
          search: { title: "name", body: ["domain", "website"] },
        },
        person: {
          url: "/crm/contacts/{id}",
          search: { title: "name", body: ["email", "phone", "title"] },
        },
      },
    },
    "pipelines",
    { block: "deals", names: { deal: { url: "/crm/deals" } } },
    // Call recordings on ai-files, with transcripts and notes. Confirmed
    // bookings show up as meetings on the booker's contact.
    { block: "activities", options: { recordings: true, bookings: true } },
    // A rejected, withdrawn or expired quote is sent again in one call.
    {
      block: "quotes",
      options: { resend: true },
      names: { quote: { url: "/crm/quotes/{id}" } },
    },
    "goals",
    {
      block: "state-machine",
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
          // Stages, their order and the moves between them come from the
          // tenant's published `change-requests` workflow.
          change_request: { column: "status", workflow: "change-requests" },
        },
      },
    },
    "rank",
    // The app already has `projects` and `saved_views` tables (appTables), and
    // its own `tasks` table is the `task` subject, so the block keeps the
    // work_item noun.
    {
      block: "tasks",
      tables: { projects: "work_projects" },
      names: {
        task: { name: "work_item", url: "/work" },
        // The app table `public.projects` is already the `project` subject.
        project: { name: "work_project" },
      },
    },
    // A second tasks instance: maintenance requests on leased units. It
    // renames project because a record type can't be shared, and it keeps
    // no project or iteration table.
    {
      name: "facilities",
      block: "tasks",
      names: { task: "maintenance_request", project: "maintenance_project" },
      tables: { projects: null, iterations: null },
      options: { prefix: "MR" },
    },
    { block: "saved-views", tables: { views: "shared_views" } },
    "sla",
    // Encrypted definitions and sensitive values are audited when read.
    { block: "custom-fields", options: { auditReads: true } },
    // `work.setState` writes through a definer function: bulk rows run as the
    // caller, and the work items table is read-only for `authenticated`.
    {
      block: "bulk-actions",
      options: { actions: { "work.setState": "public.work_bulk_state" } },
    },
    "trash",
    "relations",
    { block: "employees", names: { employee: { url: "/people/{id}" } } },
    "hiring",
    // Time off behind /people/leave: types, requests approved through the
    // approvals block, and balances on the ledger.
    "leave",
    // Time is logged on companies and projects only.
    { block: "time-entries", options: { on: ["company", "project"] } },
    {
      block: "invoices",
      names: { invoice: { url: "/finance/payables" } },
      // Fixed deposit invoices and a discount on the invoice header.
      columns: {
        invoices: {
          archivedAt: { column: "archived_at", required: true },
          depositAmount: { column: "deposit_amount", required: true },
          discountBps: { column: "discount_bps", required: true },
          discountAmount: { column: "discount_amount", required: true },
        },
      },
    },
    { block: "catalog", names: { product: { url: "/shop" } } },
    "inventory",
    // Requests for quotation to suppliers; an award creates the purchase order.
    { block: "rfqs", names: { rfq: { url: "/rfqs" } } },
    // Till sessions, cash drawers and end-of-day counts that post to accounting.
    { block: "tills", names: { till: { url: "/tills" } } },
    // Fiscal periods and leave years close through one protocol.
    "periods",
    // Due dates computed from approved rule sets, with a citation.
    "deadlines",
    // Commission plans and entries per sales rep, and referral codes with rewards.
    "commissions",
    "referrals",
    // The kitchen display and order board under /shop/kitchen.
    {
      block: "orders",
      options: { kitchen: true },
      names: { order: { url: "/shop/orders/{id}" } },
    },
    "promotions",
    "calendar",
    // Weekly or daily rules book a series one occurrence at a time.
    {
      block: "bookings",
      options: { recurring: true },
      names: { booking: { url: "/calendar" } },
    },
    // Points and areas use PostGIS geography columns (ADR 0066).
    { block: "assets", options: { postgis: true } },
    "guests",
    // Class bookings paid for with pass credits.
    { block: "passes", options: { credits: true } },
    "billable-time",
    "leases",
    "expenses",
    "donations",
    // Product reviews with pre-moderation, public replies and a rating summary.
    "reviews",
    "collections",
    "warranty",
    "agent-checkout",
    { block: "dispatch", names: { work_order: { url: "/field/dispatch" } } },
    { block: "shipments", names: { shipment: { url: "/field/shipments" } } },
    // Contracts send for signature with signatures and remind owners of the
    // notice deadline with reminders; controls publish policies as versions.
    "signatures",
    "contracts",
    "compliance",
    // Certifications and licences members, companies and assets hold, with
    // a gap report; courses grant them with their certificates.
    "qualifications",
    // Risks link their barriers to controls and snapshot assessments as
    // versions.
    "risks",
    // Nonconformities, complaints, incidents and more, each on its kind's
    // pipeline, with actions as work items and a close guard.
    "cases",
    // Audit programmes and inspections with a checklist; findings assess
    // controls and raise cases. Planned inspections mirror to the "Audits"
    // calendar of an organization that has one.
    { block: "inspections", options: { calendar: "Audits" } },
    // Meetings with an agenda, minutes, votes on decisions and action items
    // that open as tasks; planned meetings mirror to the "Meetings" calendar.
    {
      block: "meetings",
      options: { calendar: "Meetings" },
      uses: { tasks: "tasks" },
    },
    // Preventive plans by time or meter that open dispatch work orders with
    // their spare parts, plus meter readings and calibrations.
    {
      block: "maintenance",
      names: { maintenance_plan: { url: "/maintenance" } },
    },
    // Renditions of drive files and usage rights with a territory, a channel
    // and an expiry date.
    "dam",
    // Laboratory samples tested against specification limits; an out of
    // specification result opens a nonconformity case, and instruments are
    // assets whose "calibration" qualification must be valid on the test date.
    {
      block: "lims",
      options: { instrumentQualification: "calibration" },
      names: { lims_sample: { url: "/lims" } },
    },
    // Review cycles with self, peer and manager reviews, calibration sessions
    // and sign-off through approvals.
    "appraisals",
    // Pick waves and pick lists made from inventory allocations, with cycle
    // count plans that hold large variances for review.
    "warehouse",
    // Vital signs on a customer's record, with the seeded vitals definitions;
    // a critical value alerts the record's leads.
    { block: "observations", options: { defaults: "vitals" } },
    // Rosters: shifts from templates, assignments checked for leave,
    // qualifications and rest time, open shift requests and swaps.
    "shifts",
    // Double-entry books with a chart, journals, periods and reports.
    "accounting",
    { block: "ledger", names: { ledger_account: { url: "/finance" } } },
    // Bills of materials on work centers, production orders that consume and
    // receive stock through inventory, lot genealogy and material requirements.
    "manufacturing",
    // Bank accounts with imported statements, matched to invoices and booked
    // through the accounting journals; rules book recurring lines.
    "banking",
    // Several companies in one organization with one default; null means the
    // default entity on the tables listed here.
    {
      block: "legal-entities",
      options: {
        on: [
          "invoices",
          "quotes",
          "orders",
          "numbering",
          "accounting",
          "inventory_locations",
          "settings",
        ],
      },
    },
    // Templates per legal entity and language for invoices, quotes and other
    // documents, reusable text blocks and a render call that freezes issued
    // invoices.
    "document-templates",
    // Funded care: products a funder pays per unit, awards per customer,
    // deliveries from approved time and claims the funder answers per line.
    "funding",
    // Payroll runs add up the worked and leave hours of a period for the
    // payroll provider, rendered by a pluggable file format.
    "payroll-export",
    // Members acknowledge the current version of each policy they are
    // assigned, directly, through a team or through their role.
    {
      block: "acknowledgements",
      on: {
        compliance_policy: {
          table: "better_supabase.compliance_policies",
          idType: "uuid",
          tenant: "tenant_id",
          versionColumn: "current_version_id",
        },
        // Controlled documents: members acknowledge each released version.
        drive_node: {},
      },
    },
    // Consent per customer and purpose, backed by a signature or a form.
    "consents",
    // Medication charts on customers: orders with a dose and schedule,
    // planned doses recorded as given or refused, missed doses notified and
    // opened as incident cases.
    {
      block: "medications",
      options: { missedCaseKind: "incident", guestRead: true },
    },
    // Care plans keep each customer's problems, goals and actions; a
    // restrictive measure waits for an approval before it starts.
    { block: "care-plans", names: { care_plan: { url: "/care-plans" } } },
    // Dose range, duplicate therapy and interaction alerts over medication orders.
    "clinical-decision-support",
    "e-prescribing",
    "incidents",
    "reminders",
    // Security advisories for the example's own software: products, versions,
    // vulnerabilities and published CSAF and OpenVEX documents (ADR 0188).
    "advisories",
    // mfa_satisfied() for restrictive policies, with the factor setup on
    // /settings/security.
    "mfa",
    // Email and chat identities linked to app users by a one-time code.
    "identities",
    // Time-limited, approved, read-only support sessions at /settings/support.
    "impersonation",
    // Vercel Marketplace provider state, read at /settings/integrations/vercel.
    "vercel-marketplace",
    "drive-files",
    // Contributors add files to a shared folder without seeing what's in it.
    // Controlled documents get a number, an approved effective version and a
    // yearly review; readers below the editor role see only that version.
    {
      block: "drive",
      options: {
        uploadRole: "contributor",
        control: {
          types: [{ name: "sop", numberFormat: "SOP-{n:4}" }, "policy", "form"],
          reviewMonths: 12,
        },
      },
    },
    { block: "versions", on: { customer: { columns: ["name", "kvk"] } } },
    // Pages and posts with locales and scheduled publish, read by anon.
    "content",
    "jsonb-schemas",
    { block: "forms", names: { form: { url: "/forms/{id}" } } },
    // An import target the pgTAP tests drive; real apps point one at each
    // table their source system fills.
    {
      block: "imports",
      options: {
        targets: {
          customer: {
            subjectType: "customer",
            write: "public.import_customer",
            batch: "public.import_customer_batch",
            updatedAt: "public.import_customer_updated_at",
          },
          // The same table through the one-row target, so the pgTAP parity test
          // can compare the two write paths.
          customer_row: {
            subjectType: "customer",
            write: "public.import_customer",
            updatedAt: "public.import_customer_updated_at",
          },
        },
        // An import run fires no event unless listed, and audits one entry
        // per entity instead of one per row (ADR 0141).
        events: { "customer.imported": "tag", "customer.synced": "emit" },
        audit: "summary",
      },
    },
    // Brand starters reach the organizations whose `brand` matches.
    {
      block: "templates",
      options: { brand: { table: "public.organizations", column: "brand" } },
    },
    { block: "documents", names: { document: { url: "/documents/{id}" } } },
    "webhooks",
    "outbox",
    "service-accounts",
    "signing-keys",
    // Per-tenant data keys in Vault for encrypted columns and custom fields.
    // client_notes seals its columns in its own trigger, so key rotation
    // needs it listed.
    {
      block: "field-encryption",
      options: {
        sealed: [
          {
            table: "public.client_notes",
            columns: ["diagnosis", "birth_date"],
            owner: "tenant",
          },
        ],
      },
    },
    // Exports leave out token, hash and secret columns (doctor BS341).
    { block: "data-lifecycle", options: { omitPattern: true } },
    "reserved-slugs",
    "idempotency",
    "webhook-inbox",
    "incoming-webhooks",
    "security-events",
    "domains",
    "housekeeping",
    "option-sets",
    "billing",
  ],

  // A table the provider does not declare. The select policy returns the
  // organizations a member belongs to, so two holders of the same grant do not
  // read the same rows. Share it per row. RLS still checks the read (ADR 1267).
  shares: {
    tables: {
      "public.organizations": {
        share: "row",
        permissions: ["organizations.read"],
      },
    },
  },
});
