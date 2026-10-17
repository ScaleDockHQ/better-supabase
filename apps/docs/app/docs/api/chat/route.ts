import {
  convertToModelMessages,
  createUIMessageStreamResponse,
  isStepCount,
  safeValidateUIMessages,
  streamText,
  toUIMessageStream,
  tool,
  type UIMessage,
} from "ai";
import { checkBotId } from "botid/server";
import * as v from "valibot";

import { env } from "@/env";
import {
  DEFAULT_SEARCH_LIMIT,
  pageInputSchema,
  searchInputSchema,
} from "@/lib/docs-mcp";
import { searchDocs } from "@/lib/page-search";
import { searchHits } from "@/lib/search";
import { docsUrl } from "@/lib/shared";
import { siteUrl } from "@/lib/site-url";
import { getPageMarkdown, getPageSummaries } from "@/lib/source";

const MODEL = "anthropic/claude-sonnet-5.5";
const SEED_PAGES = 6;
const MAX_MESSAGES = 20;
const MAX_STEPS = 5;

const ChatBody = v.object({ messages: v.array(v.unknown()) });

const SYSTEM = `You answer questions about better-supabase, a TypeScript
library for Supabase. Answer only from the documentation: call read_page for
the pages below that look relevant, and search_docs when none fit. When the
docs don't cover the question, say so and point to the closest page. Link
pages with their absolute URL. Keep answers short and show code in fenced
blocks.`;

/** Read-only tools over the published pages, the same ones the docs MCP server has. */
const tools = {
  search_docs: tool({
    description:
      "Full-text search over the better-supabase docs. Returns page and heading urls to pass to read_page.",
    inputSchema: searchInputSchema,
    execute: async ({ query, limit }) =>
      searchHits(query, limit ?? DEFAULT_SEARCH_LIMIT),
  }),
  read_page: tool({
    description: "One docs page as Markdown, by its url.",
    inputSchema: pageInputSchema,
    execute: async ({ url }) => {
      const target = docsUrl(url);
      return (
        (await getPageMarkdown(target)) ??
        `No page at ${target}. Use search_docs to find one.`
      );
    },
  }),
};

function lastUserText(messages: readonly UIMessage[]): string {
  const last = messages.findLast((message) => message.role === "user");
  if (last === undefined) {
    return "";
  }
  return last.parts
    .map((part) => (part.type === "text" ? part.text : ""))
    .join(" ");
}

/** Candidate pages for the question, so the first step can read instead of search. */
function candidates(question: string): string {
  const matches = searchDocs(getPageSummaries(), question, SEED_PAGES);
  if (matches.length === 0) {
    return "No page title matches the question.";
  }
  return matches
    .map(
      (match) =>
        `- ${match.title} (${siteUrl(match.url)}): ${match.description}`,
    )
    .join("\n");
}

function problem(status: number, detail: string): Response {
  return Response.json(
    { type: "about:blank", title: detail, status },
    { status, headers: { "Content-Type": "application/problem+json" } },
  );
}

export async function POST(request: Request): Promise<Response> {
  if (
    env.AI_GATEWAY_API_KEY === undefined &&
    env.VERCEL_OIDC_TOKEN === undefined
  ) {
    return problem(503, "Ask AI is not configured on this deployment");
  }

  const [verdict, body] = await Promise.all([
    checkBotId().catch(() => undefined),
    request.json().then(
      (json) => v.safeParse(ChatBody, json),
      () => null,
    ),
  ]);
  if (verdict === undefined) {
    return problem(503, "Bot protection is not available on this deployment");
  }
  if (verdict.isBot) {
    return problem(403, "Ask AI is not available to automated clients");
  }
  if (body === null) {
    return problem(400, "The request body is not JSON");
  }
  if (!body.success) {
    return problem(400, "Send between 1 and 20 chat messages");
  }
  const parsed = await safeValidateUIMessages({
    messages: body.output.messages,
    tools,
  });
  if (!parsed.success || parsed.data.length > MAX_MESSAGES) {
    return problem(400, "Send between 1 and 20 chat messages");
  }

  const messages = await convertToModelMessages(parsed.data, {
    tools,
    ignoreIncompleteToolCalls: true,
  });
  const result = streamText({
    model: MODEL,
    instructions: `${SYSTEM}\n\nPages that may answer it:\n${candidates(
      lastUserText(parsed.data),
    )}`,
    messages,
    tools,
    stopWhen: isStepCount(MAX_STEPS),
  });
  return createUIMessageStreamResponse({
    stream: toUIMessageStream({ stream: result.stream }),
  });
}
