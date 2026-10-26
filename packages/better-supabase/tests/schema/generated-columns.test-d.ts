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
  it("keeps emailDomain in Row and out of the writable columns", () => {
    expectTypeOf<RowOf<"contacts">["emailDomain"]>().toEqualTypeOf<
      string | null
    >();
    expectTypeOf<GeneratedColumnOf<"contacts">>().toEqualTypeOf<"emailDomain">();

    expectTypeOf<WritableColumnOf<"contacts">>().toEqualTypeOf<
      | "id"
      | "organizationId"
      | "email"
      | "fullName"
      | "createdAt"
      | "updatedAt"
    >();

    expectTypeOf<WritableColumns<Models, "contacts">>().toEqualTypeOf<
      WritableColumnOf<"contacts">
    >();

    expectTypeOf<GeneratedColumns<Models, "contacts">>().toEqualTypeOf<
      GeneratedColumnOf<"contacts">
    >();
  });

  it("rejects the column in create and update", () => {
    const row = { organizationId: "o", email: "a@b.test", emailDomain: "b.test" };
    // @ts-expect-error generated columns are not writable
    void db.contacts.create(row);

    void db.contacts.update("c", {
      // @ts-expect-error generated columns are not writable
      emailDomain: "b.test",
    });
  });

  it("has no generated columns on a table without them", () => {
    expectTypeOf<GeneratedColumnOf<"customers">>().toEqualTypeOf<never>();
  });
});
