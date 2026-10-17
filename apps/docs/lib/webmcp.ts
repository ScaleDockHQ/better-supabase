import * as v from "valibot";

import { docsUrl, markdownUrl } from "./shared";

const DEFAULT_LIMIT = 8;
const MAX_LIMIT = 25;

type Json =
  | string
  | number
  | boolean
  | null
  | readonly Json[]
  | { readonly [key: string]: Json };

/** The JSON object an agent passes as a tool's input. */
type ToolInput = { readonly [key: string]: Json };

/** A tool as `document.modelContext.registerTool()` takes it (WebMCP draft, 30 September 2026). */
export interface WebMcpTool {
  readonly name: string;
  readonly title: string;
  readonly description: string;
  readonly inputSchema: object;
  readonly annotations: { readonly readOnlyHint: boolean };
  readonly execute: (
    input: ToolInput,
    options?: { readonly signal?: AbortSignal },
  ) => Promise<object>;
}

type Fetch = (url: string, init: RequestInit) => Promise<Response>;

const SearchInput = v.object({
  query: v.pipe(v.string(), v.trim(), v.minLength(1)),
  limit: v.optional(
    v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(MAX_LIMIT)),
  ),
});

const PageInput = v.object({ url: v.pipe(v.string(), v.minLength(1)) });

const SearchResults = v.array(
  v.object({ url: v.string(), type: v.string(), content: v.string() }),
);

const ModelContext = v.object({ registerTool: v.function() });

/** The docs' read-only WebMCP tools, which mirror the docs MCP server. */
export function docsWebMcpTools(fetcher: Fetch = fetch): readonly WebMcpTool[] {
  return [
    {
      name: "search_docs",
      title: "Search the docs",
      description:
        "Full-text search over the better-supabase docs. Returns page and heading urls to pass to read_page.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Keywords" },
          limit: {
            type: "integer",
            minimum: 1,
            maximum: MAX_LIMIT,
            description: `Max results, ${String(DEFAULT_LIMIT)} by default`,
          },
        },
        required: ["query"],
      },
      annotations: { readOnlyHint: true },
      async execute(input, options) {
        const parsed = v.safeParse(SearchInput, input);
        if (!parsed.success) {
          return { error: "Pass a non-empty query and a limit from 1 to 25." };
        }
        const { query, limit = DEFAULT_LIMIT } = parsed.output;
        const response = await fetcher(
          `/api/search?query=${encodeURIComponent(query)}`,
          { signal: options?.signal ?? null },
        );
        const results = v.safeParse(SearchResults, await response.json());
        if (!response.ok || !results.success) {
          return { error: "Search is unavailable. Try again later." };
        }
        return {
          results: results.output.slice(0, limit).map((result) => ({
            url: result.url,
            title: result.content.replaceAll(/<\/?mark>/gu, ""),
            type: result.type,
          })),
        };
      },
    },
    {
      name: "read_page",
      title: "Read a docs page",
      description: "One better-supabase docs page as Markdown, by its url.",
      inputSchema: {
        type: "object",
        properties: {
          url: {
            type: "string",
            description:
              "The page's url from search_docs, for example /docs/cli/gen",
          },
        },
        required: ["url"],
      },
      annotations: { readOnlyHint: true },
      async execute(input, options) {
        const parsed = v.safeParse(PageInput, input);
        if (!parsed.success) {
          return { error: "Pass the page's url." };
        }
        const url = docsUrl(parsed.output.url);
        const response = await fetcher(markdownUrl(url), {
          signal: options?.signal ?? null,
          headers: { Accept: "text/markdown" },
        });
        if (!response.ok) {
          return { error: `No page at ${url}. Use search_docs to find one.` };
        }
        return { url, markdown: await response.text() };
      },
    },
  ];
}

/**
 * Registers the docs tools on `document.modelContext` until `signal` aborts.
 * Returns `false` when the browser has no WebMCP.
 */
export async function registerDocsWebMcp(
  doc: Document,
  signal: AbortSignal,
  fetcher?: Fetch,
): Promise<boolean> {
  if (!("modelContext" in doc) || !v.is(ModelContext, doc.modelContext)) {
    return false;
  }
  const context = doc.modelContext;
  await Promise.all(
    docsWebMcpTools(fetcher).map((tool) =>
      context.registerTool(tool, { signal }),
    ),
  );
  return true;
}
