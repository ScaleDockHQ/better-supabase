import "server-only";
import type {
  SigningKeyOwner,
  SigningKeys,
} from "better-supabase/blocks/signing-keys";

import { rpcTransport } from "better-supabase/blocks/organizations";
import { createSigningKeys } from "better-supabase/blocks/signing-keys";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bs } from "@/lib/supabase/server";

const API_SCHEMA = blockConfig["signing-keys"].api;

/**
 * Every signing-keys function is service-role only, because the private keys
 * sit in Vault. Callers check the member's permission first.
 */
export function signingKeys(): SigningKeys {
  return createSigningKeys({
    transport: rpcTransport(bs.admin().$client, { schema: API_SCHEMA }),
    schema: API_SCHEMA,
  });
}

export function organizationOwner(organizationId: string): SigningKeyOwner {
  return { type: "organization", id: organizationId };
}

/** Rotating or reading keys is an organization setting. */
export const SIGNING_KEYS_PERMISSION = "organization.update";
