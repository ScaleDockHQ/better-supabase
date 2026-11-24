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

export const linkContractRelations =
  recordPages.contract.actions.relations.link;

export const unlinkContractRelations =
  recordPages.contract.actions.relations.unlink;

export const removeContractAttachments =
  recordPages.contract.actions.attachments.remove;

// Service and logistics
export const linkWorkOrderRelations =
  recordPages.work_order.actions.relations.link;

export const unlinkWorkOrderRelations =
  recordPages.work_order.actions.relations.unlink;

export const removeWorkOrderAttachments =
  recordPages.work_order.actions.attachments.remove;

export const linkShipmentRelations =
  recordPages.shipment.actions.relations.link;

export const unlinkShipmentRelations =
  recordPages.shipment.actions.relations.unlink;

export const removeShipmentAttachments =
  recordPages.shipment.actions.attachments.remove;

// Support
export const linkCaseRelations = recordPages.case.actions.relations.link;

export const unlinkCaseRelations = recordPages.case.actions.relations.unlink;

export const removeCaseAttachments =
  recordPages.case.actions.attachments.remove;

export const linkContentEntryRelations =
  recordPages.content_entry.actions.relations.link;

export const unlinkContentEntryRelations =
  recordPages.content_entry.actions.relations.unlink;

export const removeContentEntryAttachments =
  recordPages.content_entry.actions.attachments.remove;

export const linkMeetingRelations = recordPages.meeting.actions.relations.link;

export const unlinkMeetingRelations =
  recordPages.meeting.actions.relations.unlink;

export const removeMeetingAttachments =
  recordPages.meeting.actions.attachments.remove;

export const linkCarePlanRelations =
  recordPages.care_plan.actions.relations.link;

export const unlinkCarePlanRelations =
  recordPages.care_plan.actions.relations.unlink;

export const removeCarePlanAttachments =
  recordPages.care_plan.actions.attachments.remove;

export const linkRiskRelations = recordPages.risk.actions.relations.link;

export const unlinkRiskRelations = recordPages.risk.actions.relations.unlink;

export const removeRiskAttachments =
  recordPages.risk.actions.attachments.remove;

export const linkVulnerabilityRelations =
  recordPages.vulnerability.actions.relations.link;

export const unlinkVulnerabilityRelations =
  recordPages.vulnerability.actions.relations.unlink;

export const removeVulnerabilityAttachments =
  recordPages.vulnerability.actions.attachments.remove;

// People

export const linkEmployeeRelations =
  recordPages.employee.actions.relations.link;

export const unlinkEmployeeRelations =
  recordPages.employee.actions.relations.unlink;

export const removeEmployeeAttachments =
  recordPages.employee.actions.attachments.remove;

export const linkApplicationRelations =
  recordPages.application.actions.relations.link;

export const unlinkApplicationRelations =
  recordPages.application.actions.relations.unlink;

export const removeApplicationAttachments =
  recordPages.application.actions.attachments.remove;

export const linkCourseRelations = recordPages.course.actions.relations.link;

export const unlinkCourseRelations =
  recordPages.course.actions.relations.unlink;

export const removeCourseAttachments =
  recordPages.course.actions.attachments.remove;

export const linkOrderRelations = recordPages.order.actions.relations.link;

export const unlinkOrderRelations = recordPages.order.actions.relations.unlink;

export const removeOrderAttachments =
  recordPages.order.actions.attachments.remove;

export const linkInvoiceRelations = recordPages.invoice.actions.relations.link;

export const unlinkInvoiceRelations =
  recordPages.invoice.actions.relations.unlink;

export const removeInvoiceAttachments =
  recordPages.invoice.actions.attachments.remove;

export const linkProductionOrderRelations =
  recordPages.production_order.actions.relations.link;

export const unlinkProductionOrderRelations =
  recordPages.production_order.actions.relations.unlink;

export const removeProductionOrderAttachments =
  recordPages.production_order.actions.attachments.remove;

export const linkInspectionRelations =
  recordPages.inspection.actions.relations.link;

export const unlinkInspectionRelations =
  recordPages.inspection.actions.relations.unlink;

export const removeInspectionAttachments =
  recordPages.inspection.actions.attachments.remove;

export const linkProductRelations = recordPages.product.actions.relations.link;

export const unlinkProductRelations =
  recordPages.product.actions.relations.unlink;

export const removeProductAttachments =
  recordPages.product.actions.attachments.remove;

export const linkTillRelations = recordPages.till.actions.relations.link;

export const unlinkTillRelations = recordPages.till.actions.relations.unlink;

export const removeTillAttachments =
  recordPages.till.actions.attachments.remove;
