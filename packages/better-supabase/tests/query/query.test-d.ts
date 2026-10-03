import type { SupabaseClient } from "@supabase/supabase-js";

import {
  type InfiniteData,
  QueryClient,
  skipToken,
  useInfiniteQuery,
  useMutation,
  useQuery,
} from "@tanstack/react-query";
import { describe, expectTypeOf, it } from "vitest";

import type { DbException } from "../../src/core/errors.ts";
import type {
  CursorPage,
  OffsetPage,
} from "../../src/core/repository-types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { softDelete } from "../../src/plugins/soft-delete/index.ts";
import { createQueries } from "../../src/query/index.ts";
import { type CustomersStatus, schema } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
const betterSupabase = defineSupabase(schema).use(softDelete());
const q = createQueries(betterSupabase, betterSupabase.connect(client));

describe("query option types", () => {
  it("flows payload types into useQuery and the cache", () => {
    const options = q.customers.findMany({ select: ["id", "status"] });
    const { data, error } = useQuery(options);
    expectTypeOf(data).toEqualTypeOf<
      { id: string; status: CustomersStatus }[] | undefined
    >();
    // Without a `Register { defaultError: DbException }` augmentation TanStack reports `Error`.
    expectTypeOf(error).toEqualTypeOf<Error | null>();
    expectTypeOf<DbException>().toExtend<Error>();
    expectTypeOf(
      new QueryClient().getQueryData(options.queryKey),
    ).toEqualTypeOf<{ id: string; status: CustomersStatus }[] | undefined>();
  });

  it("types infinite queries and mutations", () => {
    const { data } = useInfiniteQuery(
      q.customers.infinite({ select: ["id"], size: 20 }),
    );
    expectTypeOf(data).toEqualTypeOf<
      InfiniteData<CursorPage<{ id: string }>> | undefined
    >();

    const create = useMutation(q.customers.create({ select: ["id"] }));
    expectTypeOf(create.data).toEqualTypeOf<{ id: string } | undefined>();
    const update = useMutation(q.customers.update());
    expectTypeOf(update.mutate).parameter(0).toHaveProperty("patch");
  });

  it("keeps plugin arguments", () => {
    q.customers.findMany({ withDeleted: true });
    // @ts-expect-error unknown column
    q.customers.findMany({ select: ["nope"] });
  });

  it("accepts skipToken and keeps the payload type", () => {
    const id: string | undefined = undefined as string | undefined;
    const { data } = useQuery(
      q.customers.findById(id ?? skipToken, { select: ["id"] }),
    );
    expectTypeOf(data).toEqualTypeOf<{ id: string } | undefined>();
  });

  it("types offset infinite queries and specs", () => {
    const { data } = useInfiniteQuery(
      q.customers.infinitePages({ select: ["id"], size: 20 }),
    );
    expectTypeOf(data).toEqualTypeOf<
      InfiniteData<OffsetPage<{ id: string }>> | undefined
    >();
    const fromSpec = useQuery(
      q.$spec(betterSupabase.spec.customers.findFirst({ select: ["status"] })),
    );
    expectTypeOf(fromSpec.data).toEqualTypeOf<
      { status: CustomersStatus } | null | undefined
    >();
  });
});
