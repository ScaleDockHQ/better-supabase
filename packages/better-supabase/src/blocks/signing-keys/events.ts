import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `signing_key.*`: the key's owner and kid, never key material. */
export interface SigningKeyEventData {
  readonly ownerType: string;
  readonly ownerId: string;
  readonly kid: string;
}

/** `signing_key.created` also carries the key type. */
export interface SigningKeyCreatedEventData extends SigningKeyEventData {
  readonly alg: "Ed25519" | "ES256";
}

/** The events of the `signing-keys` block: type to data. */
export type SigningKeysEvents = {
  readonly "signing_key.created": SigningKeyCreatedEventData;
  readonly "signing_key.retired": SigningKeyEventData;
};

/** The `signing-keys` block's event types, for its manifest and `onBlockEvent`. */
export const signingKeysEvents: Events<SigningKeysEvents> = defineEvents({
  "signing_key.created": event<SigningKeyCreatedEventData>(),
  "signing_key.retired": event<SigningKeyEventData>(),
});
