import { LEGACY_OPTION } from "./legacy-option-key.ts";

export { LEGACY_OPTION };

/** The table a block's `extraColumns` option added its columns to. */
const EXTRA_COLUMNS_TABLE: Readonly<Record<string, string>> = {
  invitations: "invitations",
  "webhook-inbox": "messages",
  organizations: "organizations",
  profiles: "profiles",
  notifications: "events",
  "api-keys": "keys",
  flags: "flags",
  attachments: "attachments",
  waitlist: "entries",
  announcements: "announcements",
  "workflow-editor": "definitions",
  "ai-chat": "chats",
  "ai-files": "files",
  agents: "agents",
  connectors: "servers",
  "ai-schedules": "tasks",
  push: "devices",
  teams: "teams",
  tags: "tags",
  "share-links": "links",
  reminders: "reminders",
  "saved-views": "views",
  relations: "relations",
  calendar: "events",
  bookings: "bookings",
  versions: "versions",
  trash: "items",
  approvals: "requests",
  "access-requests": "requests",
  catalog: "products",
  inventory: "locations",
  drive: "nodes",
  orders: "orders",
  promotions: "promotions",
  forms: "forms",
  signatures: "requests",
  "time-entries": "entries",
  "service-accounts": "principals",
  templates: "templates",
  pipelines: "pipelines",
  contacts: "companies",
  activities: "activities",
  deals: "deals",
  tasks: "items",
  quotes: "quotes",
  invoices: "invoices",
  sla: "policies",
  goals: "targets",
  hiring: "jobs",
  employees: "employees",
  collections: "collections",
  reviews: "reviews",
  leave: "requests",
  leases: "leases",
  expenses: "reports",
  donations: "donations",
  dispatch: "workOrders",
  shipments: "shipments",
  contracts: "contracts",
  compliance: "controls",
  incidents: "incidents",
  courses: "courses",
  messaging: "messages",
  posts: "posts",
  qualifications: "qualifications",
  risks: "risks",
  shifts: "shifts",
  accounting: "entries",
  observations: "observations",
  medications: "orders",
  "care-plans": "plans",
  cases: "cases",
  inspections: "inspections",
  manufacturing: "orders",
  banking: "accounts",
  meetings: "meetings",
  funding: "awards",
};

/** The table each prefixed `<name>ExtraColumns` option added its columns to. */
const PREFIXED_TABLE: Readonly<Record<string, string>> = {
  project: "projects",
  participant: "participants",
  message: "messages",
  run: "runs",
  approval: "approvals",
  policy: "policies",
  input: "inputs",
  source: "sources",
  feedback: "feedback",
  share: "shares",
  model: "models",
  moderation: "moderation",
  step: "steps",
  sandbox: "sandboxes",
  harness: "harness",
  calendar: "calendars",
  variant: "variants",
  category: "categories",
  privateDetails: "privateDetails",
  contract: "contracts",
  application: "applications",
  charge: "charges",
  medication: "medications",
  administration: "administrations",
  versionLine: "versionLines",
  line: "lines",
};

/**
 * The logical tables the legacy option `key` of `block` may have added columns
 * to, most likely first: the expenses block adds them to its expenses table
 * when it has no reports table. Empty for a key this release never had.
 */
export function legacyOptionTables(
  block: string,
  key: string,
): readonly string[] {
  if (key === "extraColumns") {
    const table = EXTRA_COLUMNS_TABLE[block];

    if (table === undefined) {
      return [];
    }

    return block === "expenses" ? [table, "expenses"] : [table];
  }

  const table = PREFIXED_TABLE[key.replace(/ExtraColumns$/, "")];

  return table === undefined ? [] : [table];
}

/**
 * The first table of `legacyOptionTables(block, key)` the project has: one that
 * `tables` maps to `null` or that `resolve` can't name is skipped.
 */
export function legacyOptionTarget(
  block: string,
  key: string,
  tables: Readonly<Record<string, string | null | undefined>> | undefined,
  resolve: (logical: string) => {
    readonly schema: string;
    readonly name: string;
  },
): { readonly logical: string; readonly table: string } | undefined {
  for (const logical of legacyOptionTables(block, key)) {
    if (tables?.[logical] === null) {
      continue;
    }

    try {
      const { schema, name } = resolve(logical);

      return { logical, table: `${schema}.${name}` };
    } catch {
      // The block has no such table in this project; try the next.
    }
  }

  return undefined;
}

/**
 * `invoices.options.uniqueNumber` is gone: the table is unique on (tenant,
 * direction, kind, identifier or number) in every project.
 */
const UNIQUE_NUMBER_REMOVED =
  "was removed: the invoices table is unique on tenant, direction, kind and identifier (or number), whatever the option said. Delete the option. If numbers repeat inside a kind, give each invoice a distinct `identifier` or renumber the duplicates before you apply the migration (see the 0.57 to 0.58 guide for a query that finds them).";

/** What an option the module doesn't declare is told: the codemod, or the list. */
export function unknownOptionMessage(
  where: string,
  key: string,
  declared: ReadonlySet<string>,
): string {
  if (key === "uniqueNumber" && where.endsWith("invoices")) {
    return `${where}.options.uniqueNumber ${UNIQUE_NUMBER_REMOVED}`;
  }

  return LEGACY_OPTION.test(key)
    ? `${where}.options.${key} was removed: write the column in your schema files. Run \`better-supabase codemod extra-columns\` to move it.`
    : `${where}.options: unknown option "${key}". Options: ${[...declared].join(", ") || "none"}`;
}
