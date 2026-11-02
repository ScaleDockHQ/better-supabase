import { describe, expect, it } from "vitest";

import { createInbox } from "../../../src/blocks/inbox/index.ts";
import { AT, fakeTransport, messageRow } from "./fixtures.ts";

const draftRow = {
  id: "d1",
  tenant_id: "o1",
  conversation_id: "c1",
  author_id: "u1",
  source: "user",
  status: "draft",
  input: {
    body: "Hi there",
    kind: "note",
    format: "markdown",
    attachments: ["f1"],
    mentions: ["u2"],
    reply_to: "m1",
  },
  metadata: { model: "m" },
  updated_at: AT,
};

describe("inbox drafts", () => {
  it("upserts, suggests and lists drafts", async () => {
    const { transport, call } = fakeTransport({
      save_inbox_draft: draftRow,
      suggest_inbox_draft: {
        ...draftRow,
        author_id: null,
        source: "ai",
        input: { body: "Try this" },
        metadata: null,
      },
      list_inbox_drafts: [draftRow],
    });

    const { drafts } = createInbox({ transport });

    const saved = await drafts
      .upsert({
        conversationId: "c1",
        input: { body: "Hi there", kind: "note", replyTo: "m1" },
      })
      .orThrow();

    expect(saved).toMatchObject({
      id: "d1",
      authorId: "u1",
      source: "user",
      status: "draft",
      kind: "note",
      format: "markdown",
      attachments: ["f1"],
      mentions: ["u2"],
      replyTo: "m1",
      metadata: { model: "m" },
    });
    expect(call.mock.calls[0]?.[2]).toEqual({
      conversation: "c1",
      input: { body: "Hi there", kind: "note", reply_to: "m1" },
      metadata: null,
    });

    const suggested = await drafts
      .suggest({
        conversationId: "c1",
        input: { body: "Try this" },
        metadata: { model: "m" },
      })
      .orThrow();

    expect(suggested).toMatchObject({
      authorId: null,
      source: "ai",
      kind: "message",
      format: null,
      replyTo: null,
      metadata: {},
    });
    expect(call.mock.calls[1]?.[2]).toMatchObject({ metadata: { model: "m" } });

    expect(await drafts.list().orThrow()).toHaveLength(1);
    expect(call.mock.calls[2]?.[2]).toEqual({ conversation: null });
    await drafts.list("c1").orThrow();
    expect(call.mock.calls[3]?.[2]).toEqual({ conversation: "c1" });
  });

  it("sends a draft with edits and discards one", async () => {
    const { transport, call } = fakeTransport({
      send_inbox_draft: messageRow,
      discard_inbox_draft: true,
    });

    const { drafts } = createInbox({ transport });

    const message = await drafts
      .send({ draftId: "d1", edits: { body: "Edited" } })
      .orThrow();

    expect(message.id).toBe(messageRow["id"]);
    expect(call.mock.calls[0]?.[2]).toEqual({
      draft: "d1",
      input: { body: "Edited" },
    });

    await drafts.send({ draftId: "d1" }).orThrow();
    expect(call.mock.calls[1]?.[2]).toEqual({ draft: "d1", input: null });

    await drafts.discard("d1").orThrow();
    expect(call.mock.calls[2]?.[2]).toEqual({ draft: "d1" });
  });
});
