export {
  createPosts,
  type Post,
  type PostBoard,
  type PostBoardInput,
  type PostBoardKind,
  type PostInput,
  type PostModeration,
  type Posts,
  type PostsFilter,
  type PostsOptions,
  type PostStateInput,
  type PostStatus,
  type PostVotes,
} from "./posts.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../core/block-hooks.ts";

export type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport, RpcClient } from "../../core/block-transport.ts";

export { postsBlock } from "./manifest.ts";

export { postsSqlOptions, type PostsSqlOptions } from "./options.ts";

export { postBoardInputSchema, postInputSchema } from "./schemas.ts";

export { postsEvents } from "./events.ts";

export type {
  PostBoardEventData,
  PostEventData,
  PostsEvents,
} from "./events.ts";
