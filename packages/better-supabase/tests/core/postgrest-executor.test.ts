import { describe, expect, it } from "vitest";

import type { Executor } from "../../src/core/executor.ts";
import type { Operation } from "../../src/ir/types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { resolveUrlLengthLimit } from "../../src/core/postgrest-executor.ts";
import { ok } from "../../src/core/result.ts";
import {
  type PostgrestClientLike,
  postgrestExecutor,
} from "../../src/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

interface Call {
  readonly schema: string;
  readonly name: string;
  readonly args: unknown;
  readonly options: unknown;
  signal?: AbortSignal;
}

function fakeClient(response: { data?: unknown; error?: unknown }) {
  const calls: Call[] = [];
  const schemaCalls: string[] = [];
  const scoped = (schema: string) => ({
    from: () => ({}),
    rpc: (name: string, args: unknown, options?: unknown) => {
      const call: Call = { schema, name, args, options };
      calls.push(call);
      const builder = Object.assign(Promise.resolve(response), {
        abortSignal: (signal: AbortSignal): unknown => {
          call.signal = signal;
          return builder;
        },
      });
      return builder;
    },
  });
  const client = {
    ...scoped("public"),
    schema(schema: string) {
      schemaCalls.push(schema);
      return scoped(schema);
    },
  };
  // SAFETY: the executor only calls schema() and rpc() on this fake.
  return {
    client: client as unknown as PostgrestClientLike,
    calls,
    schemaCalls,
  };
}

describe("postgrestExecutor rpc", () => {
  it("builds one scoped client per schema and reuses it", async () => {
    const { client, calls, schemaCalls } = fakeClient({ data: "ok" });
    const executor = postgrestExecutor(client);
    const context = { schema: "api", errorMappers: [] };

    expect(await executor.rpc?.("a", {}, context)).toMatchObject({ ok: true });
    expect(await executor.rpc?.("b", {}, context)).toMatchObject({ ok: true });
    await executor.rpc?.("c", {}, { schema: "public", errorMappers: [] });

    expect(schemaCalls).toEqual(["api"]);
    expect(calls.map((call) => call.schema)).toEqual(["api", "api", "public"]);
  });

  it("sends GET arguments with objects as JSON", async () => {
    const { client, calls } = fakeClient({ data: "ok" });
    await postgrestExecutor(client).rpc?.(
      "search",
      { filter: { a: 1 }, tags: ["x"], limit: 2, empty: null },
      { schema: "public", get: true, errorMappers: [] },
    );

    expect(calls[0]?.args).toEqual({
      filter: '{"a":1}',
      tags: ["x"],
      limit: 2,
      empty: null,
    });
    expect(calls[0]?.options).toEqual({ get: true });
  });

  it("passes the signal and stops when it is already aborted", async () => {
    const { client, calls } = fakeClient({ data: "ok" });
    const executor = postgrestExecutor(client);
    const controller = new AbortController();

    await executor.rpc?.(
      "a",
      {},
      { schema: "public", signal: controller.signal, errorMappers: [] },
    );
    expect(calls[0]?.signal).toBe(controller.signal);

    controller.abort();
    const result = await executor.rpc?.(
      "a",
      {},
      { schema: "public", signal: controller.signal, errorMappers: [] },
    );
    expect(result).toMatchObject({ ok: false, error: { kind: "aborted" } });
    expect(calls).toHaveLength(1);
  });

  it("maps a PostgREST error", async () => {
    const { client } = fakeClient({
      error: { code: "42501", message: "permission denied" },
    });
    const result = await postgrestExecutor(client).rpc?.(
      "a",
      {},
      { schema: "public", errorMappers: [] },
    );
    expect(result).toMatchObject({ ok: false });
  });

  it("fails without rpc() on the client", async () => {
    // SAFETY: a client with from() only, as some custom clients are.
    const client = { from: () => ({}) } as unknown as PostgrestClientLike;
    const result = await postgrestExecutor(client).rpc?.(
      "a",
      {},
      { schema: "public", errorMappers: [] },
    );
    expect(result).toMatchObject({ ok: false });
  });
});

