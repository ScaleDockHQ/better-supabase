import { describe, expect, it } from "vitest";

import {
  bitstringEntry,
  issueJwtVc,
  verifyJwtVc,
} from "../../src/verifiable-credentials/index.ts";
import { testKey } from "./fixtures.ts";

describe("W3C credentials as vc+jwt", () => {
  it("issues and verifies a VC Data Model 2.0 credential", async () => {
    const key = await testKey("ES256");

    const token = await issueJwtVc({
      signer: key.signer,
      issuer: "https://issuer.example",
      types: ["PassCredential"],
      subject: { id: "did:example:1", event: "Conf" },
      validFrom: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      validUntil: Temporal.Instant.from("2026-02-01T00:00:00Z"),
      status: bitstringEntry("https://issuer.example/s/1", 7),
    });

    const [header] = token.split(".");

    expect(JSON.parse(atob(header!))).toMatchObject({
      typ: "vc+jwt",
      cty: "vc",
      alg: "ES256",
    });

    const inside = Temporal.Instant.from("2026-01-15T00:00:00Z");
    const verified = await verifyJwtVc(token, { jwks: key.jwks, now: inside });

    expect(verified.types).toEqual(["VerifiableCredential", "PassCredential"]);
    expect(verified.credential["@context"]).toEqual([
      "https://www.w3.org/ns/credentials/v2",
    ]);

    await expect(
      verifyJwtVc(token, {
        jwks: key.jwks,
        now: Temporal.Instant.from("2026-03-01T00:00:00Z"),
      }),
    ).rejects.toMatchObject({ code: "VC_EXPIRED" });
    await expect(
      verifyJwtVc(token, {
        jwks: key.jwks,
        now: Temporal.Instant.from("2025-12-01T00:00:00Z"),
      }),
    ).rejects.toMatchObject({ code: "VC_NOT_YET" });
  });

  it("rejects a token signed by another key", async () => {
    const key = await testKey("ES256");
    const other = await testKey("ES256");

    const token = await issueJwtVc({
      signer: key.signer,
      issuer: "i",
      types: [],
      subject: {},
    });

    await expect(verifyJwtVc(token, { jwks: other.jwks })).rejects.toThrow(
      /signature|key/i,
    );
  });
});
