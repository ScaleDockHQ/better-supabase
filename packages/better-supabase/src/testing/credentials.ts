import type { Result } from "../core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
} from "../credentials/provider.ts";

import { tenantCredentialRef } from "../credentials/provider.ts";
import { type ConformanceReport, conform, expect } from "./conformance.ts";

export interface TestCredentialProviderOptions {
  /** An app-scoped ref the kit may store into and revoke. */
  readonly ref: CredentialRef;
  /** Stores `value` as the credential `ref` names for `subject`. */
  readonly seed: (
    ref: CredentialRef,
    subject: CredentialSubject,
    value: string,
  ) => Promise<void>;
  /** A per-user ref, for providers that keep one credential per user. */
  readonly userRef?: CredentialRef;
  /** A ref with an inbound scheme and a function that signs a request with `secret`. */
  readonly inbound?: {
    readonly ref: CredentialRef;
    readonly sign: (body: string, secret: string) => Promise<Request>;
  };
}

const APP: CredentialSubject = { type: "app" };

const kindOf = (result: Result<unknown>): string | undefined =>
  result.ok ? undefined : result.error.kind;

/**
 * Runs the `CredentialProvider` contract against `provider`: the API version,
 * an unknown ref, a stored token with its headers, a new value seen after it
 * is stored, separate credentials per user and per tenant (`ref` with a
 * `tenant`, which `seed` must store too), revoke, and inbound checks that
 * accept a signed request and refuse a tampered one.
 */
export function testCredentialProvider(
  provider: CredentialProvider,
  options: TestCredentialProviderOptions,
): Promise<ConformanceReport> {
  const value = (): string => `token-${crypto.randomUUID()}`;
  const { ref, seed, userRef, inbound } = options;
  return conform(`CredentialProvider "${provider.name}"`, [
    [
      "has apiVersion 1 and a name",
      () => {
        const version: unknown = provider.apiVersion;
        expect(version === 1, `apiVersion is ${String(version)}`);
        expect(provider.name.length > 0, "name is empty");
      },
    ],
    [
      "refuses a ref for another provider",
      async () => {
        const result = await provider.getToken(
          { provider: "conformance-unknown" },
          { subject: APP },
        );
        expect(
          kindOf(result) === "invalid_input",
          `got ${kindOf(result) ?? "a token"}`,
        );
      },
    ],
    [
      "returns a stored token with headers",
      async () => {
        const token = value();
        await seed(ref, APP, token);
        const got = await provider.getToken(ref, { subject: APP }).orThrow();
        expect(got.token === token, "returned another token");
        expect(
          Object.values(got.headers).some((header) => header.includes(token)),
          "no header carries the token",
        );
      },
    ],
    [
      "sees a new value once it is stored",
      async () => {
        await seed(ref, APP, value());
        await provider.getToken(ref, { subject: APP }).orThrow();
        const next = value();
        await seed(ref, APP, next);
        const got = await provider.getToken(ref, { subject: APP }).orThrow();
        expect(got.token === next, "returned the previous value");
      },
    ],
    userRef !== undefined && [
      "keeps a credential per user",
      async () => {
        const alice: CredentialSubject = {
          type: "user",
          id: crypto.randomUUID(),
        };
        const bob: CredentialSubject = {
          type: "user",
          id: crypto.randomUUID(),
        };
        const [forAlice, forBob] = [value(), value()];
        await seed(userRef, alice, forAlice);
        await seed(userRef, bob, forBob);
        const a = await provider
          .getToken(userRef, { subject: alice })
          .orThrow();
        const b = await provider.getToken(userRef, { subject: bob }).orThrow();
        expect(
          a.token === forAlice && b.token === forBob,
          "users share a credential",
        );
        expect(
          provider.capabilities(userRef).userSubjects,
          "capabilities do not report user subjects",
        );
        const asApp = await provider.getToken(userRef, {
          subject: APP,
        });
        expect(!asApp.ok, "the app read a per-user credential");
      },
    ],
    [
      "keeps a tenant's credential inside its namespace",
      async () => {
        const forA = tenantCredentialRef(crypto.randomUUID(), ref);
        const forB = tenantCredentialRef(crypto.randomUUID(), ref);
        const [app, a, b] = [value(), value(), value()];
        await seed(ref, APP, app);
        await seed(forA, APP, a);
        await seed(forB, APP, b);
        const tokenOf = async (of: CredentialRef) =>
          (await provider.getToken(of, { subject: APP }).orThrow()).token;
        expect(
          (await tokenOf(ref)) === app &&
            (await tokenOf(forA)) === a &&
            (await tokenOf(forB)) === b,
          "a tenant's ref resolved another tenant's or the app's credential",
        );
        expect(
          await provider.revoke(forA, { subject: APP }).orThrow(),
          "revoke found nothing in the tenant's namespace",
        );
        const after = await provider.getToken(forA, { subject: APP });
        expect(
          kindOf(after) === "not_found",
          `after revoke got ${kindOf(after) ?? "a token"}`,
        );
        expect(
          (await tokenOf(forB)) === b && (await tokenOf(ref)) === app,
          "revoking a tenant's ref removed another tenant's or the app's credential",
        );
        await provider.revoke(forB, { subject: APP }).orThrow();
      },
    ],
    [
      "revokes a credential",
      async () => {
        await seed(ref, APP, value());
        expect(
          await provider.revoke(ref, { subject: APP }).orThrow(),
          "revoke found nothing",
        );
        const after = await provider.getToken(ref, { subject: APP });
        expect(
          kindOf(after) === "not_found",
          `after revoke got ${kindOf(after) ?? "a token"}`,
        );
        expect(
          !(await provider.revoke(ref, { subject: APP }).orThrow()),
          "a second revoke found a credential",
        );
      },
    ],
    inbound !== undefined && [
      "verifies inbound requests",
      async () => {
        const verify = provider.verifyInbound?.bind(provider);
        expect(verify !== undefined, "no verifyInbound");
        const secret = `whsec_${btoa(crypto.randomUUID())}`;
        await seed(inbound.ref, APP, secret);
        const body = JSON.stringify({ hello: "world" });
        const signed = await inbound.sign(body, secret);
        expect(
          await verify(signed, inbound.ref).orThrow(),
          "refused a signed request",
        );
        const tampered = new Request(signed.url, {
          method: "POST",
          headers: signed.headers,
          body: `${body} `,
        });
        expect(
          !(await verify(tampered, inbound.ref).orThrow()),
          "accepted a tampered request",
        );
      },
    ],
  ]);
}
