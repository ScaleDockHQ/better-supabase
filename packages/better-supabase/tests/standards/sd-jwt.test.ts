import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import {
  StatusList,
  issueSdJwt,
  parseSdJwt,
  verifySdJwt,
} from "../../src/verifiable-credentials/index.ts";
import { testKey } from "../verifiable-credentials/fixtures.ts";

describe("SD-JWT, SD-JWT VC and Token Status List", () => {
  it("pins the versions", () => {
    expect(SPEC_PINS.sdJwt).toBe("RFC 9901");
    expect(SPEC_PINS.sdJwtVc).toBe("draft-19");
    expect(SPEC_PINS.tokenStatusList).toBe("draft-21");
  });

  it("computes disclosure digests the way RFC 9901 section 4.2.3 does", async () => {
    // The RFC's example: SHA-256 over the ASCII bytes of the base64url disclosure.
    const disclosure =
      "WyIyR0xDNDJzS1F2ZUNmR2ZyeU5STjl3IiwgImdpdmVuX25hbWUiLCAiSm9obiJd";

    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(disclosure),
    );

    expect(
      btoa(String.fromCodePoint(...new Uint8Array(digest)))
        .replaceAll("+", "-")
        .replaceAll("/", "_")
        .replace(/[=]+$/, ""),
    ).toBe("jsu9yVulwQQlhFlM_3JlzMaSFzglhQG0DpfayQwLUK4");
    expect(parseSdJwt(`a.b.c~${disclosure}~`).disclosures[0]).toMatchObject({
      name: "given_name",
      value: "John",
    });
  });

  it("types the SD-JWT VC dc+sd-jwt and rejects other typ values", async () => {
    const key = await testKey("ES256");

    const token = await issueSdJwt({
      signer: key.signer,
      issuer: "i",
      vct: "v",
      claims: { a: 1 },
    });

    expect((await verifySdJwt(token, { jwks: key.jwks })).header["typ"]).toBe(
      "dc+sd-jwt",
    );

    const [jwt, ...rest] = token.split("~");
    const [h, ...tail] = jwt!.split(".");
    const header = JSON.parse(atob(h!));

    const forged = btoa(JSON.stringify({ ...header, typ: "JWT" })).replaceAll(
      "=",
      "",
    );

    await expect(
      verifySdJwt([[forged, ...tail].join("."), ...rest].join("~"), {
        jwks: key.jwks,
      }),
    ).rejects.toThrow(/typ|signature/i);
  });

  it("orders status bits least significant first (draft-21 section 4)", () => {
    const list = StatusList.create(8);

    list.set(1, 1);
    list.set(7, 1);

    expect(list.bytes[0]).toBe(0b1000_0010);
  });
});
