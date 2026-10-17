import { describe, expect, it } from "vitest";

import { createSignatures } from "../../../src/blocks/forms/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      expect(schema).toBe("better_supabase");
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const AT = "2026-10-01T00:00:00Z";

const REQUEST = {
  id: "r1",
  organizationId: "o",
  subjectType: "contract",
  subjectId: "c1",
  versionId: "v1",
  contentHash: "abc",
  signers: ["u1", "u2"],
  order: "sequential",
  status: "pending",
  approvalRequestId: "a1",
  message: "Please sign",
  requestedBy: "u0",
  createdAt: AT,
  completedAt: null,
};

const SIGNATURE = {
  id: "s1",
  requestId: "r1",
  signer: "u1",
  method: "typed",
  typedName: "Ada",
  imageAttachmentId: null,
  signedHash: "f".repeat(64),
  ip: "203.0.113.7",
  userAgent: "test",
  signedAt: AT,
};

describe("signatures client", () => {
  it("requests, signs, declines, cancels, reads and lists", async () => {
    const fake = transport({
      create_signature_request: () => REQUEST,
      sign_signature: () => ({ ...SIGNATURE, requestStatus: "pending" }),
      decline_signature_request: () => ({ ...REQUEST, status: "declined" }),
      cancel_signature_request: () => ({
        ...REQUEST,
        status: "cancelled",
        completedAt: AT,
      }),
      get_signature_request: () => ({
        ...REQUEST,
        signatures: [SIGNATURE],
        verification: {
          valid: true,
          contentMatches: true,
          changedSince: false,
          latestVersionId: "v1",
          signatures: [{ id: "s1", signer: "u1", valid: true }],
        },
      }),
      list_signature_requests: () => [REQUEST],
    });

    const signatures = createSignatures({ transport: fake });

    const subject = {
      organizationId: "o",
      subjectType: "contract",
      subjectId: "c1",
    };

    const request = await signatures
      .request({ ...subject, signers: ["u1", "u2"] })
      .orThrow();

    expect(request).toMatchObject({
      id: "r1",
      order: "sequential",
      signers: ["u1", "u2"],
      approvalRequestId: "a1",
    });
    expect(request.completedAt).toBeUndefined();
    await signatures
      .request({
        ...subject,
        signers: ["u1"],
        versionId: "v1",
        order: "sequential",
        approvalRequestId: "a1",
        message: "Sign",
      })
      .orThrow();

    const signed = await signatures
      .sign("r1", { method: "typed", typedName: "Ada" })
      .orThrow();

    expect(signed).toMatchObject({
      method: "typed",
      typedName: "Ada",
      requestStatus: "pending",
    });
    expect(signed.imageAttachmentId).toBeUndefined();
    await signatures.sign("r1", { method: "drawn", imageAttachmentId: "i1" });
    await signatures.sign("r1", { method: "click" });

    expect((await signatures.decline("r1").orThrow()).status).toBe("declined");
    await signatures.decline("r1", "Wrong terms");
    const cancelled = await signatures.cancel("r1").orThrow();
    expect(cancelled.completedAt?.toString()).toBe(AT);

    const detail = await signatures.get("r1").orThrow();
    expect(detail.signatures).toHaveLength(1);
    expect(detail.verification).toEqual({
      valid: true,
      contentMatches: true,
      changedSince: false,
      latestVersionId: "v1",
      signatures: [{ id: "s1", signer: "u1", valid: true }],
    });

    expect(await signatures.list("o").orThrow()).toHaveLength(1);
    await signatures.list("o", {
      subjectType: "contract",
      subjectId: "c1",
      status: "pending",
      mine: true,
      pageSize: 10,
      before: Temporal.Instant.from(AT),
    });

    expect(fake.calls.map(([fn, args]) => [fn, args])).toEqual([
      [
        "create_signature_request",
        {
          tenant: "o",
          subject_type: "contract",
          subject_id: "c1",
          signers: ["u1", "u2"],
          version_id: null,
          sign_order: "parallel",
          approval_request_id: null,
          message: null,
        },
      ],
      [
        "create_signature_request",
        {
          tenant: "o",
          subject_type: "contract",
          subject_id: "c1",
          signers: ["u1"],
          version_id: "v1",
          sign_order: "sequential",
          approval_request_id: "a1",
          message: "Sign",
        },
      ],
      [
        "sign_signature",
        {
          request_id: "r1",
          method: "typed",
          typed_name: "Ada",
          image_attachment_id: null,
        },
      ],
      [
        "sign_signature",
        {
          request_id: "r1",
          method: "drawn",
          typed_name: null,
          image_attachment_id: "i1",
        },
      ],
      [
        "sign_signature",
        {
          request_id: "r1",
          method: "click",
          typed_name: null,
          image_attachment_id: null,
        },
      ],
      ["decline_signature_request", { request_id: "r1", reason: null }],
      [
        "decline_signature_request",
        { request_id: "r1", reason: "Wrong terms" },
      ],
      ["cancel_signature_request", { request_id: "r1" }],
      ["get_signature_request", { request_id: "r1" }],
      [
        "list_signature_requests",
        {
          tenant: "o",
          subject_type: null,
          subject_id: null,
          status: null,
          mine: false,
          page_size: null,
          before: null,
        },
      ],
      [
        "list_signature_requests",
        {
          tenant: "o",
          subject_type: "contract",
          subject_id: "c1",
          status: "pending",
          mine: true,
          page_size: 10,
          before: AT,
        },
      ],
    ]);
  });

  it("reads a verification with missing parts as failing", async () => {
    const signatures = createSignatures({
      transport: transport({
        get_signature_request: () => ({
          ...REQUEST,
          signers: null,
          signatures: [],
          verification: { signatures: [] },
        }),
      }),
    });

    const detail = await signatures.get("r1").orThrow();
    expect(detail.signers).toEqual([]);
    expect(detail.verification).toEqual({
      valid: false,
      contentMatches: false,
      changedSince: false,
      signatures: [],
    });
  });

  it("returns a typed error for an unknown status", async () => {
    const signatures = createSignatures({
      transport: transport({
        get_signature_request: () => ({ ...REQUEST, status: "lost" }),
      }),
    });

    expect((await signatures.get("r1")).ok).toBe(false);
  });
});
