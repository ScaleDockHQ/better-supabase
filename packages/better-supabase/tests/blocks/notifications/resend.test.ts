import { describe, expect, it, vi } from "vitest";

import type {
  DeliveryEventInput,
  DeliveryTransport,
  EmailMessage,
  RecordedDeliveryEvent,
  SuppressInput,
} from "../../../src/blocks/notifications/index.ts";

import {
  mailHeaders,
  ResendError,
  resendDeliveryEvent,
  resendSuppressions,
  resendTransport,
  resendWebhook,
} from "../../../src/blocks/notifications/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok, type Result } from "../../../src/core/result.ts";
import { signWebhook } from "../../../src/core/signatures.ts";
import { ConformanceError } from "../../../src/testing/conformance.ts";
import { testDeliveryTransport } from "../../../src/testing/delivery-transport.ts";

const SECRET = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw";

function fakeFetch(
  answer: () => Response = () => Response.json({ id: "re_1" }),
) {
  const requests: { url: string; init: RequestInit }[] = [];

  const fetcher = vi.fn(
    async (url: string | URL | Request, init?: RequestInit) => {
      requests.push({ url: String(url), init: init ?? {} });

      return answer();
    },
  );

  return { fetch: fetcher as unknown as typeof fetch, requests };
}

const mail = (overrides: Partial<EmailMessage> = {}): EmailMessage => ({
  from: "Acme <hi@acme.test>",
  to: "u1@acme.test",
  subject: "Assigned",
  text: "You have a task",
  category: "notification",
  headers: mailHeaders("notification", { url: "https://acme.test/u" }),
  ...overrides,
});

describe("resendTransport", () => {
  it("posts to /emails with the idempotency key and the mail headers", async () => {
    const { fetch, requests } = fakeFetch();

    const transport = resendTransport({
      apiKey: "re_test",
      baseUrl: "https://resend.test/",
      fetch,
    });

    expect(
      await transport.send(
        mail({ html: "<p>Hi</p>", replyTo: "s@acme.test" }),
        { idempotencyKey: "d-1" },
      ),
    ).toEqual({ providerMessageId: "re_1" });
    const [request] = requests;
    expect(request?.url).toBe("https://resend.test/emails");
    expect(request?.init).toMatchObject({
      method: "POST",
      redirect: "error",
      headers: {
        authorization: "Bearer re_test",
        "content-type": "application/json",
        "idempotency-key": "d-1",
      },
    });
    expect(JSON.parse(String(request?.init.body))).toEqual({
      from: "Acme <hi@acme.test>",
      to: ["u1@acme.test"],
      subject: "Assigned",
      text: "You have a task",
      html: "<p>Hi</p>",
      reply_to: "s@acme.test",
      headers: {
        "Auto-Submitted": "auto-generated",
        "List-Unsubscribe": "<https://acme.test/u>",
        "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
      },
      tags: [{ name: "category", value: "notification" }],
    });
  });

  it("defaults to api.resend.com and tolerates an answer without an id", async () => {
    const { fetch, requests } = fakeFetch(() => new Response("{}"));
    const transport = resendTransport({ apiKey: "re_test", fetch });
    expect(await transport.send(mail(), { idempotencyKey: "d-2" })).toEqual({});
    expect(requests[0]?.url).toBe("https://api.resend.com/emails");
  });

  it("throws a ResendError with Resend's status, name and message", async () => {
    const { fetch } = fakeFetch(() =>
      Response.json(
        { name: "validation_error", message: "Invalid `to` field" },
        { status: 422 },
      ),
    );

    const transport = resendTransport({ apiKey: "re_test", fetch });

    const failure = await Promise.resolve()
      .then(() => transport.send(mail(), { idempotencyKey: "d-3" }))
      .catch((error: unknown) => error);

    expect(failure).toBeInstanceOf(ResendError);
    expect(failure).toMatchObject({
      status: 422,
      code: "validation_error",
      message: "Resend answered 422: Invalid `to` field",
    });
  });

  it("uses the status text for a body that is not JSON, and status 0 without an answer", async () => {
    const { fetch } = fakeFetch(
      () => new Response("gateway", { status: 502, statusText: "Bad Gateway" }),
    );

    await expect(
      resendTransport({ apiKey: "re_test", fetch }).send(mail(), {
        idempotencyKey: "d-4",
      }),
    ).rejects.toMatchObject({
      status: 502,
      code: undefined,
      message: /Bad Gateway/,
    });

    const offline = vi.fn(async () => {
      throw new TypeError("network down");
    });

    await expect(
      resendTransport({ apiKey: "re_test", fetch: offline }).send(mail(), {
        idempotencyKey: "d-5",
      }),
    ).rejects.toMatchObject({ status: 0, message: /network down/ });
  });

  it("needs an API key", () => {
    expect(() => resendTransport({ apiKey: "" })).toThrow(/apiKey/);
  });

  it("passes the DeliveryTransport conformance kit", async () => {
    const { fetch, requests } = fakeFetch();

    const report = await testDeliveryTransport(
      resendTransport({ apiKey: "re_test", fetch }),
      {
        received: async () =>
          requests.map((request) => {
            const headers = request.init.headers as Record<string, string>;

            const body = JSON.parse(String(request.init.body)) as {
              headers: Record<string, string>;
            };

            return {
              idempotencyKey: headers["idempotency-key"] ?? "",
              headers: body.headers,
            };
          }),
      },
    );

    expect(report.checks.filter((check) => check.ok)).toHaveLength(5);
  });
});

