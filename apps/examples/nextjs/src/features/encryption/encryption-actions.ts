"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/**
 * Replaces the organization's data key and encrypts every stored value again
 * (`rotate_field_key` checks `field_encryption.manage`).
 */
export const rotateFieldKey = bsb.blockAction(
  ({ db }) => db.fieldEncryption,
  "rotateKey",
  {
    input: v.object({}),
    requireTenant: true,
    permission: "field_encryption.manage",
    tags: () => [tags.encryption()],
    refresh: true,
    args: (_, { tenant }) => [`tenant:${tenant}`],
  },
  (rotated) => rotated.values,
);
