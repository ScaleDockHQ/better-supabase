import type { BlockOptions } from "../shared.ts";
import type { SsfReceiver, SsfReceiverOptions } from "./receiver.ts";
import type { SsfTransmitter, SsfTransmitterOptions } from "./transmitter.ts";

import { createSsfReceiver } from "./receiver.ts";
import { createSsfTransmitter } from "./transmitter.ts";

export type SecurityEventsOptions = BlockOptions;

/**
 * The `security-events` block: transmitters and receivers on the shared
 * transport.
 */
export interface SecurityEvents {
  transmitter(
    options: Omit<SsfTransmitterOptions, keyof BlockOptions>,
  ): SsfTransmitter;
  receiver(options: Omit<SsfReceiverOptions, keyof BlockOptions>): SsfReceiver;
}

/**
 * What `createBlocks` builds: each transmitter and receiver takes the block's
 * transport.
 */
export function createSecurityEvents(
  options: SecurityEventsOptions,
): SecurityEvents {
  return {
    transmitter: (config) => createSsfTransmitter({ ...options, ...config }),
    receiver: (config) => createSsfReceiver({ ...options, ...config }),
  };
}
