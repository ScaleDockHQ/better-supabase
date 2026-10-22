import { describe, expect, it, vi } from "vitest";

import type { MailProvider } from "../../../src/blocks/mail-sync/index.ts";

import {
  buildMime,
  gmailMail,
  gmailMessage,
  mailProviderOf,
  newMessageId,
  outlookMail,
  outlookMessage,
  parseAddresses,
} from "../../../src/blocks/mail-sync/index.ts";

const token = { token: "t", headers: { authorization: "Bearer t" } };

const b64url = (value: string): string =>
  btoa(String.fromCodePoint(...new TextEncoder().encode(value)))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/[=]+$/, "");

type Route = (init: RequestInit) => unknown;

/** A fetch that answers by path prefix, JSON bodies by default. */
function fakeFetch(routes: Readonly<Record<string, Route>>) {
  return vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const matching = Object.keys(routes).filter((part) => url.includes(part));

    const key =
      matching.find((part) => url.endsWith(part)) ??
      matching.toSorted((a, b) => b.length - a.length)[0];

    if (key === undefined) {
      return new Response("missing", { status: 404 });
    }

    const answer = routes[key]?.(init ?? {});

    return answer instanceof Response
      ? answer
      : new Response(answer === undefined ? "" : JSON.stringify(answer), {
          status: 200,
        });
  });
}

const gmailFull = {
  id: "g1",
  threadId: "t1",
  labelIds: ["SENT"],
  snippet: "Hello",
  internalDate: "1767225600000",
  payload: {
    mimeType: "multipart/alternative",
    headers: [
      { name: "From", value: '"Ada, L" <Ada@Acme.test>' },
      { name: "To", value: "bob@globex.test, Carol <carol@globex.test>" },
      { name: "Cc", value: "dan@globex.test" },
      { name: "Subject", value: "Hi" },
      { name: "Message-ID", value: "<m1@acme.test>" },
    ],
    parts: [
      { mimeType: "text/plain", body: { data: b64url("Hello there") } },
      { mimeType: "text/html", body: { data: b64url("<p>Hello</p>") } },
    ],
  },
};

describe("mailProviderOf", () => {
  it("refuses another API version", () => {
    const provider = { ...gmailMail(), apiVersion: 2 };

    expect(() =>
      // SAFETY: a provider from a newer release, which the check refuses.
      mailProviderOf(provider as unknown as MailProvider),
    ).toThrow(/mail provider API 2/);
    expect(mailProviderOf(outlookMail()).name).toBe("outlook");
  });
});

describe("parseAddresses", () => {
  it("splits names, quotes and bare addresses", () => {
    expect(parseAddresses(undefined)).toEqual([]);
    expect(
      parseAddresses('"Last, First" <A@B.test>, c@d.test, nobody, <e@f.test>'),
    ).toEqual([
      { address: "a@b.test", name: "Last, First" },
      { address: "c@d.test" },
      { address: "e@f.test" },
    ]);
  });
});

describe("buildMime", () => {
  it("builds a multipart message with reply headers", () => {
    const mime = buildMime({
      from: { address: "me@acme.test", name: "Zoë" },
      draft: {
        to: [{ address: "bob@globex.test" }],
        cc: [{ address: "c@globex.test", name: "Carol" }],
        bcc: [{ address: "d@globex.test" }],
        subject: "Héllo\r\nBcc: evil@x.test",
        text: "Hi",
        html: "<p>Hi</p>",
      },
      messageId: "<id@acme.test>",
      reply: { threadId: "t1", externalId: "g1", messageId: "<m1@acme.test>" },
    });

    expect(mime).toContain("From: =?UTF-8?B?");
    expect(mime).toContain("To: bob@globex.test");
    expect(mime).toContain("Cc: Carol <c@globex.test>");
    expect(mime).toContain("Bcc: d@globex.test");
    expect(mime).toContain("In-Reply-To: <m1@acme.test>");
    expect(mime).toContain('Content-Type: text/html; charset="UTF-8"');
    expect(mime).not.toContain("\r\nBcc: evil");
  });

  it("builds a plain message without reply headers", () => {
    const mime = buildMime({
      from: { address: "me@acme.test" },
      draft: { to: [{ address: "bob@globex.test" }], subject: "Plain" },
      messageId: "<id@acme.test>",
      reply: { threadId: "t1", externalId: "g1" },
    });

    expect(mime).toContain("Subject: Plain");
    expect(mime).not.toContain("Cc:");
    expect(mime).not.toContain("In-Reply-To");
    expect(mime).not.toContain("text/html");
  });

  it("puts a message id on the sender's domain", () => {
    expect(newMessageId({ address: "me@acme.test" })).toMatch(
      /^<[0-9a-f-]+@acme\.test>$/,
    );
    expect(newMessageId({ address: "me" })).toMatch(/@localhost>$/);
  });
});

