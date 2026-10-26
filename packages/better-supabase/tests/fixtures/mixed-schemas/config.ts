import type { ResolveInput, BlocksConfig } from "../../../src/config/index.ts";

/** The blocks the fixture installs, the first five with their defaults. */
export const MIXED_SCHEMAS_BLOCKS: BlocksConfig = {
  "updated-at": {},
  memberships: {},
  permissions: {},
  subjects: {},
  ledger: {},
  organizations: { tables: { organizations: "public.organizations" } },
  invoices: {
    tables: { invoices: "public.invoices" },
    columns: { invoices: { tenant: "organization_id" } },
  },
  contacts: {
    tables: { people: "public.contacts" },
    columns: { people: { tenant: "organization_id" } },
  },
};

/**
 * An app with its own declarative schema: it creates organizations, invoices
 * (with an enum status), contacts and notes. The blocks run over the first
 * three and create the rest, and `tables.notes` enriches the app's notes.
 */
export const MIXED_SCHEMAS_CONFIG: ResolveInput = {
  blocks: MIXED_SCHEMAS_BLOCKS,
  appTables: { notes: { columns: { body: { type: "text" } } } },
};
