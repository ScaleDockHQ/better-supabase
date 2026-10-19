export {
  createDomains,
  createDomainsAdmin,
  normalizeHostname,
  type Domains,
  type DomainsAdmin,
  type DomainsAdminOptions,
  type DomainsOptions,
  type Hostname,
  type HostnameMatch,
  type HostnameRecord,
} from "./domains.ts";

export {
  domainsEvents,
  type DomainsEvents,
  type HostnameEventData,
} from "./events.ts";

export {
  dohResolver,
  type DohResolverOptions,
  type TxtResolver,
} from "../sso/sso.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
  type BlockHooks,
  type BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
  type BlockTransport,
  type RpcClient,
} from "../../core/block-transport.ts";

export { domainsBlock } from "./manifest.ts";
