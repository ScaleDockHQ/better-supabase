"use server";

import type { Result } from "better-supabase";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { ENCRYPTION_TAG } from "./encryption-cache";

/**
 * Replaces the organization's data key and encrypts every stored value again
 * (`rotate_field_key` checks `field_encryption.manage`).
 */
export const rotateFieldKey = bsb.action(
  {
    input: v.object({}),
    requireTenant: true,
    permission: "field_encryption.manage",
  },
  async (_input, { tenant, db, auth }): Promise<Result<number>> => {
    const rotated = await db.fieldEncryption.rotateKey(`tenant:${tenant}`);

    if (!rotated.ok) {
      return rotated;
    }

    await refreshCaller(auth, [ENCRYPTION_TAG]);

    return ok(rotated.data.values);
  },
);
