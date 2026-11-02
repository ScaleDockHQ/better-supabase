import { describe, expect, it, vi } from "vitest";

import {
  createNotificationDigests,
  digestText,
} from "../../../src/blocks/notifications/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const claim = (id: string, email: string | null) => ({
  digest_id: id,
  user_id: `u-${id}`,
  email,
  channel: "email",
  cadence: "daily",
  items: [
    {
      type: "comment.created",
      summary: "Ada commented",
      action_path: "/tasks/1",
      created_at: "2026-01-01T00:00:00Z",
    },
    { type: "approval.requested", created_at: "2026-01-01T01:00:00Z" },
  ],
});

describe("createNotificationDigests", () => {
  it("sends one email per digest and reports each outcome", async () => {
    const { transport, call } = fakeTransport({
      claim_notification_digests: [
        claim("d1", "ada@example.test"),
        claim("d2", "bob@example.test"),
        claim("d3", null),
      ],
      complete_notification_digest: "sent",
    });

    const send = vi
      .fn()
      .mockReturnValueOnce(AsyncResult.ok({ id: "m1" }))
      .mockReturnValueOnce(AsyncResult.err(dbError("unsupported", "down")));

    const digests = createNotificationDigests({
      transport,
      mailer: { send },
      accountId: "acc",
    });

    expect(await digests.sendDue({ limit: 5 }).orThrow()).toEqual({
      claimed: 3,
      sent: 1,
      failed: 1,
      skipped: 1,
    });
    expect(call).toHaveBeenCalledWith(
      "better_supabase",
      "claim_notification_digests",
      { max_items: 5 },
    );
    expect(send).toHaveBeenCalledWith({
      accountId: "acc",
      draft: {
        to: [{ address: "ada@example.test" }],
        subject: "Your notifications",
        text: "- Ada commented (/tasks/1)\n- approval.requested",
      },
    });
    expect(call).toHaveBeenCalledWith(
      "better_supabase",
      "complete_notification_digest",
      { digest: "d1", status: "sent", provider_message_id: "m1" },
    );
    expect(call).toHaveBeenCalledWith(
      "better_supabase",
      "complete_notification_digest",
      expect.objectContaining({ digest: "d2", status: "pending" }),
    );
    expect(call).toHaveBeenCalledWith(
      "better_supabase",
      "complete_notification_digest",
      expect.objectContaining({ digest: "d3", status: "skipped" }),
    );
  });

  it("names the email with the subject option and reads weekly digests", async () => {
    const { transport } = fakeTransport({
      claim_notification_digests: [
        { ...claim("d1", "a@b.test"), cadence: "weekly" },
      ],
      complete_notification_digest: "sent",
    });

    const send = vi.fn().mockReturnValue(AsyncResult.ok({ id: "m1" }));

    await createNotificationDigests({
      transport,
      mailer: { send },
      accountId: "acc",
      subject: (digest) => `${digest.cadence}: ${digest.items.length}`,
    })
      .sendDue()
      .orThrow();

    expect(send.mock.calls[0]?.[0].draft.subject).toBe("weekly: 2");
  });

  it("renders a line per notification", () => {
    expect(
      digestText({
        id: "d",
        userId: "u",
        email: null,
        channel: "email",
        cadence: "daily",
        items: [{ type: "t", subjectLabel: "Task 1", createdAt: "x" }],
      }),
    ).toBe("- Task 1");
  });
});
