import { describe, expect, it } from "vitest";

import { serializeDocument, specResponse } from "../../src/spec/serialize.ts";

describe("serializeDocument", () => {
  it("writes indented JSON with a trailing newline", () => {
    expect(serializeDocument({ b: 1, a: [1, { c: undefined }] })).toBe(
      '{\n  "b": 1,\n  "a": [\n    1,\n    {}\n  ]\n}\n',
    );
    expect(serializeDocument({ a: 1 }, { indent: 0 })).toBe('{"a":1}\n');
  });

  it("sorts keys by code unit on request", () => {
    expect(
      serializeDocument(
        { b: 1, B: 2, a: { z: 1, y: 2 } },
        { indent: 0, sortKeys: true },
      ),
    ).toBe('{"B":2,"a":{"y":2,"z":1},"b":1}\n');
  });

  it("rejects values JSON cannot hold", () => {
    expect(() => serializeDocument({ a: [Number.NaN] })).toThrow('at "/a/0"');
    expect(() => serializeDocument({ a: Infinity })).toThrow(
      "has no JSON form",
    );
  });
});

describe("specResponse", () => {
  const document = { openapi: "3.1.2", info: { title: "x" } };

  it("serves the document with a strong SHA-256 ETag", async () => {
    const response = await specResponse(document);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("application/json");
    expect(response.headers.get("cache-control")).toBe("public, no-cache");
    const etag = response.headers.get("etag");
    expect(etag).toMatch(/^"[A-Za-z0-9_-]{43}"$/);
    expect(await response.text()).toBe(serializeDocument(document));
    const again = await specResponse(document);
    expect(again.headers.get("etag")).toBe(etag);
  });

  it("answers 304 to a matching If-None-Match", async () => {
    const etag = (await specResponse(document)).headers.get("etag") ?? "";
    for (const header of [etag, `W/${etag}`, `"other", ${etag}`, "*"]) {
      const response = await specResponse(
        document,
        new Request("https://api.test/openapi.json", {
          headers: { "if-none-match": header },
        }),
      );
      expect(response.status).toBe(304);
      expect(response.headers.get("etag")).toBe(etag);
      expect(await response.text()).toBe("");
    }
    const miss = await specResponse(
      document,
      new Request("https://api.test/openapi.json", {
        headers: { "if-none-match": '"other"' },
      }),
    );
    expect(miss.status).toBe(200);
  });

  it("answers HEAD without a body and rejects other methods", async () => {
    const head = await specResponse(
      document,
      new Request("https://api.test/openapi.json", { method: "HEAD" }),
    );
    expect(head.status).toBe(200);
    expect(head.headers.get("etag")).toBeTruthy();
    expect(await head.text()).toBe("");
    const post = await specResponse(
      document,
      new Request("https://api.test/openapi.json", { method: "POST" }),
    );
    expect(post.status).toBe(405);
    expect(post.headers.get("allow")).toBe("GET, HEAD");
  });

  it("takes the cache, type and indent options", async () => {
    const response = await specResponse({ a: 1 }, undefined, {
      cacheControl: "no-store",
      contentType: "application/openapi+json",
      indent: 0,
    });
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("content-type")).toBe(
      "application/openapi+json",
    );
    expect(await response.text()).toBe('{"a":1}\n');
  });
});
