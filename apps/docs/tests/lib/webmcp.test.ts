import { describe, expect, it } from "vitest";

import {
  docsWebMcpTools,
  registerDocsWebMcp,
  type WebMcpTool,
} from "../../lib/webmcp";

const NAME = /^[A-Za-z0-9_.-]{1,128}$/u;

function fakeFetch(routes: Record<string, Response>) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetcher = (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(
      routes[url] ?? new Response("Not found", { status: 404 }),
    );
  };
  return { calls, fetcher };
}

function toolNamed(tools: readonly WebMcpTool[], name: string): WebMcpTool {
  const found = tools.find((tool) => tool.name === name);
  if (found === undefined) throw new Error(`No tool ${name}`);
  return found;
}

describe("docsWebMcpTools", () => {
  it("declares valid, read-only tools with serializable schemas", () => {
    const tools = docsWebMcpTools();
    expect(tools.map((tool) => tool.name)).toEqual([
      "search_docs",
      "read_page",
    ]);
    for (const tool of tools) {
      expect(tool.name).toMatch(NAME);
      expect(tool.description).not.toBe("");
      expect(tool.annotations.readOnlyHint).toBe(true);
      expect(() => JSON.stringify(tool.inputSchema)).not.toThrow();
    }
  });

  it("searches through /api/search without highlights", async () => {
    const { calls, fetcher } = fakeFetch({
      "/api/search?query=verify%20token": Response.json([
        { url: "/docs/auth", type: "page", content: "<mark>Auth</mark>" },
        { url: "/docs/auth#verify", type: "heading", content: "Verify" },
      ]),
    });
    const search = toolNamed(docsWebMcpTools(fetcher), "search_docs");
    const result = await search.execute({ query: "verify token", limit: 1 });
    expect(result).toEqual({
      results: [{ url: "/docs/auth", title: "Auth", type: "page" }],
    });
    expect(JSON.parse(JSON.stringify(result))).toEqual(result);
    expect(calls).toHaveLength(1);
  });

  it("rejects bad search input without fetching", async () => {
    const { calls, fetcher } = fakeFetch({});
    const search = toolNamed(docsWebMcpTools(fetcher), "search_docs");
    expect(await search.execute({ query: " " })).toHaveProperty("error");
    expect(await search.execute({ query: "x", limit: 99 })).toHaveProperty(
      "error",
    );
    expect(calls).toHaveLength(0);
  });

  it("reads a page's Markdown from its .md url", async () => {
    const { calls, fetcher } = fakeFetch({
      "/docs/cli/gen.md": new Response("# gen"),
    });
    const read = toolNamed(docsWebMcpTools(fetcher), "read_page");
    const signal = new AbortController().signal;
    expect(
      await read.execute(
        { url: "https://bettersupabase.com/docs/cli/gen" },
        { signal },
      ),
    ).toEqual({ url: "/docs/cli/gen", markdown: "# gen" });
    expect(calls[0]?.init.signal).toBe(signal);
    expect(await read.execute({ url: "/docs/nope" })).toEqual({
      error: "No page at /docs/nope. Use search_docs to find one.",
    });
  });
});

describe("registerDocsWebMcp", () => {
  it("does nothing without document.modelContext", async () => {
    const signal = new AbortController().signal;
    expect(await registerDocsWebMcp({} as Document, signal)).toBe(false);
    const broken = { modelContext: {} } as unknown as Document;
    expect(await registerDocsWebMcp(broken, signal)).toBe(false);
  });

  it("registers every tool with the lifetime signal", async () => {
    const registered: { name: string; signal: AbortSignal }[] = [];
    const modelContext = {
      registerTool(tool: WebMcpTool, options: { signal: AbortSignal }) {
        registered.push({ name: tool.name, signal: options.signal });
        return Promise.resolve();
      },
    };
    const lifetime = new AbortController();
    const doc = { modelContext } as unknown as Document;
    expect(await registerDocsWebMcp(doc, lifetime.signal)).toBe(true);
    expect(registered).toEqual([
      { name: "search_docs", signal: lifetime.signal },
      { name: "read_page", signal: lifetime.signal },
    ]);
  });
});
