import type { BlockOf } from "../define-block.ts";
import type { FieldEncryptionEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { fieldEncryptionEvents } from "./events.ts";
import { createFieldEncryption } from "./field-encryption.ts";

/** The `field-encryption` block's manifest (ADR 0029). */
export const fieldEncryptionBlock: BlockOf<
  "field-encryption",
  typeof createFieldEncryption,
  FieldEncryptionEvents
> = defineBlock({
  name: "field-encryption",
  sql: ["field-encryption"],
  events: fieldEncryptionEvents,
  create: createFieldEncryption,
  category: "database",
  entities: { field_key: { mutability: "state-machine" } },
  description:
    "Encrypts app table columns and custom field values at rest with a data key per tenant, user or app, kept in Supabase Vault as bs:field-key:<owner>. Only security definer read paths that check the caller's scope decrypt; a lookup column keeps an HMAC of the value under the owner's lookup key for equality searches; drop_field_key deletes both keys so the values can no longer be read or found. Members read which of their owners have keys through field_key_status().",
});
