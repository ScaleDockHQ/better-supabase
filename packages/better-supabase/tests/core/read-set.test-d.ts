import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { AsyncResult } from "../../src/core/result.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { defineReadSet } from "../../src/core/read-set.ts";
import { schema } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;

const sb = defineSupabase(schema);
const db = sb.connect(client);

const chrome = defineReadSet(
  sb,
  "app_chrome",
  { params: { orgId: "uuid", kinds: "text[]", limit: "int4" } },
  (s, p) => {
    expectTypeOf(p.orgId).toEqualTypeOf<string>();
    expectTypeOf(p.kinds).toEqualTypeOf<readonly string[]>();
    expectTypeOf(p.limit).toEqualTypeOf<number>();
    return {
      names: s.customers.findMany({
        select: ["id", "name"],
        where: { organizationId: p.orgId },
      }),
      calls: s.notes.count({ where: { organizationId: p.orgId } }),
    };
  },
);

describe("db.$many", () => {
  it("types a read set result by key", () => {
    expectTypeOf(
      db.$many(chrome, { orgId: "o", kinds: ["call"], limit: 5 }),
    ).toEqualTypeOf<
      AsyncResult<{
        readonly names: { id: string; name: string }[];
        readonly calls: number;
      }>
    >();
  });

  it("requires every parameter with its type", () => {
    // @ts-expect-error kinds is missing
    void db.$many(chrome, { orgId: "o", limit: 5 });
    // @ts-expect-error limit is a number
    void db.$many(chrome, { orgId: "o", kinds: [], limit: "5" });
  });

  it("returns a tuple for ad-hoc specs", () => {
    expectTypeOf(
      db.$many([
        sb.spec.tags.count(),
        sb.spec.customers.findFirst({ select: ["id"] }),
      ]),
    ).toEqualTypeOf<AsyncResult<[number, { id: string } | null]>>();
  });
});
