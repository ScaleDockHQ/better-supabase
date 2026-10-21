"use server";

import { dbError, err, ok } from "better-supabase";
import * as v from "valibot";

import { getMembers } from "@/features/organization/organization-queries";
import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

import { driveOf } from "./drive-client";
import { DRIVE_ROLES } from "./drive-roles";

const Id = v.pipe(v.string(), v.uuid());

const Principal = v.object({ type: v.picklist(["user", "team"]), id: Id });

export interface SharingGrant {
  readonly type: "user" | "team" | "role";
  readonly id: string;
  readonly name: string;
  readonly role: string;
  /** Granted on a folder above the item, so it is removed there. */
  readonly inherited: boolean;
}

export interface SharingTarget {
  readonly type: "user" | "team";
  readonly id: string;
  readonly name: string;
}

/**
 * The item's grants, inherited ones included, and the members and teams it can
 * be shared with. The drive functions decide who may read the grants.
 */
export const loadDriveSharing = bs.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "drive.read"),
  },
  async ({ id }, { tenant, supabase }) => {
    const [grants, members, teams] = await Promise.all([
      driveOf(supabase).grants(id),
      getMembers(tenant),
      blocks(supabase).teams.list(tenant),
    ]);

    if (!grants.ok) {
      return grants;
    }

    if (!teams.ok) {
      return teams;
    }

    const targets: SharingTarget[] = [
      ...members.map((member) => ({
        type: "user" as const,
        id: member.userId,
        name: member.name ?? member.email ?? member.userId,
      })),
      ...teams.data.map((team) => ({
        type: "team" as const,
        id: team.id,
        name: team.name,
      })),
    ];

    const names = new Map(
      targets.map((target) => [`${target.type}:${target.id}`, target.name]),
    );

    return ok({
      grants: grants.data.map((grant): SharingGrant => ({
        type: grant.principal.type,
        id: grant.principal.id,
        name:
          names.get(`${grant.principal.type}:${grant.principal.id}`) ??
          grant.principal.id,
        role: grant.role,
        inherited: grant.inherited,
      })),
      targets,
    });
  },
);

/** Shares the item with a member or a team; a second share changes the role. */
export const shareDriveItem = bs.action(
  {
    input: v.object({
      id: Id,
      principal: Principal,
      role: v.picklist(DRIVE_ROLES),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "drive.read"),
  },
  async ({ id, principal, role }, { supabase, auth }) => {
    const shared = await driveOf(supabase).share(id, principal, role);

    if (!shared.ok) {
      return shared;
    }

    refreshCaller(auth);

    return ok(null);
  },
);

/** Removes a grant made on the item itself. */
export const unshareDriveItem = bs.action(
  {
    input: v.object({ id: Id, principal: Principal }),
    requireTenant: true,
    authorize: (session) => can(session, "drive.read"),
  },
  async ({ id, principal }, { supabase, auth }) => {
    const removed = await driveOf(supabase).unshare(id, principal);

    if (!removed.ok) {
      return removed;
    }

    if (!removed.data) {
      return err(dbError("not_found", "Grant not found"));
    }

    refreshCaller(auth);

    return ok(null);
  },
);
