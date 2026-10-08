"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import { after } from "next/server";
import * as v from "valibot";

import { recordAudit } from "@/features/audit/record-audit";
import { can, canAssign } from "@/features/user/user-permissions";
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
    after(() =>
      recordAudit(supabase, {
        eventType: "organization.created",
        category: "organization",
        organizationId: created.data.id,
        targetType: "organization",
        record: created.data.id,
        targetLabel: name,
      }),
    );
    return organizations.switch(created.data.id);
  },
);

export const updateOrganization = bs.action(
  {
    input: v.object({ name: Name, slug: Slug }),
    requireTenant: true,
    authorize: (session) => can(session, "organization.update"),
  },
  async ({ name, slug }, { tenant: organizationId, supabase }) => {
    const updated = await blocks(supabase).organizations.update(
      organizationId,
      {
        name,
        slug,
      },
    );
    if (!updated.ok) return updated;
    after(() =>
      recordAudit(supabase, {
        eventType: "organization.updated",
        category: "organization",
        organizationId,
        targetType: "organization",
        record: organizationId,
        targetLabel: name,
      }),
    );
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
    requireTenant: true,
    authorize: (session, { role }) => canAssign(session, role),
  },
  async ({ email, role }, { tenant: organizationId, supabase }) => {
    const { organizations, onboarding } = blocks(supabase);
    const sent = await organizations.invite({ organizationId, email, role });
    if (!sent.ok) return sent;
    after(() =>
      recordAudit(supabase, {
        eventType: "invitation.created",
        category: "membership",
        organizationId,
        targetType: "invitation",
        record: sent.data.invitation.id,
        targetLabel: email,
        metadata: { role },
      }),
    );
    await onboarding.complete("invite", organizationId);
    refresh();
    return ok({ token: sent.data.token });
  },
);

export const revokeInvitation = bs.action(
  {
    input: v.object({ invitationId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "members.invite"),
  },
  async ({ invitationId }, { tenant: organizationId, supabase }) => {
    const revoked =
      await blocks(supabase).organizations.revokeInvitation(invitationId);
    if (!revoked.ok) return revoked;
    after(() =>
      recordAudit(supabase, {
        eventType: "invitation.revoked",
        category: "membership",
        organizationId,
        targetType: "invitation",
        record: invitationId,
      }),
    );
    refresh();
    return ok(revoked.data);
  },
);

export const updateMemberRole = bs.action(
  {
    input: v.object({ userId: Id, role: Role }),
    requireTenant: true,
    authorize: (session, { role }) => canAssign(session, role),
  },
  async ({ userId, role }, { tenant: organizationId, supabase }) => {
    const updated = await blocks(supabase).organizations.updateMemberRole(
      organizationId,
      userId,
      role,
    );
    if (!updated.ok) return updated;
    after(() =>
      recordAudit(supabase, {
        eventType: "membership.role_changed",
        category: "membership",
        organizationId,
        targetType: "user",
        record: userId,
        metadata: { role },
      }),
    );
    // The member's token still carries the old role until it refreshes.
    bs.invalidateSession(userId);
    return ok(true);
  },
);

export const removeMember = bs.action(
  {
    input: v.object({ userId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "members.remove"),
  },
  async ({ userId }, { tenant: organizationId, supabase }) => {
    const removed = await blocks(supabase).organizations.removeMember(
      organizationId,
      userId,
    );
    if (!removed.ok) return removed;
    after(() =>
      recordAudit(supabase, {
        eventType: "membership.removed",
        category: "membership",
        organizationId,
        targetType: "user",
        record: userId,
      }),
    );
    bs.invalidateSession(userId);
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
    requireTenant: true,
    authorize: (session) => can(session, "settings.update"),
  },
  async ({ defaultRole, weekStart }, { tenant: organizationId, supabase }) => {
    const { settings } = blocks(supabase);
    const [role, week] = await Promise.all([
      settings.organization.set(organizationId, "defaultRole", defaultRole),
      settings.organization.set(organizationId, "weekStart", weekStart),
    ]);
    if (!role.ok) return role;
    if (!week.ok) return week;
    refresh();
    return ok(true);
  },
);

/** Leaves the active organization; the owner has to transfer ownership first. */
export const leaveOrganization = bs.action(
  { requireTenant: true },
  async (_input, { tenant: organizationId, supabase }) =>
    blocks(supabase).organizations.leave(organizationId),
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
    after(() =>
      recordAudit(
        supabase,
        v.is(v.string(), name) ? { ...event, targetLabel: name } : event,
      ),
    );
    return organizations.switch(organizationId);
  },
);
