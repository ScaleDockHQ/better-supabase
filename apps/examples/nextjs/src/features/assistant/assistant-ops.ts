import "server-only";
import type { AiAccess } from "better-supabase/blocks/prompts";

import { tenantOf } from "better-supabase/next";

import type { Permission } from "@/features/user/user-permissions";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

/**
 * The caller the service-role AI blocks act for: the active organization and
 * whether the caller holds `permission`. Passed as the blocks' `access`, it
 * makes them refuse another organization's prompts, datasets, runs and log.
 */
export async function opsAccess(permission: Permission): Promise<AiAccess> {
  const [session, permissions] = await Promise.all([
    getSession(),
    getPermissions(),
  ]);

  return {
    organizationId: tenantOf(session),
    allowed: can(permissions, permission),
    permission,
  };
}

/** The access of a server action that already passed `requireTenant`. */
export const actionAccess = (tenant: string, permission: string): AiAccess => ({
  organizationId: tenant,
  allowed: true,
  permission,
});

/** The prompt name of the assistant's system instructions. */
export const ASSISTANT_PROMPT = "assistant.system";

/** The prompt name of one agent's instructions. */
export const agentPrompt = (slug: string): string =>
  `agent.${slug}.instructions`;

/** The agent name the guardrail policies and decisions use for the assistant. */
export const ASSISTANT_AGENT = "assistant";