describe("postgrestExecutor request options", () => {
  const betterSupabase = defineSupabase(schema);

  it("sends maxAffected as a strict Prefer on updateMany and deleteMany", async () => {
    const { client, requests } = capturingClient(() => ({
      status: 204,
      headers: { "content-range": "*/2" },
    }));
    const db = betterSupabase.connect(client);
    await db.customers.updateMany({
      where: { status: "lead" },
      data: { status: "active" },
      maxAffected: 5,
    });
    await db.customers.deleteMany({
      where: { status: "lead" },
      maxAffected: 2,
    });

    for (const request of requests) {
      const prefer = request.headers.get("prefer") ?? "";
      expect(prefer).toContain("handling=strict");
    }
    expect(requests[0]?.headers.get("prefer")).toContain("max-affected=5");
    expect(requests[1]?.headers.get("prefer")).toContain("max-affected=2");
  });

  it("leaves Prefer alone without maxAffected", async () => {
    const { client, last } = capturingClient(() => ({ status: 204 }));
    await betterSupabase
      .connect(client)
      .customers.deleteMany({ where: { status: "lead" } });
    expect(last().headers.get("prefer")).not.toContain("max-affected");
  });

  it("maps PGRST124 to max_affected with the limit", async () => {
    const { client } = capturingClient(() => ({
      status: 400,
      body: {
        code: "PGRST124",
        message: "Query result exceeds max-affected preference constraint",
        details: "The query affects 3 rows",
        hint: null,
      },
    }));
    const result = await betterSupabase.connect(client).customers.deleteMany({
      where: { status: "lead" },
      maxAffected: 2,
    });
    expect(result).toMatchObject({
      ok: false,
      error: {
        kind: "max_affected",
        status: 400,
        code: "PGRST124",
        maxAffected: 2,
        table: "customers",
      },
    });
  });

  it("refuses maxAffected before PostgREST 13 without a request", async () => {
    const { client, requests } = capturingClient();
    const old = defineSupabase(schema, { postgrestVersion: "12.2" });
    const result = await old.connect(client).customers.updateMany({
      where: { status: "lead" },
      data: { status: "active" },
      maxAffected: 1,
    });
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "invalid_request" },
    });
    expect(!result.ok && result.error.message).toContain("PostgREST 13");
    expect(requests).toHaveLength(0);
  });

  it("passes the count mode for { count } writes", async () => {
    const { client, last } = capturingClient(() => ({
      status: 204,
      headers: { "content-range": "*/7" },
    }));
    const result = await betterSupabase.connect(client).customers.updateMany({
      where: { status: "lead" },
      data: { status: "active" },
      count: "planned",
    });
    expect(last().headers.get("prefer")).toContain("count=planned");
    expect(result).toMatchObject({ ok: true, data: { count: 7 } });
  });

  it("sends defaultToNull=false as columns on createMany, true on request", async () => {
    const { client, requests } = capturingClient(() => ({ status: 201 }));
    const db = betterSupabase.connect(client);
    const rows = [
      { organizationId: "o", name: "a" },
      { organizationId: "o", name: "b", color: "red" as const },
    ];
    await db.tags.createMany(rows, { returning: false });
    await db.tags.createMany(rows, { returning: false, defaultToNull: true });

    expect(requests[0]?.headers.get("prefer")).toContain("missing=default");
    expect(requests[1]?.headers.get("prefer") ?? "").not.toContain(
      "missing=default",
    );
  });

  it("turns retries off per call and per connection", async () => {
    const retried: boolean[] = [];
    const builder = (): object => {
      const self: object = Object.assign(
        Promise.resolve({ data: [], error: null, count: null }),
        {
          select: () => self,
          filter: () => self,
          order: () => self,
          limit: () => self,
          abortSignal: () => self,
          retry: (enabled: boolean) => {
            retried.push(enabled);
            return self;
          },
        },
      );
      return self;
    };
    // SAFETY: the executor only calls from() and the builder methods above.
    const client = { from: builder } as unknown as PostgrestClientLike;
    await betterSupabase.connect(client).tags.findMany({ retry: false });
    await betterSupabase
      .connect(client, {}, { retry: false })
      .tags.findMany({ limit: 1 });
    await betterSupabase
      .connect(client, {}, { retry: false })
      .tags.findMany({ retry: true });
    await betterSupabase.connect(client).tags.findMany();
    expect(retried).toEqual([false, false, true]);
  });

  it("fails a call that runs past its timeout with a timeout error", async () => {
    const pending = (): object => {
      let settle: (value: unknown) => void = () => {};
      const self: object = Object.assign(
        new Promise((resolve) => {
          settle = resolve;
        }),
        {
          select: () => self,
          filter: () => self,
          order: () => self,
          limit: () => self,
          abortSignal: (signal: AbortSignal) => {
            signal.addEventListener("abort", () => {
              settle({
                data: null,
                error: { message: "AbortError: aborted", code: "20" },
              });
            });
            return self;
          },
        },
      );
      return self;
    };
    // SAFETY: the executor only calls from() and the builder methods above.
    const client = { from: pending } as unknown as PostgrestClientLike;
    const caller = new AbortController();
    const result = await betterSupabase
      .connect(client)
      .tags.findMany({ timeout: 5, signal: caller.signal });
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "timeout", status: 504 },
    });
    expect(caller.signal.aborted).toBe(false);

    const executorLevel = await postgrestExecutor(client, {
      timeout: 5,
    }).execute(
      {
        ...(await captureSelect()),
      },
      { errorMappers: [] },
    );
    expect(executorLevel).toMatchObject({
      ok: false,
      error: { kind: "timeout", message: "The request timed out after 5 ms" },
    });
  });

  it("reports the caller's abort as aborted, not timeout", async () => {
    const { client } = capturingClient();
    const controller = new AbortController();
    controller.abort();
    const result = await betterSupabase
      .connect(client)
      .tags.findMany({ timeout: 1000, signal: controller.signal });
    expect(result).toMatchObject({ ok: false, error: { kind: "aborted" } });
  });

  it.each([0, -1, Number.NaN, "5"])(
    "rejects timeout %j before any request",
    async (timeout) => {
      const { client, requests } = capturingClient();
      const result = await betterSupabase
        .connect(client)
        .tags.findMany({ timeout: timeout as number });
      expect(result).toMatchObject({
        ok: false,
        error: { kind: "invalid_request" },
      });
      expect(requests).toHaveLength(0);
    },
  );
});

