"use server";

import { dbError, err, ok } from "better-supabase";
import { toSession } from "better-supabase/next";
import { refresh } from "next/cache";
import * as v from "valibot";

import { recordAudit } from "@/features/audit/record-audit";
import {
  activeOrganizationId,
  can,
  canAssign,
} from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { Role } from "@/lib/claims";
import { bs } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());
const Name = v.pipe(v.string(), v.trim(), v.minLength(2), v.maxLength(80));
const Slug = v.pipe(
  v.string(),
  v.trim(),
  v.toLowerCase(),
  v.regex(/^[a-z0-9](?:[a-z0-9-]{0,46}[a-z0-9])?$/),
);

function slugify(name: string): string {
  return name
    .normalize("NFKD")
    .replaceAll(/[\u0300-\u036F]/g, "")
    .toLowerCase()
    .replaceAll(/[^a-z0-9]+/g, "-")
    .replaceAll(/^-+|-+$/g, "")
    .slice(0, 48);
}

/**
 * Makes `organizationId` the active tenant. The tenant is a claim, so the
 * browser refreshes its session afterwards (see `useSwitchOrganization`).
 */
export const switchOrganization = bs.action(
  { input: v.object({ organizationId: Id }) },
  async ({ organizationId }, { supabase }) =>
    blocks(supabase).organizations.switch(organizationId),
);

/** Creates an organization owned by the caller, then switches to it. */
export const createOrganization = bs.action(
  { input: v.object({ name: Name }) },
  async ({ name }, { supabase }) => {
    const { organizations } = blocks(supabase);
    const created = await organizations.create({ name, slug: slugify(name) });
    if (!created.ok) return created;
    await recordAudit(supabase, {
      eventType: "organization.created",
      category: "organization",
      organizationId: created.data.id,
      targetType: "organization",
      record: created.data.id,
      targetLabel: name,
    });
    return organizations.switch(created.data.id);
  },
);

export const updateOrganization = bs.action(
  { input: v.object({ name: Name, slug: Slug }) },
  async ({ name, slug }, { auth, supabase }) => {
    const session = toSession(auth);
    const organizationId = activeOrganizationId(session);
    if (!organizationId || !can(session, "organization.update")) {
      return err(dbError("forbidden", "You cannot change this organization"));
    }
    const updated = await blocks(supabase).organizations.update(
      organizationId,
      {
        name,
        slug,
      },
    );
    if (!updated.ok) return updated;
    await recordAudit(supabase, {
      eventType: "organization.updated",
      category: "organization",
      organizationId,
      targetType: "organization",
      record: organizationId,
      targetLabel: name,
    });
    refresh();
    return ok(true);
  },
);

/**
 * Invites `email` to the active organization. There is no mailer in the
 * example: the token comes back so the page can show the accept link.
 */
export const inviteMember = bs.action(
  {
    input: v.object({
      email: v.pipe(v.string(), v.trim(), v.toLowerCase(), v.email()),
      role: Role,
    }),
  },
  async ({ email, role }, { auth, supabase }) => {
    const session = toSession(auth);
    const organizationId = activeOrganizationId(session);
    if (!organizationId || !canAssign(session, role)) {
      return err(dbError("forbidden", "You cannot invite with this role"));
    }
    const { organizations, onboarding } = blocks(supabase);
    const sent = await organizations.invite({ organizationId, email, role });
    if (!sent.ok) return sent;
    await recordAudit(supabase, {
      eventType: "invitation.created",
      category: "membership",
      organizationId,
      targetType: "invitation",
      record: sent.data.invitation.id,
      targetLabel: email,
      metadata: { role },
    });
    await onboarding.complete("invite", organizationId);
    refresh();
    return ok({ token: sent.data.token });
  },
);

export const revokeInvitation = bs.action(
  { input: v.object({ invitationId: Id }) },
  async ({ invitationId }, { auth, supabase }) => {
    const session = toSession(auth);
    const organizationId = activeOrganizationId(session);
    if (!organizationId || !can(session, "members.invite")) {
      return err(dbError("forbidden", "You cannot revoke invitations"));
    }
    const revoked =
      await blocks(supabase).organizations.revokeInvitation(invitationId);
    if (!revoked.ok) return revoked;
    await recordAudit(supabase, {
      eventType: "invitation.revoked",
      category: "membership",
      organizationId,
      targetType: "invitation",
      record: invitationId,
    });
    refresh();
    return ok(revoked.data);
  },
);

