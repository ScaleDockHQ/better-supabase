import { describe, expect, it, vi } from "vitest";

import type { Knowledge } from "../../../src/blocks/knowledge/index.ts";

import {
  createUrlSource,
  htmlToText,
} from "../../../src/blocks/knowledge/index.ts";
import { refusedUrl } from "../../../src/blocks/knowledge/url-source.ts";
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
});