describe("testDeliveryTransport", () => {
  const good: DeliveryTransport = {
    apiVersion: 1,
    channel: "email",
    provider: "good",
    send: () => ({}),
  };

  it("passes a minimal transport", async () => {
    expect((await testDeliveryTransport(good)).checks).toHaveLength(4);
  });

  it("lists every broken check", async () => {
    const broken = {
      apiVersion: 2,
      channel: "sms",
      provider: "",
      send: (message: EmailMessage) => {
        // @ts-expect-error -- a transport that mutates the message
        message.subject = "changed";

        return {};
      },
    } as unknown as DeliveryTransport;

    const failure = await testDeliveryTransport(broken).catch(
      (error: unknown) => error,
    );

    expect(failure).toBeInstanceOf(ConformanceError);
    expect(
      (failure as ConformanceError).report.checks.filter((check) => !check.ok),
    ).toHaveLength(4);
  });

  it("fails when the key or a header never reaches the provider", async () => {
    await expect(
      testDeliveryTransport(good, { received: async () => [] }),
    ).rejects.toThrow(/idempotency key/);
    await expect(
      testDeliveryTransport(good, {
        received: async () => [
          {
            idempotencyKey: "00000000-0000-4000-8000-00000000d0f0",
            headers: { "Auto-Submitted": "auto-generated" },
          },
        ],
      }),
    ).rejects.toThrow(/List-Unsubscribe/);
  });

  it("rejects a receipt with a provider id that is not a string", async () => {
    await expect(
      testDeliveryTransport({
        ...good,
        // @ts-expect-error -- a broken receipt
        send: () => ({ providerMessageId: 7 }),
      }),
    ).rejects.toThrow(/providerMessageId/);
  });
});

