import {
  convertToModelMessages,
  createUIMessageStreamResponse,
  safeValidateUIMessages,
  streamText,
  toUIMessageStream,
  type UIMessage,
} from "ai";
import * as v from "valibot";

import { env } from "@/env";
import { searchDocs } from "@/lib/docs-mcp";
import { siteUrl } from "@/lib/site-url";
import { getLLMText, getPageSummaries, source } from "@/lib/source";

const MODEL = "anthropic/claude-sonnet-5.5";
const CONTEXT_PAGES = 4;
const MAX_MESSAGES = 20;

const ChatBody = v.object({ messages: v.array(v.unknown()) });

const SYSTEM = `You answer questions about better-supabase, a TypeScript
library for Supabase. Answer only from the documentation pages below. When they
don't cover the question, say so and point to the closest page. Link pages with
their absolute URL. Keep answers short and show code in fenced blocks.`;

function lastUserText(messages: readonly UIMessage[]): string {
  const last = messages.findLast((message) => message.role === "user");
  if (last === undefined) {
    return "";
  }
  return last.parts
    .map((part) => (part.type === "text" ? part.text : ""))
    .join(" ");
}

async function documentation(question: string): Promise<string> {
  const matches = searchDocs(getPageSummaries(), question, CONTEXT_PAGES);
  const pages = await Promise.all(
    matches.map(async (match) => {
      const page = source.getPage([...match.slugs]);
      return page === undefined
        ? ""
        : `URL: ${siteUrl(page.url)}\n${await getLLMText(page)}`;
    }),
  );
  return pages.filter((page) => page !== "").join("\n\n---\n\n");
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

  let json: unknown;
  try {
    json = await request.json();
  } catch {
    return problem(400, "The request body is not JSON");
  }
  const body = v.safeParse(ChatBody, json);
  if (!body.success) {
    return problem(400, "Send between 1 and 20 chat messages");
  }
  const parsed = await safeValidateUIMessages({
    messages: body.output.messages,
  });
  if (!parsed.success || parsed.data.length > MAX_MESSAGES) {
    return problem(400, "Send between 1 and 20 chat messages");
  }

  const result = streamText({
    model: MODEL,
    instructions: `${SYSTEM}\n\n${await documentation(lastUserText(parsed.data))}`,
    messages: await convertToModelMessages(parsed.data),
  });
  return createUIMessageStreamResponse({
    stream: toUIMessageStream({ stream: result.stream }),
  });
}
