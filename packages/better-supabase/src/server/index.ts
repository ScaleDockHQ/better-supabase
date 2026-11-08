export { SERVER_EVENT_SOURCE } from "./audit.ts";

export type { AccountEventType } from "./audit.ts";

export type { RequestIdOptions } from "./request-ids.ts";

export type { LiteDriver } from "./lite.ts";

export { PRIMARY_COOKIE } from "./replicas.ts";

export type { ReplicaState } from "./replicas.ts";

export { adapterBase } from "./adapter-base.ts";

export type { AdapterBase, AdapterBaseOptions } from "./adapter-base.ts";

export { createServer, extendServer } from "./server.ts";

export { TENANT_HEADER } from "./server-types.ts";

export {
  flushEvents,
  withFlush,
  handle,
  resolveToken,
  unexpectedResponse,
} from "./adapter.ts";

export type { HandleOptions } from "./adapter.ts";

export type {
  ActiveSupport,
  SupportApi,
  SupportCaller,
  SupportAuthorizeInput,
  SupportExpireRouteOptions,
  SupportOptions,
  SupportPolicy,
  SupportSessions,
  SupportStartRequest,
} from "./support.ts";

export { impersonationEvents } from "../blocks/impersonation/events.ts";

export type { ImpersonationEvents } from "../blocks/impersonation/events.ts";

export { defineAuthorizationHooks } from "../core/contracts/authorization-hooks.ts";

export {
  AUTHZ_VERSION_CLAIM,
  decodeEntitlementClaim,
  FEATURES_CLAIM,
  isApiKeySession,
  isTruncated,
  isUserSession,
  MEMBERSHIPS_CLAIM,
  PERMISSION_CAP_CLAIM,
  permissionCapOf,
  PERMISSIONS_CLAIM,
  PERMISSIONS_TRUNCATED_CLAIM,
} from "../claims/index.ts";

export type {
  ApiKeySession,
  ClaimsRecord,
  ClaimsSource,
  UserSession,
} from "../claims/index.ts";

export type {
  Approver,
  ApproverOf,
  ApprovalRequestRef,
  AuthorizationHooks,
  AutomationHooks,
  AutomationRef,
  ChatAction,
  ChatActionHook,
  DelegationPermissions,
  DelegationRef,
  IdentityRef,
  IdentityTarget,
  PrincipalByIdentity,
  Subscriber,
  SubscriberEvent,
  SubscriberPolicy,
  SupportAuthorize,
  SupportDecision,
  TicketSubject,
} from "../core/contracts/authorization-hooks.ts";

export { subjectReaders } from "../core/subject-readers.ts";

export type { SubjectReadersOptions } from "../core/subject-readers.ts";

export {
  liveRelayTopic,
  realtimeRelay,
  realtimeTopicAccess,
} from "./realtime-relay.ts";

export type {
  RealtimeRelayOptions,
  RelayAccessInput,
  RelayAuthorize,
  RelayEndReason,
  RelayPostgres,
  RelayServer,
  RelayTopic,
} from "./realtime-relay.ts";

export {
  clearSupportCookie,
  SUPPORT_COOKIE,
  supportCookie,
  supportCookieValue,
} from "../auth/support-cookie.ts";

export type { SupportCookieOptions } from "../auth/support-cookie.ts";

export { sqlSupportStore, supportClaims } from "../auth/support.ts";

export type {
  SqlSupportStoreOptions,
  SupportCallerClaims,
  SupportEndedBy,
  SupportApprovalQuery,
  SupportApprover,
  SupportListFilter,
  SupportRequest,
  SupportRequestInput,
  SupportSession,
  SupportSessionStore,
  SupportStartInput,
} from "../auth/support.ts";

export { supportOf } from "../auth/support-view.ts";

export type { SupportView } from "../auth/support-view.ts";

export type {
  AdminDb,
  ApprovalOptions,
  BetterServer,
  ContextOptions,
  ForContextOptions,
  TransactionOptions,
  ResolveRequestOptions,
  ServerContext,
  ServerDbOptions,
  ServerOptions,
} from "./server-types.ts";

export {
  contextFromSupabase,
  withBetterDb,
  withBetterPostgres,
} from "./entries/upstream.ts";

export type { SupabaseAuthContext } from "./entries/upstream.ts";

export { withBetterSupabase } from "./composite.ts";

export type {
  BetterSupabaseConfig,
  BetterSupabaseContributions,
  BetterSupabaseEntry,
} from "./composite.ts";

export { withBlock } from "./entries/block.ts";

export { withSession } from "./entries/session.ts";

export type { AuthOutageHook, SessionEntryOptions } from "./entries/session.ts";

