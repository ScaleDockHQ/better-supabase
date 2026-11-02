/* oxlint-disable no-underscore-dangle -- `_sd` and `_sd_alg` are RFC 9901 claim names (3 findings) */
import { describe, expect, it } from "vitest";

import {
  CredentialError,
  issueSdJwt,
  parseSdJwt,
  presentSdJwt,
  signerFromSigningKeys,
  verifySdJwt,
} from "../../src/verifiable-credentials/index.ts";
import { testKey } from "./fixtures.ts";

const VCT = "https://example.com/credentials/qualification";

async function issued(extra: Record<string, unknown> = {}) {
  const issuer = await testKey("Ed25519");
  const holder = await testKey("ES256");

  const token = await issueSdJwt({
    signer: issuer.signer,
    issuer: "https://issuer.example",
    vct: VCT,
    claims: { holder_name: "Ada", level: 3, region: "EU" },
    disclosable: ["holder_name", "level"],
    decoys: 2,
    holderKey: holder.publicKey,
    ...extra,
  });

  return { issuer, holder, token };
}

describe("SD-JWT VC issuance", () => {
  it("hides disclosable claims behind sorted digests and ends with a tilde", async () => {
    const { token } = await issued();
    const parsed = parseSdJwt(token);

    expect(token.endsWith("~")).toBe(true);
    expect(parsed.disclosures.map((item) => item.name).toSorted()).toEqual([
      "holder_name",
      "level",
    ]);

    const payload = JSON.parse(
      atob(parsed.jwt.split(".")[1]!.replaceAll("-", "+").replaceAll("_", "/")),
    );

    expect(payload.holder_name).toBeUndefined();
    expect(payload.region).toBe("EU");
    expect(payload._sd_alg).toBe("sha-256");
    expect(payload._sd).toHaveLength(4);
    expect(payload._sd).toEqual(payload._sd.toSorted());
  });

  it("rejects reserved and unknown claim names", async () => {
    const { issuer } = await issued();
    const base = { signer: issuer.signer, issuer: "i", vct: VCT };

    await expect(issueSdJwt({ ...base, claims: { iss: "x" } })).rejects.toThrow(
      "set by issueSdJwt",
    );
    await expect(
      issueSdJwt({ ...base, claims: { a: 1 }, disclosable: ["b"] }),
    ).rejects.toThrow("not in claims");
  });
});

describe("SD-JWT VC verification", () => {
  it("verifies an issued token and restores every claim", async () => {
    const { issuer, token } = await issued();
    const verified = await verifySdJwt(token, { jwks: issuer.jwks, vct: VCT });

    expect(verified.claims).toMatchObject({
      holder_name: "Ada",
      level: 3,
      region: "EU",
    });
    expect(verified.claims["_sd"]).toBeUndefined();
    expect(verified.header["typ"]).toBe("dc+sd-jwt");
    expect(verified.keyBound).toBe(false);
  });

  it("presents only the revealed claims with a key binding JWT", async () => {
    const { issuer, holder, token } = await issued();

    const presentation = await presentSdJwt(token, {
      reveal: ["level"],
      keyBinding: { signer: holder.signer, audience: "verifier", nonce: "n-1" },
    });

    const verified = await verifySdJwt(presentation, {
      jwks: issuer.jwks,
      requireKeyBinding: true,
      audience: "verifier",
      nonce: "n-1",
    });

    expect(verified.disclosed).toEqual(["level"]);
    expect(verified.claims["holder_name"]).toBeUndefined();
    expect(verified.claims["level"]).toBe(3);
    expect(verified.keyBound).toBe(true);
  });

  it("rejects a wrong nonce, a wrong audience and a missing binding", async () => {
    const { issuer, holder, token } = await issued();

    const presentation = await presentSdJwt(token, {
      reveal: [],
      keyBinding: { signer: holder.signer, audience: "verifier", nonce: "n-1" },
    });

    await expect(
      verifySdJwt(presentation, { jwks: issuer.jwks, nonce: "other" }),
    ).rejects.toMatchObject({ code: "SD_JWT_KEY_BINDING" });
    await expect(
      verifySdJwt(presentation, { jwks: issuer.jwks, audience: "other" }),
    ).rejects.toMatchObject({ code: "SD_JWT_KEY_BINDING" });
    await expect(
      verifySdJwt(token, { jwks: issuer.jwks, requireKeyBinding: true }),
    ).rejects.toMatchObject({ code: "SD_JWT_KEY_BINDING" });
  });

  it("rejects a key binding signed by another key", async () => {
    const { issuer, token } = await issued();
    const stranger = await testKey("ES256");

    const presentation = await presentSdJwt(token, {
      reveal: [],
      keyBinding: { signer: stranger.signer, audience: "v", nonce: "n" },
    });

    await expect(
      verifySdJwt(presentation, { jwks: issuer.jwks }),
    ).rejects.toBeInstanceOf(CredentialError);
  });

  it("rejects a tampered disclosure and a copied one", async () => {
    const { issuer, token } = await issued();
    const parsed = parseSdJwt(token);
    const [first] = parsed.disclosures;

    const forged = btoa(JSON.stringify(["salt", "level", 99])).replaceAll(
      "=",
      "",
    );

    await expect(
      verifySdJwt(`${parsed.jwt}~${forged}~`, { jwks: issuer.jwks }),
    ).rejects.toMatchObject({ code: "SD_JWT_DISCLOSURE" });
    await expect(
      verifySdJwt(`${parsed.jwt}~${first!.encoded}~${first!.encoded}~`, {
        jwks: issuer.jwks,
      }),
    ).rejects.toMatchObject({ code: "SD_JWT_DISCLOSURE" });
  });

  it("rejects an expired token, a wrong vct and a foreign issuer key", async () => {
    const { issuer, token } = await issued({
      issuedAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      expiresAt: Temporal.Instant.from("2026-02-01T00:00:00Z"),
    });

    await expect(
      verifySdJwt(token, {
        jwks: issuer.jwks,
        now: Temporal.Instant.from("2026-03-01T00:00:00Z"),
      }),
    ).rejects.toMatchObject({ code: "SD_JWT_EXPIRED" });
    await expect(
      verifySdJwt(token, {
        jwks: issuer.jwks,
        now: Temporal.Instant.from("2026-01-15T00:00:00Z"),
        vct: "other",
      }),
    ).rejects.toMatchObject({ code: "SD_JWT_VCT" });
    await expect(
      verifySdJwt(token, {
        jwks: (await testKey("Ed25519")).jwks,
        now: Temporal.Instant.from("2026-01-15T00:00:00Z"),
      }),
    ).rejects.toBeInstanceOf(CredentialError);
  });

  it("rejects text that is not an SD-JWT", () => {
    expect(() => parseSdJwt("a.b.c")).toThrow(CredentialError);
  });
});

describe("signerFromSigningKeys", () => {
  it("learns the active key and fails when it rotates mid-signature", async () => {
    const key = await testKey("ES256");
    let kid = "k1";

    const source = {
      sign: (data: Uint8Array) => ({
        orThrow: async () => ({
          kid,
          alg: key.signer.alg,
          signature: await key.signer.sign(data),
        }),
      }),
    };

    const signer = await signerFromSigningKeys(source);

    expect(signer.kid).toBe("k1");
    expect(await signer.sign(new Uint8Array([1]))).toHaveLength(64);

    kid = "k2";
    await expect(signer.sign(new Uint8Array([1]))).rejects.toMatchObject({
      code: "CREDENTIAL_KEY_ROTATED",
    });
  });
});