export const updateMemberRole = bs.action(
  { input: v.object({ userId: Id, role: Role }) },
  async ({ userId, role }, { auth, supabase }) => {
    const session = toSession(auth);
    const organizationId = activeOrganizationId(session);
    if (!organizationId || !canAssign(session, role)) {
      return err(dbError("forbidden", "You cannot give this role"));
    }
    const updated = await blocks(supabase).organizations.updateMemberRole(
      organizationId,
      userId,
      role,
    );
    if (!updated.ok) return updated;
    await recordAudit(supabase, {
      eventType: "membership.role_changed",
      category: "membership",
      organizationId,
      targetType: "user",
      record: userId,
      metadata: { role },
    });
    // The member's token still carries the old role until it refreshes.
    bs.invalidateSession(userId);
    refresh();
    return ok(true);
  },
);

export const removeMember = bs.action(
  { input: v.object({ userId: Id }) },
  async ({ userId }, { auth, supabase }) => {
    const session = toSession(auth);
    const organizationId = activeOrganizationId(session);
    if (!organizationId || !can(session, "members.remove")) {
      return err(dbError("forbidden", "You cannot remove members"));
    }
    const removed = await blocks(supabase).organizations.removeMember(
      organizationId,
      userId,
    );
    if (!removed.ok) return removed;
    await recordAudit(supabase, {
      eventType: "membership.removed",
      category: "membership",
      organizationId,
      targetType: "user",
      record: userId,
    });
    bs.invalidateSession(userId);
    refresh();
    return ok(true);
  },
);

/** Settings from `settings-definition.ts`; the settings module checks `settings.update`. */
export const updateOrganizationSettings = bs.action(
  {
    input: v.object({
      defaultRole: v.picklist(["member", "admin"]),
      weekStart: v.picklist(["monday", "sunday"]),
    }),
  },
  async ({ defaultRole, weekStart }, { auth, supabase }) => {
    const session = toSession(auth);
    const organizationId = activeOrganizationId(session);
    if (!organizationId || !can(session, "settings.update")) {
      return err(dbError("forbidden", "You cannot change these settings"));
    }
    const { settings } = blocks(supabase);
    const role = await settings.organization.set(
      organizationId,
      "defaultRole",
      defaultRole,
    );
    if (!role.ok) return role;
    const week = await settings.organization.set(
      organizationId,
      "weekStart",
      weekStart,
    );
    if (!week.ok) return week;
    refresh();
    return ok(true);
  },
);

/** Leaves the active organization; the owner has to transfer ownership first. */
export const leaveOrganization = bs.action(
  {},
  async (_input, { auth, supabase }) => {
    const organizationId = activeOrganizationId(toSession(auth));
    if (!organizationId) {
      return err(dbError("forbidden", "You are not in an organization"));
    }
    return blocks(supabase).organizations.leave(organizationId);
  },
);

export const declineInvitation = bs.action(
  { input: v.object({ token: v.pipe(v.string(), v.minLength(8)) }) },
  async ({ token }, { supabase }) =>
    blocks(supabase).organizations.declineInvitation(token),
);

/** Accepts an invitation for the signed-in user and switches to it. */
export const acceptInvitation = bs.action(
  { input: v.object({ token: v.pipe(v.string(), v.minLength(8)) }) },
  async ({ token }, { supabase }) => {
    const { organizations } = blocks(supabase);
    const preview = await organizations.previewInvitation(token);
    const accepted = await organizations.acceptInvitation(token);
    if (!accepted.ok) return accepted;
    const organizationId = accepted.data.organizationId;
    if (!organizationId) return ok({ organizationId: null, refresh: false });
    const name = preview.ok ? preview.data?.organization?.["name"] : undefined;
    const event = {
      eventType: "invitation.accepted",
      category: "membership",
      organizationId,
      targetType: "organization",
      record: organizationId,
    };
    await recordAudit(
      supabase,
      v.is(v.string(), name) ? { ...event, targetLabel: name } : event,
    );
    return organizations.switch(organizationId);
  },
);
