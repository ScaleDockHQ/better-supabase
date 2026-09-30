import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { createOrpc } from "../../src/orpc/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
const sb = defineSupabase(schema);
const bs = createOrpc(sb);
const db = sb.connect(client);

describe("unwrap", () => {
  it("infers the data type of a Result or AsyncResult", () => {
    expectTypeOf(bs.unwrap(ok({ id: "c1" }))).toEqualTypeOf<
      Promise<{ id: string }>
    >();
    expectTypeOf(
      bs.unwrap(db.customers.findById("c1", { select: ["id", "name"] })),
    ).toEqualTypeOf<Promise<{ id: string; name: string }>>();
    expectTypeOf(
      bs.unwrap<{ id: string }>(err(dbError("conflict", "Taken"))),
    ).toEqualTypeOf<Promise<{ id: string }>>();
  });

  it("passes plain values through", () => {
    expectTypeOf(bs.unwrap(Promise.resolve(1))).toEqualTypeOf<
      Promise<number>
    >();
  });
});