describe("resendSuppressions", () => {
  const bounced = {
    type: "email.bounced",
    created_at: "2026-01-01T00:00:00Z",
    data: {
      email_id: "re_9",
      to: ["a@acme.test", "b@acme.test", 7],
      bounce: { type: "Permanent", subType: "General", message: "No mailbox" },
    },
  };

  it("suppresses each recipient of a permanent bounce with the details", () => {
    expect(resendSuppressions(bounced, "msg_1")).toEqual([
      {
        address: "a@acme.test",
        reason: "bounce",
        channel: "email",
        provider: "resend",
        providerEventId: "msg_1",
        detail: {
          emailId: "re_9",
          bounceType: "Permanent",
          subType: "General",
          message: "No mailbox",
        },
      },
      expect.objectContaining({ address: "b@acme.test" }),
    ]);
  });

  it("suppresses a complaint and ignores transient bounces and other events", () => {
    expect(
      resendSuppressions({
        type: "email.complained",
        data: { to: "c@acme.test" },
      }),
    ).toEqual([
      {
        address: "c@acme.test",
        reason: "complaint",
        channel: "email",
        provider: "resend",
        detail: {},
      },
    ]);
    expect(
      resendSuppressions({
        ...bounced,
        data: { ...bounced.data, bounce: { type: "Transient" } },
      }),
    ).toEqual([]);
    expect(resendSuppressions({ type: "email.delivered", data: {} })).toEqual(
      [],
    );
    expect(resendSuppressions(null)).toEqual([]);
    expect(resendSuppressions({ type: "email.bounced" })).toEqual([]);
  });
});

describe("resendDeliveryEvent", () => {
  it("maps each Resend status to a delivery event on the email id", () => {
    expect(
      resendDeliveryEvent(
        {
          type: "email.clicked",
          created_at: "2026-01-01T00:00:00Z",
          data: { email_id: "re_9", click: { link: "https://acme.test/t" } },
        },
        "msg_1",
      ),
    ).toEqual({
      provider: "resend",
      providerMessageId: "re_9",
      kind: "clicked",
      providerEventId: "msg_1",
      occurredAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      detail: { link: "https://acme.test/t" },
    });

    for (const [type, kind] of [
      ["email.delivered", "delivered"],
      ["email.opened", "opened"],
      ["email.bounced", "bounced"],
      ["email.complained", "complained"],
      ["email.delivery_delayed", "delayed"],
    ] as const) {
      expect(
        resendDeliveryEvent({ type, data: { email_id: "re_9" } }),
      ).toMatchObject({ kind, providerMessageId: "re_9" });
    }
  });

  it("keeps a transient bounce from suppressing and carries the bounce details", () => {
    expect(
      resendDeliveryEvent({
        type: "email.bounced",
        created_at: "not a time",
        data: {
          email_id: "re_9",
          bounce: { type: "Transient", subType: "MailboxFull" },
        },
      }),
    ).toEqual({
      provider: "resend",
      providerMessageId: "re_9",
      kind: "bounced",
      detail: { bounceType: "Transient", subType: "MailboxFull" },
      suppress: false,
    });
  });

  it("ignores other events and events without an email id", () => {
    expect(
      resendDeliveryEvent({ type: "email.sent", data: { email_id: "re_9" } }),
    ).toBeUndefined();
    expect(
      resendDeliveryEvent({ type: "email.delivered", data: {} }),
    ).toBeUndefined();
    expect(resendDeliveryEvent({ type: "toString", data: {} })).toBeUndefined();
    expect(resendDeliveryEvent(null)).toBeUndefined();
  });
});

