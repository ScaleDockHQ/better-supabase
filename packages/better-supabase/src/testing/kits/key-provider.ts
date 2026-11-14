import type {
  KeyProvider,
  Signature,
  SignedJwt,
  SigningKeyOwner,
} from "../../blocks/signing-keys/key-provider.ts";
import type { Jwks, JwsAlgorithm, SigningAlgorithm } from "../../core/jws.ts";
import type { ConformanceReport } from "../conformance.ts";

import { fromBase64, toBase64Url } from "../../core/base64.ts";
import { isRecord } from "../../core/guards.ts";
import { verifyCompact } from "../../core/jws.ts";
import { temporal } from "../../core/temporal-required.ts";
import { conform, expect } from "../conformance.ts";

/** What `verify` gets: a JWT the provider signed, or a raw signature. */
export type KeyProviderSample =
  | { readonly kind: "jwt"; readonly token: string }
  | {
      readonly kind: "signature";
      readonly data: Uint8Array;
      readonly signature: Signature;
    };

export interface TestKeyProviderOptions {
  /** An owner the provider can sign for. */
  readonly owner: SigningKeyOwner;
  /**
   * Passed as `create`, for a provider that generates the owner's key on first
   * use (Vault). Default: `Ed25519`.
   */
  readonly create?: SigningAlgorithm;
  /**
   * The owner's public keys, or a function that reads them after the first
   * signature. The kit verifies the JWT and a raw signature against them with
   * `verifyCompact`.
   */
  readonly jwks?: Jwks | (() => Jwks | Promise<Jwks>);
  /** Checks a sample yourself: return `false` or throw when it is invalid. */
  readonly verify?: (sample: KeyProviderSample) => boolean | Promise<boolean>;
}

const JWS_ALGORITHMS: readonly string[] = [
  "EdDSA",
  "Ed25519",
  "ES256",
  "PS256",
  "RS256",
] satisfies readonly JwsAlgorithm[];

const TYP = "vnd.conformance+jwt";

function headerOf(token: string): Record<string, unknown> {
  const parts = token.split(".");
  expect(parts.length === 3, `the JWT has ${parts.length} parts, not 3`);

  const header: unknown = JSON.parse(
    new TextDecoder().decode(fromBase64(parts[0] ?? "")),
  );

  expect(isRecord(header), "the JWT header is not a JSON object");

  return header;
}

/**
 * Runs the `KeyProvider` contract against `provider`: the API version, a raw
 * signature with a `kid` and a known `alg`, a compact JWS whose header carries
 * the provider's `kid` and `alg` and the caller's `typ`, `noteExp` when the
 * provider has it, and, with `jwks` or `verify`, that both signatures verify.
 */
export function testKeyProvider(
  provider: KeyProvider,
  options: TestKeyProviderOptions,
): Promise<ConformanceReport> {
  const { owner } = options;
  const create = options.create ?? "Ed25519";
  const encoder = new TextEncoder();
  const data = encoder.encode("conformance");
  const exp = Math.floor(Date.now() / 1000) + 300;
  let signature: Signature | undefined;
  let token: SignedJwt | undefined;

  const signed = async (): Promise<Signature> => {
    signature ??= await provider.sign({ owner, data, create }).orThrow();

    return signature;
  };

  const jwt = async (): Promise<SignedJwt> => {
    token ??= await provider
      .signJwt({
        owner,
        claims: { sub: "conformance", exp },
        header: { typ: TYP },
        create,
      })
      .orThrow();

    return token;
  };

  return conform(`KeyProvider "${provider.name}"`, [
    [
      "has apiVersion 1 and a name",
      () => {
        const version: unknown = provider.apiVersion;
        expect(version === 1, `apiVersion is ${String(version)}`);
        expect(provider.name.length > 0, "name is empty");
      },
    ],
    [
      "signs bytes with a kid and a known alg",
      async () => {
        const found = await signed();
        expect(found.signature.length > 0, "the signature is empty");
        expect(found.kid.length > 0, "kid is empty");
        expect(
          JWS_ALGORITHMS.includes(found.alg),
          `alg "${found.alg}" is not a JWS alg`,
        );
      },
    ],
    [
      "signs a JWT with its kid, its alg and the caller's typ in the header",
      async () => {
        const found = await jwt();
        const header = headerOf(found.token);

        for (const [member, expected] of [
          ["kid", found.kid],
          ["alg", found.alg],
          ["typ", TYP],
        ] as const) {
          expect(
            header[member] === expected,
            `the header ${member} is ${JSON.stringify(header[member])}, not "${expected}"`,
          );
        }
      },
    ],
    provider.noteExp !== undefined && [
      "notes an exp for the kid it signs with",
      async () => {
        const found = await signed();

        const noted = await provider.noteExp?.({
          kid: found.kid,
          exp: temporal().Instant.fromEpochMilliseconds(exp * 1000),
        });

        expect(noted?.ok === true, "noteExp failed for the signing kid");
      },
    ],
    (options.jwks !== undefined || options.verify !== undefined) && [
      "signs a JWT and bytes that verify",
      async () => {
        const found = await signed();
        const compact = (await jwt()).token;

        if (options.verify !== undefined) {
          expect(
            await options.verify({ kind: "jwt", token: compact }),
            "verify refused the JWT",
          );
          expect(
            await options.verify({ kind: "signature", data, signature: found }),
            "verify refused the signature",
          );
        }

        if (options.jwks === undefined) {
          return;
        }

        const jwks =
          typeof options.jwks === "function"
            ? await options.jwks()
            : options.jwks;

        const algorithms = [found.alg];
        await verifyCompact(compact, jwks, { algorithms, typ: TYP });

        // A raw signature verifies with verifyCompact once the bytes are a JWS signing input.
        const input = `${toBase64Url(JSON.stringify({ alg: found.alg, kid: found.kid }))}.${toBase64Url("{}")}`;

        const raw = await provider
          .sign({ owner, data: encoder.encode(input), create })
          .orThrow();

        await verifyCompact(`${input}.${toBase64Url(raw.signature)}`, jwks, {
          algorithms,
        });
      },
    ],
  ]);
}
