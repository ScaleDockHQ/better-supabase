"use server";

import { ok } from "better-supabase";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

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
export const rotateSigningKey = bsb.action(
  {
    requireTenant: true,
    authorize: async () => can(await getPermissions(), SIGNING_KEYS_PERMISSION),
  },
  async (_input, { tenant, auth }) => {
    const rotated = await signingKeys().rotate(organizationOwner(tenant));

    if (!rotated.ok) {
      return rotated;
    }

    refreshCaller(auth);

    return ok({ kid: rotated.data.kid, retired: rotated.data.retired });
  },
);
