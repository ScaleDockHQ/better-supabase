import { describe, expect, it } from "vitest";

import type { PgQueryable } from "../../src/db.ts";

import { managementSource, pgSource } from "../../src/introspect/source.ts";
import { fakeFetch } from "../fixtures/fake-fetch.ts";

describe("pgSource", () => {
  it("runs concurrent queries one at a time and keeps going after a failure", async () => {
    const events: string[] = [];
    const pending = new Map<string, () => void>();
    const client: PgQueryable = {
      query: <R>(text: string) => {
        events.push(`start ${text}`);
        return new Promise<{ rows: R[] }>((done, fail) => {
          pending.set(text, () => {
            events.push(`end ${text}`);
            if (text === "bad") fail(new Error("syntax error"));
            else done({ rows: [{ text }] as R[] });
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
