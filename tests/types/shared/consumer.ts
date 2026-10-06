import type { SupabaseClient } from "@supabase/supabase-js";
import type { Job } from "better-supabase/blocks/jobs";

import { QueryClient } from "@tanstack/react-query";
import {
  type AsyncResult,
  type BetterResultValue,
  type CacheAdapter,
  type DbError,
  defineRepository,
  defineSupabase,
  type Executor,
  fromBetterResult,
  type Logger,
  memoryCache,
  ok,
  type Result,
  silentLogger,
  toBetterResult,
} from "better-supabase";
import { hasEntitlement } from "better-supabase/blocks/entitlements";
import { verifyWebhook } from "better-supabase/blocks/webhooks";
import { createClient } from "better-supabase/client";
import { defineConfig, zod } from "better-supabase/config";
import { createEdge } from "better-supabase/edge";
import { parseEnv } from "better-supabase/env";
import { forwardMutations, httpSink } from "better-supabase/events";
import { createHono } from "better-supabase/hono";
import { defineListQuery } from "better-supabase/list";
import { createNext, nextCache, requireAal } from "better-supabase/next";
import { createImageLoader } from "better-supabase/next/image";
import { createOpenApi } from "better-supabase/openapi";
import { createOrpc } from "better-supabase/orpc";
import { otel } from "better-supabase/otel";
import { softDelete } from "better-supabase/plugins/soft-delete";
import { tenant } from "better-supabase/plugins/tenant";
import { timestamps } from "better-supabase/plugins/timestamps";
import { createPostgres, postgresExecutor } from "better-supabase/postgres";
import { createQueries, queryCache } from "better-supabase/query";
import {
  createHooks,
  type LiveCountSeed,
  useLiveCount,
} from "better-supabase/react";
import { defineTopic, liveCount } from "better-supabase/realtime";
import {
  type Aal,
  checkAal,
  createServer,
  impersonatorOf,
  PRIMARY_COOKIE,
} from "better-supabase/server";
import {
  defineBucket,
  defineBuckets,
  type StoragePath,
} from "better-supabase/storage";
import {
  defineSeed,
  expectTenantIsolation,
  testExecutor,
} from "better-supabase/testing";

import {
  type Database,
  type Functions,
  type Models,
  schema,
} from "./generated.ts";

type Equal<A, B> =
  (<T>() => T extends A ? 1 : 2) extends <T>() => T extends B ? 1 : 2
    ? true
    : false;
// SAFETY: T extends true, so true is its only value.
const assert = <T extends true>(): T => true as T;

declare const client: SupabaseClient;

const logger: Logger = silentLogger;
const base = defineSupabase(schema, { logger })
  .use(timestamps())
  .use(softDelete())
  .use(tenant())
  .use(otel());

const customers = defineRepository(base, "customers", (repo) => ({
  active: () =>
    repo.findMany({ where: { status: "active" }, select: ["id", "name"] }),
}));
export const betterSupabase = base.use(customers);

const db = betterSupabase.connect(client, { tenant: "organization" });

export async function reads(): Promise<void> {
  const rows = await db.customers
    .findMany({ select: ["id", "status", "createdAt"] })
    .orThrow();
  assert<
    Equal<
      (typeof rows)[number],
      { id: string; status: "lead" | "active" | "archived"; createdAt: string }
    >
  >();

  const active = db.customers.active();
  assert<Equal<typeof active, AsyncResult<{ id: string; name: string }[]>>>();

  const withTags = await db.customers
    .findFirst({
      select: ["id"],
      include: { customerTags: { select: ["tagId"] } },
    })
    .orThrow();
  assert<
    Equal<
      typeof withTags,
      { id: string; customerTags: { tagId: string }[] } | null
    >
  >();

  const result: Result<unknown> = await db.tags.count();
  if (!result.ok) {
    const error: DbError = result.error;
    void error.kind;
  }

  // @ts-expect-error unknown column
  await db.customers.findMany({ select: ["nope"] });
  // @ts-expect-error the method exists on customers only
  db.tags.active(); // oxlint-disable-line typescript/no-unsafe-call -- the call is the expected type error.
  await db.customers.restore("id");
}

// `lib` leaves out ESNext.Temporal: the published declarations reference it.
export function jobAge(job: Job, now: Temporal.Instant): Temporal.Duration {
  return now.since(job.enqueuedAt);
}

