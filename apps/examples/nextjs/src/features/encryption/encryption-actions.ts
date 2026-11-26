"use server";

import type { Result } from "better-supabase";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/**
 * Replaces the organization's data key and encrypts every stored value again
 * (`rotate_field_key` checks `field_encryption.manage`).
 */
export const rotateFieldKey = bsb.action(
  {
    input: v.object({}),
    requireTenant: true,
    permission: "field_encryption.manage",
    tags: () => [tags.encryption()],
    refresh: true,
  },
  async (_input, { tenant, db }): Promise<Result<number>> => {
    const rotated = await db.fieldEncryption.rotateKey(`tenant:${tenant}`);

    if (!rotated.ok) {
      return rotated;
    }

    return ok(rotated.data.values);
  },
);
