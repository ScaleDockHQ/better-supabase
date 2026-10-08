"use server";

import { dbError, err, ok } from "better-supabase";
import { toSession } from "better-supabase/next";
import { refresh } from "next/cache";
import { after } from "next/server";
import * as v from "valibot";

import { recordAudit } from "@/features/audit/record-audit";
import { activeOrganizationId, can } from "@/features/user/user-permissions";
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
  },
  async ({ name }, { auth, supabase }) => {
    const session = toSession(auth);
    const organizationId = activeOrganizationId(session);
    if (!organizationId || !can(session, "api_keys.own")) {
      return err(dbError("forbidden", "You cannot create API keys"));
    }
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
  { input: v.object({ id: v.pipe(v.string(), v.uuid()) }) },
  async ({ id }, { auth, supabase }) => {
    const organizationId = activeOrganizationId(toSession(auth));
    if (!organizationId) {
      return err(dbError("forbidden", "You are not in an organization"));
    }
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
