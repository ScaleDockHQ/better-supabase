export {
  type Access,
  type AccessCallOptions,
  type AccessOptions,
  createAccess,
} from "./access.ts";

export { accessBlock } from "./manifest.ts";

export {
  can,
  permissionFlags,
  type PermissionFlags,
  permissionMatches,
  type PermissionSet,
} from "./permissions.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export { batchPermissions, createPermissionsController } from "./client.ts";

export type {
  PermissionsActions,
  PermissionsController,
  PermissionsControllerOptions,
  PermissionSource,
  PermissionsSnapshot,
} from "./client.ts";
