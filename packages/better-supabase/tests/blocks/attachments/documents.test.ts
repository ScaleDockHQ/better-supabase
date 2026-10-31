import { describe, expect, it } from "vitest";

import type { AttachmentStorage } from "../../../src/blocks/attachments/index.ts";

import { createAttachments } from "../../../src/blocks/attachments/index.ts";

const row = (overrides: Record<string, unknown> = {}) => ({
  id: "a1",
  organization_id: "org-1",
  subject_type: "customer",
  subject_id: "c1",
  bucket: "attachments",
  object_path: "org-1/attachments/a1",
  name: "invoice.pdf",
  mime_type: "application/pdf",
  size: "0",
  status: "pending",
  scan_detail: null,
  uploaded_by: null,
  created_at: "2026-10-06T12:00:00Z",
  uploaded_at: null,
  scanned_at: null,
  document_type_id: "t1",
  source: "erp",
  external_id: "F-1",
  storage_status: "pending_upload",
  source_path: "/inv/1.pdf",
  ...overrides,
});

const typeRow = {
  id: "t1",
  organization_id: "org-1",
  key: "invoice",
  name: "Invoice",
  fields: { amount: { type: "amount", required: true } },
  created_at: "2026-10-06T12:00:00Z",
  updated_at: "2026-10-06T12:00:00Z",
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        const reply = results[fn];

        return reply instanceof Error
          ? Promise.reject(reply)
          : Promise.resolve(reply);
      },
    },
  };
}

// SAFETY: these tests never reach Storage.
const storage = {} as AttachmentStorage;

describe("attachment document types", () => {
  it("sends the document type, source, external id and source path", async () => {
    const { transport, calls } = fakeTransport({ create_attachment: row() });

    const attachments = createAttachments({
      transport,
      storage: {
        from: () => ({
          createSignedUploadUrl: () =>
            Promise.resolve({
              data: { signedUrl: "https://s/u", token: "t" },
              error: null,
            }),
        }),
        // SAFETY: only the signed upload URL is used.
      } as unknown as AttachmentStorage,
      tenant: "org-1",
    });

    const upload = await attachments
      .upload(
        { type: "customer", id: "c1" },
        {
          name: "invoice.pdf",
          mimeType: "application/pdf",
          size: 0,
          documentType: "invoice",
          source: "erp",
          externalId: "F-1",
          sourcePath: "/inv/1.pdf",
          metadata: { amount: { amount: 1250, currency: "EUR" } },
        },
      )
      .orThrow();

    expect(calls[0]?.[1]).toMatchObject({
      document_type: "invoice",
      source: "erp",
      external_id: "F-1",
      source_path: "/inv/1.pdf",
    });
    expect(upload.attachment).toMatchObject({
      documentTypeId: "t1",
      source: "erp",
      externalId: "F-1",
      storageStatus: "pending_upload",
      sourcePath: "/inv/1.pdf",
    });
  });

  it("returns a typed error with its hint when the metadata doesn't match", async () => {
    const { transport } = fakeTransport({
      create_attachment: Object.assign(new Error("amount is required"), {
        code: "22023",
        hint: "ATTACHMENT_FIELD_INVALID",
      }),
    });

    const attachments = createAttachments({
      transport,
      storage,
      tenant: "org-1",
    });

    const result = await attachments.upload(null, {
      name: "invoice.pdf",
      mimeType: "application/pdf",
      size: 0,
      documentType: "invoice",
    });

    expect(result.ok ? undefined : result.error.hint).toBe(
      "ATTACHMENT_FIELD_INVALID",
    );
  });

  it("claims a pending record and marks a missing one", async () => {
    const { transport, calls } = fakeTransport({
      claim_attachment_upload: row({ uploaded_by: "u1" }),
      mark_attachment_missing: row({ storage_status: "missing" }),
    });

    const attachments = createAttachments({
      transport,
      storage,
      tenant: "org-1",
    });

    const claimed = await attachments.claim("a1").orThrow();
    const missing = await attachments.markMissing("a1").orThrow();

    expect(claimed.uploadedBy).toBe("u1");
    expect(missing.storageStatus).toBe("missing");
    expect(calls.map(([fn]) => fn)).toEqual([
      "claim_attachment_upload",
      "mark_attachment_missing",
    ]);
  });

  it("defines, lists and removes document types in the tenant", async () => {
    const { transport, calls } = fakeTransport({
      define_attachment_document_type: typeRow,
      list_attachment_document_types: [typeRow],
      delete_attachment_document_type: true,
    });

    const attachments = createAttachments({
      transport,
      storage,
      tenant: "org-1",
    });

    const defined = await attachments.documentTypes
      .define({
        key: "invoice",
        name: "Invoice",
        fields: { amount: { type: "amount", required: true } },
      })
      .orThrow();

    const listed = await attachments.documentTypes.list().orThrow();
    const removed = await attachments.documentTypes.remove("invoice").orThrow();

    expect(defined).toMatchObject({ key: "invoice", organizationId: "org-1" });
    expect(defined.fields["amount"]?.required).toBe(true);
    expect(listed).toHaveLength(1);
    expect(removed).toBe(true);
    expect(calls[0]?.[1]).toEqual({
      tenant: "org-1",
      key: "invoice",
      name: "Invoice",
      fields: { amount: { type: "amount", required: true } },
    });
  });
});
