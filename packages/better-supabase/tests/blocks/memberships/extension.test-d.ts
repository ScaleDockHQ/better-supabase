import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { Schema } from "../../../src/index.ts";

import { membershipsExtension } from "../../../src/blocks/memberships/index.ts";
import { defineSupabase } from "../../../src/core/define.ts";

/**
 * What `gen` emits for the app's own `client_rows` after a `tables.<name>`
 * entry enriched it: the tenant column it added is nullable until a backfill
 * fills the rows the table had, and the table still has the tenant flag.
 */
type Models = {
  clientRows: {
    Row: { id: string; companyId: string | null; name: string };
    Insert: { id?: string; companyId?: string | null; name: string };
    Update: { id?: string; companyId?: string | null; name?: string };
    Relations: Record<never, never>;
    PrimaryKey: "id";
    UniqueKeys: Record<never, never>;
    Checks: never;
    ForeignKeys: never;
    Flags: { tenant: "companyId" };
  };
};

declare const schema: Schema<Models>;
declare const client: SupabaseClient;

const db = defineSupabase(schema).use(membershipsExtension()).connect(client);

describe("membershipsExtension over an enriched table", () => {
  it("takes the tenant options and leaves the tenant column to the extension", async () => {
    const rows = await db.clientRows
      .list({ select: ["companyId"], allTenants: true })
      .orThrow();

    expectTypeOf(rows).toEqualTypeOf<{ companyId: string | null }[]>();

    db.clientRows.create({ name: "Acme" });
  });
});
