"use server";

import { ok } from "better-supabase";

import { tags } from "@/lib/supabase/generated.tags";
import { bsbCore } from "@/lib/supabase/server-core";

import {
  organizationOwner,
  SIGNING_KEYS_PERMISSION,
  signingKeys,
} from "./signing-keys-server";

/**
 * Makes a new key active and retires the current one, which stays in the JWKS
 * until the tokens it signed expire. With no key yet, it creates the first
 * (Ed25519).
 */
export const rotateSigningKey = bsbCore.action(
  {
    requireTenant: true,
    permission: SIGNING_KEYS_PERMISSION,
    tags: () => [tags.signingKeys()],
    refresh: true,
  },
  async (_input, { tenant }) => {
    const rotated = await signingKeys().rotate({
      owner: organizationOwner(tenant),
    });

    if (!rotated.ok) {
      return rotated;
    }

    return ok({ kid: rotated.data.kid, retired: rotated.data.retired });
  },
);
