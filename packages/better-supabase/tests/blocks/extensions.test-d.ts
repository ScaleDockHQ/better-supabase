import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { AsyncResult } from "../../src/core/result.ts";

import { membershipsExtension } from "../../src/blocks/memberships/index.ts";
import { trashExtension } from "../../src/blocks/trash/index.ts";
import { updatedAtExtension } from "../../src/blocks/updated-at/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { schema } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;

const db = defineSupabase(schema)
  .use(updatedAtExtension())
  .use(trashExtension())
  .use(membershipsExtension())
  .connect(client);

describe("plugin extensions", () => {
  it("adds restore only to soft-delete tables", () => {
    expectTypeOf(db.customers.restore).toEqualTypeOf<
      (
        key: string,
        args?: { readonly signal?: AbortSignal },
      ) => AsyncResult<void>
    >();
    // @ts-expect-error tags has no softDelete flag
    db.tags.restore("t");
  });

  it("adds per-call options only where the flag is set", () => {
    db.customers.findMany({ withDeleted: true, allTenants: true });
    db.customers.delete("c", { hard: true });
    db.tags.findMany({ allTenants: true });
    // @ts-expect-error tags has no softDelete flag
    db.tags.findMany({ withDeleted: true });
    // @ts-expect-error tags has no softDelete flag
    db.tags.delete("t", { hard: true });
  });

  it("keeps the base API intact", async () => {
    const rows = await db.customers
      .findMany({ select: ["id"], withDeleted: true })
      .orThrow();

    expectTypeOf(rows).toEqualTypeOf<{ id: string }[]>();
  });
});
