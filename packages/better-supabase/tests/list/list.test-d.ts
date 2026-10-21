import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type {
  CursorPage,
  OffsetPage,
} from "../../src/core/repository-types.ts";
import type {
  FilterField,
  FilterQuery,
  ListQuery,
} from "../../src/list/index.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { defineListQuery } from "../../src/list/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
const betterSupabase = defineSupabase(schema);
const db = betterSupabase.connect(client);

describe("list types", () => {
  it("types filter columns and the filter tree", () => {
    defineListQuery(betterSupabase, "customers", {
      filters: {
        name: { type: "text" },
        contact: { type: "relation", column: "primaryContactId" },
        // @ts-expect-error -- not a customers column
        typo: { type: "text", column: "nmae" },
      },
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
    });

    const list = defineListQuery(betterSupabase, "customers", {
      filters: { name: { type: "text" } },
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
    });

    expectTypeOf(list.parse(undefined).value!.filter).toEqualTypeOf<
      FilterQuery | undefined
    >();
    expectTypeOf(list.filterFields()).toEqualTypeOf<FilterField[]>();
  });

  it("keeps sort and facet keys literal", async () => {
    const list = defineListQuery(betterSupabase, "customers", {
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
      CursorPage<{ id: string; name: string }>
    >();
  });

  it("returns an offset page with offset pagination", async () => {
    const list = defineListQuery(betterSupabase, "customers", {
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      pagination: "offset",
    });

    expectTypeOf(list.pagination).toEqualTypeOf<"offset">();

    const page = await list
      .run(db, list.defaults, { select: ["id"] })
      .orThrow();

    expectTypeOf(page).toEqualTypeOf<OffsetPage<{ id: string }>>();
  });

  it("returns a cursor page by default", async () => {
    const list = defineListQuery(betterSupabase, "customers", {
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
    });

    expectTypeOf(list.pagination).toEqualTypeOf<"cursor">();

    const page = await list
      .run(db, list.defaults, { select: ["id"] })
      .orThrow();

    expectTypeOf(page).toEqualTypeOf<CursorPage<{ id: string }>>();
    expectTypeOf(list.args(list.defaults).after).toEqualTypeOf<string | null>();
  });

  it("types facet counts and relation includes", async () => {
    const list = defineListQuery(betterSupabase, "customers", {
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
    defineListQuery(betterSupabase, "customers", {
      // @ts-expect-error search only takes text columns
      search: ["createdAtNumber"],
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
    });
    defineListQuery(betterSupabase, "customers", {
      sorts: { name: { name: "asc" } },
      // @ts-expect-error default sort must be one of the sorts
      defaultSort: "other",
    });
  });
});
