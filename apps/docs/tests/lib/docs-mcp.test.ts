import { describe, expect, it } from "vitest";

import {
  findPage,
  handleMcpBody,
  negotiateProtocolVersion,
  normalizeDocsPath,
  searchDocs,
  type DocsMcpTools,
  type DocsPageSummary,
} from "../../lib/docs-mcp";

const pages: readonly DocsPageSummary[] = [
  {
    title: "Hono",
    description: "Middleware and REST resources for Hono",
    url: "/docs/frameworks/hono",
    slugs: ["frameworks", "hono"],
  },
  {
    title: "Extension interfaces",
    description: "Executors, caches and sinks",
    url: "/docs/extending/interfaces",
    slugs: ["extending", "interfaces"],
  },
  {
    title: "Quickstart",
    description: "Install and generate",
    url: "/docs/getting-started",
    slugs: ["getting-started"],
  },
];

const tools: DocsMcpTools = {
  search: (query, limit) => searchDocs(pages, query, limit),
  getPage: (path) => {
    const page = findPage(pages, path);
    return Promise.resolve(
      page === null ? null : `# ${page.title}\n\n${page.description}`,
    );
  },
};

describe("searchDocs", () => {
  it("ranks title matches above path matches", () => {
    const hits = searchDocs(pages, "hono");
    expect(hits[0]?.url).toBe("/docs/frameworks/hono");
  });

  it("returns nothing for an empty query", () => {
    expect(searchDocs(pages, "   ")).toEqual([]);
  });

  it("caps the limit", () => {
    expect(searchDocs(pages, "hono", 1)).toHaveLength(1);
  });
});

describe("normalizeDocsPath", () => {
  it("strips /docs, hosts and suffixes", () => {
    expect(normalizeDocsPath("/docs/frameworks/hono")).toEqual([
      "frameworks",
      "hono",
    ]);
    expect(
      normalizeDocsPath("https://bettersupabase.com/docs/frameworks/hono.md"),
    ).toEqual(["frameworks", "hono"]);
    expect(normalizeDocsPath("llms.mdx/docs/frameworks/hono")).toEqual([
      "frameworks",
      "hono",
    ]);
  });
});

describe("findPage", () => {
  it("resolves a slug path", () => {
    expect(findPage(pages, "frameworks/hono")?.title).toBe("Hono");
  });

  it("returns null for an unknown path", () => {
    expect(findPage(pages, "frameworks/missing")).toBeNull();
  });
});

describe("negotiateProtocolVersion", () => {
  it("echoes a known version and otherwise uses 2025-03-26", () => {
    expect(negotiateProtocolVersion("2025-06-18")).toBe("2025-06-18");
    expect(negotiateProtocolVersion("nope")).toBe("2025-03-26");
  });
});

describe("handleMcpBody", () => {
  it("initializes without a subject", async () => {
    const result = await handleMcpBody(
      {
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: { protocolVersion: "2025-03-26" },
      },
      tools,
    );
    expect(result.status).toBe(200);
    expect(result.body).toMatchObject({
      result: {
        serverInfo: { name: "better-supabase-docs" },
        capabilities: { tools: {} },
      },
    });
  });

  it("lists the two read-only tools", async () => {
    const result = await handleMcpBody(
      { jsonrpc: "2.0", id: 2, method: "tools/list" },
      tools,
    );
    expect(result.body).toMatchObject({
      result: {
        tools: [{ name: "search_docs" }, { name: "get_page" }],
      },
    });
  });

  it("searches and fetches a page", async () => {
    const search = await handleMcpBody(
      {
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: { name: "search_docs", arguments: { query: "extension" } },
      },
      tools,
    );
    expect(JSON.stringify(search.body)).toContain("extending/interfaces");

    const page = await handleMcpBody(
      {
        jsonrpc: "2.0",
        id: 4,
        method: "tools/call",
        params: {
          name: "get_page",
          arguments: { path: "/docs/frameworks/hono" },
        },
      },
      tools,
    );
    expect(JSON.stringify(page.body)).toContain("# Hono");
  });

  it("fails closed on an unknown page and an unknown tool", async () => {
    const missing = await handleMcpBody(
      {
        jsonrpc: "2.0",
        id: 5,
        method: "tools/call",
        params: { name: "get_page", arguments: { path: "nope" } },
      },
      tools,
    );
    expect(JSON.stringify(missing.body)).toContain("Unknown page");

    const unknown = await handleMcpBody(
      {
        jsonrpc: "2.0",
        id: 6,
        method: "tools/call",
        params: { name: "delete_page", arguments: {} },
      },
      tools,
    );
    expect(JSON.stringify(unknown.body)).toContain("Unknown tool");
  });

  it("acknowledges initialized with 202 and no body", async () => {
    const result = await handleMcpBody(
      { jsonrpc: "2.0", method: "notifications/initialized" },
      tools,
    );
    expect(result).toEqual({ status: 202, body: null });
  });

  it("rejects a non-request", async () => {
    const result = await handleMcpBody({ hello: true }, tools);
    expect(result.status).toBe(400);
  });
});
