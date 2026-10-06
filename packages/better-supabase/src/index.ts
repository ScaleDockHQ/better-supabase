export { BetterSupabase, defineSupabase } from "./core/define.ts";
export type {
  ConnectOptions,
  SupabaseOptions,
  RpcDefinition,
} from "./core/define.ts";
export { EMPTY_STATS, recordStats, StatsRecorder } from "./core/stats.ts";
export type { DbStats } from "./core/stats.ts";
export {
  AsyncResult,
  defineBetterResultErrors,
  err,
  fromBetterResult,
  ok,
  toBetterResult,
  toDbError,
} from "./core/result.ts";
export type {
  BetterResultApi,
  BetterResultErr,
  BetterResultErrors,
  BetterResultOk,
  BetterResultValue,
  DbErrorClass,
  DbErrorClasses,
  Err,
  MappedDbError,
  Ok,
  Result,
} from "./core/result.ts";
export {
  DbException,
  dbError,
  isCheck,
  isConflict,
  isDbError,
  isForeignKey,
  mapDbError,
  statusOf,
} from "./core/errors.ts";
export type {
  DbError,
  DbErrorKind,
  DbErrorKinds,
  DbErrorOf,
  ErrorMapper,
  RawDbError,
  ValidationIssue,
} from "./core/errors.ts";
export { definePlugin, PLUGIN_API_VERSION } from "./core/plugin.ts";
export { defineRepository } from "./core/define-repository.ts";
export type { TableRepositoryExtension } from "./core/define-repository.ts";
export {
  cacheTargetOf,
  memoryCache,
  rowKey,
  rpcCacheTargets,
} from "./core/cache.ts";
export { isQuerySpec, specTables } from "./core/spec.ts";
export type {
  InferResult,
  QuerySpec,
  ReadMethod,
  Specs,
  TableSpecs,
} from "./core/spec.ts";
export { defineReadSet, isReadSet, readSetTables } from "./core/read-set.ts";
export type {
  InferReadSetParams,
  ReadSet,
  ReadSetOptions,
  ReadSetParams,
  ReadSetParamType,
  ReadSetParamTypes,
  ReadSetParamValue,
  ReadSetResult,
} from "./core/read-set.ts";
export { invalidationTargets, touchedTables } from "./ir/tables.ts";
export type { CacheAdapter, CacheTarget, MemoryCache } from "./core/cache.ts";
export { consoleLogger, silentLogger } from "./core/logger.ts";
export type { LogFields, Logger } from "./core/logger.ts";
export { postgrestCompiler } from "./core/compiler.ts";
export type { Compiler } from "./core/compiler.ts";
export type {
  Actor,
  AnyPlugin,
  ApplyExtension,
  CallOptions,
  ExtensionOf,
  NoExtension,
  WithExtension,
  HasFlag,
  HookArgs,
  MutationEvent,
  MutationIntent,
  MutationKind,
  Plugin,
  RepositoryApi,
  RepositoryExtension,
  RequestContext,
} from "./core/plugin.ts";
export type {
  ExecuteContext,
  ExecuteResult,
  Executor,
  RpcContext,
} from "./core/executor.ts";
export {
  explainPostgrest,
  postgrestExecutor,
} from "./core/postgrest-executor.ts";
export type {
  PostgrestClientLike,
  PostgrestExecutorOptions,
} from "./core/postgrest-executor.ts";
export { EventHub } from "./core/events.ts";
export type {
  AuthEvent,
  BetterSupabaseEvents,
  ErrorEvent,
  EventHandler,
  EventName,
  MutationNotice,
  QueryEvent,
  RefreshEvent,
  RpcNotice,
} from "./core/events.ts";
export type {
  BlockEvent,
  BlockEventMap,
  BlockEventType,
} from "./core/block-events.ts";
export type { Policy, PolicyDecision } from "./core/policy.ts";
export type {
  ConflictTarget,
  CursorPage,
  CursorPageArgs,
  Db,
  DbHelpers,
  DeleteArgs,
  DeleteExt,
  FindExt,
  ManyResult,
  ManyReturningArgs,
  OffsetPage,
  OffsetPageArgs,
  OffsetRangeArgs,
  PageOf,
  Repository,
  RepositoryOf,
  Returned,
  RpcOptions,
  UpdateArgs,
  UpsertArgs,
  WriteArgs,
} from "./core/repository-types.ts";
export { encodeCursor, decodeCursor } from "./core/cursor.ts";
export {
  fromProblem,
  isProblem,
  PROBLEM_CONTENT_TYPE,
  PROBLEM_TYPE_BASE,
  problemResponse,
  toProblem,
} from "./core/problem.ts";
export type {
  ProblemDetails,
  ProblemOptions,
  ProblemResponseOptions,
} from "./core/problem.ts";
export { validate } from "./core/standard.ts";
export type { StandardSchemaV1 } from "./core/standard.ts";
export { SPEC_PINS } from "./core/spec-pins.ts";

export { defineSchema, tableMeta } from "./schema/define.ts";
export type { EnrichDatabase } from "./schema/enrich.ts";
export type { StoragePath } from "./storage/path.ts";
export type * from "./schema/types.ts";

export type { SearchArgs } from "./core/search.ts";
export type * from "./ir/args.ts";
export type * from "./ir/types.ts";
export { escapeLike } from "./ir/build.ts";
export { decodeRows } from "./ir/codec.ts";
export { encodeValue } from "./ir/wire.ts";
export {
  isInstant,
  isPlainDate,
  isPlainDateTime,
  isPlainTime,
  isZonedDateTime,
  provideTemporal,
} from "./core/temporal.ts";
export { and, column, not, or } from "./ir/types.ts";
export { scopeCondition, scopeOperation, scopeSelection } from "./ir/scope.ts";
export type { ScopeFor } from "./ir/scope.ts";
export { simplify } from "./ir/simplify.ts";
export { compilePostgrest } from "./compile/postgrest.ts";
export type {
  PlanFilter,
  PlanLimit,
  PlanOrder,
  PostgrestPlan,
} from "./compile/postgrest.ts";
export { toCamel, toSnake } from "./casing/index.ts";
