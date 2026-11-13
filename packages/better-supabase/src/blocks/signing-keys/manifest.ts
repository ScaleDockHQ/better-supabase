import type { BlockOf } from "../define-block.ts";
import type { SigningKeysEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { signingKeysEvents } from "./events.ts";
import { signingKeysSqlOptions } from "./options.ts";
import { createSigningKeys } from "./signing-keys.ts";

/** The `signing-keys` block's manifest (ADR 0029). */
export const signingKeysBlock: BlockOf<
  "signing-keys",
  typeof createSigningKeys,
  SigningKeysEvents
> = defineBlock({
  name: "signing-keys",
  sql: ["signing-keys"],
  options: { "signing-keys": signingKeysSqlOptions },
  events: signingKeysEvents,
  create: createSigningKeys,
  category: "developer",
  entities: {
    signing_key: { mutability: "state-machine", emits: { create: true } },
  },
  description:
    "Ed25519 or ES256 signing keys per owner: the private JWK in Supabase Vault, one active key per owner, rotation that keeps a retired kid in the JWKS until the latest exp a signer noted, and a purge. Only the service role calls it; createSigningKeys() in better-supabase/blocks/signing-keys generates keys and signs with WebCrypto.",
  recipes: ["signing-keys-rotation"],
});
