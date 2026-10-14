import type { SchemaMeta } from "better-supabase";

import { defineSchema, defineSupabase } from "better-supabase";
import { defineListQuery } from "better-supabase/list";

const column = (db: string, type: string, nullable = false) => ({
  db,
  type,
  nullable,
  hasDefault: true,
});

/**
 * The `better_supabase.orders` columns the grid reads, as `gen` writes them
 * with `schemas: ["public", "better_supabase"]`.
 */
const meta: SchemaMeta = {
  version: 1,
  casing: "snake",
  enums: {},
  functions: {},
  tables: {
    better_supabase_orders: {
      key: "better_supabase_orders",
      name: "orders",
      schema: "better_supabase",
      kind: "table",
      columns: {
        id: column("id", "uuid"),
        tenant_id: column("tenant_id", "uuid"),
        number: column("number", "text", true),
        email: column("email", "text", true),
        status: column("status", "text"),
        placed_at: column("placed_at", "timestamptz"),
      },
      primaryKey: ["id"],
      uniqueKeys: {},
      relations: {},
      flags: { tenant: "tenant_id" },
    },
  },
};

interface OrderRow {
  id: string;
  tenant_id: string;
  number: string | null;
  email: string | null;
  status: string;
  placed_at: string;
}

type Models = {
  better_supabase_orders: {
    Row: OrderRow;
    Insert: Partial<OrderRow>;
    Update: Partial<OrderRow>;
    Relations: {};
    PrimaryKey: "id";
    UniqueKeys: {};
    Checks: never;
    ForeignKeys: never;
    Flags: { tenant: "tenant_id" };
  };
};

const betterSupabase = defineSupabase(defineSchema<Models>(meta));

/** The admin order grid: search by number or email, a status facet, newest first. */
export const orderList = defineListQuery(
  betterSupabase,
  "better_supabase_orders",
  {
    search: ["number", "email"],
    facets: { status: "status" },
    sorts: {
      newest: [{ placed_at: "desc" }, { id: "asc" }],
      oldest: [{ placed_at: "asc" }, { id: "asc" }],
    },
    defaultSort: "newest",
  },
);
