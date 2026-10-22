import { describe, expect, it, vi } from "vitest";

import type { MailProvider } from "../../../src/blocks/mail-sync/index.ts";

import { createMailSync } from "../../../src/blocks/mail-sync/index.ts";
import {
  pixelResponse,
  trackHtml,
  trackingHash,
  trackingHitOf,
} from "../../../src/blocks/mail-sync/tracking.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const BASE = "https://app.test/api/mail/t";

const TOKEN = "a".repeat(43);

const accountRow = {
  id: "a1",
  tenant_id: "org",
  user_id: "u1",
  provider: "gmail",
  address: "me@acme.test",
  credential_ref: { provider: "vault", tenant: "org", key: "gmail" },
  share: "records",
  status: "active",
  sync_cursor: null,
  last_synced_at: null,
  last_error: null,
  created_at: AT,
};

const sentRow = {
  id: "m3",
  thread_id: "t1",
  account_id: "a1",
  external_id: "s1",
  rfc_message_id: null,
  direction: "outbound",
  from_address: "me@acme.test",
  from_name: null,
  to_addresses: ["bob@globex.test"],
  cc_addresses: null,
  subject: "Hi",
  snippet: null,
  body_text: null,
  body_html: "<p>Hi</p>",
  sent_at: AT,
  template_version_id: "v1",
  tracking_hash: "f".repeat(64),
  open_count: 2,
  click_count: 1,
  opened_at: AT,
  clicked_at: AT,
};

const credentials = {
  apiVersion: 1 as const,
  name: "vault",
  getToken: () => AsyncResult.ok({ token: "t", headers: {} }),
  capabilities: () => ({
    userSubjects: true,
    authorization: false,
    revoke: true,
    inbound: false,
  }),
  revoke: () => AsyncResult.ok(true),
};

const gmail = (): MailProvider & { send: ReturnType<typeof vi.fn> } => {
  const send = vi.fn(() =>
    AsyncResult.ok({ externalId: "s1", threadId: "gt1" }),
  );

  return {
    apiVersion: 1,
    name: "gmail",
    list: () => AsyncResult.ok({ messages: [], cursor: "c", more: false }),
    send,
  };
};

const answers = {
  get_mail_account: accountRow,
  record_sent_mail: sentRow,
  track_mail: (args: Record<string, unknown>) =>
    args["link"] === 9
      ? null
      : {
          messageId: "m3",
          url: args["kind"] === "click" ? "https://x.test/a?b=1&c=2" : null,
        },
  mail_template_stats: [
    { templateVersionId: "v1", sent: 3, opened: 2, clicked: 1, replied: 1 },
  ],
};

describe("trackHtml", () => {
  it("rewrites http links and adds the pixel before </body>", async () => {
    const tracked = await trackHtml(
      `<html><body><a class="x" href="https://x.test/a?b=1&amp;c=2">A</a> <a href='http://y.test'>B</a> <a href="mailto:me@x.test">M</a></body></html>`,
      `${BASE}/`,
    );

    expect(tracked.links).toEqual([
      "https://x.test/a?b=1&c=2",
      "http://y.test",
    ]);
    expect(tracked.hash).toMatch(/^[0-9a-f]{64}$/u);
    expect(tracked.html).toMatch(
      /<a class="x" href="https:\/\/app\.test\/api\/mail\/t\/c\/[\w-]{43}\/0">A<\/a>/u,
    );
    expect(tracked.html).toContain("href='https://app.test/api/mail/t/c/");
    expect(tracked.html).toContain('href="mailto:me@x.test"');
    expect(tracked.html).toMatch(
      /\/o\/[\w-]{43}" width="1"[^>]*><\/body><\/html>$/u,
    );

    const token = /\/o\/([\w-]{43})"/u.exec(tracked.html)?.[1] ?? "";

    expect(await trackingHash(token)).toBe(tracked.hash);
  });

  it("appends the pixel without a body and skips links past the limits", async () => {
    const long = `https://x.test/${"l".repeat(2048)}`;

    const many = Array.from(
      { length: 101 },
      (_, index) =>
        `<a href="https://x.test/${String(index)}">${String(index)}</a>`,
    ).join("");

    const tracked = await trackHtml(`<a href="${long}">L</a>${many}`, BASE);

    expect(tracked.links).toHaveLength(100);
    expect(tracked.html).toContain(`href="${long}"`);
    expect(tracked.html).toContain('href="https://x.test/100"');
    expect(tracked.html.endsWith('style="display:none">')).toBe(true);
  });
});

describe("trackingHitOf", () => {
  it("reads opens and clicks", () => {
    expect(trackingHitOf(`${BASE}/o/${TOKEN}`)).toEqual({
      kind: "open",
      token: TOKEN,
    });
    expect(trackingHitOf(`${BASE}/c/${TOKEN}/12?x=1`)).toEqual({
      kind: "click",
      token: TOKEN,
      position: 12,
    });
  });

  it("refuses anything else", () => {
    for (const url of [
      `${BASE}/o/short`,
      `${BASE}/x/${TOKEN}`,
      `${BASE}/c/${TOKEN}/1234`,
      `${BASE}/c/${TOKEN}/-1`,
      `${BASE}/c/${TOKEN}`,
      "https://app.test/",
    ]) {
      expect(trackingHitOf(url)).toBeUndefined();
    }
  });

  it("answers with an uncached gif", async () => {
    const response = pixelResponse();

    expect(response.headers.get("content-type")).toBe("image/gif");
    expect(response.headers.get("cache-control")).toContain("no-store");
    expect(
      new TextDecoder().decode((await response.arrayBuffer()).slice(0, 6)),
    ).toBe("GIF89a");
  });
});

