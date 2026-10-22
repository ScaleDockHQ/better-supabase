export {
  createTrash,
  type Trash,
  type TrashBatch,
  type TrashItem,
  type TrashListOptions,
  type TrashOptions,
} from "./trash.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export {
  type TrashDeleteArgs,
  type TrashExtension,
  trashExtension,
  type TrashFindArgs,
  type TrashMethods,
} from "./extension.ts";

export { trashBlock } from "./manifest.ts";

export { trashEvents } from "./events.ts";

export type { TrashEvents } from "./events.ts";
