import "server-only";
import type { Team } from "better-supabase/blocks/teams";

import { tenantOf } from "better-supabase/next";
import { cacheLife, cacheTag } from "next/cache";

import { bsb } from "@/lib/supabase/server";

import { teamsTag } from "./teams-cache";

export type { Team } from "better-supabase/blocks/teams";

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

  // Every write to the teams calls updateTag(teamsTag), so the entry never
  // needs to expire on a timer.
  cacheLife("max");
  cacheTag(teamsTag(tenant));

  return db.teams.list(tenant, { limit: 100 }).orThrow();
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
      limit: 100,
    })
    .orThrow();
}

/** One team of `getTeams`, `null` when the organization has no such team. */
export async function getTeam(id: string): Promise<Team | null> {
  const teams = await getTeams();

  return teams.find((team) => team.id === id) ?? null;
}
