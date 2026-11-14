"use server";

import type { Result } from "better-supabase";
import type { JsonPatchOperation } from "better-supabase/blocks/versions";

import { fromBetterResult, dbError, err, ok } from "better-supabase";
import { withBetterResult } from "better-supabase/better-result";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { CRM_TAG } from "@/features/crm/crm-cache";
import { DRIVE_TAG } from "@/features/drive/drive-cache";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { appErrors } from "@/lib/app-error";
import { logos } from "@/lib/buckets";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { customerPage } from "./customer-record";
import { CUSTOMERS_TAG } from "./customers-cache";

const Id = v.pipe(v.string(), v.uuid());

/**
 * Hands the customer to a team from the teams block, or to nobody. The
 * `customers_owner_team_check` trigger refuses a team from another organization
 * with `foreign_key_violation`.
 */
export const setCustomerOwnerTeam = bsb.action(
  {
    input: v.object({ customerId: Id, teamId: v.nullable(Id) }),
    requireTenant: true,
    permission: "customers.write",
  },
  async ({ customerId, teamId }, { db }) =>
    db.customers.update(
      customerId,
      { ownerTeamId: teamId },
      { select: ["id", "ownerTeamId"] },
    ),
);

/**
 * Uploads a new logo, points the row at its path, then removes the old one. The
 * row keeps the path; URLs are built when rendering.
 */
export const uploadCustomerLogo = bsb.action(
  {
    input: v.object({
      customerId: Id,
      logo: v.pipe(
        v.instance(File),
        v.check((file) => file.size > 0, "Pick a file"),
      ),
    }),
    requireTenant: true,
    permission: "customers.write",
  },
  async ({ customerId, logo }, { tenant: organizationId, db, supabase }) => {
    // A better-result value with an AppError, converted back for the action.
    const customer = await withBetterResult(db, appErrors).customers.get(
      customerId,
      { select: ["id", "logoPath"] },
    );

    if (customer.isErr()) {
      return fromBetterResult(customer);
    }

    return logos
      .connect(supabase)
      .replace(
        { organizationId, customerId, version: crypto.randomUUID() },
        logo,
        {
          contentType: logo.type,
          previous: customer.value.logoPath,
          commit: (path) => db.customers.update(customerId, { logoPath: path }),
        },
      );
  },
);

const SUBJECT = "customer";

export const revokeCustomerShareLinks = customerPage.actions.shareLinks.revoke;

export const snapshotCustomerVersions = customerPage.actions.versions.snapshot;

// #region share links

const SHARE_EXPIRY_DAYS = [1, 7, 30, 0] as const;

/**
 * Creates a view link to the customer. The token comes back once, so the dialog
 * shows it and nothing stores it.
 */
export const createShareLink = bsb.action(
  {
    input: v.object({
      customerId: Id,
      /** 0 creates a link without an expiry. */
      expiresInDays: v.picklist(SHARE_EXPIRY_DAYS),
    }),
    requireTenant: true,
    permission: "share_links.create",
  },
  async (
    { customerId, expiresInDays },
    { tenant: organizationId, db, auth },
  ) => {
    const options =
      expiresInDays === 0
        ? { role: "view" }
        : {
            role: "view",
            expiresAt: Temporal.Now.instant().add({
              hours: expiresInDays * 24,
            }),
          };

    const created = await db
      .$with({ tenant: organizationId })
      .shareLinks.create({
        subject: { type: SUBJECT, id: customerId },
        options,
      });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, [CUSTOMERS_TAG, CRM_TAG, DRIVE_TAG]);

    return ok({ token: created.data.token });
  },
);

// #endregion share links

// #region versions

/**
 * Keeps the current details as a version, then writes the chosen version's
 * `name` and `kvk` back to the customer (`versions.restore`).
 */
export const restoreCustomerVersion = bsb.action(
  {
    input: v.object({ customerId: Id, versionId: Id }),
    requireTenant: true,
    permission: "versions.restore",
    authorize: async () => can(await getPermissions(), "customers.write"),
  },
  async ({ customerId, versionId }, { tenant: organizationId, db, auth }) => {
    const { versions } = db.$with({ tenant: organizationId });
    const version = await versions.get(versionId);

    if (!version.ok) {
      return version;
    }

    if (
      version.data.subject.type !== SUBJECT ||
      version.data.subject.id !== customerId
    ) {
      return err(
        dbError("not_found", "This version belongs to another record"),
      );
    }

    // Unchanged details return the latest version instead of a new one.
    const kept = await versions.snapshot({
      subject: { type: SUBJECT, id: customerId },
    });

    if (!kept.ok) {
      return kept;
    }

    const restored = await versions.restore(versionId);

    if (!restored.ok) {
      return restored;
    }

    await refreshCaller(auth, [CUSTOMERS_TAG, CRM_TAG, DRIVE_TAG]);

    return ok(null);
  },
);

/** The changes from one version to a later one, as JSON Patch operations. */
export const compareCustomerVersions = bsb.action(
  {
    input: v.object({ fromId: Id, toId: Id }),
    requireTenant: true,
    permission: "versions.read",
  },
  async (
    { fromId, toId },
    { db },
  ): Promise<Result<readonly JsonPatchOperation[]>> =>
    db.versions.diff({ fromId, toId }),
);

// #endregion versions

// #region sla

/** The policy `startCustomerSla` creates when none covers customers yet. */
const DEFAULT_CUSTOMER_POLICY = {
  subjectType: SUBJECT,
  name: "Customer default",
  firstResponseMinutes: 4 * 60,
  resolutionMinutes: 3 * 24 * 60,
} as const;

/**
 * Starts the customer's SLA clocks. With no policy for customers, a caller who
 * may manage policies gets the default one first.
 */
export const startCustomerSla = bsb.action(
  {
    input: v.object({ customerId: Id }),
    requireTenant: true,
    permission: "sla.read",
  },
  async ({ customerId }, { tenant: organizationId, db, auth }) => {
    const { sla } = db.$with({ tenant: organizationId });
    const subject = { type: SUBJECT, id: customerId };
    const started = await sla.start({ subject });

    if (!started.ok || started.data.length > 0) {
      await refreshCaller(auth, [CUSTOMERS_TAG, CRM_TAG, DRIVE_TAG]);

      return started.ok ? ok(started.data.length) : started;
    }

    if (!can(await getPermissions(), "sla.manage")) {
      return err(
        dbError(
          "forbidden",
          "No SLA policy covers customers, and creating one needs the sla.manage permission",
        ),
      );
    }

    const policy = await sla.savePolicy(DEFAULT_CUSTOMER_POLICY);

    if (!policy.ok) {
      return policy;
    }

    const restarted = await sla.start({ subject });

    await refreshCaller(auth, [CUSTOMERS_TAG, CRM_TAG, DRIVE_TAG]);

    return restarted.ok ? ok(restarted.data.length) : restarted;
  },
);

// #endregion sla
