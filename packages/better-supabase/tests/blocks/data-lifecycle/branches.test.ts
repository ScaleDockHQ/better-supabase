import { describe, expect, it } from "vitest";

import type { LifecycleStorage } from "../../../src/blocks/data-lifecycle/index.ts";

import { createDataLifecycle } from "../../../src/blocks/data-lifecycle/index.ts";

type Answer = (args: Record<string, unknown>) => unknown;

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

        const result = results[fn];

        const value =
          typeof result === "function"
            ? (result as Answer)({ ...args })
            : result;

        return value instanceof Error
          ? Promise.reject(value)
          : Promise.resolve(value);
      },
    },
  };
}

const exportRow = (overrides: Record<string, unknown> = {}) => ({
  id: "x1",
  subject: "weird",
  user_id: null,
  organization_id: null,
  subject_type: "project",
  subject_id: "p1",
  format: "csv",
  status: "ready",
  bucket: "data-exports",
  files: ["x1/public.projects.csv"],
  error: null,
  requested_by: null,
  requested_at: "2026-10-06T12:00:00Z",
  completed_at: null,
  expires_at: null,
  ...overrides,
});

const requestRow = (overrides: Record<string, unknown> = {}) => ({
  id: "r1",
  organization_id: "org-1",
  kind: "access",
  requester: "ada@example.com",
  subject_type: null,
  subject_id: null,
  details: null,
  status: "received",
  received_at: "2026-10-06T12:00:00Z",
  due_at: "2026-11-05T12:00:00Z",
  ...overrides,
});

function storageReturning(reply: unknown): LifecycleStorage {
  // SAFETY: the stub implements createSignedUrl, the one method download calls.
  return {
    from: () => ({
      createSignedUrl: () =>
        reply instanceof Error ? Promise.reject(reply) : Promise.resolve(reply),
    }),
  } as unknown as LifecycleStorage;
}

describe("export rows", () => {
  it("falls back to the user subject and keeps the subject and format", async () => {
    const { transport, calls } = fakeTransport({
      request_subject_export: exportRow({ status: "pending", files: [] }),
    });

    const requested = await createDataLifecycle({ transport })
      .requestSubjectExport({
        subjectType: "project",
        subjectId: "p1",
        format: "csv",
      })
      .orThrow();

    expect(requested).toMatchObject({
      subject: "user",
      subjectType: "project",
      subjectId: "p1",
      format: "csv",
    });
    expect(calls[0]?.[1]["format"]).toBe("csv");

    await createDataLifecycle({ transport })
      .requestSubjectExport({ subjectType: "project", subjectId: "p1" })
      .orThrow();

    expect(calls[1]?.[1]["format"]).toBe("ndjson");
  });

  it("rejects an unknown export status", async () => {
    const { transport } = fakeTransport({
      list_data_exports: [exportRow({ status: "bogus" })],
    });

    const result = await createDataLifecycle({ transport }).exports("org-1");

    expect(result.ok).toBe(false);
  });
});

describe("download", () => {
  const ready = () => fakeTransport({ get_data_export: exportRow() }).transport;

  it("reports a storage error and a reply without data", async () => {
    const failing = await createDataLifecycle({
      transport: ready(),
      storage: storageReturning({ data: null, error: { message: "denied" } }),
    }).download("x1");

    expect(failing.ok).toBe(false);

    const empty = await createDataLifecycle({
      transport: ready(),
      storage: storageReturning({ data: null, error: null }),
    }).download("x1");

    expect(!empty.ok && empty.error.message).toBe("Storage returned no data");
  });

  it("reports a storage call that throws", async () => {
    const result = await createDataLifecycle({
      transport: ready(),
      storage: storageReturning(new Error("offline")),
    }).download("x1");

    expect(result.ok).toBe(false);
  });
});

describe("exportNow", () => {
  it("returns the request error", async () => {
    const { transport } = fakeTransport({
      request_data_export: new Error("down"),
    });

    const result = await createDataLifecycle({ transport }).exportNow({
      intervalMs: 1,
    });

    expect(result.ok).toBe(false);
  });

  it("returns the listing error", async () => {
    const { transport } = fakeTransport({
      request_data_export: exportRow({ status: "pending", files: [] }),
      list_data_exports: new Error("down"),
    });

    const result = await createDataLifecycle({ transport }).exportNow({
      intervalMs: 1,
    });

    expect(result.ok).toBe(false);
  });

  it("polls until the export is ready", async () => {
    let listings = 0;

    const { transport } = fakeTransport({
      request_data_export: exportRow({ status: "pending", files: [] }),
      list_data_exports: () => {
        listings += 1;

        return [exportRow({ status: listings < 3 ? "running" : "ready" })];
      },
      get_data_export: exportRow(),
    });

    const download = await createDataLifecycle({
      transport,
      storage: storageReturning({
        data: { signedUrl: "https://s/x" },
        error: null,
      }),
    })
      .exportNow({ intervalMs: 1, timeoutMs: 5000, organizationId: "org-1" })
      .orThrow();

    expect(listings).toBe(3);
    expect(download.files).toEqual([
      { table: "public.projects", url: "https://s/x" },
    ]);
  });

  it("keeps polling while the export is missing from the listing", async () => {
    const { transport } = fakeTransport({
      request_data_export: exportRow({ status: "pending", files: [] }),
      list_data_exports: [],
    });

    const result = await createDataLifecycle({ transport }).exportNow({
      intervalMs: 1,
      timeoutMs: 3,
    });

    expect(!result.ok && result.error.hint).toBe("DATA_EXPORT_NOT_READY");
  });
});

