import type { Preset, PresetInstance } from "./fields.ts";

/** Tasks named for support work: tickets grouped under issues. */
export const TICKETS: NonNullable<Preset["instances"]> = {
  tasks: { names: { task: "ticket", project: "issue" } },
};

/** Attachments served by public URL, for media such as images on a site. */
export const PUBLIC_MEDIA: NonNullable<Preset["instances"]> = {
  attachments: {
    options: { publicBuckets: ["attachments"], requireScan: false },
  },
};

/**
 * The quality blocks behind `qms` and `ehs`: cases, audits, risks and
 * qualifications on the work, people and document blocks they link through.
 */
export const QUALITY: readonly string[] = [
  "drive",
  "attachments",
  "versions",
  "signatures",
  "approvals",
  "state-machine",
  "numbering",
  "pipelines",
  "tasks",
  "forms",
  "relations",
  "compliance",
  "acknowledgements",
  "cases",
  "inspections",
  "meetings",
  "maintenance",
  "appraisals",
  "risks",
  "qualifications",
  "courses",
  "enrollments",
  "employees",
  "contacts",
  "assets",
  "metrics",
];

/** One approval by a holder of `approvals.manage` releases a document. */
const DOCUMENT_RELEASE: PresetInstance = {
  options: {
    policies: {
      drive_node: {
        release: {
          steps: [
            { approvers: { permission: "approvals.manage" }, required: 1 },
          ],
        },
      },
    },
  },
};

/** Controlled documents in the drive, released by one approval. */
export const CONTROLLED_DOCUMENTS: NonNullable<Preset["instances"]> = {
  drive: {
    options: {
      control: {
        types: ["manual", "policy", "procedure", "work_instruction", "form"],
      },
    },
  },
  approvals: DOCUMENT_RELEASE,
};

/**
 * The ERP blocks behind `erp` and `manufacturing`: sales, purchasing, stock,
 * people and the books they post to.
 */
export const ERP: readonly string[] = [
  "legal-entities",
  "tax",
  "imports",
  "custom-fields",
  "attachments",
  "document-templates",
  "contacts",
  "catalog",
  "inventory",
  "assets",
  "quotes",
  "orders",
  "invoices",
  "numbering",
  "accounting",
  "banking",
  "approvals",
  "employees",
  "time-tracking",
  "leave",
  "expenses",
  "saved-views",
  "automations",
];

/** Accepted quotes become orders. */
export const QUOTE_TO_ORDER: NonNullable<Preset["instances"]> = {
  automations: { options: { enable: ["quotes.quote_to_order"] } },
};

/**
 * The blocks behind `care`: the client record, its team and read log, the
 * clinical blocks on it, and the people, funding and quality blocks around it.
 */
export const CARE: readonly string[] = [
  "contacts",
  "guests",
  "field-encryption",
  "data-lifecycle",
  "consents",
  "activities",
  "care-plans",
  "observations",
  "medications",
  "forms",
  "bookings",
  "calendar",
  "reminders",
  "time-tracking",
  "funding",
  "shifts",
  "qualifications",
  "courses",
  "cases",
  "acknowledgements",
  "drive",
  "attachments",
  "versions",
  "approvals",
  "state-machine",
  "numbering",
  "signatures",
];

/**
 * Clients are contacts' persons: their record team reads and edits them, and
 * every read lands in the audit log. Missed doses open client incidents, and
 * protocols are released through one approval.
 */
export const CARE_SETTINGS: NonNullable<Preset["instances"]> = {
  contacts: {
    subjects: {
      person: { auditReads: true, team: { actions: ["read", "write"] } },
    },
  },
  observations: { options: { defaults: "vitals" } },
  medications: { options: { missedCaseKind: "incident" } },
  cases: {
    options: {
      kinds: [
        { key: "incident", name: "Client incident", prefix: "INC" },
        { key: "employee_incident", name: "Employee incident", prefix: "EINC" },
        { key: "complaint", name: "Complaint", prefix: "CMP" },
      ],
    },
  },
  drive: {
    options: {
      control: {
        types: ["protocol", "policy", "procedure", "work_instruction", "form"],
      },
    },
  },
  approvals: DOCUMENT_RELEASE,
};

export const SAAS: readonly string[] = [
  "organizations",
  "invitations",
  "teams",
  "profiles",
  "billing",
  "entitlements",
  "notifications",
  "audit",
  "api-keys",
  "settings",
  "onboarding",
  "outbox",
];
