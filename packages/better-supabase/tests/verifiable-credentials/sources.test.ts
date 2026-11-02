import { describe, expect, it } from "vitest";

import {
  courseCompletionSource,
  defineCredentialSource,
  passSource,
  qualificationSource,
  signerFromJwk,
  signerFromSigningKeys,
} from "../../src/verifiable-credentials/index.ts";
import { testKey } from "./fixtures.ts";

const display = [{ name: "Card", locale: "en" }];
const validFor = Temporal.Duration.from({ days: 30 });

describe("credential sources", () => {
  it("returns a source as it is", () => {
    const source = qualificationSource({
      vct: "urn:q",
      lookup: () => Promise.resolve(undefined),
    });

    expect(defineCredentialSource(source)).toBe(source);
  });

  it("builds qualification claims with and without options", async () => {
    const bare = qualificationSource({
      vct: "urn:q",
      lookup: (subject) =>
        Promise.resolve(
          subject === "none"
            ? undefined
            : { holderName: "Ada", qualification: "Welder" },
        ),
    });

    expect(bare.configuration).not.toHaveProperty("validFor");
    expect(bare.configuration).not.toHaveProperty("display");
    expect(await bare.claims("none")).toBeUndefined();
    expect(await bare.claims("x")).toEqual({
      holder_name: "Ada",
      qualification: "Welder",
    });

    const full = qualificationSource({
      vct: "urn:q",
      validFor,
      display,
      lookup: () =>
        Promise.resolve({
          holderName: "Ada",
          qualification: "Welder",
          issuedOn: "2026-01-01",
          validUntil: "2027-01-01",
        }),
    });

    expect(full.configuration).toMatchObject({ validFor, display });
    expect(await full.claims("x")).toMatchObject({
      issued_on: "2026-01-01",
      valid_until: "2027-01-01",
    });
  });

  it("builds course completion claims", async () => {
    const make = (score?: number, extra = {}) =>
      courseCompletionSource({
        vct: "urn:c",
        ...extra,
        lookup: (subject) =>
          Promise.resolve(
            subject === "none"
              ? undefined
              : {
                  learnerName: "Ada",
                  course: "Safety",
                  completedOn: "2026-02-01",
                  ...(score === undefined ? {} : { score }),
                },
          ),
      });

    expect(make().configuration).not.toHaveProperty("validFor");
    expect(await make().claims("none")).toBeUndefined();
    expect(await make().claims("x")).not.toHaveProperty("score");
    expect(await make(9).claims("x")).toMatchObject({ score: 9 });
    expect(make(1, { validFor, display }).configuration).toMatchObject({
      validFor,
      display,
    });
  });

  it("builds pass claims", async () => {
    const make = (extra = {}, fact: object = {}) =>
      passSource({
        vct: "urn:p",
        ...extra,
        lookup: (subject) =>
          Promise.resolve(
            subject === "none"
              ? undefined
              : { holderName: "Ada", event: "Conf", ...fact },
          ),
      });

    expect(make().configuration).not.toHaveProperty("display");
    expect(await make().claims("none")).toBeUndefined();
    expect(await make().claims("x")).toEqual({
      holder_name: "Ada",
      event: "Conf",
    });
    expect(
      await make(
        { validFor, display },
        { validFrom: "a", validUntil: "b" },
      ).claims("x"),
    ).toMatchObject({ valid_from: "a", valid_until: "b" });
    expect(make({ validFor, display }).configuration).toMatchObject({
      display,
    });
  });
});

describe("signers", () => {
  it("rejects a key that is not a private signing JWK", async () => {
    const { publicKey } = await testKey();

    await expect(signerFromJwk(publicKey)).rejects.toThrow(TypeError);
  });

  it("builds EdDSA and keyless signers", async () => {
    const { privateKey } = await testKey("Ed25519");
    const signer = await signerFromJwk(privateKey);

    expect(signer.alg).toBe("EdDSA");
    expect(signer).not.toHaveProperty("kid");
  });

  it("detects a key that rotated mid signature", async () => {
    let calls = 0;

    const signer = await signerFromSigningKeys({
      sign: () => ({
        orThrow: () => {
          calls += 1;

          return Promise.resolve({
            kid: calls > 2 ? "other" : "k1",
            alg: "ES256" as const,
            signature: new Uint8Array(),
          });
        },
      }),
    });

    expect(signer.kid).toBe("k1");
    await expect(signer.sign(new Uint8Array([1]))).resolves.toBeInstanceOf(
      Uint8Array,
    );
    await expect(signer.sign(new Uint8Array([1]))).rejects.toThrow(/rotated/u);
  });
});
