import "server-only";
import type { Team } from "better-supabase/blocks/teams";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { bsb } from "@/lib/supabase/server";

export type { Team } from "better-supabase/blocks/teams";

/** The tag of one organization's teams. */
export function teamsTag(organizationId: string): string {
  return `teams:${organizationId}`;
}

/**
 * The active organization's teams through the teams block's `list_teams`,
 * sorted by name, with their status and member ids. Empty without an
 * organization. Refused without `teams.read`.
 */
export async function getTeams(): Promise<readonly Team[]> {
  "use cache: private";
  const { db, session } = await bsb.cached();
  const tenant = tenantOf(session);

  if (tenant === undefined) {
    return [];
  }

  cacheTag(teamsTag(tenant));

  return db.teams.list(tenant).orThrow();
}

/**
 * The customers a team owns, from `public.customers_with_owner`: an app view
 * over the app's `customers` table joined to the teams block's table. It is
 * `security_invoker`, so the customers' RLS decides the rows.
 */
export async function getTeamCustomers(teamId: string) {
  "use cache: private";
  const { db } = await bsb.cached({ tables: ["customers"] });

  return db.customersWithOwner
    .list({
      where: { ownerTeamId: teamId },
      select: ["id", "name", "status"],
      orderBy: { name: "asc" },
    })
    .orThrow();
}

/** One team of `getTeams`, `null` when the organization has no such team. */
export async function getTeam(id: string): Promise<Team | null> {
  const teams = await getTeams();

  return teams.find((team) => team.id === id) ?? null;
}
