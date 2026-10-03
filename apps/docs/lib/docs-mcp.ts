import { McpServer, type ToolAnnotations } from "@modelcontextprotocol/server";
import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";

export const DOCS_MCP_NAME = "better-supabase-docs";
const DEFAULT_SEARCH_LIMIT = 8;
const MAX_SEARCH_LIMIT = 25;

const INSTRUCTIONS = `Read-only access to the better-supabase documentation:
a TypeScript library for Supabase (typed repositories, auth, codegen, the CLI
and its doctor checks). Call search_docs with keywords, then get_page with a
result's url for the full Markdown page; list_pages returns the whole index.
No tool needs a token, and none sees your project or your data.`;

/** Every docs tool only reads the published pages. */
const READ_ONLY: ToolAnnotations = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
};

export interface DocsSearchHit {
  readonly url: string;
  readonly title: string;
  readonly type: "page" | "heading" | "text";
}

/** What the server reads; the route backs it with the fumadocs source. */
export interface DocsMcpSource {
  readonly version: string;
  readonly search: (
    query: string,
    limit: number,
  ) => Promise<readonly DocsSearchHit[]>;
  /** `llms.txt`: every page with its url and description. */
  readonly index: () => Promise<string>;
  /** One page as Markdown, or `undefined` when no page has this url. */
  readonly page: (url: string) => Promise<string | undefined>;
}

const SearchInput = v.object({
  query: v.pipe(v.string(), v.minLength(1), v.description("Keywords")),
  limit: v.optional(
    v.pipe(
      v.number(),
      v.integer(),
      v.minValue(1),
      v.maxValue(MAX_SEARCH_LIMIT),
      v.description(`Max results, ${String(DEFAULT_SEARCH_LIMIT)} by default`),
    ),
  ),
});

const SearchOutput = v.object({
  results: v.array(
    v.object({
      url: v.string(),
      title: v.string(),
      type: v.picklist(["page", "heading", "text"]),
    }),
  ),
});

const PageInput = v.object({
  url: v.pipe(
    v.string(),
    v.minLength(1),
    v.description(
      "The page's url from search_docs or list_pages, e.g. /docs/cli/gen",
    ),
  ),
});

const searchInputSchema = toStandardJsonSchema(SearchInput);
const searchOutputSchema = toStandardJsonSchema(SearchOutput);
const pageInputSchema = toStandardJsonSchema(PageInput);

/** `/docs/cli/gen`, `cli/gen`, a full URL or a `.md` route, as the page url. */
export function docsUrl(input: string): string {
  const path = input
    .trim()
    .replace(/^https?:\/\/[^/]+/u, "")
    .split(/[?#]/u)[0]!
    .replace(/\.mdx?$/u, "")
    .replace(/\/+$/u, "");
  const parts = path.split("/").filter((part) => part.length > 0);
  const slugs = parts[0] === "docs" ? parts.slice(1) : parts;
  return `/docs${slugs.length > 0 ? `/${slugs.join("/")}` : ""}`;
}

/** A fresh server per request; `createMcpHandler` calls this. */
export function createDocsMcpServer(docs: DocsMcpSource): McpServer {
  const mcp = new McpServer(
    { name: DOCS_MCP_NAME, version: docs.version },
    { instructions: INSTRUCTIONS },
  );

  mcp.registerTool(
    "search_docs",
    {
      title: "Search the docs",
      description:
        "Full-text search over the better-supabase docs. Returns page and heading urls to pass to get_page.",
      inputSchema: searchInputSchema,
      outputSchema: searchOutputSchema,
      annotations: READ_ONLY,
    },
    async ({ query, limit }) => {
      const results = await docs.search(query, limit ?? DEFAULT_SEARCH_LIMIT);
      const summary =
        results.length === 0
          ? `No pages match "${query}".`
          : results.map((hit) => `${hit.title} (${hit.url})`).join("\n");
      return {
        content: [{ type: "text", text: summary }],
        structuredContent: { results: [...results] },
      };
    },
  );

  mcp.registerTool(
    "list_pages",
    {
      title: "List the docs pages",
      description:
        "Every docs page with its url and description, as llms.txt Markdown.",
      annotations: READ_ONLY,
    },
    async () => ({ content: [{ type: "text", text: await docs.index() }] }),
  );

  mcp.registerTool(
    "get_page",
    {
      title: "Read a docs page",
      description: "One docs page as Markdown, by its url.",
      inputSchema: pageInputSchema,
      annotations: READ_ONLY,
    },
    async ({ url }) => {
      const target = docsUrl(url);
      const markdown = await docs.page(target);
      return markdown === undefined
        ? {
            content: [
              {
                type: "text",
                text: `No page at ${target}. Use search_docs or list_pages to find one.`,
              },
            ],
            isError: true,
          }
        : { content: [{ type: "text", text: markdown }] };
    },
  );

  return mcp;
}
