import { describe, expect, it } from "vitest";

import type { Jwk, Jwks } from "../../src/core/jws.ts";

import {
  generateSigningKey,
  importSigningKey,
  JwsError,
  jwksOf,
  jwkThumbprint,
  publicJwk,
  signCompact,
  verifyCompact,
} from "../../src/core/jws.ts";

const keySet = (kid: string, jwk: Jwk): Jwks => ({ keys: [{ ...jwk, kid }] });

describe("jws", () => {
  it.each(["Ed25519", "ES256"] as const)(
    "signs and verifies a compact JWS with %s",
    async (alg) => {
      const key = await generateSigningKey(alg);

      const token = await signCompact(
        await importSigningKey(key.privateKey),
        alg,
        { alg: alg === "Ed25519" ? "EdDSA" : "ES256", kid: key.kid },
        { sub: "u1" },
      );

      const verified = await verifyCompact(
        token,
        keySet(key.kid, key.publicKey),
      );

      expect(verified.payload).toEqual({ sub: "u1" });
      expect(key.publicKey).not.toHaveProperty("d");
    },
  );

  it("uses the RFC 7638 thumbprint as kid", async () => {
    // RFC 8037 appendix A.3.
    const jwk = {
      kty: "OKP",
      crv: "Ed25519",
      x: "11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo",
    };

    expect(await jwkThumbprint(jwk)).toBe(
      "kPrK_qmxVWaYVA9wwBF6Iuo3vVzz7TxHCTwXBygrS4k",
    );
  });

  it("refuses a tampered token, an unknown alg and a missing key", async () => {
    const key = await generateSigningKey("Ed25519");
    const signing = await importSigningKey(key.privateKey);

    const token = await signCompact(
      signing,
      "Ed25519",
      { alg: "EdDSA", kid: key.kid, typ: "secevent+jwt" },
      { a: 1 },
    );

    const jwks = keySet(key.kid, key.publicKey);
    const [header, , signature] = token.split(".");
    const forged = `${header}.${btoa('{"a":2}').replaceAll("=", "")}.${signature}`;
    await expect(verifyCompact(forged, jwks)).rejects.toMatchObject({
      code: "JWS_SIGNATURE",
    });
    await expect(
      verifyCompact(token, jwks, { algorithms: ["ES256"] }),
    ).rejects.toBeInstanceOf(JwsError);
    await expect(
      verifyCompact(token, jwks, { typ: "JWT" }),
    ).rejects.toMatchObject({ code: "JWS_TYP" });
    await expect(verifyCompact(token, { keys: [] })).rejects.toMatchObject({
      code: "JWS_KEY",
    });
    await expect(
      verifyCompact(token, jwks, { typ: "SECEVENT+JWT" }),
    ).resolves.toMatchObject({ payload: { a: 1 } });
  });

  it("keeps only Ed25519 and P-256 keys from a key set", () => {
    expect(
      jwksOf({
        keys: [
          { kty: "RSA", n: "x", e: "AQAB" },
          { kty: "OKP", crv: "Ed25519", x: "a" },
          "junk",
        ],
      }).keys,
    ).toEqual([{ kty: "OKP", crv: "Ed25519", x: "a" }]);
    expect(jwksOf(null).keys).toEqual([]);
    expect(() => publicJwk({ kty: "RSA" })).toThrow(TypeError);
  });

  it.each([
    ["RS256", { name: "RSASSA-PKCS1-v1_5" }],
    ["PS256", { name: "RSA-PSS", saltLength: 32 }],
  ] as const)("verifies %s only when listed", async (alg, params) => {
    const pair = await crypto.subtle.generateKey(
      {
        name: params.name,
        modulusLength: 2048,
        publicExponent: new Uint8Array([1, 0, 1]),
        hash: "SHA-256",
      },
      true,
      ["sign", "verify"],
    );

    const jwk = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as Jwk;

    const json = (value: unknown) =>
      btoa(JSON.stringify(value))
        .replaceAll("=", "")
        .replaceAll("+", "-")
        .replaceAll("/", "_");

    const input = `${json({ alg, kid: "r1" })}.${json({ sub: "u1" })}`;

    const signature = new Uint8Array(
      await crypto.subtle.sign(
        params,
        pair.privateKey,
        new TextEncoder().encode(input),
      ),
    );

    const token = `${input}.${btoa(String.fromCodePoint(...signature))
      .replaceAll("=", "")
      .replaceAll("+", "-")
      .replaceAll("/", "_")}`;

    const jwks = jwksOf({ keys: [{ ...jwk, kid: "r1" }] }, { rsa: true });

    expect(jwks.keys).toHaveLength(1);
    await expect(verifyCompact(token, jwks)).rejects.toMatchObject({
      code: "JWS_ALG",
    });
    await expect(
      verifyCompact(token, jwks, { algorithms: [alg] }),
    ).resolves.toMatchObject({ payload: { sub: "u1" } });
    await expect(
      verifyCompact(
        token,
        {
          keys: [
            { ...jwk, kid: "r1", alg: alg === "RS256" ? "PS256" : "RS256" },
          ],
        },
        { algorithms: [alg] },
      ),
    ).rejects.toMatchObject({ code: "JWS_KEY" });
  });

  it("drops RSA keys under 2048 bits", () => {
    expect(
      jwksOf(
        { keys: [{ kty: "RSA", n: "AQAB".repeat(40), e: "AQAB" }] },
        { rsa: true },
      ).keys,
    ).toEqual([]);
  });

  it("refuses malformed tokens, alg none and public keys for signing", async () => {
    const key = await generateSigningKey("Ed25519");
    const jwks = keySet(key.kid, key.publicKey);

    const json = (value: unknown) =>
      btoa(JSON.stringify(value)).replaceAll("=", "");

    for (const token of [
      "a.b",
      "!!.e30.AA",
      `${btoa("[]")}.e30.AA`,
      `${json({ alg: "none" })}.e30.`,
    ]) {
      await expect(verifyCompact(token, jwks)).rejects.toBeInstanceOf(JwsError);
    }

    expect(() => importSigningKey(key.publicKey)).toThrow(TypeError);
  });
});
