import type { SupabaseClient } from "@supabase/supabase-js";
import type { QueryClient } from "@tanstack/react-query";

import { describe, expectTypeOf, it } from "vitest";

import type { AuthResolver } from "../../src/auth/resolve.ts";
import type { Generator } from "../../src/config/index.ts";
import type { CacheAdapter } from "../../src/core/cache.ts";
import type { Compiler } from "../../src/core/compiler.ts";
import type { Executor } from "../../src/core/executor.ts";
import type { Logger } from "../../src/core/logger.ts";
import type {
  AnyPlugin,
  MutationEvent,
  MutationIntent,
} from "../../src/core/plugin.ts";
import type { AsyncResult } from "../../src/core/result.ts";
import type { EventSink } from "../../src/events/index.ts";
import type { Operation } from "../../src/ir/types.ts";
import type { QueueBackend } from "../../src/jobs/index.ts";

import { jsonSchema } from "../../src/config/index.ts";
import { memoryCache } from "../../src/core/cache.ts";
import { postgrestCompiler } from "../../src/core/compiler.ts";
import { defineRepository } from "../../src/core/define-repository.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { consoleLogger, silentLogger } from "../../src/core/logger.ts";
import { postgrestExecutor } from "../../src/core/postgrest-executor.ts";
import { httpSink } from "../../src/events/index.ts";
import { valibot } from "../../src/generators/valibot.ts";
import { zod } from "../../src/generators/zod.ts";
import { pgmqPublicBackend, sqlQueueBackend } from "../../src/jobs/index.ts";
import { nextCache } from "../../src/next/index.ts";
import { softDelete } from "../../src/plugins/soft-delete/index.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { timestamps } from "../../src/plugins/timestamps/index.ts";
import { postgresExecutor, sqlCompiler } from "../../src/postgres/index.ts";
import { queryCache } from "../../src/query/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
declare const queryClient: QueryClient;

describe("extension interfaces", () => {
  it("are implemented by the first-party extensions", () => {
    expectTypeOf(postgrestExecutor(client)).toExtend<Executor>();
    expectTypeOf(postgresExecutor).returns.toExtend<Executor>();
    expectTypeOf(postgrestCompiler).toExtend<Compiler<unknown>>();
    expectTypeOf(sqlCompiler).toExtend<Compiler<unknown>>();
    expectTypeOf(memoryCache()).toExtend<CacheAdapter>();
    expectTypeOf(nextCache()).toExtend<CacheAdapter>();
    expectTypeOf(queryCache(queryClient)).toExtend<CacheAdapter>();
    expectTypeOf(httpSink).returns.toExtend<EventSink>();
    expectTypeOf(sqlQueueBackend).returns.toExtend<QueueBackend>();
    expectTypeOf(pgmqPublicBackend).returns.toExtend<QueueBackend>();
    expectTypeOf<QueueBackend["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf(consoleLogger).toExtend<Logger>();
    expectTypeOf(silentLogger).toExtend<Logger>();
    expectTypeOf(zod()).toExtend<Generator>();
    expectTypeOf(valibot()).toExtend<Generator>();
    expectTypeOf(jsonSchema()).toExtend<Generator>();
    expectTypeOf(timestamps()).toExtend<AnyPlugin>();
    expectTypeOf<AuthResolver["resolve"]>()
      .parameter(0)
      .toEqualTypeOf<Request>();
  });

  it("keeps Executor.batch optional, so existing executors still conform", () => {
    const minimal: Executor = {
      name: "minimal",
      execute: () => Promise.reject(new Error("unused")),
    };
    expectTypeOf(minimal).toExtend<Executor>();
    expectTypeOf<NonNullable<Executor["batch"]>>()
      .parameter(0)
      .toEqualTypeOf<readonly Operation[]>();
    expectTypeOf<Executor["functionSources"]>().toEqualTypeOf<
      boolean | undefined
    >();
  });
});

describe("defineRepository", () => {
  const betterSupabase = defineSupabase(schema).use(softDelete()).use(tenant());
  const tags = defineRepository(betterSupabase, "tags", (base) => ({
    named: (name: string) =>
      base.findFirst({ where: { name }, select: ["id", "name"] }),
  }));
  const db = betterSupabase.use(tags).connect(client);

  it("types methods on the target table only", () => {
    expectTypeOf(db.tags.named).parameters.toEqualTypeOf<[name: string]>();
    expectTypeOf(db.tags.named("x")).toEqualTypeOf<
      AsyncResult<{ id: string; name: string } | null>
    >();
    expectTypeOf(db.customers).not.toHaveProperty("named");
  });

  it("keeps plugin extensions on the base repository", () => {
    defineRepository(betterSupabase, "customers", (base) => {
      expectTypeOf(base).toHaveProperty("restore");
      return {};
    });
  });

  it("accepts only known tables", () => {
    // @ts-expect-error unknown table
    defineRepository(betterSupabase, "nope", () => ({}));
  });
});

describe("mutation events", () => {
  it("carry the intent, the known keys and the resolved tenant", () => {
    expectTypeOf<MutationEvent["intent"]>().toEqualTypeOf<
      MutationIntent | undefined
    >();
    expectTypeOf<MutationIntent>().toEqualTypeOf<
      "insert" | "upsert" | "update" | "delete" | "softDelete"
    >();
    expectTypeOf<MutationEvent["tenant"]>().toEqualTypeOf<string | undefined>();
    expectTypeOf<MutationEvent["keys"]>().toEqualTypeOf<
      readonly Readonly<Record<string, unknown>>[] | undefined
    >();
  });
});
