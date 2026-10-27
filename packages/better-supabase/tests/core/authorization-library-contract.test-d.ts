import { describe, expectTypeOf, it } from "vitest";

import type { ApiKeyResolverOptions } from "../../src/blocks/api-keys/index.ts";
import type { AuthorizationProvider } from "../../src/config/index.ts";
import type { CredentialProvider } from "../../src/credentials/index.ts";
import type { McpOptions } from "../../src/mcp/index.ts";
import type { SessionSnapshot as NextSessionSnapshot } from "../../src/next/index.ts";
import type { AccessTopicPolicy } from "../../src/realtime/index.ts";
import type { AnyFunctions, AnyModels } from "../../src/schema/types.ts";
import type {
  AuthorizationHooks,
  Authorizer,
  AuthzVersionCache,
  ServerOptions,
  SessionSnapshot,
  SupportAuthorize,
} from "../../src/server/index.ts";
import type { AccessBucketPolicy } from "../../src/storage/index.ts";

import { stubProvider } from "../fixtures/authorization-provider.ts";

// Every slot an authorization library plugs into, imported from the entry an
// app imports. Changing one of these types fails the test that names it.
describe("authorization library contract", () => {
  it("takes a provider in the authorization config key", () => {
    expectTypeOf(stubProvider).toExtend<AuthorizationProvider>();
    expectTypeOf<AuthorizationProvider["apiVersion"]>().toEqualTypeOf<1>();
  });

  it("takes an authorizer, runtime hooks and a version cache on the server", () => {
    const authorizer = {
      apiVersion: 1,
      name: "library",
      key: (ref: string) => ref,
      evaluate: () => ({ outcome: "granted" }) as const,
    } satisfies Authorizer;

    const versions = { evict: () => undefined } satisfies AuthzVersionCache;

    const authorization = {
      apiVersion: 1,
      name: "library",
    } satisfies AuthorizationHooks;

    expectTypeOf({ authorizer, authorization, versions }).toExtend<
      Pick<ServerOptions, "authorizer" | "authorization" | "versions">
    >();
  });

  it("takes bucket and topic policies as permission keys", () => {
    expectTypeOf({
      access: { read: "files.read", write: "files.write" },
    }).toExtend<AccessBucketPolicy>();
    expectTypeOf({ receive: "chat.read" }).toExtend<AccessTopicPolicy>();
  });

  it("takes an API key verifier, credentials and an MCP authorize", () => {
    expectTypeOf<ApiKeyResolverOptions>().toHaveProperty("keys");
    expectTypeOf<CredentialProvider["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<McpOptions<AnyModels, AnyFunctions, never>>().toHaveProperty(
      "authorize",
    );
  });

  it("takes a support authorize", () => {
    const authorize: SupportAuthorize = () => false;

    expectTypeOf(authorize).toBeFunction();
  });

  it("hands subject builders the same session snapshot on every adapter", () => {
    expectTypeOf<NextSessionSnapshot>().toEqualTypeOf<SessionSnapshot>();
    expectTypeOf<SessionSnapshot["authzVersion"]>().toEqualTypeOf<
      number | null
    >();
  });
});
