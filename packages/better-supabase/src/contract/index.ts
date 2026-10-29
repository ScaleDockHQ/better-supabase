/**
 * The types an authorization library implements or reads, in one entry with no
 * runtime code. Every slot is versioned `apiVersion: 1`; a breaking change to
 * one needs a new `apiVersion`.
 */
export type ContractApiVersion = 1;

export type {
  AuthorizationFunctions,
  AuthorizationMembership,
  AuthorizationOperation,
  AuthorizationPermission,
  AuthorizationProvider,
  AuthorizationRequirement,
  AuthorizationRoleSource,
  AuthorizationScope,
  AuthorizationTokenHook,
  AuthorizationVersions,
} from "../config/authorization.ts";

export type { AuthzVersionSource } from "../core/authz-topic.ts";

export type {
  AnyAuthorizer,
  AuthorizationCallKind,
  AuthorizationChange,
  AuthorizationContext,
  AuthorizationIntent,
  AuthorizationOutcome,
  AuthorizationPurpose,
  AuthorizationRequest,
  AuthorizationResource,
  AuthorizationResourceSource,
  AuthorizationSubject,
  Authorizer,
  AuthorizerRuntime,
  AuthzVersionCache,
  PermissionRef,
  RequestMemo,
} from "../core/authorizer.ts";

export type {
  AuthorizationHooks,
  SubscriberPolicy,
  SupportAuthorize,
  SupportAuthorizeInput,
} from "../core/contracts/authorization-hooks.ts";

export type {
  AccessBucketPolicy,
  AccessPolicySql,
  AccessTopicPolicy,
} from "../schema/types.ts";

export type { ApiKeyResolverOptions } from "../blocks/api-keys/index.ts";

export type { CredentialProvider } from "../credentials/provider.ts";

export type { McpOptions, ToolDecision, ToolRef } from "../mcp/index.ts";

export type { SessionSnapshot } from "../auth/snapshot.ts";

export type { ApprovalOptions } from "../server/server-types.ts";

export type { BlockTable, BlockTables } from "../sql/block-tables.ts";
