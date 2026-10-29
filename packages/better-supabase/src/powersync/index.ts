export { checkSqlite, sqliteCompiler } from "./compiler.ts";

export type { CheckSqliteOptions } from "./compiler.ts";

export {
  fromSqliteError,
  postgrestTimestamp,
  powersyncExecutor,
} from "./executor.ts";

export type {
  PowerSyncDatabaseLike,
  PowerSyncExecutorOptions,
  SqliteContextLike,
} from "./executor.ts";

export { powersyncEngine } from "./engine.ts";

export type { PowerSyncEngineOptions } from "./engine.ts";

export type { SyncStatusLike } from "./sync.ts";

export {
  compileSqlite,
  likeToGlob,
  quoteSqliteIdent,
  sqliteValue,
} from "../compile/sqlite.ts";

export type {
  SqliteColumn,
  SqliteCompilerOptions,
  SqliteDecode,
  SqliteInsertPlan,
  SqliteKeyedPlan,
  SqliteKeys,
  SqliteNested,
  SqlitePlan,
  SqliteQuery,
  SqliteReturning,
  SqliteSelectPlan,
  SqliteValue,
} from "../compile/sqlite.ts";

export { claimsFingerprint, syncWithAuth } from "./auth.ts";

export type {
  AuthSourceLike,
  AuthSync,
  SyncClaims,
  SyncedDatabaseLike,
  SyncWithAuthOptions,
} from "./auth.ts";

export {
  createUploadConnector,
  uploadOutcome,
  uploadRoute,
} from "./connector.ts";

export type {
  CreateUploadRepository,
  CrudEntryLike,
  CrudQueueLike,
  RejectedChange,
  RejectedStore,
  UploadConnector,
  UploadConnectorOptions,
  UploadErrorContext,
  UploadFunction,
  UploadOutcome,
  UploadRepository,
  UploadRoute,
  UploadRouteOptions,
} from "./connector.ts";

export { attachmentQueueRoute } from "./attachments.ts";

export type {
  AttachmentPathRow,
  AttachmentQueueRoute,
  AttachmentQueueRouteOptions,
} from "./attachments.ts";

export {
  notificationRecipientsRoute,
  powersyncNotificationsTransport,
  powersyncTopicPort,
} from "./notifications.ts";

export type {
  LocalNotificationFunction,
  NotificationRecipientWrites,
  PowerSyncNotificationsOptions,
} from "./notifications.ts";

export {
  membershipsRoute,
  powersyncMembershipsTransport,
} from "./memberships.ts";

export type {
  LocalMembershipFunction,
  MembershipWrites,
  PowerSyncMembershipsOptions,
} from "./memberships.ts";

export {
  powersyncTeamsTransport,
  teamMembersRoute,
  teamsRoute,
} from "./teams.ts";

export type {
  LocalTeamFunction,
  PowerSyncTeamsOptions,
  TeamWrites,
} from "./teams.ts";

export { powersyncProfilesTransport, profilesRoute } from "./profiles.ts";

export type {
  LocalProfileFunction,
  PowerSyncProfilesOptions,
  ProfileWrites,
} from "./profiles.ts";
