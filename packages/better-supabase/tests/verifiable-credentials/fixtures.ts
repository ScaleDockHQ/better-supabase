import type { Jwk, Jwks } from "../../src/core/jws.ts";
import type { CredentialSigner } from "../../src/verifiable-credentials/index.ts";

import { generateSigningKey } from "../../src/core/jws.ts";
import { signerFromJwk } from "../../src/verifiable-credentials/index.ts";

export interface TestKey {
  readonly signer: CredentialSigner;
  readonly publicKey: Jwk;
  readonly privateKey: Jwk;
  readonly jwks: Jwks;
}

export async function testKey(
  alg: "Ed25519" | "ES256" = "ES256",
): Promise<TestKey> {
  const { kid, publicKey, privateKey } = await generateSigningKey(alg);

  return {
    signer: await signerFromJwk(privateKey, kid),
    publicKey,
    privateKey,
    jwks: { keys: [{ ...publicKey, kid }] },
  };
}