describe("data subject requests", () => {
  it("opens a request with and without a subject", async () => {
    const { transport, calls } = fakeTransport({
      open_data_subject_request: requestRow({
        kind: "erasure",
        subject_type: "contact",
        subject_id: "c1",
        details: "please",
        overdue: false,
      }),
    });

    const lifecycle = createDataLifecycle({ transport });

    const opened = await lifecycle
      .openDataSubjectRequest({
        organizationId: "org-1",
        kind: "erasure",
        requester: "ada@example.com",
        subject: { type: "contact", id: "c1" },
        details: "please",
      })
      .orThrow();

    expect(opened).toMatchObject({
      kind: "erasure",
      subjectType: "contact",
      subjectId: "c1",
      details: "please",
      overdue: false,
    });
    expect(calls[0]?.[1]).toMatchObject({
      subject_type: "contact",
      subject_id: "c1",
      details: "please",
    });

    await lifecycle
      .openDataSubjectRequest({
        organizationId: "org-1",
        kind: "access",
        requester: "ada@example.com",
      })
      .orThrow();

    expect(calls[1]?.[1]).toMatchObject({
      subject_type: null,
      subject_id: null,
      details: null,
    });
  });

  it("verifies, extends, fulfils and refuses a request", async () => {
    const { transport, calls } = fakeTransport({
      verify_data_subject_request: requestRow({
        status: "verified",
        verified_at: "2026-10-07T12:00:00Z",
        verified_by: "u1",
        verification_method: "email",
      }),
      extend_data_subject_request: requestRow({
        extended_at: "2026-10-08T12:00:00Z",
        extension_reason: "complex",
      }),
      fulfil_data_subject_request: requestRow({
        status: "fulfilled",
        export_id: "x1",
        resolution: "sent",
        closed_at: "2026-10-09T12:00:00Z",
      }),
      refuse_data_subject_request: requestRow({ status: "refused" }),
    });

    const lifecycle = createDataLifecycle({ transport });

    const verified = await lifecycle
      .verifyDataSubjectRequest({ requestId: "r1", method: "email" })
      .orThrow();

    expect(verified).toMatchObject({
      verifiedBy: "u1",
      verificationMethod: "email",
    });
    expect(verified.verifiedAt).toBeDefined();
    expect(verified.overdue).toBeUndefined();

    const extended = await lifecycle
      .extendDataSubjectRequest({ requestId: "r1", reason: "complex" })
      .orThrow();

    expect(extended.extensionReason).toBe("complex");

    const fulfilled = await lifecycle
      .fulfilDataSubjectRequest({ requestId: "r1", resolution: "sent" })
      .orThrow();

    expect(fulfilled).toMatchObject({ exportId: "x1", resolution: "sent" });

    await lifecycle.fulfilDataSubjectRequest({ requestId: "r1" }).orThrow();
    expect(calls[3]?.[1]["resolution"]).toBeNull();

    const refused = await lifecycle
      .refuseDataSubjectRequest({
        requestId: "r1",
        reason: "manifestly unfounded",
      })
      .orThrow();

    expect(refused.status).toBe("refused");
  });

  it("lists requests with and without filters", async () => {
    const { transport, calls } = fakeTransport({
      list_data_subject_requests: [requestRow()],
    });

    const lifecycle = createDataLifecycle({
      transport,
      logger: { debug() {}, info() {}, warn() {}, error() {} },
    });

    await lifecycle
      .dataSubjectRequests({
        organizationId: "org-1",
        status: "verified",
        openOnly: true,
      })
      .orThrow();
    await lifecycle.dataSubjectRequests({ organizationId: "org-1" }).orThrow();

    expect(calls[0]?.[1]).toMatchObject({
      status: "verified",
      open_only: true,
    });
    expect(calls[1]?.[1]).toMatchObject({ status: null, open_only: false });
  });

  it("rejects an unknown request kind or status", async () => {
    const lifecycle = (row: Record<string, unknown>) =>
      createDataLifecycle({
        transport: fakeTransport({
          list_data_subject_requests: [requestRow(row)],
        }).transport,
      });

    expect(
      (
        await lifecycle({ kind: "bogus" }).dataSubjectRequests({
          organizationId: "org-1",
        })
      ).ok,
    ).toBe(false);
    expect(
      (
        await lifecycle({ status: "bogus" }).dataSubjectRequests({
          organizationId: "org-1",
        })
      ).ok,
    ).toBe(false);
  });
});
