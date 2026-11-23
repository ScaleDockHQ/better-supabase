import type { Schema } from "better-supabase";

import { createSupabase, defineSchema } from "better-supabase";

// The two CentraKit tables the service test reads, written out by hand: the
// fixture has no generated client, and `gen` output for these would match.
interface CustomerRow {
  id: string;
  organizationId: string;
  companyName: string;
  status: string;
}

interface OrganizationUserRow {
  userId: string;
  organizationId: string;
  roleId: string;
}

export type Models = {
  customers: {
    Row: CustomerRow;
    Insert: Omit<CustomerRow, "id">;
    Update: Partial<Omit<CustomerRow, "id">>;
    Relations: Record<never, never>;
    PrimaryKey: "id";
    UniqueKeys: Record<never, never>;
    Flags: { tenant: "organizationId" };
  };
  organizationUsers: {
    Row: OrganizationUserRow;
    Insert: OrganizationUserRow;
    Update: Partial<OrganizationUserRow>;
    Relations: Record<never, never>;
    PrimaryKey: never;
    UniqueKeys: Record<never, never>;
    Flags: { tenant: "organizationId" };
  };
};

export const schema: Schema<Models> = defineSchema<Models>({
  version: 1,
  casing: "camel",
  tables: {
    customers: {
      key: "customers",
      name: "customers",
      schema: "centrakit",
      kind: "table",
      columns: {
        id: { db: "id", type: "int8", hasDefault: true, generated: true },
        organizationId: { db: "organization_id", type: "uuid" },
        companyName: { db: "company_name", type: "text" },
        status: { db: "status", type: "text", hasDefault: true },
      },
      primaryKey: ["id"],
      uniqueKeys: {},
      relations: {},
      flags: { tenant: "organizationId" },
    },
    organizationUsers: {
      key: "organizationUsers",
      name: "organization_users",
      schema: "centrakit",
      kind: "table",
      columns: {
        userId: { db: "user_id", type: "uuid" },
        organizationId: { db: "organization_id", type: "uuid" },
        roleId: { db: "role_id", type: "uuid" },
      },
      primaryKey: [],
      uniqueKeys: {},
      relations: {},
      flags: { tenant: "organizationId" },
    },
  },
  enums: {},
  functions: {},
});

export const betterSupabase = createSupabase(schema);
