import { describe, expect, it, vi } from "vitest";

import type { Knowledge } from "../../../src/blocks/knowledge/index.ts";

import {
  createUrlSource,
  htmlToText,
} from "../../../src/blocks/knowledge/index.ts";
import { refusedUrl } from "../../../src/blocks/knowledge/url-source.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const page = (body: string, type = "text/html", status = 200) =>
  new Response(body, { status, headers: { "content-type": type } });

function fixture(fetcher: typeof fetch) {
  const ingested: Record<string, unknown>[] = [];
  const written: Record<string, unknown>[] = [];

  const doc = {
    id: "d1",
    source: "https://docs.example.com/a",
    metadata: { kind: "url" },
    chunkCount: 1,
    status: "ready",
    embeddingModel: "m",
  };

  const knowledge = {
    ingest: {
      text: vi.fn((input: Record<string, unknown>) => {
        ingested.push(input);

        return AsyncResult.ok({ ...doc, id: "d2" });
      }),
    },
    documents: {
      get: vi.fn(() => AsyncResult.ok(doc)),
      write: vi.fn((input: Record<string, unknown>) => {
        written.push(input);

        return AsyncResult.ok({ ...doc, chunkCount: 2 });
      }),
      page: vi.fn(() =>
        Promise.resolve({
          ok: true,
          data: { items: [doc], hasMore: false, nextCursor: null },
        }),
      ),
    },
  } as unknown as Knowledge;
  // SAFETY: the source calls only these members of Knowledge.

  return {
    ingested,
    written,
    source: createUrlSource({ knowledge, fetch: fetcher }),
  };
}

describe("htmlToText", () => {
  it("keeps headings, drops scripts and decodes entities", () => {
    const { title, text } = htmlToText(
      "<html><head><title>A &amp; B</title></head><body><script>x()</script><h2>Rates</h2><p>5 &lt; 6</p><p>two</p></body></html>",
    );

    expect(title).toBe("A & B");
    expect(text).toBe("## Rates\n\n5 < 6\n\ntwo");
  });

  it("decodes numeric entities and leaves ones it cannot", () => {
    const { text } = htmlToText(
      "<p>&#65; &#x42; &#X43; &#0; &#x110000; &unknown;</p>",
    );

    expect(text).toBe("A B C &#0; &#x110000; &unknown;");
  });
});

describe("refusedUrl", () => {
  it.each([
    "http://localhost/x",
    "http://127.0.0.1/",
    "http://2130706433/",
    "http://10.1.2.3/",
    "http://169.254.169.254/latest",
    "http://192.168.1.1/",
    "http://[::1]/",
    "http://[fd00::1]/",
    "http://[::ffff:7f00:1]/",
    "http://intranet/",
    "http://db.internal/",
    "ftp://example.com/",
    "https://user:pw@example.com/",
  ])("refuses %s", (url) => {
    expect(refusedUrl(new URL(url), undefined)).toBeTypeOf("string");
  });

  it("allows public hosts and matches allowed hosts with subdomains", () => {
    expect(
      refusedUrl(new URL("https://example.com/a"), undefined),
    ).toBeUndefined();
    expect(
      refusedUrl(new URL("https://docs.example.com/"), ["example.com"]),
    ).toBeUndefined();
    expect(
      refusedUrl(new URL("https://evilexample.com/"), ["example.com"]),
    ).toBeTypeOf("string");
  });

  it("refuses the remaining private ranges and accepts public addresses", () => {
    for (const url of [
      "http://0.0.0.0/",
      "http://100.64.1.1/",
      "http://100.127.255.1/",
      "http://172.16.0.1/",
      "http://172.31.1.1/",
      "http://192.0.0.1/",
      "http://198.18.0.1/",
      "http://198.19.0.1/",
      "http://224.0.0.1/",
      "http://[::]/",
      "http://[fe80::1]/",
      "http://[ff02::1]/",
      "http://[::ffff:10.1.2.3]/",
      "http://[::ffff:a00:1]/",
    ]) {
      expect(refusedUrl(new URL(url), undefined)).toBeTypeOf("string");
    }

    expect(refusedUrl(new URL("http://8.8.8.8/"), undefined)).toBeUndefined();
    expect(
      refusedUrl(new URL("http://100.63.0.1/"), undefined),
    ).toBeUndefined();
    expect(
      refusedUrl(new URL("http://172.15.0.1/"), undefined),
    ).toBeUndefined();
    expect(
      refusedUrl(new URL("http://198.51.100.1/"), undefined),
    ).toBeUndefined();
    expect(
      refusedUrl(new URL("http://[2001:db8::1]/"), undefined),
    ).toBeUndefined();
  });
});