describe("resendWebhook", () => {
  const writer = (result: Result<boolean> = ok(true)) => {
    const written: SuppressInput[] = [];

    return {
      written,
      notifications: {
        suppress: (input: SuppressInput) => {
          written.push(input);

          return new AsyncResult(Promise.resolve(result));
        },
      },
    };
  };

  const signed = async (payload: unknown, prefix = "svix") => {
    const body = JSON.stringify(payload);
    const headers = await signWebhook(SECRET, { id: "msg_1", body });

    const renamed = Object.fromEntries(
      Object.entries(headers).map(([name, value]) => [
        name.replace(/^webhook/, prefix),
        value,
      ]),
    );

    return new Request("https://app.test/hooks/resend", {
      method: "POST",
      headers: renamed,
      body,
    });
  };

  const complaint = { type: "email.complained", data: { to: ["c@acme.test"] } };

  it("verifies the Svix signature and writes the suppression", async () => {
    const { written, notifications } = writer();
    const handle = resendWebhook({ secret: SECRET, notifications });
    const response = await handle(await signed(complaint));
    expect(response.status).toBe(204);
    expect(written).toEqual([
      expect.objectContaining({
        address: "c@acme.test",
        reason: "complaint",
        providerEventId: "msg_1",
      }),
    ]);
  });

  it("accepts Standard Webhooks headers and a rotated secret list", async () => {
    const { written, notifications } = writer();

    const handle = resendWebhook({
      secret: ["whsec_b2xkIHNlY3JldCBrZXkgaGVyZQ==", SECRET],
      notifications,
    });

    expect((await handle(await signed(complaint, "webhook"))).status).toBe(204);
    expect(written).toHaveLength(1);
  });

  it("acknowledges other events without writing", async () => {
    const { written, notifications } = writer();
    const handle = resendWebhook({ secret: SECRET, notifications });

    const response = await handle(
      await signed({ type: "email.delivered", data: { to: ["c@acme.test"] } }),
    );

    expect(response.status).toBe(204);
    expect(written).toEqual([]);
  });

  it("refuses a bad signature, a wrong method and an oversized body", async () => {
    const { written, notifications } = writer();

    const handle = resendWebhook({
      secret: SECRET,
      notifications,
      maxBodyBytes: 64,
    });

    const good = await signed(complaint);

    const forged = new Request(good.url, {
      method: "POST",
      headers: good.headers,
      body: JSON.stringify({ ...complaint, data: { to: ["x@acme.test"] } }),
    });

    expect((await handle(forged)).status).toBe(401);
    expect(
      (await handle(new Request(good.url, { method: "GET" }))).status,
    ).toBe(405);
    const big = await signed({ ...complaint, padding: "x".repeat(200) });
    expect((await handle(big)).status).toBe(413);
    expect(written).toEqual([]);
  });

  it("refuses a replayed message id through seen", async () => {
    const { notifications } = writer();

    const handle = resendWebhook({
      secret: SECRET,
      notifications,
      seen: () => true,
    });

    expect((await handle(await signed(complaint))).status).toBe(409);
  });

  const tracker = (result: Result<RecordedDeliveryEvent | null> = ok(null)) => {
    const recorded: DeliveryEventInput[] = [];
    const base = writer();

    return {
      recorded,
      written: base.written,
      notifications: {
        ...base.notifications,
        recordDeliveryEvent: (input: DeliveryEventInput) => {
          recorded.push(input);

          return new AsyncResult(Promise.resolve(result));
        },
      },
    };
  };

  it("records every status on its delivery, then suppresses as before", async () => {
    const { recorded, written, notifications } = tracker();
    const handle = resendWebhook({ secret: SECRET, notifications });
    expect(
      (
        await handle(
          await signed({ type: "email.opened", data: { email_id: "re_1" } }),
        )
      ).status,
    ).toBe(204);
    expect(
      (
        await handle(
          await signed({
            type: "email.complained",
            data: { email_id: "re_1", to: ["c@acme.test"] },
          }),
        )
      ).status,
    ).toBe(204);
    expect(recorded).toEqual([
      expect.objectContaining({ kind: "opened", providerMessageId: "re_1" }),
      expect.objectContaining({ kind: "complained", providerEventId: "msg_1" }),
    ]);
    expect(written).toEqual([
      expect.objectContaining({ address: "c@acme.test", reason: "complaint" }),
    ]);
  });

  it("answers with the problem of a failed delivery event", async () => {
    const { notifications, written } = tracker(
      err(dbError("unexpected", "db down")),
    );

    const handle = resendWebhook({ secret: SECRET, notifications });

    const response = await handle(
      await signed({
        type: "email.complained",
        data: { email_id: "re_1", to: ["c@acme.test"] },
      }),
    );

    expect(response.status).toBe(500);
    expect(written).toEqual([]);
  });

  it("answers with the problem of a failed write so Resend retries", async () => {
    const { notifications } = writer(err(dbError("unexpected", "db down")));
    const handle = resendWebhook({ secret: SECRET, notifications });
    const response = await handle(await signed(complaint));
    expect(response.status).toBe(500);
    expect(response.headers.get("content-type")).toMatch(/problem\+json/);
  });
});
