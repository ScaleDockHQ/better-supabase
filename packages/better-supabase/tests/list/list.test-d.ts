import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { OffsetPage } from "../../src/core/repository-types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { defineListQuery, type ListQuery } from "../../src/list/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
const sb = defineSupabase(schema);
const db = sb.connect(client);

describe("list types", () => {
  it("keeps sort and facet keys literal", async () => {
    const list = defineListQuery(sb, "customers", {
      search: ["name"],
      facets: { status: "status" },
      sorts: { name: { name: "asc" }, newest: { createdAt: "desc" } },
      defaultSort: "newest",
    });
    const query = list.parse(undefined).value!;
    expectTypeOf(query).toEqualTypeOf<ListQuery<"name" | "newest", "status">>();
    const page = await list
      .run(db, query, { select: ["id", "name"] })
      .orThrow();
    expectTypeOf(page).toEqualTypeOf<
      OffsetPage<{ id: string; name: string }>
    >();
  });

  it("types facet counts and relation includes", async () => {
    const list = defineListQuery(sb, "customers", {
      facets: { status: "status" },
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      facetCounts: true,
      count: "planned",
    });
    const page = await list
      .run(db, list.defaults, { include: { notes: true }, count: "exact" })
      .orThrow();
    expectTypeOf(page.facetCounts).toEqualTypeOf<{
      readonly status: Readonly<Record<string, number>>;
    }>();
    expectTypeOf(page.items[0]!.notes).toBeArray();
    // @ts-expect-error include takes relation names
    void list.run(db, list.defaults, { include: { select: ["id"] } });
  });

  it("checks columns", () => {
    defineListQuery(sb, "customers", {
      // @ts-expect-error search only takes text columns
      search: ["createdAtNumber"],
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
    });
    defineListQuery(sb, "customers", {
      sorts: { name: { name: "asc" } },
      // @ts-expect-error default sort must be one of the sorts
      defaultSort: "other",
    });
  });
});