describe("createUrlSource", () => {
  it("ingests a page with its URL as the source", async () => {
    const { ingested, source } = fixture(() =>
      Promise.resolve(page("<title>Docs</title><h1>Hi</h1><p>text</p>")),
    );

    await source
      .ingest({ organizationId: "o1", url: "https://docs.example.com/a" })
      .orThrow();

    expect(ingested[0]).toMatchObject({
      organizationId: "o1",
      document: {
        title: "Docs",
        source: "https://docs.example.com/a",
        metadata: { kind: "url", url: "https://docs.example.com/a" },
        text: "# Hi\n\ntext",
      },
    });
  });

  it("checks every redirect hop", async () => {
    const calls: string[] = [];

    const { source } = fixture((input) => {
      calls.push(String(input));

      return Promise.resolve(
        new Response(null, {
          status: 302,
          headers: { location: "http://169.254.169.254/latest" },
        }),
      );
    });

    const result = await source.ingest({
      organizationId: "o1",
      url: "https://example.com/a",
    });

    expect(result.ok).toBe(false);
    expect(result.error?.hint).toBe("KNOWLEDGE_URL_REFUSED");
    expect(calls).toEqual(["https://example.com/a"]);
  });

  it("stops at the size limit and reports a failed status", async () => {
    const { source: big } = fixture(() =>
      Promise.resolve(page("x".repeat(100), "text/plain")),
    );

    const tooBig = createUrlSource({
      knowledge: {} as Knowledge,
      fetch: () => Promise.resolve(page("x".repeat(100), "text/plain")),
      maxBytes: 10,
    });

    expect(
      (await tooBig.ingest({ organizationId: null, url: "https://e.com/" })).ok,
    ).toBe(false);
    expect(big).toBeDefined();

    const { source } = fixture(() =>
      Promise.resolve(page("nope", "text/html", 404)),
    );

    const result = await source.ingest({
      organizationId: "o1",
      url: "https://e.com/",
    });

    expect(result.error?.hint).toBe("KNOWLEDGE_URL_STATUS");
  });

  it("resyncs a document and rewrites its chunks", async () => {
    const { source, written } = fixture(() =>
      Promise.resolve(page("<h1>New</h1><p>body</p>")),
    );

    const result = await source.resync({ documentId: "d1" }).orThrow();

    expect(written[0]).toMatchObject({ documentId: "d1" });
    expect(result.changed).toBe(true);

    const all = await source.resyncAll({ organizationId: "o1" }).orThrow();

    expect(all).toMatchObject({ resynced: 1, failed: [] });
  });

  it("reports a bad URL, a failed fetch, a redirect without a location and a plain body", async () => {
    const knowledge = {} as Knowledge;

    const refused = await createUrlSource({ knowledge, fetch }).ingest({
      organizationId: null,
      url: "not a url",
    });

    expect(refused.error?.hint).toBe("KNOWLEDGE_URL_REFUSED");

    const bare = await createUrlSource({ knowledge }).ingest({
      organizationId: null,
      url: "http://127.0.0.1/",
    });

    expect(bare.error?.hint).toBe("KNOWLEDGE_URL_REFUSED");

    const down = await createUrlSource({
      knowledge,
      fetch: () => Promise.reject("down"),
    }).ingest({ organizationId: null, url: "https://example.com/" });

    expect(down.error?.kind).toBe("network");

    const lost = await createUrlSource({
      knowledge,
      fetch: () => Promise.resolve(new Response(null, { status: 302 })),
    }).ingest({ organizationId: null, url: "https://example.com/a" });

    expect(lost.error?.message).toContain("no location");

    const plain = new Response("plain text");
    plain.headers.delete("content-type");

    const { ingested, source } = fixture(() => Promise.resolve(plain));

    await source
      .ingest({
        organizationId: "o1",
        url: "https://docs.example.com/plain",
        document: { title: "Kept" },
        signal: AbortSignal.timeout(5000),
      })
      .orThrow();

    expect(ingested[0]).toMatchObject({
      document: { title: "Kept", text: "plain text" },
    });
  });

  it("refuses a declared size, an empty body and a document that is not a URL", async () => {
    const huge = createUrlSource({
      knowledge: {} as Knowledge,
      fetch: () =>
        Promise.resolve(
          new Response("hi", {
            headers: {
              "content-length": "999999",
              "content-type": "text/plain",
            },
          }),
        ),
      maxBytes: 10,
    });

    expect(
      (await huge.ingest({ organizationId: null, url: "https://e.com/" })).ok,
    ).toBe(false);

    const { source, ingested } = fixture(() =>
      Promise.resolve(
        new Response(null, { headers: { "content-type": "text/plain" } }),
      ),
    );

    await source
      .ingest({ organizationId: null, url: "https://docs.example.com/empty" })
      .orThrow();

    expect(ingested[0]).toMatchObject({
      document: { text: "", title: "https://docs.example.com/empty" },
    });

    const notUrl = createUrlSource({
      knowledge: {
        documents: {
          get: () =>
            AsyncResult.ok({
              id: "d1",
              metadata: { kind: "file" },
              source: undefined,
            }),
        },
      } as unknown as Knowledge,
      fetch,
    });

    expect((await notUrl.resync({ documentId: "d1" })).error?.hint).toBe(
      "KNOWLEDGE_NOT_URL",
    );
  });

  it("stops resyncing when the page fails and counts an unchanged document", async () => {
    const failed = createUrlSource({
      knowledge: {
        documents: {
          page: () =>
            Promise.resolve({ ok: false, error: dbError("network", "down") }),
        },
      } as unknown as Knowledge,
      fetch,
    });

    expect((await failed.resyncAll({ organizationId: "o1" })).error?.kind).toBe(
      "network",
    );

    const doc = {
      id: "d1",
      source: "https://docs.example.com/a",
      metadata: { kind: "url" },
      chunkCount: 1,
      status: "ready",
      embeddingModel: "m",
    };

    const broken = { ...doc, id: "d2", source: "not a url" };
    let pages = 0;

    const same = createUrlSource({
      knowledge: {
        documents: {
          get: (id: string) => AsyncResult.ok(id === "d2" ? broken : doc),
          write: () => AsyncResult.ok(doc),
          page: () => {
            pages += 1;

            return Promise.resolve({
              ok: true,
              data:
                pages === 1
                  ? { items: [doc, broken], hasMore: true, nextCursor: ["d1"] }
                  : { items: [], hasMore: false, nextCursor: null },
            });
          },
        },
      } as unknown as Knowledge,
      fetch: () => Promise.resolve(page("<p>x</p>")),
    });

    const first = await same.resyncAll({
      organizationId: "o1",
      signal: AbortSignal.timeout(5000),
    });

    expect(first.data).toMatchObject({
      resynced: 1,
      changed: 0,
      failed: [{ documentId: "d2" }],
    });
  });
});
