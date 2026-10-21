import type { BlockOptions } from "../shared.ts";

import {
  createSsfReceiver,
  type SsfReceiver,
  type SsfReceiverOptions,
} from "./receiver.ts";
import {
  createSsfTransmitter,
  type SsfTransmitter,
  type SsfTransmitterOptions,
} from "./transmitter.ts";

export type SharedSignalsOptions = BlockOptions;

/**
 * The `shared-signals` block: transmitters and receivers on the shared
 * transport.
 */
export interface SharedSignals {
  transmitter(
    options: Omit<SsfTransmitterOptions, keyof BlockOptions>,
  ): SsfTransmitter;
  receiver(options: Omit<SsfReceiverOptions, keyof BlockOptions>): SsfReceiver;
}

/**
 * What `createBlocks` builds: each transmitter and receiver takes the block's
 * transport.
 */
export function createSharedSignals(
  options: SharedSignalsOptions,
): SharedSignals {
  return {
    transmitter: (config) => createSsfTransmitter({ ...options, ...config }),
    receiver: (config) => createSsfReceiver({ ...options, ...config }),
  };
}
