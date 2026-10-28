import { describe, expectTypeOf, it } from "vitest";

import type { ApiKeyResolverOptions } from "../../src/blocks/api-keys/index.ts";
import type {
  AUTHZ_VERSION_CLAIM,
  FEATURES_CLAIM,
  MEMBERSHIPS_CLAIM,
  PERMISSION_CAP_CLAIM,
  PERMISSIONS_CLAIM,
  PERMISSIONS_TRUNCATED_CLAIM,
} from "../../src/claims/index.ts";
import type {
  AuthorizationProvider,
  AuthorizationTokenHook,
  ResolvedConfig,
} from "../../src/config/index.ts";
import type * as Contract from "../../src/contract/index.ts";
import type { CredentialProvider } from "../../src/credentials/index.ts";
import type { McpOptions } from "../../src/mcp/index.ts";
import type { SessionSnapshot as NextSessionSnapshot } from "../../src/next/index.ts";
import type { AccessTopicPolicy } from "../../src/realtime/index.ts";
import type { AnyFunctions, AnyModels } from "../../src/schema/types.ts";
import type {
  ApprovalOptions,
  AuthorizationCallKind,
  AuthorizationChange,
  AuthorizationContext,
  AuthorizationHooks,
  AuthorizationIntent,
  AuthorizationRequest,
  AuthorizationResource,
  AuthorizationResourceSource,
  Authorizer,
  AuthorizerRuntime,
  AuthzVersionCache,
  createServer,
  ServerOptions,
  SessionSnapshot,
  SupportAuthorize,
} from "../../src/server/index.ts";
import type { BlockTables } from "../../src/sql/index.ts";
import type { AccessBucketPolicy } from "../../src/storage/index.ts";

