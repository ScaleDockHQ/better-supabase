import { describe, expect, it } from "vitest";

import {
  hmacHex,
  signWebhook,
  timingSafeEqual,
  verifySharedSecret,
  verifyWebhook,
} from "../../src/core/signatures.ts";

describe("signatures", () => {
  it("hmacHex matches the known HMAC-SHA256 vector", async () => {
    expect(
      await hmacHex("key", "The quick brown fox jumps over the lazy dog"),
    ).toBe("f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8");
  });

  it("timingSafeEqual compares text of equal and different length", () => {
    expect(timingSafeEqual("abc", "abc")).toBe(true);
    expect(timingSafeEqual("abc", "abd")).toBe(false);
    expect(timingSafeEqual("abc", "ab")).toBe(false);
  });

  it("signs and verifies a webhook", async () => {
    const secret = `whsec_${btoa("super-secret-key")}`;
    const body = JSON.stringify({ ok: true });
    const headers = await signWebhook(secret, { id: "msg_1", body });
    const good = await verifyWebhook({ headers, body }, secret);
    expect(good.ok).toBe(true);
    const tampered = await verifyWebhook({ headers, body: `${body} ` }, secret);
    expect(tampered.ok).toBe(false);
  });

  it("verifySharedSecret rejects a wrong secret", () => {
    const request = new Request("https://x.test", {
      headers: { authorization: "Bearer right" },
    });
    expect(verifySharedSecret(request, "right")).toBe(true);
    expect(verifySharedSecret(request, "wrong")).toBe(false);
  });
});
