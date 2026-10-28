import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";
import type { InboxMessage } from "./types.ts";

import {
  nullableText,
  oneOf,
  optionalText,
  recordOf,
  recordOrEmpty,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";
import { messageOf } from "./rows.ts";

/** `user` drafts belong to their author; `ai` drafts to the inbox's staff. */
export type InboxDraftSource = "user" | "ai";

export type InboxDraftStatus = "draft" | "sent" | "discarded";

/** What a draft carries: a message or a note, without the service's fields. */
export interface InboxDraftInput {
  /** May stay empty until the draft is sent. */
  readonly body: string;
  readonly kind?: "message" | "note";
  readonly format?: "text" | "markdown";
  readonly attachments?: readonly string[];
  readonly mentions?: readonly string[];
  readonly replyTo?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

export interface InboxDraft {
  readonly id: string;
  readonly tenant: string;
  readonly conversationId: string;
  /** None for an ai draft. */
  readonly authorId: string | null;
  readonly source: InboxDraftSource;
  readonly status: InboxDraftStatus;
  readonly body: string;
  readonly kind: "message" | "note";
  readonly format: "text" | "markdown" | null;
  readonly attachments: readonly string[];
  readonly mentions: readonly string[];
  readonly replyTo: string | null;
  /** The draft's own data, such as the model that wrote it. */
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly updatedAt: Temporal.Instant;
}

export interface InboxDrafts {
  /**
   * Saves the caller's draft on a conversation: their one open draft is
   * replaced, else a new one starts.
   */
  upsert(
    conversationId: string,
    input: InboxDraftInput,
    metadata?: Readonly<Record<string, unknown>>,
  ): AsyncResult<InboxDraft>;
  /** Service only: an ai draft that staff who can reply review. */
  suggest(
    conversationId: string,
    input: InboxDraftInput,
    metadata?: Readonly<Record<string, unknown>>,
  ): AsyncResult<InboxDraft>;
  /**
   * The open drafts the caller sees, newest first: their own and the ai drafts,
   * on one conversation or all.
   */
  list(conversationId?: string): AsyncResult<readonly InboxDraft[]>;
  /**
   * Sends a draft as the caller, with `edits` over its fields, and marks it
   * sent.
   */
  send(
    draftId: string,
    edits?: Partial<InboxDraftInput>,
  ): AsyncResult<InboxMessage>;
  discard(draftId: string): AsyncResult<void>;
}

const SOURCES: readonly InboxDraftSource[] = ["user", "ai"];
const STATUSES: readonly InboxDraftStatus[] = ["draft", "sent", "discarded"];

function draftOf(value: unknown): InboxDraft {
  const row = recordOf(value, "inbox_draft");
  const input = recordOrEmpty(row["input"]);
  const format = input["format"];

  return {
    id: textOf(row["id"]),
    tenant: textOf(row["tenant_id"]),
    conversationId: textOf(row["conversation_id"]),
    authorId: nullableText(row["author_id"]),
    source: oneOf(row["source"], SOURCES, "user"),
    status: oneOf(row["status"], STATUSES, "draft"),
    body: optionalText(input["body"]) ?? "",
    kind: input["kind"] === "note" ? "note" : "message",
    format: format === "text" || format === "markdown" ? format : null,
    attachments: stringsOf(input["attachments"]),
    mentions: stringsOf(input["mentions"]),
    replyTo: nullableText(input["reply_to"]),
    metadata: recordOrEmpty(row["metadata"]),
    updatedAt: requiredInstant(row["updated_at"], "inbox_draft.updated_at"),
  };
}

/**
 * The draft methods of `createInbox`. `inputArg` turns a draft's input into the
 * jsonb `send_inbox_message` takes.
 */
export function inboxDrafts(
  call: BlockCall,
  inputArg: (input: Partial<InboxDraftInput>) => Record<string, unknown>,
): InboxDrafts {
  const write =
    (fn: string) =>
    (
      conversationId: string,
      input: InboxDraftInput,
      metadata?: Readonly<Record<string, unknown>>,
    ): AsyncResult<InboxDraft> =>
      call(
        fn,
        {
          conversation: conversationId,
          input: inputArg(input),
          metadata: metadata ?? null,
        },
        draftOf,
      );

  return {
    upsert: write("save_inbox_draft"),
    suggest: write("suggest_inbox_draft"),
    list: (conversationId) =>
      call(
        "list_inbox_drafts",
        { conversation: conversationId ?? null },
        (value) => recordsOf(value, "list_inbox_drafts").map(draftOf),
      ),
    send: (draftId, edits) =>
      call(
        "send_inbox_draft",
        { draft: draftId, input: edits ? inputArg(edits) : null },
        messageOf,
      ),
    discard: (draftId) =>
      call("discard_inbox_draft", { draft: draftId }, () => undefined),
  };
}
