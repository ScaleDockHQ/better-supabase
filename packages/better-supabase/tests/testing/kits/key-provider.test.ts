import { describe, expect, it } from "vitest";

import type { KeyProvider } from "../../../src/blocks/signing-keys/index.ts";

import {
  createSigningKeys,
  jwksOf,
  vaultKeyProvider,
  vercelKmsKeyProvider,
  verifyCompact,
} from "../../../src/blocks/signing-keys/index.ts";
import { ConformanceError } from "../../../src/testing/conformance.ts";
import { testKeyProvider } from "../../../src/testing/kits/key-provider.ts";
import { fakeKms, signingKeysStore } from "../../fixtures/signing-keys.ts";

const owner = { type: "organization", id: "o1" };

async function failures(
  provider: KeyProvider,
  jwks?: Parameters<typeof testKeyProvider>[1]["jwks"],
): Promise<string[]> {
  const error = await testKeyProvider(provider, {
    owner,
    ...(jwks === undefined ? {} : { jwks }),
  }).then(
    () => undefined,
    (cause: unknown) => cause,
  );

  expect(error).toBeInstanceOf(ConformanceError);

  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => check.name);
}

describe("testKeyProvider", () => {
  it("passes the Vault provider over a fake transport", async () => {
    const t = signingKeysStore();
    const keys = createSigningKeys({ transport: t });

    const report = await testKeyProvider(vaultKeyProvider({ transport: t }), {
      owner,
      create: "ES256",
      jwks: async () => jwksOf(await keys.jwks({ owner }).orThrow()),
    });

    expect(report.subject).toBe('KeyProvider "vault"');
    expect(report.checks.map((check) => check.name)).toEqual([
      "has apiVersion 1 and a name",
      "signs bytes with a kid and a known alg",
      "signs a JWT with its kid, its alg and the caller's typ in the header",
      "notes an exp for the kid it signs with",
      "signs a JWT and bytes that verify",
    ]);
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("passes the Vercel KMS provider over a fake KMS module", async () => {
    const fake = await fakeKms();
    const samples: string[] = [];

    const report = await testKeyProvider(
      vercelKmsKeyProvider(fake.kms, { issuer: "iss_1" }),
      {
        owner,
        jwks: fake.jwks,
        verify: async (sample) => {
          samples.push(sample.kind);

          if (sample.kind === "jwt") {
            await verifyCompact(sample.token, fake.jwks);
          }

          return true;
        },
      },
    );

    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(report.checks).toHaveLength(4);
    expect(samples).toEqual(["jwt", "signature"]);
  });

  it("skips the verify check without jwks or verify", async () => {
    const fake = await fakeKms();

    const report = await testKeyProvider(
      vercelKmsKeyProvider(fake.kms, { issuer: "iss_1" }),
      { owner },
    );

    expect(report.checks).toHaveLength(3);
  });

  it("fails a provider that drops the typ, signs with another key or names an unknown alg", async () => {
    const fake = await fakeKms();
    const kms = vercelKmsKeyProvider(fake.kms, { issuer: "iss_1" });

    expect(
      await failures({
        ...kms,
        signJwt: (input) => kms.signJwt({ ...input, header: {} }),
      }),
    ).toEqual([
      "signs a JWT with its kid, its alg and the caller's typ in the header",
    ]);

    const other = await fakeKms();
    expect(await failures(kms, other.jwks)).toEqual([
      "signs a JWT and bytes that verify",
    ]);

    expect(
      await failures({
        ...kms,
        sign: (input) =>
          // SAFETY: simulates a provider that reports an alg outside the union.
          kms
            .sign(input)
            .map((signed) => ({ ...signed, alg: "HS256" as never })),
      }),
    ).toEqual(["signs bytes with a kid and a known alg"]);
  });

  it("fails another apiVersion", async () => {
    const fake = await fakeKms();
    const kms = vercelKmsKeyProvider(fake.kms, { issuer: "iss_1" });

    // SAFETY: simulates a provider built for a newer API.
    expect(await failures({ ...kms, apiVersion: 2 as never })).toEqual([
      "has apiVersion 1 and a name",
    ]);
  });
});