describe("gmailMessage", () => {
  it("reads a full message", () => {
    const message = gmailMessage(gmailFull);

    expect(message).toMatchObject({
      externalId: "g1",
      threadId: "t1",
      messageId: "<m1@acme.test>",
      direction: "outbound",
      from: { address: "ada@acme.test", name: "Ada, L" },
      to: [
        { address: "bob@globex.test" },
        { address: "carol@globex.test", name: "Carol" },
      ],
      cc: [{ address: "dan@globex.test" }],
      subject: "Hi",
      snippet: "Hello",
      text: "Hello there",
      html: "<p>Hello</p>",
    });
    expect(message?.sentAt.epochMilliseconds).toBe(1_767_225_600_000);
  });

  it("skips drafts and rows without an id, and fills the gaps", () => {
    expect(gmailMessage({ id: "d", labelIds: ["DRAFT"] })).toBeUndefined();
    expect(gmailMessage(null)).toBeUndefined();

    const bare = gmailMessage({ id: "g9", internalDate: "x" });

    expect(bare).toMatchObject({ externalId: "g9", threadId: "g9", to: [] });
    expect(bare?.direction).toBeUndefined();
    expect(bare?.text).toBeUndefined();
  });
});

describe("gmailMail", () => {
  it("reads recent mail on the first sync", async () => {
    const fetch = fakeFetch({
      "/profile": () => ({ historyId: "100" }),
      "/messages?": () => ({
        messages: [{ id: "g1" }, { id: "gone" }, { id: "draft" }, {}],
      }),
      "/messages/g1": () => gmailFull,
      "/messages/draft": () => ({ id: "draft", labelIds: ["DRAFT"] }),
    });

    const gmail = gmailMail({ fetch, initialDays: 7 });

    const page = await gmail.list({ token, limit: 10 }).orThrow();

    expect(page.cursor).toBe("100");
    expect(page.more).toBe(false);
    expect(page.messages.map((message) => message.externalId)).toEqual(["g1"]);
    expect(String(fetch.mock.calls[1]?.[0])).toContain("newer_than%3A7d");
    expect(fetch.mock.calls[0]?.[1]?.headers).toMatchObject({
      authorization: "Bearer t",
    });
  });

  it("reads the history since the cursor", async () => {
    const fetch = fakeFetch({
      "/history": () => ({
        history: [
          { id: "101", messagesAdded: [{ message: { id: "g1" } }, {}] },
          { id: "102", messagesAdded: [{ message: { id: "g1" } }] },
        ],
        historyId: "110",
      }),
      "/messages/g1": () => gmailFull,
    });

    const gmail = gmailMail({ fetch, baseUrl: "https://mail.test" });

    const page = await gmail
      .list({ token, limit: 10, cursor: "100" })
      .orThrow();

    expect(page).toMatchObject({ cursor: "110", more: false });
    expect(page.messages).toHaveLength(1);
  });

  it("pages the history and keeps the cursor without one", async () => {
    const paged = gmailMail({
      fetch: fakeFetch({
        "/history": () => ({ history: [{ id: "105" }], nextPageToken: "n" }),
      }),
    });

    expect(
      await paged.list({ token, limit: 1, cursor: "100" }).orThrow(),
    ).toEqual({ messages: [], cursor: "105", more: true });

    const empty = gmailMail({ fetch: fakeFetch({ "/history": () => ({}) }) });

    expect(
      (await empty.list({ token, limit: 1, cursor: "100" }).orThrow()).cursor,
    ).toBe("100");
  });

  it("starts over when the history id expired", async () => {
    const signal = new AbortController().signal;

    const fetch = fakeFetch({
      "/history": () => new Response("", { status: 404 }),
      "/profile": () => ({}),
      "/messages?": () => ({}),
    });

    const page = await gmailMail({ fetch })
      .list({ token, limit: 5, cursor: "1", signal })
      .orThrow();

    expect(page).toEqual({ messages: [], cursor: "", more: false });
    expect(fetch.mock.calls[0]?.[1]?.signal).toBe(signal);

    const again = await gmailMail({ fetch })
      .list({ token, limit: 5, cursor: "1" })
      .orThrow();

    expect(again.cursor).toBe("");
  });

  it("maps provider errors", async () => {
    const answer = (status: number, headers: Record<string, string> = {}) =>
      gmailMail({
        fetch: fakeFetch({
          "/history": () => new Response("nope", { status, headers }),
        }),
      }).list({ token, limit: 1, cursor: "1" });

    const refused = await answer(401);
    const limited = await answer(429, { "retry-after": "30" });
    const limitedBare = await answer(429);
    const down = await answer(503, { "retry-after": "5" });
    const failing = await answer(500);

    expect(!refused.ok && refused.error).toMatchObject({
      kind: "unauthorized",
      hint: "MAIL_TOKEN_REFUSED",
      message: "gmail answered 401: nope",
    });
    expect(!limited.ok && limited.error).toMatchObject({
      kind: "rate_limited",
      retryAfter: 30,
    });
    expect(!limitedBare.ok && limitedBare.error.kind).toBe("rate_limited");
    expect(!down.ok && down.error).toMatchObject({
      kind: "network",
      retryAfter: 5,
    });
    expect(!failing.ok && failing.error.kind).toBe("network");

    const lost = await gmailMail({
      fetch: fakeFetch({
        "/history": () => ({
          history: [{ messagesAdded: [{ message: { id: "x" } }] }],
        }),
        "/messages/x": () => new Response("", { status: 500 }),
      }),
    }).list({ token, limit: 1, cursor: "1" });

    expect(!lost.ok && lost.error.message).toBe("gmail answered 500");
  });

  it("sends a raw message, on the thread for a reply", async () => {
    const fetch = fakeFetch({
      "/messages/send": () => ({ id: "s1", threadId: "t1" }),
    });

    const gmail = gmailMail({ fetch });
    const draft = { to: [{ address: "bob@globex.test" }], subject: "Hi" };

    const sent = await gmail
      .send({
        token,
        from: { address: "me@acme.test" },
        draft,
        reply: { threadId: "t1", externalId: "g1" },
      })
      .orThrow();

    expect(sent).toMatchObject({ externalId: "s1", threadId: "t1" });
    expect(sent.messageId).toMatch(/@acme\.test>$/);

    const body = JSON.parse(String(fetch.mock.calls[0]?.[1]?.body)) as {
      raw: string;
      threadId?: string;
    };

    expect(body.threadId).toBe("t1");
    expect(atob(body.raw.replaceAll("-", "+").replaceAll("_", "/"))).toContain(
      "Subject: Hi",
    );

    const fresh = await gmailMail({
      fetch: fakeFetch({ "/messages/send": () => ({}) }),
    })
      .send({ token, from: { address: "me@acme.test" }, draft })
      .orThrow();

    expect(fresh).toMatchObject({ externalId: "", threadId: "" });
  });
});

