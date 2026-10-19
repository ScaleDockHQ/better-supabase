import { describe, expect, it } from "vitest";

import type { PgQueryable } from "../../../src/cli/db.ts";

import {
  CLI_QUERY_TAG,
  managementSource,
  pgSource,
} from "../../../src/cli/introspect/source.ts";
import { fakeFetch } from "../fixtures/fake-fetch.ts";

describe("pgSource", () => {
  it("runs concurrent queries one at a time and keeps going after a failure", async () => {
    const events: string[] = [];
    const pending = new Map<string, () => void>();

    const client: PgQueryable = {
      query: <R>(sql: string) => {
        const text = sql.replace(`${CLI_QUERY_TAG}\n`, "");
        events.push(`start ${text}`);

        return new Promise<{ rows: R[] }>((done, fail) => {
          pending.set(text, () => {
            events.push(`end ${text}`);

            if (text === "bad") {
              fail(new Error("syntax error"));
            } else {
              done({ rows: [{ text }] as R[] });
            }
          });
        });
      },
    };

    let closed = 0;
    const urls: string[] = [];

    const source = await pgSource("postgresql://u:p@db/x", (url) => {
      urls.push(url);

      return Promise.resolve({
        client,
        close: () => {
          closed += 1;

          return Promise.resolve();
        },
        describe: "postgresql://u:***@db/x",
      });
    });

    expect(urls).toEqual(["postgresql://u:p@db/x"]);
    expect(source.describe).toBe("postgresql://u:***@db/x");

    const first = source.queryable.query("bad");
    const second = source.queryable.query("second");
    await Promise.resolve();
    expect(events).toEqual(["start bad"]);
    pending.get("bad")!();
    await expect(first).rejects.toThrow("syntax error");
    await new Promise((done) => {
      setTimeout(done, 0);
    });
    expect(events).toEqual(["start bad", "end bad", "start second"]);
    pending.get("second")!();
    expect(await second).toEqual({ rows: [{ text: "second" }] });

    await source.close();
    expect(closed).toBe(1);
  });

  it("asks for a pool and tags each query it sends", async () => {
    const texts: string[] = [];

    const client: PgQueryable = {
      query: <R>(text: string) => {
        texts.push(text);

        return Promise.resolve({ rows: [] as R[] });
      },
    };

    const signal = new AbortController().signal;
    const requested: unknown[] = [];

    const source = await pgSource(
      "postgresql://db/x",
      (_url, _load, options) => {
        requested.push(options);

        return Promise.resolve({
          client,
          pooled: true,
          close: () => Promise.resolve(),
          describe: "postgresql://db/x",
        });
      },
      signal,
    );

    expect(requested).toEqual([{ pool: 4, statementTimeout: 120_000, signal }]);
    expect(await source.queryable.query("select 1")).toEqual({ rows: [] });
    expect(texts).toEqual(["/* better-supabase */\nselect 1"]);
  });
});

describe("managementSource", () => {
  it("uses a custom API URL and closes without a connection", async () => {
    const api = fakeFetch(() => ({ body: [] }));

    const source = managementSource({
      projectRef: "a/b",
      accessToken: "t",
      apiUrl: "http://localhost:9000/",
      fetch: api.fetch,
    });

    expect(source.describe).toBe("project a/b (Management API)");
    expect(await source.queryable.query("select 1")).toEqual({ rows: [] });
    expect(api.calls[0]!.url).toBe(
      "http://localhost:9000/v1/projects/a%2Fb/database/query/read-only",
    );
    await expect(source.close()).resolves.toBeUndefined();
  });

  it("aborts the request when the run's signal aborts", async () => {
    const signals: (AbortSignal | null | undefined)[] = [];
    const controller = new AbortController();

    const source = managementSource({
      projectRef: "abc",
      accessToken: "t",
      fetch: async (_input, init) => {
        signals.push(init?.signal);

        return Response.json([]);
      },
      signal: controller.signal,
    });

    await source.queryable.query("select 1");
    expect(signals[0]?.aborted).toBe(false);
    controller.abort();
    expect(signals[0]?.aborted).toBe(true);
  });

  it("rejects a body that is not a row array", async () => {
    const source = managementSource({
      projectRef: "abc",
      accessToken: "t",
      fetch: fakeFetch(() => ({ body: { message: "ok" } })).fetch,
    });

    await expect(source.queryable.query("select 1")).rejects.toThrow(
      "Management API returned an unexpected body for project abc.",
    );
  });
});
