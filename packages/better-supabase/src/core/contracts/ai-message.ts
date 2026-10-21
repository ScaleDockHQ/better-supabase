/**
 * The `type` of each part in the canonical AI message (version 1); the SQL
 * module and the message code both read it.
 */
export type AiMessagePartTypeName =
  | "text"
  | "reasoning"
  | "file"
  | "tool-call"
  | "tool-result"
  | "tool-approval"
  | "source"
  | "data"
  | "step";

export const AI_MESSAGE_PART_TYPES: readonly AiMessagePartTypeName[] = [
  "text",
  "reasoning",
  "file",
  "tool-call",
  "tool-result",
  "tool-approval",
  "source",
  "data",
  "step",
];
