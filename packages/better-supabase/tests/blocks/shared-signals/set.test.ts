import { describe, expect, it } from "vitest";

import {
  CAEP_EVENTS,
  mintSet,
  verifySet,
} from "../../../src/blocks/shared-signals/index.ts";
import { signingKey } from "./fixtures.ts";

const ISSUER = "https://tx.example";
const SUBJECT = { format: "email", email: "ada@example.com" };
const EVENT = {
  type: CAEP_EVENTS.sessionRevoked,
  claims: { event_timestamp: 1_900_000_000 },
};

describe("SETs", () => {
  it("mints an SSF SET that verifies with the transmitter's keys", async () => {
    const { signer, jwks } = await signingKey();
    const minted = await mintSet(signer, {
      issuer: ISSUER,
      audience: ["rx"],
      subject: SUBJECT,
      event: EVENT,
      txn: "t1",
    }).orThrow();
    const [header, payload] = minted.token
      .split(".")
      .slice(0, 2)
      .map((part) => JSON.parse(Buffer.from(part, "base64url").toString()));
    expect(header).toMatchObject({ typ: "secevent+jwt", alg: "EdDSA" });
    expect(payload).toMatchObject({
      iss: ISSUER,
      aud: "rx",
      jti: minted.jti,
      txn: "t1",
      sub_id: SUBJECT,
    });
    expect(payload).not.toHaveProperty("sub");
    expect(payload).not.toHaveProperty("exp");
    const verified = await verifySet(minted.token, {
      jwks,
      issuer: ISSUER,
      audience: "rx",
    });
    expect(verified).toMatchObject({
      ok: true,
      set: {
        jti: minted.jti,
        type: EVENT.type,
        claims: EVENT.claims,
        txn: "t1",
      },
    });
  });

  it("answers with the RFC 8935 error code", async () => {
    const { signer, jwks } = await signingKey();
    const other = await signingKey();
    const { token } = await mintSet(signer, {
      issuer: ISSUER,
      audience: "rx",
      subject: SUBJECT,
      event: EVENT,
    }).orThrow();
    const check = (options: Partial<Parameters<typeof verifySet>[1]>) =>
      verifySet(token, { jwks, issuer: ISSUER, audience: "rx", ...options });
    expect(await check({ issuer: "https://evil.example" })).toMatchObject({
      ok: false,
      err: "invalid_issuer",
    });
    expect(await check({ audience: "other" })).toMatchObject({
      err: "invalid_audience",
    });
    expect(await check({ jwks: other.jwks })).toMatchObject({
      err: "invalid_key",
    });
    expect(
      await verifySet("not.a.jws", { jwks, issuer: ISSUER, audience: "rx" }),
    ).toMatchObject({ err: "invalid_request" });
  });

  it("refuses a SET with two events or a plain JWT typ", async () => {
    const { signer, jwks } = await signingKey();
    const opts = { jwks, issuer: ISSUER, audience: "rx" };
    const claims = {
      iss: ISSUER,
      aud: "rx",
      jti: "j1",
      iat: Math.floor(Date.now() / 1000),
      sub_id: SUBJECT,
    };
    const two = await signer
      .signJwt({ ...claims, events: { a: {}, b: {} } }, { typ: "secevent+jwt" })
      .orThrow();
    expect(await verifySet(two, opts)).toMatchObject({
      err: "invalid_request",
      description: "A SET carries exactly one event",
    });
    const jwt = await signer
      .signJwt({ ...claims, events: { a: {} } })
      .orThrow();
    expect(await verifySet(jwt, opts)).toMatchObject({
      err: "invalid_request",
    });
  });

  it("refuses a critical subject member it does not understand", async () => {
    const { signer, jwks } = await signingKey();
    const { token } = await mintSet(signer, {
      issuer: ISSUER,
      audience: "rx",
      subject: {
        format: "complex",
        user: { format: "opaque", id: "u" },
        region: "eu",
      },
      event: EVENT,
    }).orThrow();
    const verified = await verifySet(token, {
      jwks,
      issuer: ISSUER,
      audience: "rx",
      criticalSubjectMembers: ["user", "region"],
    });
    expect(verified).toMatchObject({ ok: false, err: "invalid_request" });
  });
});
