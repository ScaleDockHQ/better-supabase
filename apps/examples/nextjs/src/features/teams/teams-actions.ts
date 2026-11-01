"use server";

import { ok } from "better-supabase";
import { updateTag } from "next/cache";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { teamsTag } from "./teams-queries";

const Id = v.pipe(v.string(), v.uuid());
const Name = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80));

const Description = v.pipe(
  v.optional(v.string(), ""),
  v.trim(),
  v.maxLength(280),
  v.transform((value) => (value === "" ? null : value)),
);

/**
 * Expires the organization's team list for everyone and re-renders the caller's
 * page. `list_teams` and the functions below check `teams.manage` again in
 * SQL.
 */
async function teamsChanged(
  tenant: string,
  auth: Parameters<typeof refreshCaller>[0],
): Promise<void> {
  updateTag(teamsTag(tenant));
  await refreshCaller(auth);
}

/** Creates a team; the block derives the slug from the name. */
export const createTeam = bsb.action(
  {
    input: v.object({ name: Name, description: Description }),
    requireTenant: true,
  },
  async ({ name, description }, { tenant, db, auth }) => {
    const created = await db.teams.create({
      organizationId: tenant,
      name,
      description: description ?? undefined,
    });

    if (!created.ok) {
      return created;
    }

    await teamsChanged(tenant, auth);

    return ok(created.data.id);
  },
);

/** Renames a team and sets or clears its description. */
export const updateTeam = bsb.action(
  {
    input: v.object({ id: Id, name: Name, description: Description }),
    requireTenant: true,
  },
  async ({ id, name, description }, { tenant, db, auth }) => {
    const updated = await db.teams.update({
      id,
      name,
      options: { description },
    });

    if (!updated.ok) {
      return updated;
    }

    await teamsChanged(tenant, auth);

    return ok(updated.data.id);
  },
);

/** Archives or restores a team. */
export const setTeamArchived = bsb.action(
  { input: v.object({ id: Id, archived: v.boolean() }), requireTenant: true },
  async ({ id, archived }, { tenant, db, auth }) => {
    const changed = archived
      ? await db.teams.archive(id)
      : await db.teams.restore(id);

    if (!changed.ok) {
      return changed;
    }

    await teamsChanged(tenant, auth);

    return ok(changed.data);
  },
);

/** Deletes a team; customers it owned keep no owner (`on delete set null`). */
export const deleteTeam = bsb.action(
  { input: v.object({ id: Id }), requireTenant: true },
  async ({ id }, { tenant, db, auth }) => {
    const deleted = await db.teams.delete(id);

    if (!deleted.ok) {
      return deleted;
    }

    await teamsChanged(tenant, auth);

    return ok(deleted.data);
  },
);

/** Adds a member of the organization to a team, or takes them off it. */
export const setTeamMember = bsb.action(
  {
    input: v.object({ teamId: Id, userId: Id, member: v.boolean() }),
    requireTenant: true,
  },
  async ({ teamId, userId, member }, { tenant, db, auth }) => {
    const changed = member
      ? await db.teams.addMember({ teamId, userId })
      : await db.teams.removeMember({ teamId, userId });

    if (!changed.ok) {
      return changed;
    }

    await teamsChanged(tenant, auth);

    return ok(changed.data);
  },
);
