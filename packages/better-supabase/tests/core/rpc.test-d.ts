import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { Functions } from "../fixtures/generated-camel.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { schema as camel } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
const db = defineSupabase(camel).connect(client);

describe("$rpc arguments", () => {
  it("takes one named argument object and types the result", async () => {
    expectTypeOf(
      await db.$rpc("customers_by_status", { p_status: "lead" }).orThrow(),
    ).toEqualTypeOf<Functions["customers_by_status"]["Returns"]>();

    expectTypeOf(
      await db
        .$rpc("customers_by_status", { p_status: "lead", p_limit: 5 })
        .orThrow(),
    ).toEqualTypeOf<Functions["customers_by_status"]["Returns"]>();
  });

  it("requires the arguments the function requires", () => {
    // @ts-expect-error p_status is required
    void db.$rpc("customers_by_status", {});
    // @ts-expect-error p_status is required
    void db.$rpc("customers_by_status");
    // @ts-expect-error p_limit is a number
    void db.$rpc("customers_by_status", { p_status: "lead", p_limit: "5" });
    // @ts-expect-error a misspelled argument
    void db.$rpc("customers_by_status", { p_status: "lead", p_limt: 5 });
    // @ts-expect-error a function that does not exist
    void db.$rpc("missing_function", {});
  });

  it("leaves the arguments out when all are optional", async () => {
    expectTypeOf(await db.$rpc("customer_note_counts").orThrow()).toEqualTypeOf<
      Functions["customer_note_counts"]["Returns"]
    >();

    expectTypeOf(
      await db
        .$rpc("customer_note_counts", { p_customer_ids: ["a"] })
        .orThrow(),
    ).toEqualTypeOf<Functions["customer_note_counts"]["Returns"]>();

    expectTypeOf(await db.$rpc("my_organizations").orThrow()).toEqualTypeOf<
      Functions["my_organizations"]["Returns"]
    >();
  });
});

describe("$rpc options", () => {
  it("narrows the result with returns and widens it with raw", async () => {
    const returns = {} as StandardSchemaV1<unknown, { total: number }>;

    expectTypeOf(
      await db
        .$rpc("customer_note_counts", {}, { returns, timeout: 5 })
        .orThrow(),
    ).toEqualTypeOf<{ total: number }>();

    expectTypeOf(
      await db.$rpc("customer_note_counts", {}, { raw: true }).orThrow(),
    ).toEqualTypeOf<unknown>();
  });
});
