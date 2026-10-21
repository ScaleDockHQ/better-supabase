import { describe, expect, it } from "vitest";

import {
  generateSigningKey,
  importSigningKey,
  jwkThumbprint,
  JwsError,
  signCompact,
  verifyCompact,
} from "../../src/core/jws.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const segment = (value: unknown): string =>
  btoa(JSON.stringify(value))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/[=]+$/, "");

describe(`JWS with fully specified algorithms (RFC 9864, ${SPEC_PINS.rfc9864})`, () => {
  it("signs and verifies an Ed25519 key under both EdDSA and Ed25519", async () => {
    const key = await generateSigningKey("Ed25519");
    const kid = await jwkThumbprint(key.publicKey);
    const jwks = { keys: [{ ...key.publicKey, kid }] };
    const signing = await importSigningKey(key.privateKey);

    for (const alg of ["EdDSA", "Ed25519"] as const) {
      const token = await signCompact(
        signing,
        "Ed25519",
        { alg, kid, typ: "JWT" },
        { sub: "u1" },
      );

      const verified = await verifyCompact(token, jwks);
      expect(verified.header["alg"]).toBe(alg);
    }
  });

  it("refuses an algorithm that does not match the key", async () => {
    const key = await generateSigningKey("ES256");
    const kid = await jwkThumbprint(key.publicKey);
    const token = `${segment({ alg: "Ed25519", kid })}.${segment({})}.AA`;
    await expect(
      verifyCompact(token, { keys: [{ ...key.publicKey, kid }] }),
    ).rejects.toBeInstanceOf(JwsError);
  });
});
