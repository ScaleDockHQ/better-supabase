"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { CRM_TAG } from "@/features/crm/crm-cache";
import { CUSTOMERS_TAG } from "@/features/customers/customers-cache";
import { DRIVE_TAG } from "@/features/drive/drive-cache";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { recordAttachments } from "./record-attachments";
import { recordPages } from "./record-pages";
import { RECORD_TYPES } from "./record-subject";

const Id = v.pipe(v.string(), v.uuid());

const MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024;

const Subject = v.object({ type: v.picklist(RECORD_TYPES), id: Id });

/** Reads the record page again, for the cards' Retry buttons. */
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryRecord(): Promise<void> {
  refresh();
}

/**
 * Records a pending file and returns its signed upload URL for
 * `useAttachmentUpload`, which sends the bytes and calls `confirmAttachment`.
 */
export const startAttachmentUpload = bsb.action(
  {
    input: v.object({
      subject: Subject,
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
    permission: "attachments.upload",
  },
  async (
    { subject, name, mimeType, size },
    { tenant: organizationId, supabase },
  ) => {
    const upload = await recordAttachments(supabase, organizationId).upload({
      subject,
      attachment: {
        name,
        mimeType: mimeType === "" ? "application/octet-stream" : mimeType,
        size,
      },
    });

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
    requireTenant: true,
    permission: "attachments.upload",
  },
  async ({ id }, { supabase, auth }) => {
    const confirmed = await recordAttachments(supabase).confirm(id);

    await refreshCaller(auth, [CUSTOMERS_TAG, CRM_TAG, DRIVE_TAG]);

    return confirmed.ok ? ok(null) : confirmed;
  },
);

/** A short-lived download URL; refused until the file was scanned clean. */
export const downloadAttachment = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "attachments.read",
  },
  async ({ id }, { supabase }) =>
    recordAttachments(supabase)
      .download({ id, options: { as: "download" } })
      .map((download) => ({ signedUrl: download.signedUrl })),
);

// One export per record type and write: a Server Action is a module export,
// and the bindings' writes are bound to a record type.
export const linkCustomerRelations =
  recordPages.customer.actions.relations.link;

export const unlinkCustomerRelations =
  recordPages.customer.actions.relations.unlink;

export const removeCustomerAttachments =
  recordPages.customer.actions.attachments.remove;

export const linkCompanyRelations = recordPages.company.actions.relations.link;

export const unlinkCompanyRelations =
  recordPages.company.actions.relations.unlink;

export const removeCompanyAttachments =
  recordPages.company.actions.attachments.remove;

export const linkPersonRelations = recordPages.person.actions.relations.link;

export const unlinkPersonRelations =
  recordPages.person.actions.relations.unlink;

export const removePersonAttachments =
  recordPages.person.actions.attachments.remove;

export const linkDealRelations = recordPages.deal.actions.relations.link;
export const unlinkDealRelations = recordPages.deal.actions.relations.unlink;

export const removeDealAttachments =
  recordPages.deal.actions.attachments.remove;
