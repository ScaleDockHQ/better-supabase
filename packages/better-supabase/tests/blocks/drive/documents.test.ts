import { describe, expect, it } from "vitest";

import { createAttachments } from "../../../src/blocks/attachments/attachments.ts";
import { createDrive } from "../../../src/blocks/drive/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: unknown) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const DOCUMENT = {
  number: "DOC-00001",
  type: "sop",
  status: "effective",
  ownerId: "u1",
  effectiveVersionId: "v1",
  effectiveVersion: 1,
  effectiveAttachmentId: "a1",
  effectiveFrom: "2026-10-01T00:00:00Z",
  reviewIntervalMonths: 12,
  nextReviewOn: "2027-10-01",
  reviewDue: false,
  effectiveOnly: false,
};

const NODE = {
  id: "n1",
  organizationId: "o",
  parentId: null,
  kind: "file",
  name: "Cleaning.pdf",
  createdAt: "2026-10-01T00:00:00Z",
  attachmentId: "a2",
  document: DOCUMENT,
};

const ATTACHMENT = {
  organization_id: "o",
  subject_type: "drive_node",
  subject_id: "n1",
  bucket: "attachments",
  name: "Cleaning.pdf",
  mime_type: "application/pdf",
  size: 12,
  status: "clean",
  scan_detail: null,
  metadata: {},
  uploaded_by: "u1",
  created_at: "2026-10-01T00:00:00Z",
  uploaded_at: "2026-10-01T00:00:00Z",
  scanned_at: null,
};

const storage = {
  from: () => ({
    createSignedUploadUrl: () =>
      Promise.resolve({ data: { signedUrl: "u", token: "t" }, error: null }),
    createSignedUrl: (path: string) =>
      Promise.resolve({
        data: { signedUrl: `https://down/${path}` },
        error: null,
      }),
    download: () => Promise.resolve({ data: new Blob(["x"]), error: null }),
    remove: () => Promise.resolve({ data: [], error: null }),
  }),
};

describe("drive documents", () => {
  it("parses a node's document and calls the document functions", async () => {
    const fake = transport({
      drive_document_save: () => ({
        ...NODE,
        document: {
          ...DOCUMENT,
          status: "draft",
          effectiveVersionId: null,
          effectiveVersion: null,
          effectiveAttachmentId: null,
          effectiveFrom: null,
          nextReviewOn: null,
        },
      }),
      drive_document_submit: () => ({
        ...NODE,
        document: { ...DOCUMENT, status: "in_review" },
      }),
      drive_document_release: () => NODE,
      drive_document_obsolete: () => ({
        ...NODE,
        document: { ...DOCUMENT, status: "obsolete" },
      }),
      drive_document_review: () => NODE,
      drive_documents: () => [NODE, { ...NODE, id: "n2", document: null }],
      notify_due_drive_reviews: () => 2,
    });

    const drive = createDrive({ transport: fake });

    const saved = await drive
      .saveDocument({
        id: "n1",
        document: { type: "sop", ownerId: "u1", reviewIntervalMonths: 6 },
      })
      .orThrow();

    expect(saved.document?.status).toBe("draft");
    expect(saved.document?.effectiveVersionId).toBeUndefined();
    expect(saved.document?.nextReviewOn).toBeUndefined();

    await drive.saveDocument({ id: "n1", document: { type: "sop" } }).orThrow();

    const submitted = await drive
      .submitDocument({ id: "n1", attachmentId: "a2", reason: "Annual update" })
      .orThrow();

    expect(submitted.document?.status).toBe("in_review");
    await drive.submitDocument({ id: "n1" }).orThrow();

    const released = await drive
      .releaseDocument({ id: "n1", attachmentId: "a2" })
      .orThrow();

    expect(released.document?.effectiveFrom?.toString()).toBe(
      "2026-10-01T00:00:00Z",
    );
    expect(released.document?.nextReviewOn?.toString()).toBe("2027-10-01");
    expect(released.document?.effectiveVersion).toBe(1);

    const obsolete = await drive
      .obsoleteDocument({ id: "n1", reason: "Replaced" })
      .orThrow();

    expect(obsolete.document?.status).toBe("obsolete");

    await drive
      .reviewDocument({ id: "n1", outcome: "unchanged", note: "Still right" })
      .orThrow();
    await drive.reviewDocument({ id: "n1", outcome: "revise" }).orThrow();

    const register = await drive
      .documents({
        organizationId: "o",
        filters: { status: "effective", reviewDue: true },
      })
      .orThrow();

    expect(register.map((node) => node.document?.number)).toEqual([
      "DOC-00001",
      undefined,
    ]);

    await drive.documents({ organizationId: "o" }).orThrow();
    expect(await drive.notifyDueReviews().orThrow()).toBe(2);

    expect(fake.calls).toEqual([
      [
        "drive_document_save",
        {
          node: "n1",
          document_type: "sop",
          owner_id: "u1",
          review_interval_months: 6,
        },
      ],
      [
        "drive_document_save",
        {
          node: "n1",
          document_type: "sop",
          owner_id: null,
          review_interval_months: null,
        },
      ],
      [
        "drive_document_submit",
        { node: "n1", attachment: "a2", reason: "Annual update" },
      ],
      ["drive_document_submit", { node: "n1", attachment: null, reason: null }],
      ["drive_document_release", { node: "n1", attachment: "a2" }],
      ["drive_document_obsolete", { node: "n1", reason: "Replaced" }],
      [
        "drive_document_review",
        { node: "n1", outcome: "unchanged", note: "Still right" },
      ],
      ["drive_document_review", { node: "n1", outcome: "revise", note: null }],
      [
        "drive_documents",
        { tenant: "o", filters: { status: "effective", reviewDue: true } },
      ],
      ["drive_documents", { tenant: "o", filters: {} }],
      ["notify_due_drive_reviews", {}],
    ]);
  });

  it("downloads the effective version for a reader below the write role", async () => {
    const download = async (document: Record<string, unknown>) => {
      const fake = transport({
        drive_get: () => ({ ...NODE, document }),
        get_attachment: (args) => ({
          ...ATTACHMENT,
          id: (args as { id: string }).id,
          object_path: `o/attachments/${(args as { id: string }).id}`,
        }),
      });

      const drive = createDrive({
        transport: fake,
        storage,
        attachments: createAttachments({ transport: fake, storage }),
      });

      return (await drive.download({ id: "n1" }).orThrow()).signedUrl;
    };

    expect(await download({ ...DOCUMENT, effectiveOnly: true })).toBe(
      "https://down/o/attachments/a1",
    );
    expect(await download(DOCUMENT)).toBe("https://down/o/attachments/a2");
    expect(
      await download({
        ...DOCUMENT,
        effectiveOnly: true,
        effectiveAttachmentId: null,
      }),
    ).toBe("https://down/o/attachments/a2");
  });
});
