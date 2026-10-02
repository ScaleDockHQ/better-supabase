import { createClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { capturingClient } from "../fixtures/client.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";

// DOM AbortSignal semantics: an aborted signal stops work before it starts,
// an abort during a request rejects the fetch, and either way the caller
// gets a value (an `aborted` DbError), not a thrown AbortError.
const sb = defineSupabase(schema);

/** A fetch that never answers until its signal aborts, as a slow network would. */
function hangingClient() {
  const seen: (AbortSignal | undefined)[] = [];
  const fetch = (
    _input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> => {
    const signal = init?.signal ?? undefined;
    seen.push(signal);
    return new Promise((_resolve, reject) => {
      if (signal?.aborted) reject(signal.reason);
      signal?.addEventListener("abort", () => reject(signal.reason), {
        once: true,
      });
    });
  };
  const client = createClient("http://localhost:54321", "sb_publishable_test", {
    global: { fetch },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return { client, seen };
}

describe("AbortSignal", () => {
  it("an already aborted signal sends no request", async () => {
    const { client, requests } = capturingClient();
    const controller = new AbortController();
    controller.abort();
    const result = await sb
      .connect(client)
      .customers.findMany({ signal: controller.signal });
    expect(result.ok).toBe(false);
    expect(!result.ok && result.error.kind).toBe("aborted");
    expect(requests).toHaveLength(0);
  });

  it("passes the signal to fetch and returns aborted when it fires mid-request", async () => {
    const { client, seen } = hangingClient();
    const controller = new AbortController();
    const pending = sb
      .connect(client)
      .customers.findMany({ signal: controller.signal });
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(seen.at(-1)).toBeDefined();
    controller.abort(new DOMException("stop", "AbortError"));
    const result = await pending;
    expect(!result.ok && result.error.kind).toBe("aborted");
  });

  it("AbortSignal.timeout() works the same way", async () => {
    const { client } = hangingClient();
    const result = await sb
      .connect(client)
      .customers.findMany({ signal: AbortSignal.timeout(5) });
    expect(!result.ok && result.error.kind).toBe("aborted");
  });

  it("an aborted signal on rpc sends no request", async () => {
    const { client, requests } = capturingClient();
    const result = await sb
      .connect(client)
      .$rpc("customer_stats" as never, {} as never, {
        signal: AbortSignal.abort(),
      });
    expect(!result.ok && result.error.kind).toBe("aborted");
    expect(requests).toHaveLength(0);
  });

  it("the Postgres executor checks the signal before it queries", async () => {
    const fake = fakeSql([]);
    const result = await sb
      .connect(postgresExecutor(fake.sql))
      .customers.findMany({ signal: AbortSignal.abort() });
    expect(!result.ok && result.error.kind).toBe("aborted");
    expect(fake.calls).toHaveLength(0);
  });
});
