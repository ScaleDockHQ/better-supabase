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

export { syncWithAuth } from "./auth.ts";

export type {
  AuthSourceLike,
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