const outlookRow = {
  id: "o1",
  conversationId: "c1",
  internetMessageId: "<o1@globex.test>",
  subject: "Hi",
  bodyPreview: "Hello",
  body: { contentType: "html", content: "<p>Hello</p>" },
  from: { emailAddress: { address: "Bob@Globex.test", name: "Bob" } },
  toRecipients: [{ emailAddress: { address: "me@acme.test" } }, {}],
  ccRecipients: [],
  receivedDateTime: "2026-01-01T00:00:00Z",
};

describe("outlookMessage", () => {
  it("reads a Graph message", () => {
    expect(outlookMessage(outlookRow, "inbox")).toMatchObject({
      externalId: "o1",
      threadId: "c1",
      messageId: "<o1@globex.test>",
      direction: "inbound",
      from: { address: "bob@globex.test", name: "Bob" },
      to: [{ address: "me@acme.test" }],
      html: "<p>Hello</p>",
    });

    const sent = outlookMessage(
      { id: "o2", body: { contentType: "text", content: "Plain" } },
      "sentitems",
    );

    expect(sent).toMatchObject({
      threadId: "o2",
      direction: "outbound",
      text: "Plain",
    });
    expect(sent?.html).toBeUndefined();
    expect(sent?.from).toBeUndefined();
  });

  it("skips drafts, removals and rows without an id", () => {
    expect(outlookMessage({ id: "d", isDraft: true }, "inbox")).toBeUndefined();
    expect(
      outlookMessage({ id: "r", "@removed": {} }, "inbox"),
    ).toBeUndefined();
    expect(outlookMessage({}, "inbox")).toBeUndefined();
  });
});

