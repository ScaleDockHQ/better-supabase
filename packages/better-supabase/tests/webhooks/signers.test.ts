import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";

import { temporal } from "../../src/core/temporal-required.ts";
import { testWebhookSigner } from "../../src/testing/index.ts";
import {
  hmacSigner,
  standardWebhooks,
  verifyWebhook,
} from "../../src/webhooks/index.ts";

const SECRET = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw";
const OLD = "whsec_C2FVsBQIhrscChlQIMV+b5sSYspob7oD";
const body = JSON.stringify({ type: "invoice.paid", data: { id: 7 } });

const verify = async (
  request: {
    readonly headers: Readonly<Record<string, string>>;
    readonly body: string;
  },
  secret: string,
) => (await verifyWebhook(request, secret)).ok;

describe("standardWebhooks", () => {
  it("signs with every live secret so receivers on either one verify", async () => {
    const headers = await standardWebhooks().sign({
      id: "msg_1",
      body,
      timestamp: temporal().Now.instant(),
      secrets: [SECRET, OLD],
    });
    expect(headers["webhook-id"]).toBe("msg_1");
    expect(headers["webhook-signature"]?.split(" ")).toHaveLength(2);
    expect(await verify({ headers, body }, SECRET)).toBe(true);
    expect(await verify({ headers, body }, OLD)).toBe(true);
    expect(await verify({ headers, body: `${body} ` }, SECRET)).toBe(false);
  });

  it("renames the headers", async () => {
    const headers = await standardWebhooks({
      headers: {
        id: "svix-id",
        timestamp: "svix-timestamp",
        signature: "svix-signature",
      },
    }).sign({
      id: "msg_1",
      body,
      timestamp: temporal().Now.instant(),
      secrets: [SECRET],
    });
    expect(Object.keys(headers).toSorted()).toEqual([
      "svix-id",
      "svix-signature",
      "svix-timestamp",
    ]);
  });

  it("refuses to sign without a secret", async () => {
    await expect(
      standardWebhooks().sign({
        id: "msg_1",
        body,
        timestamp: temporal().Now.instant(),
        secrets: [],
      }),
    ).rejects.toThrow("no signing secret");
  });

  it("passes the signer conformance kit", async () => {
    const report = await testWebhookSigner(standardWebhooks(), { verify });
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });
});

describe("hmacSigner", () => {
  const timestamp = temporal().Instant.from("2026-01-01T00:00:00Z");
  const seconds = String(timestamp.epochMilliseconds / 1000);

  it("reproduces a v1=<hex> signature over timestamp.body", async () => {
    const signer = hmacSigner({
      signatureHeader: "x-centrakit-signature",
      timestampHeader: "x-centrakit-timestamp",
    });
    const headers = await signer.sign({
      id: "d1",
      body,
      timestamp,
      secrets: [SECRET],
    });
    const expected = createHmac("sha256", SECRET)
      .update(`${seconds}.${body}`)
      .digest("hex");
    expect(headers).toEqual({
      "x-centrakit-signature": `v1=${expected}`,
      "x-centrakit-timestamp": seconds,
    });
  });

  it("takes the signed content, encoding, prefix, separator and id header", async () => {
    const signer = hmacSigner({
      name: "acme",
      signatureHeader: "x-sig",
      idHeader: "x-id",
      content: ({ id, body: text }) => `${id}:${text}`,
      encoding: "base64",
      prefix: "",
      separator: " ",
    });
    expect(signer.name).toBe("acme");
    const headers = await signer.sign({
      id: "d1",
      body,
      timestamp,
      secrets: [SECRET, OLD],
    });
    const mac = (secret: string) =>
      createHmac("sha256", secret).update(`d1:${body}`).digest("base64");
    expect(headers).toEqual({
      "x-sig": `${mac(SECRET)} ${mac(OLD)}`,
      "x-id": "d1",
    });
  });

  it("passes the signer conformance kit", async () => {
    const report = await testWebhookSigner(
      hmacSigner({ signatureHeader: "x-sig" }),
    );
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });
});

describe("testWebhookSigner", () => {
  it("fails a signer that ignores the body", async () => {
    await expect(
      testWebhookSigner({
        apiVersion: 1,
        name: "static",
        sign: () => ({ "x-sig": "same" }),
      }),
    ).rejects.toThrow("the signature must cover the body");
  });

  it("fails a signature the receiver rejects", async () => {
    await expect(
      testWebhookSigner(hmacSigner({ signatureHeader: "x-sig" }), { verify }),
    ).rejects.toThrow("the receiver rejected the signature");
  });
});
