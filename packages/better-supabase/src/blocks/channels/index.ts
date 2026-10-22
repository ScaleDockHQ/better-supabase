export {
  type Channel,
  type ChannelChange,
  type Channels,
  type ChannelsOptions,
  type ChannelVisibility,
  createChannels,
  type NewChannel,
} from "./channels.ts";

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

export { channelsBlock } from "./manifest.ts";

export { channelChangeSchema, channelInputSchema } from "./schemas.ts";

export { channelsEvents } from "./events.ts";

export type { ChannelsEvents } from "./events.ts";
