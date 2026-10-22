import type { Result } from "better-result";

import { Result as ResultApi, TaggedError } from "better-result";
import { describe, expectTypeOf, it } from "vitest";

import type { BetterResultRepository } from "../../src/better-result/index.ts";
import type { DbError } from "../../src/core/errors.ts";
import type { Repository } from "../../src/core/repository-types.ts";
import type { Models } from "../fixtures/generated-camel.ts";

import { withBetterResult } from "../../src/better-result/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { defineBetterResultErrors } from "../../src/core/result.ts";
import { defineListQuery } from "../../src/list/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

class NotFound extends TaggedError("NotFound")<{
  message: string;
  error: DbError;
}> {}

class DbFailure extends TaggedError("DbFailure")<{
  message: string;
  error: DbError;
}> {}

const betterSupabase = defineSupabase(schema);
const plain = betterSupabase.connect(capturingClient().client);

const db = withBetterResult(
  plain,
  defineBetterResultErrors(ResultApi, { not_found: NotFound }, DbFailure),
);

describe("withBetterResult types", () => {
  it("mirrors every Repository method", () => {
    type Mirrored = Exclude<
      keyof Repository<Models, "customers">,
      | keyof BetterResultRepository<Models, "customers", unknown, never>
      | "extend"
    >;

    expectTypeOf<Mirrored>().toEqualTypeOf<never>();
  });

  it("keeps the selected row type and the converter's errors", () => {
    expectTypeOf(db.customers.list({ select: ["id", "name"] })).toEqualTypeOf<
      Promise<Result<{ id: string; name: string }[], NotFound | DbFailure>>
    >();
    expectTypeOf(db.customers.count()).toEqualTypeOf<
      Promise<Result<number, NotFound | DbFailure>>
    >();
    expectTypeOf(db.$table("customers").delete("c1")).toEqualTypeOf<
      Promise<Result<void, NotFound | DbFailure>>
    >();
  });

  it("types $rpc, $list and $from", () => {
    expectTypeOf(db.$rpc("my_organizations")).toExtend<
      Promise<Result<readonly unknown[], NotFound | DbFailure>>
    >();

    const list = defineListQuery(betterSupabase, "customers", {
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
    });

    expectTypeOf(db.$list(list, list.defaults, { select: ["id"] })).toExtend<
      Promise<Result<{ items: { id: string }[] }, NotFound | DbFailure>>
    >();
    expectTypeOf(
      db.$from(plain.customers.count().map((n) => n > 0)),
    ).toEqualTypeOf<Promise<Result<boolean, NotFound | DbFailure>>>();
    expectTypeOf(db.$db).toEqualTypeOf(plain);
  });

  it("uses mapError's return type for a { Result, mapError } mapping", () => {
    const keyed = withBetterResult(plain, {
      Result: ResultApi,
      mapError: (error: DbError) => error.kind,
    });

    expectTypeOf(keyed.customers.count()).toEqualTypeOf<
      Promise<Result<number, DbError["kind"]>>
    >();
  });
});
