import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type {
  CrudEntryLike,
  UploadRepository,
  UploadRoute,
} from "../../src/powersync/connector.ts";
import type { Insert } from "../../src/schema/types.ts";
import type { Models } from "../fixtures/generated-camel.ts";

import { defineSupabase } from "../../src/core/define.ts";
import {
  createUploadConnector,
  uploadRoute,
} from "../../src/powersync/connector.ts";
import { schema as camel } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;

declare const supabase: Parameters<typeof createUploadConnector>[0]["supabase"];

const db = defineSupabase(camel).connect(client);

describe("upload routes", () => {
  it("takes a generated repository as a typed UploadRepository", () => {
    expectTypeOf(db.customers).toExtend<
      UploadRepository<Insert<Models, "customers">>
    >();
    expectTypeOf(db.customers).toExtend<UploadRoute>();
  });

  it("builds a function route from a repository without casts", () => {
    const upsert = uploadRoute(db.customers);
    const create = uploadRoute(db.notes, { put: "create" });

    expectTypeOf(create).toEqualTypeOf<
      (entry: CrudEntryLike) => PromiseLike<Result<unknown>>
    >();

    createUploadConnector({
      endpoint: "e",
      supabase,
      tables: { customers: upsert, notes: create, tags: db.tags },
    });

    const deleteOnly = { delete: (id: number) => db.notes.delete(id) };
    // @ts-expect-error a create route needs a repository with create
    void uploadRoute(deleteOnly, { put: "create" });
    // @ts-expect-error put is upsert or create
    void uploadRoute(db.notes, { put: "insert" });
  });
});
