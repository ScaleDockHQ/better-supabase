import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { GeneratedColumns, WritableColumns } from "../../src/schema/types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import {
  schema,
  type GeneratedColumnOf,
  type Models,
  type RowOf,
  type WritableColumnOf,
} from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
const db = defineSupabase(schema).connect(client);

describe("generated columns", () => {
  it("keeps tierRole in Row and out of the writable columns", () => {
    expectTypeOf<RowOf<"memberships">["tierRole"]>().toEqualTypeOf<
      string | null
    >();
    expectTypeOf<GeneratedColumnOf<"memberships">>().toEqualTypeOf<"tierRole">();

    expectTypeOf<WritableColumnOf<"memberships">>().toEqualTypeOf<
      "organizationId" | "userId" | "role" | "createdAt" | "lastUsedAt"
    >();

    expectTypeOf<WritableColumns<Models, "memberships">>().toEqualTypeOf<
      WritableColumnOf<"memberships">
    >();

    expectTypeOf<GeneratedColumns<Models, "memberships">>().toEqualTypeOf<
      GeneratedColumnOf<"memberships">
    >();
  });

  it("rejects the column in create and update", () => {
    const row = { organizationId: "o", userId: "u", tierRole: "manager" };
    // @ts-expect-error generated columns are not writable
    void db.memberships.create(row);

    void db.memberships.update(
      { organizationId: "o", userId: "u" },
      {
        // @ts-expect-error generated columns are not writable
        tierRole: "manager",
      },
    );
  });

  it("has no generated columns on a table without them", () => {
    expectTypeOf<GeneratedColumnOf<"customers">>().toEqualTypeOf<never>();
  });
});
