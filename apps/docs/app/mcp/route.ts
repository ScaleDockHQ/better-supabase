import { createMcpHandler } from "@modelcontextprotocol/server";
import manifest from "better-supabase/package.json" with { type: "json" };

import { createDocsMcpServer } from "@/lib/docs-mcp";
import { searchHits } from "@/lib/search";
import { getLLMIndex, getLLMText, source } from "@/lib/source";

const handler = createMcpHandler(
  () =>
    createDocsMcpServer({
      version: manifest.version,
      search: searchHits,
      index: getLLMIndex,
      page: async (url) => {
        const page = source.getPageByUrl(url);
        return page === undefined ? undefined : getLLMText(page);
      },
    }),
  { legacy: "stateless" },
);

/** Browser-based clients call the public server cross-origin. */
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, DELETE, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Accept, Authorization, MCP-Protocol-Version, Mcp-Session-Id",
  "Access-Control-Expose-Headers": "MCP-Protocol-Version, Mcp-Session-Id",
  "Access-Control-Max-Age": "86400",
} as const;

async function serve(request: Request): Promise<Response> {
  const response = await handler.fetch(request);
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(CORS)) headers.set(key, value);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export const GET = serve;
export const POST = serve;
export const DELETE = serve;

export function OPTIONS(): Response {
  return new Response(null, { status: 204, headers: CORS });
}
