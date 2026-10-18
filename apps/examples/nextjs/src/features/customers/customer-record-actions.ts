"use server";

import type { JsonPatchOperation } from "better-supabase/blocks/versions";

import { type Result, dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

import { customerAttachments } from "./customer-attachments";

const Id = v.pipe(v.string(), v.uuid());
const SUBJECT = "customer";

/** Reads the customer page again, for the cards' Retry buttons. */
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryCustomerRecord(): Promise<void> {
  refresh();
}

// #region share links

const SHARE_EXPIRY_DAYS = [1, 7, 30, 0] as const;

/**
 * Creates a view link to the customer. The token comes back once, so the
 * dialog shows it and nothing stores it.
 */
export const createShareLink = bs.action(
  {
    input: v.object({
      customerId: Id,
      /** 0 creates a link without an expiry. */
      expiresInDays: v.picklist(SHARE_EXPIRY_DAYS),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "share_links.create"),
  },
  async (
    { customerId, expiresInDays },
    { tenant: organizationId, supabase, auth },
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

    const created = await blocks(supabase).shareLinks.create(
      organizationId,
      SUBJECT,
      customerId,
      options,
    );

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok({ token: created.data.token });
  },
);

export const revokeShareLink = bs.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "share_links.create"),
  },
  async ({ id }, { supabase, auth }) => {
    const revoked = await blocks(supabase).shareLinks.revoke(id);

    if (!revoked.ok) {
      return revoked;
    }

    refreshCaller(auth);

    return ok(null);
  },
);

// #endregion share links

// #region attachments

const MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024;

/**
 * Records a pending file and returns a one-time upload token; the browser
 * sends the bytes with `uploadToSignedUrl`, then calls `confirmAttachment`.
 */
export const startAttachmentUpload = bs.action(
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
    requireTenant: true,
    authorize: (session) => can(session, "attachments.upload"),
  },
  async (
    { customerId, name, mimeType, size },
    { tenant: organizationId, supabase },
  ) => {
    const upload = await customerAttachments(supabase).upload({
      organizationId,
      name,
      mimeType: mimeType === "" ? "application/octet-stream" : mimeType,
      size,
      subjectType: SUBJECT,
      subjectId: customerId,
    });

    if (!upload.ok) {
      return upload;
    }

    const { attachment, token } = upload.data;

    return ok({
      id: attachment.id,
      bucket: attachment.bucket,
      path: attachment.path,
      token,
    });
  },
);

export const confirmAttachment = bs.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "attachments.upload"),
  },
  async ({ id }, { supabase, auth }) => {
    const confirmed = await customerAttachments(supabase).confirm(id);

    refreshCaller(auth);

    return confirmed.ok ? ok(null) : confirmed;
  },
);

/** A short-lived download URL; refused until the file was scanned clean. */
export const downloadAttachment = bs.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "attachments.read"),
  },
  async ({ id }, { supabase }) =>
    customerAttachments(supabase)
      .download(id, { as: "download" })
      .map((download) => ({ signedUrl: download.signedUrl })),
);

export const removeAttachment = bs.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "attachments.manage"),
  },
  async ({ id }, { supabase, auth }) => {
    const removed = await customerAttachments(supabase).remove(id);

    if (!removed.ok) {
      return removed;
    }

    refreshCaller(auth);

    return ok(null);
  },
);

// #endregion attachments

// #region relations

const RELATED_KIND = "relates";

export const linkCustomer = bs.action(
  {
    input: v.object({ customerId: Id, targetId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "relations.manage"),
  },
  async (
    { customerId, targetId },
    { tenant: organizationId, supabase, auth },
  ) => {
    if (customerId === targetId) {
      return err(dbError("invalid_input", "A customer can't link to itself"));
    }

    const linked = await blocks(supabase).relations.link({
      organizationId,
      kind: RELATED_KIND,
      source: { type: SUBJECT, id: customerId },
      target: { type: SUBJECT, id: targetId },
    });

    if (!linked.ok) {
      return linked;
    }

    refreshCaller(auth);

    return ok(null);
  },
);

/** Removes a link as the customer sees it: `kind` may be an inverse name. */
export const unlinkCustomer = bs.action(
  {
    input: v.object({
      customerId: Id,
      kind: v.pipe(v.string(), v.minLength(1)),
      subjectType: v.pipe(v.string(), v.minLength(1)),
      subjectId: v.pipe(v.string(), v.minLength(1)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "relations.manage"),
  },
  async (
    { customerId, kind, subjectType, subjectId },
    { tenant: organizationId, supabase, auth },
  ) => {
    const unlinked = await blocks(supabase).relations.unlink({
      organizationId,
      kind,
      source: { type: SUBJECT, id: customerId },
      target: { type: subjectType, id: subjectId },
    });

    if (!unlinked.ok) {
      return unlinked;
    }

    refreshCaller(auth);

    return ok(null);
  },
);

// #endregion relations

// #region versions

export const saveCustomerVersion = bs.action(
  {
    input: v.object({ customerId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "versions.create"),
  },
  async ({ customerId }, { tenant: organizationId, supabase, auth }) => {
    // Without content the block copies the customer's configured columns.
    const saved = await blocks(supabase).versions.snapshot({
      organizationId,
      subjectType: SUBJECT,
      subjectId: customerId,
    });

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok(null);
  },
);

/**
 * Keeps the current details as a version, then writes the chosen version's
 * `name` and `kvk` back to the customer (`versions.restore`).
 */
export const restoreCustomerVersion = bs.action(
  {
    input: v.object({ customerId: Id, versionId: Id }),
    requireTenant: true,
    authorize: (session) =>
      can(session, "versions.restore") && can(session, "customers.write"),
  },
  async (
    { customerId, versionId },
    { tenant: organizationId, supabase, auth },
  ) => {
    const { versions } = blocks(supabase);
    const version = await versions.get(versionId);

    if (!version.ok) {
      return version;
    }

    if (version.data.subjectId !== customerId) {
      return err(
        dbError("not_found", "This version belongs to another record"),
      );
    }

    // Unchanged details return the latest version instead of a new one.
    const kept = await versions.snapshot({
      organizationId,
      subjectType: SUBJECT,
      subjectId: customerId,
    });

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
export const compareCustomerVersions = bs.action(
  {
    input: v.object({ fromId: Id, toId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "versions.read"),
  },
  async (
    { fromId, toId },
    { supabase },
  ): Promise<Result<readonly JsonPatchOperation[]>> =>
    blocks(supabase).versions.diff(fromId, toId),
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
 * Starts the customer's SLA clocks. With no policy for customers, a caller
 * who may manage policies gets the default one first.
 */
export const startCustomerSla = bs.action(
  {
    input: v.object({ customerId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "sla.read"),
  },
  async (
    { customerId },
    { tenant: organizationId, supabase, session, auth },
  ) => {
    const { sla } = blocks(supabase);
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

    const policy = await sla.savePolicy(
      organizationId,
      DEFAULT_CUSTOMER_POLICY,
    );

    if (!policy.ok) {
      return policy;
    }

    const restarted = await sla.start(subject);

    refreshCaller(auth);

    return restarted.ok ? ok(restarted.data.length) : restarted;
  },
);

// #endregion sla
