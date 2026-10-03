import { describe, expect, it } from "vitest";

import {
  type PostgrestClientLike,
  postgrestExecutor,
} from "../../src/index.ts";

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
