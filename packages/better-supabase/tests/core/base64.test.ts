import { describe, expect, it } from "vitest";

import {
  base64ToText,
  decodeJwtPayload,
  fromBase64,
  toBase64,
  toBase64Url,
} from "../../src/core/base64.ts";

describe("base64", () => {
  it("encodes text and bytes as padded base64", () => {
    expect(toBase64("hi?")).toBe("aGk/");
    expect(toBase64(new Uint8Array([0xfb, 0xff]))).toBe("+/8=");
  });

  it("encodes base64url without padding", () => {
    expect(toBase64Url(new Uint8Array([0xfb, 0xff]))).toBe("-_8");
  });

  it("decodes padded, unpadded and URL-safe input", () => {
    expect([...fromBase64("+/8=")]).toEqual([0xfb, 0xff]);
    expect([...fromBase64("-_8")]).toEqual([0xfb, 0xff]);
    expect(base64ToText(toBase64Url("héllo"))).toBe("héllo");
  });

  it("throws on invalid input", () => {
    expect(() => fromBase64("!!")).toThrow("Invalid character");
  });
});

describe("decodeJwtPayload", () => {
  const token = (payload: string): string =>
    `e30.${toBase64Url(payload)}.signature`;

  it("reads the claims of a token", () => {
    expect(decodeJwtPayload(token('{"sub":"u","name":"Zoë"}'))).toEqual({
      sub: "u",
      name: "Zoë",
    });
  });

  it("returns undefined for malformed tokens", () => {
    expect(decodeJwtPayload("no-dots")).toBeUndefined();
    expect(decodeJwtPayload(token("not json"))).toBeUndefined();
    expect(decodeJwtPayload(token("null"))).toBeUndefined();
  });
});