describe("resolveUrlLengthLimit", () => {
  // SAFETY: only the urlLengthLimit fields are read.
  const client = (fields: object) => fields as unknown as PostgrestClientLike;

  it.each([
    [{}, {}, 6000],
    [{}, { urlLengthLimit: 9000 }, 9000],
    [{}, { maxUrlLength: 4000 }, 4000],
    [{}, { urlLengthLimit: 3000, maxUrlLength: 4000 }, 3000],
    [{ urlLengthLimit: 8000 }, {}, 6000],
    [{ urlLengthLimit: 2000 }, {}, 2000],
    [{ rest: { urlLengthLimit: 1500 } }, {}, 1500],
    [{ rest: { urlLengthLimit: 1500 } }, { urlLengthLimit: 7000 }, 7000],
  ])("client %j with options %j allows %i", (fields, options, expected) => {
    expect(resolveUrlLengthLimit(client(fields), options)).toBe(expected);
  });

  it("reads db.urlLengthLimit from a supabase-js client", () => {
    const { client: supabase } = capturingClient();
    expect(resolveUrlLengthLimit(supabase, {})).toBe(6000);
  });

  it("chunks with urlLengthLimit, and still accepts maxUrlLength", async () => {
    for (const options of [
      { urlLengthLimit: 200 },
      { maxUrlLength: 200 },
    ] as const) {
      const { client, requests } = capturingClient();
      const ids = Array.from({ length: 40 }, (_, index) => `tag-${index}`);
      const result = await defineSupabase(schema, options)
        .connect(client)
        .tags.findMany({ where: { id: { in: ids } } });
      expect(result.ok).toBe(true);
      expect(requests.length).toBeGreaterThan(1);
    }
  });
});

async function captureSelect(): Promise<Operation> {
  const ops: Operation[] = [];
  const capture: Executor = {
    name: "capture",
    execute: (op) => {
      ops.push(op);
      return Promise.resolve(ok({ rows: [], count: null }));
    },
  };
  await defineSupabase(schema).connect(capture).tags.findMany({ limit: 1 });
  const [op] = ops;
  if (!op) throw new Error("no operation");
  return op;
}
