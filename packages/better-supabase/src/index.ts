export { BetterSupabase, defineSupabase } from './core/define.ts';
export type { DefineSupabaseOptions, RpcDefinition } from './core/define.ts';
export { AsyncResult, err, ok, toDbError } from './core/result.ts';
export type { Err, Ok, Result } from './core/result.ts';
export {
  DbException,
  dbError,
  isCheck,
  isConflict,
  isDbError,
  isForeignKey,
  mapDbError,
  statusOf,
} from './core/errors.ts';
export type {
  DbError,
  DbErrorKind,
  DbErrorKinds,
  DbErrorOf,
  ErrorMapper,
  RawDbError,
  ValidationIssue,
} from './core/errors.ts';
export { definePlugin, PLUGIN_API_VERSION } from './core/plugin.ts';
export { defineRepository } from './core/define-repository.ts';
export type { TableRepositoryExtension } from './core/define-repository.ts';
export {
  cacheTargetOf,
  memoryCache,
  rowKey,
  rpcCacheTargets,
} from './core/cache.ts';
export { isQuerySpec, specTables } from './core/spec.ts';
export type {
  InferResult,
  QuerySpec,
  ReadMethod,
  Specs,
  TableSpecs,
} from './core/spec.ts';
export { invalidationTargets, touchedTables } from './ir/tables.ts';
export type { CacheAdapter, CacheTarget, MemoryCache } from './core/cache.ts';
export { consoleLogger, silentLogger } from './core/logger.ts';
export type { LogFields, Logger } from './core/logger.ts';
export { postgrestCompiler } from './core/compiler.ts';
export type { Compiler } from './core/compiler.ts';
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
  MutationKind,
  Plugin,
  RepositoryApi,
  RepositoryExtension,
  RequestContext,
} from './core/plugin.ts';
export type {
  ExecuteContext,
  ExecuteResult,
  Executor,
} from './core/executor.ts';
export {
  explainPostgrest,
  postgrestExecutor,
} from './core/postgrest-executor.ts';
export type { PostgrestClientLike } from './core/postgrest-executor.ts';
export { EventHub } from './core/events.ts';
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
} from './core/events.ts';
export type {
  ConflictTarget,
  CursorPage,
  CursorPageArgs,
  Db,
  DbHelpers,
  DeleteArgs,
  DeleteExt,
  FindExt,
  OffsetPage,
  OffsetPageArgs,
  PageOf,
  Repository,
  RepositoryOf,
  Returned,
  RpcOptions,
  UpdateArgs,
  UpsertArgs,
  WriteArgs,
} from './core/repository-types.ts';
export { encodeCursor, decodeCursor } from './core/cursor.ts';
export {
  fromProblem,
  isProblem,
  PROBLEM_CONTENT_TYPE,
  PROBLEM_TYPE_BASE,
  problemResponse,
  toProblem,
} from './core/problem.ts';
export type {
  ProblemDetails,
  ProblemOptions,
  ProblemResponseOptions,
} from './core/problem.ts';
export { validate } from './core/standard.ts';
export type { StandardSchemaV1 } from './core/standard.ts';
export { SPEC_PINS } from './core/spec-pins.ts';

export { defineSchema, tableMeta } from './schema/define.ts';
export type { EnrichDatabase } from './schema/enrich.ts';
export type * from './schema/types.ts';

export type * from './ir/args.ts';
export type * from './ir/types.ts';
export { escapeLike } from './ir/build.ts';
export { decodeRows, encodeValue } from './ir/codec.ts';
export { and, column, not, or } from './ir/types.ts';
export { scopeCondition, scopeOperation, scopeSelection } from './ir/scope.ts';
export type { ScopeFor } from './ir/scope.ts';
export { simplify } from './ir/simplify.ts';
export { compilePostgrest } from './compile/postgrest.ts';
export type {
  PlanFilter,
  PlanLimit,
  PlanOrder,
  PostgrestPlan,
} from './compile/postgrest.ts';
export { toCamel, toSnake } from './casing/index.ts';
