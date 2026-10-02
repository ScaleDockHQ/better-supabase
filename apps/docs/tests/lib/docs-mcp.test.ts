import {
  Client,
  StreamableHTTPClientTransport,
} from "@modelcontextprotocol/client";
import { createMcpHandler } from "@modelcontextprotocol/server";
import { afterEach, describe, expect, it } from "vitest";

import {
  createDocsMcpServer,
  DOCS_MCP_NAME,
  type DocsMcpSource,
  docsUrl,
} from "../../lib/docs-mcp";

const PAGES = {
  "/docs/frameworks/hono": "# Hono (/docs/frameworks/hono)\n\nMiddleware.",
  "/docs/cli/gen": "# gen (/docs/cli/gen)\n\nCodegen.",
} as const satisfies Record<string, string>;

const docs: DocsMcpSource = {
  version: "1.2.3",
  search: (query, limit) =>
    Promise.resolve(
      Object.keys(PAGES)
        .filter((url) => url.includes(query))
        .slice(0, limit)
        .map((url) => ({
          url,
          title: url.split("/").at(-1) ?? url,
          type: "page",
        })),
    ),
  index: () => Promise.resolve(Object.keys(PAGES).join("\n")),
  page: (url) =>
    Promise.resolve(
      Object.hasOwn(PAGES, url) ? PAGES[url as keyof typeof PAGES] : undefined,
    ),
};

const handler = createMcpHandler(() => createDocsMcpServer(docs), {
  legacy: "stateless",
});

let client: Client | undefined;

async function connect(): Promise<Client> {
  const connected = new Client({ name: "docs-test", version: "0.0.0" });
  await connected.connect(
    new StreamableHTTPClientTransport(new URL("https://docs.test/mcp"), {
      fetch: (url, init) => handler.fetch(new Request(url, init)),
    }),
  );
  client = connected;
  return connected;
}

const text = (result: { content: unknown }): string =>
  (result.content as { type: string; text: string }[])
    .map((block) => block.text)
    .join("\n");

afterEach(async () => {
  await client?.close();
  client = undefined;
});

describe("docs MCP server", () => {
  it("names itself with the package version and lists read-only tools", async () => {
    const mcp = await connect();
    expect(mcp.getServerVersion()).toMatchObject({
      name: DOCS_MCP_NAME,
      version: "1.2.3",
    });
    expect(mcp.getInstructions()).toContain("search_docs");

    const { tools } = await mcp.listTools();
    expect(tools.map((tool) => tool.name).toSorted()).toEqual([
      "get_page",
      "list_pages",
      "search_docs",
    ]);
    for (const tool of tools) {
      expect(tool.annotations).toEqual({
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      });
    }
    expect(
      tools.find((tool) => tool.name === "search_docs")?.outputSchema,
    ).toMatchObject({ type: "object" });
  });

  it("returns structured search results", async () => {
    const mcp = await connect();
    const result = await mcp.callTool({
      name: "search_docs",
      arguments: { query: "cli", limit: 5 },
    });
    expect(result.structuredContent).toEqual({
      results: [{ url: "/docs/cli/gen", title: "gen", type: "page" }],
    });
    expect(text(result)).toBe("gen (/docs/cli/gen)");

    const none = await mcp.callTool({
      name: "search_docs",
      arguments: { query: "nothing" },
    });
    expect(text(none)).toBe('No pages match "nothing".');
  });

  it("rejects invalid arguments", async () => {
    const mcp = await connect();
    const result = await mcp.callTool({
      name: "search_docs",
      arguments: { query: "", limit: 100 },
    });
    expect(result.isError).toBe(true);
  });

  it("reads a page by any form of its url, and reports a missing one", async () => {
    const mcp = await connect();
    const page = await mcp.callTool({
      name: "get_page",
      arguments: { url: "https://bettersupabase.com/docs/cli/gen.md#options" },
    });
    expect(text(page)).toContain("# gen");

    const missing = await mcp.callTool({
      name: "get_page",
      arguments: { url: "cli/nope" },
    });
    expect(missing.isError).toBe(true);
    expect(text(missing)).toContain("No page at /docs/cli/nope");

    const index = await mcp.callTool({ name: "list_pages", arguments: {} });
    expect(text(index)).toContain("/docs/frameworks/hono");
  });

  it("serves 2025-era clients statelessly", async () => {
    const response = await handler.fetch(
      new Request("https://docs.test/mcp", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json, text/event-stream",
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: {
            protocolVersion: "2025-06-18",
            capabilities: {},
            clientInfo: { name: "old", version: "0.0.0" },
          },
        }),
      }),
    );
    expect(response.status).toBe(200);
    expect(await response.text()).toContain(DOCS_MCP_NAME);
  });
});

describe("docsUrl", () => {
  it("normalizes paths, hosts, suffixes and anchors", () => {
    expect(docsUrl("/docs/frameworks/hono")).toBe("/docs/frameworks/hono");
    expect(docsUrl("frameworks/hono/")).toBe("/docs/frameworks/hono");
    expect(docsUrl("https://bettersupabase.com/docs/cli/gen.md?x=1")).toBe(
      "/docs/cli/gen",
    );
    expect(docsUrl("/docs")).toBe("/docs");
  });
});