describe("createMailSync tracking", () => {
  it("sends the tracked HTML and stores the original with the hash", async () => {
    const { transport, call } = fakeTransport(answers);
    const provider = gmail();

    const mail = createMailSync({
      transport,
      credentials,
      providers: [provider],
      tracking: { url: BASE },
    });

    const sent = await mail
      .send("a1", {
        to: [{ address: "bob@globex.test" }],
        subject: "Hi",
        html: '<p><a href="https://x.test">x</a></p>',
        templateVersionId: "v1",
      })
      .orThrow();

    expect(sent).toMatchObject({
      templateVersionId: "v1",
      tracked: true,
      openCount: 2,
      clickCount: 1,
    });
    expect(sent.openedAt?.toString()).toBe(AT);
    expect(sent.clickedAt?.toString()).toBe(AT);

    const draft = provider.send.mock.lastCall?.[0]?.draft as Record<
      string,
      unknown
    >;

    expect(draft["html"]).toContain(`${BASE}/c/`);
    expect(draft).not.toHaveProperty("templateVersionId");
    expect(draft).not.toHaveProperty("track");
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "record_sent_mail",
      {
        account: "a1",
        message: expect.objectContaining({
          html: '<p><a href="https://x.test">x</a></p>',
          templateVersionId: "v1",
          trackingHash: expect.stringMatching(/^[0-9a-f]{64}$/u),
          trackedLinks: ["https://x.test"],
        }),
      },
    );
  });

  it("leaves a message untracked when asked, or without HTML", async () => {
    const { transport, call } = fakeTransport({
      ...answers,
      record_sent_mail: {
        ...sentRow,
        template_version_id: null,
        tracking_hash: null,
        open_count: null,
        click_count: null,
        opened_at: null,
        clicked_at: null,
      },
    });

    const provider = gmail();

    const mail = createMailSync({
      transport,
      credentials,
      providers: [provider],
      tracking: { url: BASE },
    });

    const sent = await mail
      .send("a1", {
        to: [{ address: "bob@globex.test" }],
        subject: "Hi",
        html: "<p>Hi</p>",
        track: false,
      })
      .orThrow();

    expect(sent).toMatchObject({ tracked: false, openCount: 0, clickCount: 0 });
    expect(sent.templateVersionId).toBeUndefined();
    expect(provider.send.mock.lastCall?.[0]?.draft.html).toBe("<p>Hi</p>");

    await mail
      .send("a1", { to: [{ address: "bob@globex.test" }], subject: "Text" })
      .orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "record_sent_mail",
      {
        account: "a1",
        message: expect.not.objectContaining({
          trackingHash: expect.anything(),
        }),
      },
    );
  });

  it("refuses to track without a tracking URL", async () => {
    const { transport, call } = fakeTransport(answers);

    const mail = createMailSync({
      transport,
      credentials,
      providers: [gmail()],
    });

    const sent = await mail.send("a1", {
      to: [{ address: "bob@globex.test" }],
      subject: "Hi",
      html: "<p>Hi</p>",
      track: true,
    });

    expect(sent.ok ? undefined : sent.error.hint).toBe("MAIL_TRACKING_MISSING");
    expect(call).not.toHaveBeenCalled();
  });

  it("answers the tracking route", async () => {
    const { transport, call } = fakeTransport(answers);
    const mail = createMailSync({ transport });

    const open = await mail
      .track(
        new Request(`${BASE}/o/${TOKEN}`, {
          headers: { "user-agent": "u".repeat(400) },
        }),
      )
      .orThrow();

    expect(open.headers.get("content-type")).toBe("image/gif");
    expect(call).toHaveBeenLastCalledWith("better_supabase", "track_mail", {
      hash: await trackingHash(TOKEN),
      kind: "open",
      link: null,
      user_agent: "u".repeat(300),
    });

    const click = await mail
      .track(new Request(`${BASE}/c/${TOKEN}/0`))
      .orThrow();

    expect(click.status).toBe(302);
    expect(click.headers.get("location")).toBe("https://x.test/a?b=1&c=2");
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "track_mail",
      expect.objectContaining({ kind: "click", link: 0, user_agent: null }),
    );

    expect(
      (await mail.track(new Request(`${BASE}/c/${TOKEN}/9`)).orThrow()).status,
    ).toBe(404);
    expect(
      (await mail.track(new Request(`${BASE}/nope`)).orThrow()).status,
    ).toBe(404);
  });

  it("returns a failed tracking call", async () => {
    const { transport } = fakeTransport({
      track_mail: () => {
        throw new Error("down");
      },
    });

    const tracked = await createMailSync({ transport }).track(
      new Request(`${BASE}/o/${TOKEN}`),
    );

    expect(tracked.ok).toBe(false);
  });

  it("reads template stats", async () => {
    const { transport, call } = fakeTransport(answers);
    const mail = createMailSync({ transport });

    expect(await mail.templateStats("org").orThrow()).toEqual([
      { templateVersionId: "v1", sent: 3, opened: 2, clicked: 1, replied: 1 },
    ]);
    await mail
      .templateStats("org", { since: Temporal.Instant.from(AT) })
      .orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "mail_template_stats",
      { tenant: "org", since: AT },
    );
  });
});