export { withGuard } from "./entries/guard.ts";

export type { GuardEntryOptions } from "./entries/guard.ts";

export { authModeOf, jwtClaimsOf, userClaimsOf } from "../auth/claims.ts";

export { serverCore } from "./entries/core.ts";

export type { ServerCore } from "./entries/core.ts";

export {
  aalOf,
  actorOf,
  agentClaims,
  amrOf,
  authContext,
  checkAal,
  verifySession,
  clearSessionCookies,
  accessTokenResolver,
  clientIp,
  delegationOf,
  IDENTITY_SCOPES,
  impersonatorOf,
  permissionsOf,
  readSession,
  resolveAuth,
  sessionCookieName,
  sessionStatus,
  toSession,
} from "../auth/internal.ts";

export type {
  AccessTokenResolverOptions,
  AccessTokenRevocation,
  Aal,
  ActClaim,
  ActorOutcome,
  AgentActOptions,
  AmrEntry,
  AuthResolution,
  AuthResolver,
  AuthSession,
  AuthState,
  ClearSessionCookiesOptions,
  CookieOptions,
  CookieRecord,
  CookieWrite,
  ImpersonationOptions,
  Impersonator,
  InvalidReason,
  PermissionsOfOptions,
  ResolveAuthOptions,
  ResolvedState,
  SessionActor,
  SessionDelegation,
  SessionLookup,
  SessionRejection,
  SessionStatus,
  SessionStatusOptions,
  StoredSession,
} from "../auth/internal.ts";

export {
  fromProblem,
  isProblem,
  PROBLEM_CONTENT_TYPE,
  PROBLEM_TYPE_BASE,
  problemResponse,
  toProblem,
} from "../core/problem.ts";

export type {
  ProblemDetails,
  ProblemOptions,
  ProblemResponseOptions,
} from "../core/problem.ts";

export { guard, isResult, respond, settle } from "./respond.ts";

export type {
  AuthKind,
  GuardOptions,
  MiddlewareOptions,
  RespondOptions,
  Settled,
} from "./respond.ts";

export {
  bindAuthorizer,
  defineAuthorizer,
  requestMemo,
} from "../core/authorizer.ts";

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
  AuthzSubjectSeed,
  AuthzVersionCache,
  PermissionRef,
  RequestMemo,
} from "../core/authorizer.ts";

export {
  authzVersionOf,
  isSessionSnapshot,
  issuedAtOf,
  sessionCacheKey,
  sessionMemo,
  snapshotOf,
} from "../auth/snapshot.ts";

export { purgeKeys } from "../auth/resolve.ts";

export { passwordGrant, safeRedirectPath } from "../auth/sign-in.ts";

export {
  createVersionCache,
  subscribeAuthzVersions,
} from "./authz-versions.ts";

export {
  AUTHZ_EVENT,
  AUTHZ_TOPIC,
  authzUserTopic,
} from "../core/authz-topic.ts";

export type {
  AuthzVersionChannel,
  AuthzVersionClient,
  AuthzVersionSubscription,
  CreateVersionCacheOptions,
  SubscribeAuthzVersionsOptions,
  VersionCache,
  VersionStore,
} from "./authz-versions.ts";

export type { PasswordGrantOptions } from "../auth/sign-in.ts";

export type {
  SessionMemo,
  SessionMemoOptions,
  SessionMemoStats,
  SessionSnapshot,
} from "../auth/snapshot.ts";

export { defineResource } from "./resource.ts";

export type {
  ResourceHandler,
  ResourceInput,
  ResourceList,
  ResourceRouteOptions,
} from "./resource-types.ts";

export type { ResourcePagination } from "../spec/resource.ts";

export { isDocumentLoad, isPrefetch, refreshFor } from "./request-kind.ts";

export type { RefreshPolicy } from "./request-kind.ts";

export {
  DB_CALLS_HEADER,
  parseDbStats,
  withDbStats,
  withServerTiming,
} from "./entries/timing.ts";

export type { ServerTiming } from "./entries/timing.ts";

export { cacheTagsOf, tagCache, tagFor } from "../core/tags.ts";

export { sessionIdTag, sessionTag, tableTags } from "./cache-tags.ts";

export type {
  Access,
  AccessForOptions,
  Bootstrap,
  BootstrapCallOptions,
} from "./bootstrap.ts";

export type { TagOptions } from "../core/tags.ts";

export { hasRole, rolesAt } from "./kit.ts";

export type {
  ActionResult,
  AuthorizedContext,
  AuthorizeOptions,
  ResourceLoaderContext,
  BlockActionOptions,
  BlockRequireOptions,
} from "./kit.ts";
