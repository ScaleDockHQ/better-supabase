import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { Schema } from "../../src/schema/types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import {
  schema as camel,
  type Database,
  type Functions as FixtureFunctions,
  type Models,
} from "../fixtures/generated-camel.ts";

/** The shape `better-supabase gen` emits for overloaded functions. */
type Functions = FixtureFunctions & {
  area:
    | {
        Args: Record<PropertyKey, never>;
        Returns: boolean | null;
      }
    | {
        Args: { label: string | null; scale?: number | null };
        Returns: string | null;
      }
    | {
        Args: { side: number | null; unit?: "cm" | "in" | null };
        Returns: number[];
      };
  pick:
    | { Args: { value: number | null }; Returns: string | null }
    | { Args: { value: string | null }; Returns: number | null };
};

declare const client: SupabaseClient;
// SAFETY: the extra overloads exist only in types; these tests never run a call.
const schema = camel as unknown as Schema<Models, Database, Functions>;
const db = defineSupabase(schema).connect(client);

describe("$rpc overloads", () => {
  it("returns the type of the overload the argument names pick", async () => {
    expectTypeOf(await db.$rpc("area", { side: 2 }).orThrow()).toEqualTypeOf<
      number[]
    >();
    expectTypeOf(
      await db.$rpc("area", { side: 2, unit: "cm" }, { timeout: 5 }).orThrow(),
    ).toEqualTypeOf<number[]>();
    expectTypeOf(await db.$rpc("area", { label: "x" }).orThrow()).toEqualTypeOf<
      string | null
    >();
    expectTypeOf(
      await db.$rpc("area", { label: "x", scale: null }).orThrow(),
    ).toEqualTypeOf<string | null>();
    expectTypeOf(await db.$rpc("area").orThrow()).toEqualTypeOf<
      boolean | null
    >();
    expectTypeOf(await db.$rpc("area", {}).orThrow()).toEqualTypeOf<
      boolean | null
    >();
  });

  it("returns a union when the call can't tell overloads apart", async () => {
    expectTypeOf(await db.$rpc("pick", { value: 1 }).orThrow()).toEqualTypeOf<
      string | number | null
    >();
    const dynamic = { side: 2 } as { side: number } | { label: string };
    expectTypeOf(await db.$rpc("area", dynamic).orThrow()).toEqualTypeOf<
      number[] | string | null
    >();
  });

  it("keeps raw and returns options", async () => {
    expectTypeOf(
      await db.$rpc("area", { side: 2 }, { raw: true }).orThrow(),
    ).toEqualTypeOf<unknown>();
    expectTypeOf(
      await db.$rpc("area", {}, { raw: true }).orThrow(),
    ).toEqualTypeOf<unknown>();
    // @ts-expect-error options come after the arguments
    void db.$rpc("area", { raw: true });
    const returns = {} as StandardSchemaV1<unknown, Date>;
    expectTypeOf(
      await db.$rpc("area", { side: 2 }, { returns }).orThrow(),
    ).toEqualTypeOf<Date>();
  });

  it("rejects arguments no overload takes", () => {
    // @ts-expect-error side is a number
    void db.$rpc("area", { side: "2" });
    // @ts-expect-error unit is "cm" or "in"
    void db.$rpc("area", { side: 2, unit: "mm" });
    // @ts-expect-error no overload takes side and label
    void db.$rpc("area", { side: 2, label: "x" });
    // @ts-expect-error a misspelled name
    void db.$rpc("area", { sid: 2 });
    // @ts-expect-error every pick overload takes value
    void db.$rpc("pick");
    // @ts-expect-error value is a number or a string
    void db.$rpc("pick", { value: true });
  });

  it("leaves functions with one signature unchanged", async () => {
    expectTypeOf(
      await db.$rpc("customers_by_status", { p_status: "lead" }).orThrow(),
    ).toEqualTypeOf<FixtureFunctions["customers_by_status"]["Returns"]>();
    // @ts-expect-error an unknown argument
    void db.$rpc("customers_by_status", { p_status: "lead", typo: 1 });
  });
});