export function integrations(): unknown[] {
  const env = parseEnv({});
  const server = createServer(betterSupabase);
  const cache: CacheAdapter = memoryCache();
  betterSupabase.cache(cache);
  betterSupabase.cache(nextCache());
  betterSupabase.cache(queryCache(new QueryClient()));
  forwardMutations(betterSupabase, httpSink("https://example.com/events"), {
    source: "/crm",
  });
  const executor: Executor = postgresExecutor(
    createPostgres({ connectionString: "postgres://x" }).admin,
  );
  const list = defineListQuery(betterSupabase, "customers", {
    search: ["name"],
    facets: { status: "status" },
    sorts: { name: [{ name: "asc" }] },
    defaultSort: "name",
  });
  const logos = defineBucket({
    id: "customer-logos",
    path: "{organizationId}/{customerId}/logo.webp",
  });
  const topic = defineTopic("organization:{organizationId}:customers");
  const seed = defineSeed(betterSupabase, {
    tags: { urgent: { organizationId: "organization", name: "Urgent" } },
  });
  return [
    env,
    server,
    createNext(betterSupabase),
    createHono(betterSupabase),
    createOrpc(betterSupabase),
    createEdge(betterSupabase),
    createClient(betterSupabase),
    createHooks<
      ReturnType<typeof createClient<Models, Database, Functions, unknown>>
    >(),
    createQueries(betterSupabase, db),
    createOpenApi(betterSupabase, {
      info: { title: "CRM", version: "1" },
      resources: { customers: true },
    }),
    defineConfig({ generators: [zod()] }),
    list,
    logos.path({
      organizationId: "o",
      customerId: "c",
    }) satisfies Result<StoragePath<"customer-logos">>,
    defineBuckets({ logos }).byId("customer-logos") satisfies Result<
      typeof logos
    >,
    createImageLoader({ url: "https://x.supabase.co" })({
      src: "/a.png",
      width: 64,
    }),
    topic,
    seed.sql(),
    verifyWebhook,
    testExecutor(executor, { betterSupabase }),
    expectTenantIsolation(betterSupabase, {
      tenants: [
        { id: "a", claims: { sub: "u1", tenant_id: "a" } },
        { id: "b", claims: { sub: "u2", tenant_id: "b" } },
      ],
      tables: {
        tags: {
          row: (tenant, n) => ({ organizationId: tenant.id, name: `t${n}` }),
          update: { name: "changed" },
        },
      },
    }),
    betterSupabase.mapError(
      (error) => new Error(error.message, { cause: error }),
    ),
    requireAal("aal2", { redirect: "/mfa" }),
    createNext(betterSupabase).route(() => Promise.resolve(ok(null)), {
      aal: "aal2",
    }),
    createNext(betterSupabase)
      .session()
      .then((session) =>
        session.kind === "user" ? (session.aal satisfies Aal) : undefined,
      ),
    checkAal,
    createNext(betterSupabase)
      .session()
      .then((session) => hasEntitlement(session, "organization", "exports")),
    server
      .deleteAccount("u1", { buckets: [logos], cascades: ["customers"] })
      .map(({ removed }) => removed["customer-logos"]),
    createServer(betterSupabase, { readUrl: false, replicas: { pinMs: 1000 } })
      .context(new Request("https://app.test/"))
      .then((ctx) => {
        ctx.replica?.pin();
        return ctx.replica?.wrote satisfies boolean | undefined;
      }),
    PRIMARY_COOKIE satisfies string,
    server
      .actingAs("u1", { tenant_id: "a" }, { actor: "admin", reason: "support" })
      .customers.count(),
    impersonatorOf({ act: { sub: "admin" } })?.id satisfies string | undefined,
    createNext(betterSupabase)
      .session()
      .then((session) =>
        session.kind === "user" ? session.impersonator?.reason : undefined,
      ),
    (error: DbError) =>
      error.kind === "rate_limited"
        ? (error.retryAfter satisfies number | undefined)
        : undefined,
    createNext(betterSupabase).liveCount(
      betterSupabase.spec.customers.count(),
    ) satisfies Promise<LiveCountSeed<"customers">>,
    liveCount,
    useLiveCount,
    server
      .actingAs("u1")
      .$search("customers", { vector: [0.1, 0.2], k: 3, select: ["id"] })
      .map((rows) => rows.map((row) => row.id satisfies string)),
    defineConfig({ vectorSearch: { notes: { column: "embedding" } } }),
    fromBetterResult(
      toBetterResult(
        { ok: true, data: 1, error: null },
        { ok: (value) => ({ status: "ok", value }), err: (error) => error },
      ) satisfies BetterResultValue<number, DbError>,
    ) satisfies Result<number>,
  ];
}
