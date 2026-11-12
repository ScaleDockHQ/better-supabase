import "server-only";
import { tenantOf } from "better-supabase/next";

import type { Permission } from "@/features/user/user-permissions";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

/**
 * The tenant a read of a service-role block (prompts, evals, guardrails) may
 * serve, or `undefined` when the caller has no active organization or lacks
 * `permission`. Those blocks bypass RLS, so every read checks this itself; the
 * page's menu entry only decides whether the proxy lets the request through.
 */
export async function opsTenant(
  permission: Permission,
): Promise<string | undefined> {
  const [session, permissions] = await Promise.all([
    getSession(),
    getPermissions(),
  ]);

  const organizationId = tenantOf(session);

  return organizationId && can(permissions, permission)
    ? organizationId
    : undefined;
}

/** The prompt name of the assistant's system instructions. */
export const ASSISTANT_PROMPT = "assistant.system";

/** The prompt name of one agent's instructions. */
export const agentPrompt = (slug: string): string =>
  `agent.${slug}.instructions`;

/** The agent name the guardrail policies and decisions use for the assistant. */
export const ASSISTANT_AGENT = "assistant";
