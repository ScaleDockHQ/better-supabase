export {
  beginLink,
  createLinkedIdentities,
  type LinkedIdentities,
  type LinkedIdentitiesOptions,
  type IdentitySource,
  identityResolver,
  type LinkCode,
  type LinkedIdentity,
  redeemLink,
  type RedeemedLink,
} from "./linked-identities.ts";

export type {
  IdentityRef,
  IdentityTarget,
  PrincipalByIdentity,
} from "../../core/contracts/authorization-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export { linkedIdentitiesBlock } from "./manifest.ts";
