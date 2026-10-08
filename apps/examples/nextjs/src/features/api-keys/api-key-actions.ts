"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import { after } from "next/server";
import * as v from "valibot";

import { recordAudit } from "@/features/audit/record-audit";
import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/**
 * Admins create organization keys; everyone else gets a personal key that
 * acts as them. The token comes back once: only its hash is stored.
 */
export const createApiKey = bs.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "api_keys.own"),
  },
  async ({ name }, { tenant: organizationId, session, supabase }) => {
    const { apiKeys, onboarding } = blocks(supabase);
    const created = await apiKeys.create({
      name,
      organizationId,
      personal: !can(session, "api_keys.manage"),
    });
    if (!created.ok) return created;
    after(() =>
      recordAudit(supabase, {
        eventType: "api_key.created",
        category: "security",
        organizationId,
        targetType: "api_key",
        record: created.data.key.id,
        targetLabel: name,
      }),
    );
    await onboarding.complete("api-key", organizationId);
    refresh();
    return ok({ token: created.data.token });
  },
);

export const revokeApiKey = bs.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
  },
  async ({ id }, { tenant: organizationId, supabase }) => {
    const revoked = await blocks(supabase).apiKeys.revoke(id);
    if (!revoked.ok) return revoked;
    after(() =>
      recordAudit(supabase, {
        eventType: "api_key.revoked",
        category: "security",
        organizationId,
        targetType: "api_key",
        record: id,
      }),
    );
    refresh();
    return ok(revoked.data);
  },
);
