import { describe, expect, it } from "vitest";

import { createInbox } from "../../../src/blocks/inbox/index.ts";
import {
  conversationRow,
  fakeTransport,
  inboxRow,
  templateRow,
} from "./fixtures.ts";

const PAGE = { items: [] as unknown[], hasMore: false, nextCursor: null };

describe("inbox lists", () => {
  it("pages inboxes and reads one by id", async () => {
    const { transport, call } = fakeTransport({
      page_inboxes: { ...PAGE, items: [inboxRow] },
      get_inbox: inboxRow,
    });

    const inbox = createInbox({ transport });

    const page = await inbox.inboxes
      .page({
        organizationId: "org",
        q: "supp",
        filters: { channel: ["whatsapp", "email"] },
        sort: { by: "name", direction: "asc" },
      })
      .orThrow();

    expect(page.items.map((item) => item.name)).toEqual(["Support"]);

    expect(call.mock.calls[0]?.[1]).toBe("page_inboxes");

    expect(call.mock.calls[0]?.[2]).toMatchObject({
      tenant: "org",
      filters: {
        channel: ["whatsapp", "email"],
        search: "supp",
        sort: "name",
        paged: true,
      },
    });

    expect((await inbox.inboxes.getInbox("i1").orThrow()).id).toBe("i1");
  });

  it("pages templates, counts them and reads one by id", async () => {
    const { transport, call } = fakeTransport({
      page_message_templates: (args: { filters: { count?: boolean } }) =>
        args.filters.count === true
          ? { value: 1, exact: true }
          : { ...PAGE, items: [templateRow] },
      get_message_template: templateRow,
    });

    const inbox = createInbox({ transport });

    const page = await inbox.templates
      .page({ organizationId: "org", filters: { language: ["en"] } })
      .orThrow();

    expect(page.items[0]).toMatchObject({ name: "follow_up", language: "en" });

    expect(
      await inbox.templates
        .count({ organizationId: "org", q: "follow" })
        .orThrow(),
    ).toEqual({ value: 1, exact: true });

    expect(call.mock.calls.at(-1)?.[1]).toBe("page_message_templates");
    expect((await inbox.templates.getTemplate("t1").orThrow()).id).toBe("t1");
  });

  it("sends the priority, sla and tag filters of a conversation page", async () => {
    const { transport, call } = fakeTransport({
      page_inbox_conversations: { ...PAGE, items: [conversationRow] },
    });

    await createInbox({ transport })
      .conversations.page({
        organizationId: "org",
        filters: {
          priority: ["urgent", "high"],
          sla: ["breached"],
          slaMinutes: ["30"],
          tagId: ["g1"],
        },
      })
      .orThrow();

    expect(call.mock.calls[0]?.[2]).toMatchObject({
      tenant: "org",
      filters: {
        priority: ["urgent", "high"],
        sla: ["breached"],
        slaMinutes: ["30"],
        tagId: ["g1"],
      },
    });
  });

  it("refuses a filter the entity does not declare", async () => {
    const { transport } = fakeTransport({});

    const refused = await createInbox({ transport }).inboxes.page({
      organizationId: "org",
      filters: { color: ["red"] },
    });

    expect(!refused.ok && refused.error.kind).toBe("invalid_input");
  });
});
