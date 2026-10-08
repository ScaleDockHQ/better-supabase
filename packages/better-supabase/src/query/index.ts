export {
  createQueries,
  invalidateOnMutation,
  invalidateTables,
  queryCache,
} from "./queries.ts";
export { clearOnUserChange } from "./user-change.ts";
export { optimistic } from "./optimistic.ts";
export type {
  OptimisticHandlers,
  OptimisticSnapshot,
  OptimisticTarget,
} from "./optimistic.ts";
export { escapeLike } from "../ir/escape-like.ts";
export type { UserChangeSource } from "./user-change.ts";
export type {
  BetterQueryMeta,
  QueriesOptions,
  InfiniteExtras,
  InfiniteOptionsOf,
  MutationOptionsOf,
  BetterQueries,
  QueryHelpers,
  QueryKeyOf,
  QueryOptionsOf,
  TableQueries,
} from "./queries.ts";
