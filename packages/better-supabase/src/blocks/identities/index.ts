export {
  beginLink,
  createIdentities,
  type Identities,
  type IdentitiesOptions,
  type IdentitySource,
  identityResolver,
  type LinkCode,
  type LinkedIdentity,
  redeemLink,
  type RedeemedLink,
} from "./identities.ts";

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

export { identitiesBlock } from "./manifest.ts";
