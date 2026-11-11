"use server";

import { ok } from "better-supabase";
import { tenantCredentialRef } from "better-supabase/credentials";
import { refresh } from "next/cache";
import * as v from "valibot";

import { bsbCore } from "@/lib/supabase/server-core";

import { PROVIDERS } from "./ai-provider-options";
import { aiProviders, providerCredentials } from "./ai-providers-server";

const Slug = v.pipe(v.string(), v.trim(), v.regex(/^[a-z0-9-]{1,40}$/));

/**
 * Stores the API key in Vault under the organization, then saves the provider
 * row that names it. The row never holds the key itself.
 */
export const addProviderKey = bsbCore.action(
  {
    input: v.object({
      provider: v.picklist(PROVIDERS),
      name: v.optional(Slug),
      model: v.optional(
        v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(120)),
      ),
      apiKey: v.pipe(v.string(), v.trim(), v.minLength(8), v.maxLength(500)),
    }),
    requireTenant: true,
    permission: "ai_keys.manage",
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

    const saved = await aiProviders(supabase).keys.upsert({
      organizationId: tenant,
      key: {
        provider,
        name: keyName,
        credentialRef: ref,
        settings: model === undefined ? {} : { model },
      },
    });

    if (!saved.ok) {
      return saved;
    }

    refresh();

    return ok(saved.data.id);
  },
);

/** Deletes a key and revokes its Vault secret. */
export const removeProviderKey = bsbCore.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "ai_keys.manage",
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

/**
 * Saves the order the gateway tries the organization's providers in, and which
 * keys take part. The first enabled provider answers; the gateway moves to the
 * next when it fails (the `order` gateway option).
 */
export const setProviderRouting = bsbCore.action(
  {
    input: v.object({
      keys: v.pipe(
        v.array(
          v.object({ id: v.pipe(v.string(), v.uuid()), enabled: v.boolean() }),
        ),
        v.minLength(1),
        v.maxLength(50),
      ),
    }),
    requireTenant: true,
    permission: "ai_keys.manage",
  },
  async ({ keys }, { tenant, supabase }) => {
    const providers = aiProviders(supabase);
    const current = await providers.keys.list(tenant, { limit: 100 });

    if (!current.ok) {
      return current;
    }

    for (const [priority, entry] of keys.entries()) {
      const key = current.data.find((candidate) => candidate.id === entry.id);

      if (key === undefined) {
        continue;
      }

      const saved = await providers.keys.upsert({
        organizationId: tenant,
        key: {
          provider: key.provider,
          name: key.name,
          credentialRef: key.credentialRef,
          settings: { ...key.settings, priority },
          enabled: entry.enabled,
        },
      });

      if (!saved.ok) {
        return saved;
      }
    }

    refresh();

    return ok(keys.length);
  },
);
