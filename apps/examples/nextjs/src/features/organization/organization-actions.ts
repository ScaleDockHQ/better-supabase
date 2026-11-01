"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import { after } from "next/server";
import * as v from "valibot";

import { recordAudit } from "@/features/audit/record-audit";
import { gettingStarted } from "@/features/onboarding/checklist";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsb } from "@/lib/supabase/server";

import { toMembers, toOrganizationSummaries } from "./organization-queries";

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
 * The caller's organizations with their plans, loaded by `useOrganizations` in
 * the switcher after each switch.
 */
export const loadMyOrganizations = bsb.action({}, async (_input, { db }) =>
  db.$rpc("my_organizations").map((rows) => toOrganizationSummaries(rows)),
);

/** Creates an organization owned by the caller, then switches to it. */
export const createOrganization = bsb.action(
  { input: v.object({ name: Name }) },
  async ({ name }, { db }) => {
    const { organizations } = db.$blocks;

    const created = await organizations.create({
      attributes: { name, slug: slugify(name) },
    });

    if (!created.ok) {
      return created;
    }

    after(() =>
      recordAudit(db, {
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

export const updateOrganization = bsb.action(
  {
    input: v.object({ name: Name, slug: Slug }),
    requireTenant: true,
    permission: "organization.update",
  },
  async ({ name, slug }, { tenant: organizationId, db }) => {
    const updated = await db.$blocks.organizations.update({
      organizationId,
      attributes: { name, slug },
    });

    if (!updated.ok) {
      return updated;
    }

    after(() =>
      recordAudit(db, {
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
 * Runs after `useInvitations` sent an invitation from the browser (the
 * invitations module checks and audits the invite itself): completes the
 * onboarding step and renders the pending invitations again.
 */
export const invitationSent = bsb.action(
  { requireTenant: true, permission: "members.invite" },
  async (_input, { tenant: organizationId, db }) => {
    await db.onboarding.complete({
      checklist: gettingStarted,
      step: "invite",
      organizationId,
    });
    refresh();

    return ok(true);
  },
);

/**
 * The active organization's members with their profiles, loaded by `useMembers`
 * in the members table after a removal.
 */
export const loadMembers = bsb.action(
  { requireTenant: true },
  async (_input, { tenant: organizationId, db, supabase }) =>
    db
      .$rpc("organization_members", { organization: organizationId })
      .map((rows) => toMembers(rows, supabase)),
);

export const revokeInvitation = bsb.action(
  {
    input: v.object({ invitationId: Id }),
    requireTenant: true,
    permission: "members.invite",
  },
  async ({ invitationId }, { tenant: organizationId, db }) => {
    const revoked =
      await db.$blocks.organizations.revokeInvitation(invitationId);

    if (!revoked.ok) {
      return revoked;
    }

    after(() =>
      recordAudit(db, {
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

/**
 * Runs after `useMembers` changed a member's role or removed them from the
 * browser (the organizations module checks and audits the change itself). The
 * member's token still carries the old role until it refreshes.
 */
export const memberChanged = bsb.action(
  {
    input: v.object({ userId: Id }),
    requireTenant: true,
    authorize: async () =>
      can(await getPermissions(), "members.update_role") ||
      can(await getPermissions(), "members.remove"),
  },
  async ({ userId }) => {
    await bsb.evictSession(userId);

    return ok(true);
  },
);

/** Leaves the active organization; the owner has to transfer ownership first. */
export const leaveOrganization = bsb.action(
  { requireTenant: true },
  async (_input, { tenant: organizationId, db }) =>
    db.$blocks.organizations.leave(organizationId),
);

export const declineInvitation = bsb.action(
  { input: v.object({ token: v.pipe(v.string(), v.minLength(8)) }) },
  async ({ token }, { db }) =>
    db.$blocks.organizations.declineInvitation(token),
);

/** Accepts an invitation for the signed-in user and switches to it. */
export const acceptInvitation = bsb.action(
  { input: v.object({ token: v.pipe(v.string(), v.minLength(8)) }) },
  async ({ token }, { db }) => {
    const { organizations } = db.$blocks;
    const preview = await organizations.previewInvitation(token);
    const accepted = await organizations.acceptInvitation(token);

    if (!accepted.ok) {
      return accepted;
    }

    const organizationId = accepted.data.organizationId;

    if (!organizationId) {
      return ok({ organizationId: null, refresh: false });
    }

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
        db,
        v.is(v.string(), name) ? { ...event, targetLabel: name } : event,
      ),
    );

    return organizations.switch(organizationId);
  },
);