describe("outlookMail", () => {
  it("reads both folders through delta links", async () => {
    const fetch = fakeFetch({
      "/mailFolders/inbox/": () => ({
        value: [outlookRow, { id: "d", isDraft: true }],
        "@odata.nextLink": "https://graph.test/inbox-next",
      }),
      "/mailFolders/sentitems/": () => ({
        value: [],
        "@odata.deltaLink": "https://graph.test/sent-delta",
      }),
    });

    const outlook = outlookMail({ fetch });

    const page = await outlook.list({ token, limit: 25 }).orThrow();

    expect(page.more).toBe(true);
    expect(page.messages).toHaveLength(1);
    expect(JSON.parse(page.cursor)).toEqual({
      inbox: "https://graph.test/inbox-next",
      sentitems: "https://graph.test/sent-delta",
    });
    expect(fetch.mock.calls[0]?.[1]?.headers).toMatchObject({
      prefer: "odata.maxpagesize=25",
    });

    const next = fakeFetch({
      "https://graph.test/inbox-next": () => ({}),
      "/mailFolders/sentitems/": () => ({}),
    });

    const resumed = await outlookMail({ fetch: next })
      .list({
        token,
        limit: 25,
        cursor: JSON.stringify({
          inbox: "https://graph.test/inbox-next",
          sentitems: "http://evil.test/",
        }),
      })
      .orThrow();

    expect(JSON.parse(resumed.cursor)).toEqual({
      inbox: "https://graph.test/inbox-next",
    });
    expect(String(next.mock.calls[1]?.[0])).toContain(
      "graph.microsoft.com/v1.0/me/mailFolders/sentitems",
    );
  });

  it("ignores an unreadable cursor and returns errors", async () => {
    const fetch = fakeFetch({
      "/mailFolders/": () => new Response("", { status: 403 }),
    });

    const result = await outlookMail({
      fetch,
      baseUrl: "https://graph.test",
    }).list({ token, limit: 1, cursor: "{not json" });

    expect(!result.ok && result.error.kind).toBe("unauthorized");
    expect(String(fetch.mock.calls[0]?.[0])).toContain(
      "https://graph.test/me/mailFolders/inbox",
    );
  });

  it("sends a new message and a reply", async () => {
    const fetch = fakeFetch({
      "/me/messages": () => ({
        id: "n1",
        conversationId: "c9",
        internetMessageId: "<n1@acme.test>",
      }),
      "/createReply": () => ({ id: "r1" }),
      "/send": () => undefined,
    });

    const outlook = outlookMail({ fetch });

    const sent = await outlook
      .send({
        token,
        from: { address: "me@acme.test" },
        draft: {
          to: [{ address: "bob@globex.test", name: "Bob" }],
          subject: "Hi",
          html: "<p>Hi</p>",
        },
      })
      .orThrow();

    expect(sent).toEqual({
      externalId: "n1",
      threadId: "c9",
      messageId: "<n1@acme.test>",
    });

    const created = JSON.parse(String(fetch.mock.calls[0]?.[1]?.body)) as {
      body: { contentType: string };
      toRecipients: unknown[];
    };

    expect(created.body.contentType).toBe("html");
    expect(created.toRecipients).toEqual([
      { emailAddress: { address: "bob@globex.test", name: "Bob" } },
    ]);

    const reply = await outlook
      .send({
        token,
        from: { address: "me@acme.test" },
        draft: {
          to: [{ address: "bob@globex.test" }],
          subject: "Re",
          text: "Ok",
        },
        reply: { threadId: "c1", externalId: "o1" },
      })
      .orThrow();

    expect(reply).toEqual({ externalId: "r1", threadId: "r1" });
    expect(String(fetch.mock.calls[2]?.[0])).toContain(
      "/me/messages/o1/createReply",
    );

    const blank = await outlookMail({
      fetch: fakeFetch({
        "/me/messages": () => ({}),
        "/send": () => undefined,
      }),
    })
      .send({
        token,
        from: { address: "me@acme.test" },
        draft: { to: [], subject: "Empty" },
      })
      .orThrow();

    expect(blank.externalId).toBe("");
  });
});
