import { describe, expect, it } from "vitest";

import {
  isChannelAdapter,
  verifySlack,
  verifyWhatsapp,
} from "@/features/inbox/channel-signatures";

const sign = async (secret: string, text: string): Promise<string> => {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(text),
  );

  return [...new Uint8Array(mac)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
};

const request = (headers: Record<string, string>): Request =>
  new Request("https://example.test/hook", { method: "POST", headers });

describe("channel webhooks", () => {
  it("accepts a WhatsApp body signed with the app secret", async () => {
    const body = '{"entry":[]}';
    const signature = await sign("app-secret", body);

    expect(
      await verifyWhatsapp(
        "app-secret",
        request({ "x-hub-signature-256": `sha256=${signature}` }),
        body,
      ),
    ).toBe(true);
  });

  it("rejects a WhatsApp body with a wrong or missing signature", async () => {
    const signature = await sign("other-secret", "{}");

    expect(
      await verifyWhatsapp(
        "app-secret",
        request({ "x-hub-signature-256": `sha256=${signature}` }),
        "{}",
      ),
    ).toBe(false);
    expect(await verifyWhatsapp("app-secret", request({}), "{}")).toBe(false);
  });

  it("accepts a Slack request inside the time window", async () => {
    const signature = await sign("signing", "v0:1000:payload");

    expect(
      await verifySlack(
        "signing",
        request({
          "x-slack-request-timestamp": "1000",
          "x-slack-signature": `v0=${signature}`,
        }),
        "payload",
        1100,
      ),
    ).toBe(true);
  });

  it("rejects a Slack request whose timestamp is stale", async () => {
    const signature = await sign("signing", "v0:1000:payload");

    expect(
      await verifySlack(
        "signing",
        request({
          "x-slack-request-timestamp": "1000",
          "x-slack-signature": `v0=${signature}`,
        }),
        "payload",
        2000,
      ),
    ).toBe(false);
  });

  it("names only the supported adapters", () => {
    expect(isChannelAdapter("whatsapp")).toBe(true);
    expect(isChannelAdapter("sms")).toBe(false);
  });
});
