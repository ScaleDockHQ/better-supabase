"use server";

import type { Result } from "better-supabase";
import type { JsonPatchOperation } from "better-supabase/blocks/versions";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { customerAttachments } from "./customer-attachments";
import { customerPage } from "./customer-record";

const Id = v.pipe(v.string(), v.uuid());
const SUBJECT = "customer";

/** Reads the customer page again, for the cards' Retry buttons. */
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryCustomerRecord(): Promise<void> {
  refresh();
}

export const linkCustomerRelations = customerPage.actions.relations.link;

export const unlinkCustomerRelations = customerPage.actions.relations.unlink;

export const revokeCustomerShareLinks = customerPage.actions.shareLinks.revoke;

export const removeCustomerAttachments =
  customerPage.actions.attachments.remove;

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
    requireOrganization: true,
    authorize: (session) => can(session, "share_links.create"),
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
      .shareLinks.create({ type: SUBJECT, id: customerId }, options);

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok({ token: created.data.token });
  },
);

// #endregion share links

// #region attachments

const MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024;

/**
 * Records a pending file and returns its signed upload URL for
 * `useAttachmentUpload`, which sends the bytes and calls `confirmAttachment`.
 */
export const startAttachmentUpload = bsb.action(
  {
    input: v.object({
      customerId: Id,
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(255)),
      mimeType: v.pipe(v.string(), v.maxLength(255)),
      size: v.pipe(
        v.number(),
        v.integer(),
        v.minValue(1),
        v.maxValue(MAX_ATTACHMENT_BYTES),
      ),
    }),
    requireOrganization: true,
    authorize: (session) => can(session, "attachments.upload"),
  },
  async (
    { customerId, name, mimeType, size },
    { tenant: organizationId, supabase },
  ) => {
    const upload = await customerAttachments(supabase, organizationId).upload(
      { type: SUBJECT, id: customerId },
      {
        name,
        mimeType: mimeType === "" ? "application/octet-stream" : mimeType,
        size,
      },
    );

    if (!upload.ok) {
      return upload;
    }

    return ok({
      id: upload.data.attachment.id,
      signedUrl: upload.data.signedUrl,
    });
  },
);

export const confirmAttachment = bsb.action(
  {
    input: v.object({ id: Id }),
    requireOrganization: true,
    authorize: (session) => can(session, "attachments.upload"),
  },
  async ({ id }, { supabase, auth }) => {
    const confirmed = await customerAttachments(supabase).confirm(id);

    refreshCaller(auth);

    return confirmed.ok ? ok(null) : confirmed;
  },
);

/** A short-lived download URL; refused until the file was scanned clean. */
export const downloadAttachment = bsb.action(
  {
    input: v.object({ id: Id }),
    requireOrganization: true,
    authorize: (session) => can(session, "attachments.read"),
  },
  async ({ id }, { supabase }) =>
    customerAttachments(supabase)
      .download(id, { as: "download" })
      .map((download) => ({ signedUrl: download.signedUrl })),
);

/** Removes a file; the customer's attachments section reads again. */
// #endregion attachments

// #region versions

/**
 * Keeps the current details as a version, then writes the chosen version's
 * `name` and `kvk` back to the customer (`versions.restore`).
 */
export const restoreCustomerVersion = bsb.action(
  {
    input: v.object({ customerId: Id, versionId: Id }),
    requireOrganization: true,
    authorize: (session) =>
      can(session, "versions.restore") && can(session, "customers.write"),
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
    const kept = await versions.snapshot({ type: SUBJECT, id: customerId });

    if (!kept.ok) {
      return kept;
    }

    const restored = await versions.restore(versionId);

    if (!restored.ok) {
      return restored;
    }

    refreshCaller(auth);

    return ok(null);
  },
);

/** The changes from one version to a later one, as JSON Patch operations. */
export const compareCustomerVersions = bsb.action(
  {
    input: v.object({ fromId: Id, toId: Id }),
    requireOrganization: true,
    authorize: (session) => can(session, "versions.read"),
  },
  async (
    { fromId, toId },
    { db },
  ): Promise<Result<readonly JsonPatchOperation[]>> =>
    db.versions.diff(fromId, toId),
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
    requireOrganization: true,
    authorize: (session) => can(session, "sla.read"),
  },
  async ({ customerId }, { tenant: organizationId, db, session, auth }) => {
    const { sla } = db.$with({ tenant: organizationId });
    const subject = { type: SUBJECT, id: customerId };
    const started = await sla.start(subject);

    if (!started.ok || started.data.length > 0) {
      refreshCaller(auth);

      return started.ok ? ok(started.data.length) : started;
    }

    if (!can(session, "sla.manage")) {
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

    const restarted = await sla.start(subject);

    refreshCaller(auth);

    return restarted.ok ? ok(restarted.data.length) : restarted;
  },
);

// #endregion sla
