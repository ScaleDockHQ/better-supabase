import { UI_MESSAGE_STREAM_HEADERS } from "ai";

import { dbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";

/** A 400 problem response for a malformed chat request. */
export function badRequest(message: string): Response {
  return problemResponse(
    dbError("invalid_request", message, { code: "AI_CHAT_BAD_REQUEST" }),
  );
}

/** The JSON body of a request, or `undefined` when it is not JSON. */
export async function readJson(request: Request): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    return undefined;
  }
}

/** A UI message stream as a response, with extra headers such as the workflow run id. */
export function sse(
  stream: ReadableStream<string>,
  headers: Readonly<Record<string, string>> = {},
): Response {
  return new Response(stream.pipeThrough(new TextEncoderStream()), {
    headers: { ...UI_MESSAGE_STREAM_HEADERS, ...headers },
  });
}
