import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AiMessage, AiMessagePart, AiToolResultPart } from "./message.ts";

import { aiMessageSchema } from "./message.ts";

/** What `validateMessage` returns: the message, or the schema's issues. */
export type AiMessageCheck =
  | { readonly ok: true; readonly message: AiMessage }
  | { readonly ok: false; readonly issues: readonly StandardSchemaV1.Issue[] };

/** Checks an untrusted value (a request body) against the canonical format. */
export function validateMessage(value: unknown): AiMessageCheck {
  const result = aiMessageSchema["~standard"].validate(value);
  if (result instanceof Promise) {
    throw new TypeError("aiMessageSchema validates synchronously");
  }
  return result.issues
    ? { ok: false, issues: result.issues }
    : { ok: true, message: result.value };
}

/** A stored message with the fields the tree adds to the canonical ones. */
interface Stored extends AiMessage {
  readonly parentId?: string | undefined;
}

/** The canonical messages of a path, in order, without the tree's fields. */
export function pathToHistory(path: readonly Stored[]): AiMessage[] {
  return path.map((message) => ({
    id: message.id,
    role: message.role,
    parts: message.parts,
    ...(message.metadata === undefined ? {} : { metadata: message.metadata }),
  }));
}

/** The output a `tool-result` gets when its call never finished. */
export const INTERRUPTED_TOOL_OUTPUT = "The tool call was interrupted.";

/**
 * Closes every tool call that has no result yet, so a provider accepts the
 * history after a crash or a stop mid-call: each gets a `tool-result` with
 * `isError` right after it. A call waiting for approval is left alone.
 */
export function repairDanglingToolCalls(
  messages: readonly AiMessage[],
): AiMessage[] {
  const answered = new Set<string>();
  const waiting = new Set<string>();
  for (const message of messages) {
    for (const part of message.parts) {
      if (part.type === "tool-result") answered.add(part.toolCallId);
      if (part.type === "tool-approval" && part.state === "requested") {
        waiting.add(part.toolCallId);
      }
    }
  }
  return messages.map((message) => {
    if (!message.parts.some((part) => dangling(part, answered, waiting))) {
      return message;
    }
    const parts: AiMessagePart[] = [];
    for (const part of message.parts) {
      parts.push(part);
      if (part.type === "tool-call" && dangling(part, answered, waiting)) {
        const result: AiToolResultPart = {
          type: "tool-result",
          toolCallId: part.toolCallId,
          toolName: part.toolName,
          output: INTERRUPTED_TOOL_OUTPUT,
          isError: true,
        };
        parts.push(result);
      }
    }
    return { ...message, parts };
  });
}

function dangling(
  part: AiMessagePart,
  answered: ReadonlySet<string>,
  waiting: ReadonlySet<string>,
): boolean {
  return (
    part.type === "tool-call" &&
    part.providerExecuted !== true &&
    !answered.has(part.toolCallId) &&
    !waiting.has(part.toolCallId)
  );
}