import {
  isApiKeySession,
  isSessionSnapshot,
  isTruncated,
  isUserSession,
  permissionsOf,
  tenantOf,
} from "../../src/claims/index.ts";
import { defineAuthorizer } from "../../src/server/index.ts";
import { blockTables } from "../../src/sql/index.ts";
import {
  authorizationRequest,
  sessionSnapshot,
} from "../../src/testing/index.ts";
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

  it("names every claim through better-supabase/claims", () => {
    expectTypeOf<typeof PERMISSIONS_CLAIM>().toEqualTypeOf<"permissions">();
    expectTypeOf<
      typeof PERMISSIONS_TRUNCATED_CLAIM
    >().toEqualTypeOf<"permissions_truncated">();
    expectTypeOf<typeof MEMBERSHIPS_CLAIM>().toEqualTypeOf<"memberships">();
    expectTypeOf<typeof FEATURES_CLAIM>().toEqualTypeOf<"features">();
    expectTypeOf<typeof AUTHZ_VERSION_CLAIM>().toEqualTypeOf<"authz_ver">();
    expectTypeOf<
      typeof PERMISSION_CAP_CLAIM
    >().toEqualTypeOf<"bsb_permission_cap">();
    expectTypeOf(permissionsOf).returns.toEqualTypeOf<
      readonly string[] | undefined
    >();
    expectTypeOf(isTruncated).returns.toBeBoolean();
    expectTypeOf(tenantOf).returns.toEqualTypeOf<string | undefined>();
    expectTypeOf(isUserSession).toBeFunction();
    expectTypeOf(isApiKeySession).toBeFunction();
    expectTypeOf(isSessionSnapshot).toBeFunction();
    expectTypeOf<AuthorizationTokenHook["truncatedClaim"]>().toEqualTypeOf<
      string | undefined
    >();
  });

  it("sends intent, operation, request id, approval and the resource source", () => {
    expectTypeOf<AuthorizationIntent>().toEqualTypeOf<"read" | "write">();
    expectTypeOf<AuthorizationCallKind>().toExtend<string>();
    expectTypeOf<AuthorizationResourceSource>().toEqualTypeOf<
      "loaded" | "input"
    >();
    expectTypeOf<AuthorizationContext>().toHaveProperty("intent");
    expectTypeOf<AuthorizationContext>().toHaveProperty("operation");
    expectTypeOf<AuthorizationContext>().toHaveProperty("requestId");
    expectTypeOf<AuthorizationContext>().toHaveProperty("approval");
    expectTypeOf<
      AuthorizationRequest["context"]
    >().toExtend<AuthorizationContext>();
    expectTypeOf<AuthorizationResource["change"]>().toEqualTypeOf<
      AuthorizationChange | undefined
    >();
    expectTypeOf<AuthorizationChange["next"]>().toExtend<object>();
  });

  it("types the version cache from the server to the authorizer runtime", () => {
    interface Versions extends AuthzVersionCache {
      readonly current: (user: string) => number;
    }

    const authorizer = defineAuthorizer({
      name: "library",
      key: (ref: string) => ref,
      evaluate: (_, runtime?: AuthorizerRuntime<Versions>) =>
        runtime?.versions?.current("u") === 1
          ? ({ outcome: "granted" } as const)
          : ({ outcome: "denied" } as const),
    });

    expectTypeOf(authorizer).toExtend<Authorizer<string, Versions>>();

    type Server = ReturnType<
      typeof createServer<
        AnyModels,
        unknown,
        AnyFunctions,
        unknown,
        unknown,
        unknown,
        unknown,
        Versions
      >
    >;

    expectTypeOf<Server["versions"]>().toEqualTypeOf<Versions | undefined>();
    expectTypeOf<ServerOptions<Versions>["versions"]>().toEqualTypeOf<
      Versions | undefined
    >();
  });

  it("resumes an approval through a header", () => {
    expectTypeOf<ApprovalOptions>().toEqualTypeOf<{
      readonly header?: string;
    }>();
    expectTypeOf<ServerOptions["approval"]>().toEqualTypeOf<
      ApprovalOptions | undefined
    >();
  });

  it("resolves block table names", () => {
    expectTypeOf(blockTables).parameter(0).toEqualTypeOf<ResolvedConfig>();
    expectTypeOf(blockTables).returns.toEqualTypeOf<BlockTables>();
    expectTypeOf<
      NonNullable<BlockTables["memberships"]>["columns"]
    >().toEqualTypeOf<{
      readonly tenant: string | null;
      readonly user: string | null;
      readonly role: string | null;
      readonly disabledAt: string | null;
    }>();
  });

  it("builds requests and snapshots the way the server does", () => {
    expectTypeOf(
      authorizationRequest({ action: "documents.read" }),
    ).toEqualTypeOf<AuthorizationRequest>();
    expectTypeOf(sessionSnapshot({ claims: { sub: "u" } })).toExtend<
      SessionSnapshot<Readonly<Record<string, unknown>>>
    >();
  });

  it("re-exports exactly the slot types from better-supabase/contract", () => {
    expectTypeOf<Contract.ContractApiVersion>().toEqualTypeOf<1>();
    expectTypeOf<Contract.AuthorizationProvider>().toEqualTypeOf<AuthorizationProvider>();
    expectTypeOf<Contract.Authorizer>().toEqualTypeOf<Authorizer>();
    expectTypeOf<Contract.AuthorizationHooks>().toEqualTypeOf<AuthorizationHooks>();
    expectTypeOf<Contract.AuthzVersionCache>().toEqualTypeOf<AuthzVersionCache>();
    expectTypeOf<Contract.AuthorizationRequest>().toEqualTypeOf<AuthorizationRequest>();
    expectTypeOf<Contract.AuthorizationContext>().toEqualTypeOf<AuthorizationContext>();
    expectTypeOf<Contract.AccessBucketPolicy>().toEqualTypeOf<AccessBucketPolicy>();
    expectTypeOf<Contract.AccessTopicPolicy>().toEqualTypeOf<AccessTopicPolicy>();
    expectTypeOf<Contract.ApiKeyResolverOptions>().toEqualTypeOf<ApiKeyResolverOptions>();
    expectTypeOf<Contract.CredentialProvider>().toEqualTypeOf<CredentialProvider>();
    expectTypeOf<Contract.SupportAuthorize>().toEqualTypeOf<SupportAuthorize>();
    expectTypeOf<Contract.SessionSnapshot>().toEqualTypeOf<SessionSnapshot>();
    expectTypeOf<Contract.ApprovalOptions>().toEqualTypeOf<ApprovalOptions>();
    expectTypeOf<Contract.BlockTables>().toEqualTypeOf<BlockTables>();
    expectTypeOf<
      Contract.McpOptions<AnyModels, AnyFunctions, never>
    >().toEqualTypeOf<McpOptions<AnyModels, AnyFunctions, never>>();
  });
});
