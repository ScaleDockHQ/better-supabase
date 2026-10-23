"use server";

import { ok } from "better-supabase";
import { tenantCredentialRef } from "better-supabase/credentials";
import { refresh } from "next/cache";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { bsb } from "@/lib/supabase/server";

import { PROVIDERS } from "./ai-provider-options";
import { aiProviders, providerCredentials } from "./ai-providers-server";

const Slug = v.pipe(v.string(), v.trim(), v.regex(/^[a-z0-9-]{1,40}$/));

/**
 * Stores the API key in Vault under the organization, then saves the provider
 * row that names it. The row never holds the key itself.
 */
export const addProviderKey = bsb.action(
  {
    input: v.object({
      provider: v.picklist(PROVIDERS),
      name: v.optional(Slug),
      model: v.optional(
        v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(120)),
      ),
      apiKey: v.pipe(v.string(), v.trim(), v.minLength(8), v.maxLength(500)),
    }),
    requireOrganization: true,
    authorize: (session) => can(session, "ai.admin"),
  },
  async ({ provider, name, model, apiKey }, { tenant, supabase }) => {
    const keyName = name ?? "default";

    const ref = tenantCredentialRef(tenant, {
      provider: "vault",
      secret: `ai-provider-${provider}-${keyName}`,
    });

    const stored = await providerCredentials().set(ref, apiKey);

    if (!stored.ok) {
      return stored;
    }

    const saved = await aiProviders(supabase).keys.upsert(tenant, {
      provider,
      name: keyName,
      credentialRef: ref,
      settings: model === undefined ? {} : { model },
    });

    if (!saved.ok) {
      return saved;
    }

    refresh();

    return ok(saved.data.id);
  },
);

/** Deletes a key and revokes its Vault secret. */
export const removeProviderKey = bsb.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireOrganization: true,
    authorize: (session) => can(session, "ai.admin"),
  },
  async ({ id }, { supabase }) => {
    const removed = await aiProviders(supabase).keys.remove(id);

    if (!removed.ok) {
      return removed;
    }

    refresh();

    return ok(removed.data);
  },
);
