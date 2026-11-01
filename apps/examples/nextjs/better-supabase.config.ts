import { driveSubject } from "better-supabase/blocks/drive";
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
      plans: ["select"],
      plan_features: ["select"],
      subscriptions: ["select"],
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
    casing: "camel",
    codecs: { int8: "bigint" },
    output: "src/lib/supabase/generated.ts",
    // Rows store the object path; URLs are built when rendering.
    storagePaths: { "customers.logo_path": "customerLogos" },
    readSets: ["src/lib/read-sets.ts"],
    hooks: "react",
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
  subjects: {
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
      search: {},
    },
    // Members ask for read access to a file or folder they cannot open.
    drive_node: driveSubject({ accessRequests: true }),
    application: {
      table: "better_supabase.applications",
      idType: "uuid",
      tenant: "tenant_id",
      url: "/people/hiring",
      permissions: { read: "hiring.read", write: "hiring.write" },
      rank: { column: "rank", group: "stage_id" },
    },
  },
  blocks: {
    "updated-at": { api: false },
    "read-sets": { api: false },
    "realtime-tables": { api: false },
    "rate-limit": { api: false },
    "vector-search": { api: false },
    // The block runs over the fixture's own `public.memberships` table
    // (ADR 0098); its `role` column references the catalog's roles.
    memberships: { api: false, tables: { memberships: "public.memberships" } },
    // Roles, permission keys and their links are rows in the catalog tables
    // (seeded by a data migration), and admins override a role's keys per
    // organization in `permission_overrides`. switch_organization writes
    // app_metadata.tenant_id; the token hook copies it into the access token.
    permissions: { model: "catalog", activeTenant: "claim" },
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
    // Conversations and messages under the channels block (ADR 0062).
    messaging: {},
    channels: {},
    // The record history the customer page shows, moved out of comments.
    timeline: {},
    // Members' Gmail and Outlook mail, linked to parties and logged as
    // email engagements.
    "mail-sync": {},
    // Saved filters over companies and deals, refreshed on a schedule.
    segments: {},
    // Round robin and weighted queues that pick an owner for new records.
    assignment: {},
    // Company and person data from an enrichment provider, one result each.
    enrichment: {},
    // The forecast call by period, snapshotted so a review compares weeks.
    forecasts: {},
    // Old and new values of a deal's amount, stage, owner and close date,
    // and a company's owner and lifecycle stage.
    "field-history": {
      on: {
        deal: {
          fields: ["amount", "stage_id", "owner_user_id", "expected_close_on"],
        },
        company: { fields: ["owner_user_id", "lifecycle"] },
      },
    },
    // Tags on customers, edited with the tag input on the customer page. The
    // fixture's `public.tags` and `customer_tags` tables are separate seed
    // data that no example renders.
    tags: {},
    organizations: {
      tables: { organizations: "public.organizations" },
      columns: {
        organizations: { createdBy: null, deletedAt: null, disabledAt: null },
      },
    },
    invitations: {},
    profiles: {},
    flags: {},
    announcements: {},
    // Onboarding checklists run on enrollments (ADR 0077).
    enrollments: {},
    // Courses behind /courses: each learner's progress is an enrollment.
    courses: {},
    // Outreach sequences behind /crm/sequences: each recipient's run is an
    // enrollment, and email steps send through mail-sync (ADR 0091).
    sequences: {},
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
    "workflow-sdk": { api: false },
    // Workflows tenants build on a canvas at /workflows/builder.
    "workflow-editor": {},
    // Tenant rules for expenses, edited with the rule builder at /rules.
    automations: {},
    // Lead scoring and account health are score models over parties (ADR 0067).
    scores: {},
    // People scored under the "lead" model, again when their segments, mail
    // or enrichment change.
    "lead-scoring": {},
    // Comment reports, the review queue and bans (ADR 0076).
    moderation: {},
    // Vault-backed secrets behind the builder's credential references.
    credentials: {},
    // The support inbox behind /inbox and the Help sheet: jobs carry bot
    // turns and channel replies, streams hold the bot's resumable output.
    queue: { api: false },
    streams: {},
    inbox: {},
    "chat-sdk-state": { api: false },
    // The /assistant sample: chats in `ai-chat` on private Realtime topics,
    // resumable answers in `streams` and attachments in `ai-files`.
    // /knowledge ingests documents into `knowledge` for the assistant's
    // search tool, and `memory` keeps what it remembers. /agents builds and
    // installs assistants (`agents`), `connectors` holds the MCP servers they
    // call and `ai-schedules` their schedules.
    "ai-chat": {},
    "ai-files": {},
    knowledge: {},
    memory: {},
    agents: {},
    connectors: {},
    "ai-schedules": {},
    // Device push tokens for the Expo example's push registration.
    push: {},
    // The assistant answers with each organization's own provider keys
    // (`ai-keys`), and `ai-cache` keeps repeated model calls.
    "ai-cache": {},
    "ai-keys": {},
    // The blocks behind the remaining UI recipes (`/recipes`), one page or
    // card each in the app.
    // Ending a session on /settings/sessions cuts its access at once: every
    // app table gets the restrictive session_active() policy. A role change
    // bumps the user's authorization version, which SessionProvider hears on
    // authz:<uid> and refreshes the token for. `bootstrap` renders
    // better_supabase.bootstrap_islands, which /islands reads in one query.
    sessions: {
      options: {
        policies: true,
        authzVersions: true,
        bootstrap: { islands: "public.island_counts" },
      },
    },
    sso: {},
    approvals: {
      options: {
        // Organizations tighten these policies with their own (ADR 0119).
        tenantPolicies: true,
        // A description per organization policy, written through `fields`.
        policyExtraColumns: { description: "text" },
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
    "access-requests": {},
    grants: {},
    subjects: {},
    reactions: {},
    // Forum and feedback boards behind /community (ADR 0092).
    posts: {},
    "share-links": {},
    // The example runs no malware scanner, so uploads are readable at once.
    attachments: { options: { requireScan: false } },
    waitlist: {},
    // Teams can be renamed and restored from the trash in the app.
    teams: { options: { patch: true, restore: true } },
    contacts: {
      names: {
        company: { url: "/crm/contacts/{id}" },
        person: { url: "/crm/contacts/{id}" },
      },
    },
    pipelines: {},
    deals: { names: { deal: { url: "/crm/deals" } } },
    // Call recordings on ai-files, with transcripts and notes. Confirmed
    // bookings show up as meetings on the booker's contact.
    activities: { options: { recordings: true, bookings: true } },
    // A rejected, withdrawn or expired quote is sent again in one call.
    quotes: { options: { resend: true } },
    goals: {},
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
          // Stages, their order and the moves between them come from the
          // tenant's published `change-requests` workflow.
          change_request: { column: "status", workflow: "change-requests" },
        },
      },
    },
    rank: {},
    // The app already has `projects` and `saved_views` tables (appTables), and
    // its own `tasks` table is the `task` subject, so the block keeps the
    // work_item noun.
    tasks: {
      tables: { projects: "work_projects" },
      names: { task: { name: "work_item", url: "/work" } },
    },
    // A second tasks instance: maintenance requests on leased units.
    facilities: {
      block: "tasks",
      names: { task: "maintenance_request" },
      tables: { projects: null, iterations: null },
      options: {
        prefix: "MR",
        extraColumns: { unit_id: "uuid", lease_id: "uuid" },
      },
    },
    "saved-views": { tables: { views: "shared_views" } },
    sla: {},
    // Encrypted definitions and sensitive values are audited when read.
    "custom-fields": { options: { auditReads: true } },
    bulk: {},
    trash: {},
    relations: {},
    employees: { names: { employee: { url: "/people" } } },
    hiring: {},
    "time-tracking": {},
    // Fixed deposit invoices and a discount on the invoice header.
    invoices: {
      columns: {
        invoices: {
          depositAmount: "deposit_amount",
          discountBps: "discount_bps",
          discountAmount: "discount_amount",
        },
      },
    },
    catalog: { names: { product: { url: "/shop" } } },
    inventory: {},
    // Requests for quotation to suppliers; an award creates the purchase order.
    rfqs: {},
    // Till sessions, cash drawers and end-of-day counts that post to accounting.
    tills: {},
    // The kitchen display and order board under /shop/kitchen.
    orders: { options: { kitchen: true } },
    promotions: {},
    calendar: {},
    // Weekly or daily rules book a series one occurrence at a time.
    bookings: { options: { recurring: true } },
    // Points and areas use PostGIS geography columns (ADR 0066).
    assets: { options: { postgis: true } },
    guests: {},
    // Class bookings paid for with pass credits.
    passes: { options: { credits: true } },
    "billable-time": {},
    leases: {},
    expenses: {},
    donations: {},
    dispatch: {},
    shipments: {},
    // Contracts send for signature with signatures and remind owners of the
    // notice deadline with reminders; controls publish policies as versions.
    signatures: {},
    contracts: {},
    compliance: {},
    // Certifications and licences members, companies and assets hold, with
    // a gap report; courses grant them with their certificates.
    qualifications: {},
    // Risks link their barriers to controls and snapshot assessments as
    // versions.
    risks: {},
    // Nonconformities, complaints, incidents and more, each on its kind's
    // pipeline, with actions as work items and a close guard.
    cases: {},
    // Audit programmes and inspections with a checklist; findings assess
    // controls and raise cases. Planned inspections mirror to the "Audits"
    // calendar of an organization that has one.
    inspections: { options: { calendar: "Audits" } },
    // Meetings with an agenda, minutes, votes on decisions and action items
    // that open as tasks; planned meetings mirror to the "Meetings" calendar.
    meetings: {
      options: { calendar: "Meetings", extraColumns: { room_code: "text" } },
      uses: { tasks: "tasks" },
    },
    // Preventive plans by time or meter that open dispatch work orders with
    // their spare parts, plus meter readings and calibrations.
    maintenance: {},
    // Renditions of drive files and usage rights with a territory, a channel
    // and an expiry date.
    dam: {},
    // Laboratory samples tested against specification limits; an out of
    // specification result opens a nonconformity case, and instruments are
    // assets whose "calibration" qualification must be valid on the test date.
    lims: { options: { instrumentQualification: "calibration" } },
    // Review cycles with self, peer and manager reviews, calibration sessions
    // and sign-off through approvals.
    appraisals: {},
    // Pick waves and pick lists made from inventory allocations, with cycle
    // count plans that hold large variances for review.
    warehouse: {},
    // Vital signs on a customer's record, with the seeded vitals definitions;
    // a critical value alerts the record's leads.
    observations: { options: { defaults: "vitals" } },
    // Rosters: shifts from templates, assignments checked for leave,
    // qualifications and rest time, open shift requests and swaps.
    shifts: {},
    // Double-entry books with a chart, journals, periods and reports.
    accounting: {},
    // Bills of materials on work centers, production orders that consume and
    // receive stock through inventory, lot genealogy and material requirements.
    manufacturing: {},
    // Bank accounts with imported statements, matched to invoices and booked
    // through the accounting journals; rules book recurring lines.
    banking: {},
    // Several companies in one organization with one default; null means the
    // default entity on the tables listed here.
    "legal-entities": {
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
    "document-templates": {},
    // Funded care: products a funder pays per unit, awards per customer,
    // deliveries from approved time and claims the funder answers per line.
    funding: {},
    // Payroll runs add up the worked and leave hours of a period for the
    // payroll provider, rendered by a pluggable file format.
    "payroll-export": {},
    // Members acknowledge the current version of each policy they are
    // assigned, directly, through a team or through their role.
    acknowledgements: {
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
    consents: {},
    // Medication charts on customers: orders with a dose and schedule,
    // planned doses recorded as given or refused, missed doses notified and
    // opened as incident cases.
    medications: { options: { missedCaseKind: "incident", guestRead: true } },
    // Care plans keep each customer's problems, goals and actions; a
    // restrictive measure waits for an approval before it starts.
    "care-plans": {},
    // Dose range, duplicate therapy and interaction alerts over medication orders.
    "clinical-decision-support": {},
    incidents: {},
    reminders: {},
    "drive-files": {},
    // Contributors add files to a shared folder without seeing what's in it.
    // Controlled documents get a number, an approved effective version and a
    // yearly review; readers below the editor role see only that version.
    drive: {
      options: {
        uploadRole: "contributor",
        control: {
          types: [{ name: "sop", numberFormat: "SOP-{n:4}" }, "policy", "form"],
          reviewMonths: 12,
        },
      },
    },
    versions: { on: { customer: { columns: ["name", "kvk"] } } },
    // Pages and posts with locales and scheduled publish, read by anon.
    content: {},
    "jsonb-schemas": {},
    forms: {},
    // An import target the pgTAP tests drive; real apps point one at each
    // table their source system fills.
    imports: {
      options: {
        targets: {
          customer: {
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
    templates: {
      options: { brand: { table: "public.organizations", column: "brand" } },
    },
    documents: {},
    "webhooks-out": {},
    outbox: {},
    "service-accounts": {},
    "signing-keys": {},
    // Per-tenant data keys in Vault for encrypted columns and custom fields.
    "field-encryption": {},
    // Exports leave out token, hash and secret columns (doctor BS341).
    "data-lifecycle": { options: { omitPattern: true } },
  },
});
