import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expect, expectTypeOf, it } from "vitest";

import type { LifecycleStorage } from "../../../src/blocks/data-lifecycle/index.ts";

import {
  createDataExporter,
  createDataLifecycle,
  createOrganizationPurger,
} from "../../../src/blocks/data-lifecycle/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";

const exportRow = (overrides: Record<string, unknown> = {}) => ({
  id: "x1",
  subject: "user",
  user_id: "u1",
  organization_id: null,
  status: "ready",
  bucket: "data-exports",
  files: ["x1/public.projects.ndjson", "x1/better_supabase.memberships.ndjson"],
  error: null,
  requested_by: "u1",
  requested_at: "2026-10-06T12:00:00Z",
  completed_at: "2026-10-06T12:01:00Z",
  expires_at: "2026-10-13T12:01:00Z",
  ...overrides,
});

const deletionRow = (overrides: Record<string, unknown> = {}) => ({
  organization_id: "org-1",
  requested_by: "u1",
  requested_at: "2026-10-06T12:00:00Z",
  purge_after: "2026-11-05T12:00:00Z",
  cancelled_at: null,
  purged_at: null,
  previously_disabled: false,
  ...overrides,
});

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

interface Reply {
  data: unknown;
  error: unknown;
}

function fakeStorage(
  replies: Partial<
    Record<string, Reply | Error | ((...args: unknown[]) => Reply)>
  > = {},
) {
  const calls: unknown[][] = [];
  const reply = (method: string, fallback: unknown, ...args: unknown[]) => {
    calls.push([method, ...args]);
    const value = replies[method];
    if (value instanceof Error) return Promise.reject(value);
    if (typeof value === "function") return Promise.resolve(value(...args));
    return Promise.resolve(value ?? { data: fallback, error: null });
  };
  const storage = {
    from: (bucket: string) => ({
      upload: (path: string, body: Blob) =>
        reply("upload", { path }, bucket, path, body),
      createSignedUrl: (path: string, ttl: number) =>
        reply("createSignedUrl", { signedUrl: `https://s/${path}` }, path, ttl),
      list: (path?: string, options?: unknown) =>
        reply("list", [], path, options),
      remove: (paths: string[]) => reply("remove", [], paths),
    }),
    // SAFETY: each reply has the shape the structural type names.
  } as LifecycleStorage;
  return { calls, storage };
}

describe("createDataLifecycle", () => {
  it("accepts supabase-js storage", () => {
    expectTypeOf<SupabaseClient["storage"]>().toExtend<LifecycleStorage>();
  });

  it("requests user and organization exports and lists them", async () => {
    const { transport, calls } = fakeTransport({
      request_data_export: exportRow({ status: "pending", files: [] }),
      list_data_exports: [
        exportRow({ subject: "organization", organization_id: "org-1" }),
      ],
    });
    const lifecycle = createDataLifecycle({ transport });
    expect((await lifecycle.requestExport().orThrow()).status).toBe("pending");
    await lifecycle.requestExport({ organizationId: "org-1" }).orThrow();
    const [listed] = await lifecycle.exports("org-1").orThrow();
    expect(listed).toMatchObject({
      subject: "organization",
      organizationId: "org-1",
    });
    expect(listed!.expiresAt?.toString()).toBe("2026-10-13T12:01:00Z");
    expect(calls).toEqual([
      ["request_data_export", { subject: "user" }],
      ["request_data_export", { subject: "organization", tenant: "org-1" }],
      ["list_data_exports", { tenant: "org-1" }],
    ]);
  });

  it("signs each file of a ready export", async () => {
    const storage = fakeStorage();
    const lifecycle = createDataLifecycle({
      transport: fakeTransport({ get_data_export: exportRow() }).transport,
      storage: storage.storage,
      downloadTtl: 60,
    });
    const download = await lifecycle.download("x1").orThrow();
    expect(download.files).toEqual([
      { table: "public.projects", url: "https://s/x1/public.projects.ndjson" },
      {
        table: "better_supabase.memberships",
        url: "https://s/x1/better_supabase.memberships.ndjson",
      },
    ]);
    expect(storage.calls[0]).toEqual([
      "createSignedUrl",
      "x1/public.projects.ndjson",
      60,
    ]);
  });

  it("refuses missing, unfinished and storage-less downloads", async () => {
    const storage = fakeStorage();
    const missing = await createDataLifecycle({
      transport: fakeTransport({ get_data_export: null }).transport,
      storage: storage.storage,
    }).download("x1");
    expect(missing.ok ? undefined : missing.error.hint).toBe(
      "DATA_EXPORT_NOT_FOUND",
    );
    const running = await createDataLifecycle({
      transport: fakeTransport({
        get_data_export: exportRow({ status: "running" }),
      }).transport,
      storage: storage.storage,
    }).download("x1");
    expect(running.ok ? undefined : running.error.hint).toBe(
      "DATA_EXPORT_NOT_READY",
    );
    const noStorage = await createDataLifecycle({
      transport: fakeTransport({ get_data_export: exportRow() }).transport,
    }).download("x1");
    expect(noStorage.ok ? undefined : noStorage.error.message).toMatch(
      /Pass storage/,
    );
    const failing = await createDataLifecycle({
      transport: fakeTransport({ get_data_export: exportRow() }).transport,
      storage: fakeStorage({
        createSignedUrl: {
          data: null,
          error: { message: "Object not found", statusCode: "404" },
        },
      }).storage,
    }).download("x1");
    expect(failing.ok ? undefined : failing.error.kind).toBe("not_found");
    const odd = createDataLifecycle({
      transport: fakeTransport({
        get_data_export: exportRow({ status: "lost" }),
      }).transport,
      storage: storage.storage,
    });
    await expect(odd.download("x1").orThrow()).rejects.toThrow(
      /Unknown export status/,
    );
  });

  it("requests, cancels and reads organization deletions", async () => {
    const { transport, calls } = fakeTransport({
      request_organization_deletion: deletionRow(),
      cancel_organization_deletion: null,
      organization_deletion: deletionRow({ cancelled_at: null }),
    });
    const lifecycle = createDataLifecycle({ transport });
    const deletion = await lifecycle
      .requestOrganizationDeletion("org-1", {
        grace: Temporal.Duration.from({ days: 30 }),
      })
      .orThrow();
    expect(deletion.purgeAfter.toString()).toBe("2026-11-05T12:00:00Z");
    await lifecycle.requestOrganizationDeletion("org-1").orThrow();
    expect(await lifecycle.cancelOrganizationDeletion("org-1").orThrow()).toBe(
      undefined,
    );
    expect(
      (await lifecycle.organizationDeletion("org-1").orThrow())?.organizationId,
    ).toBe("org-1");
    expect(calls.slice(0, 2)).toEqual([
      ["request_organization_deletion", { tenant: "org-1", grace: "P30D" }],
      ["request_organization_deletion", { tenant: "org-1", grace: undefined }],
    ]);
  });
});

describe("createDataExporter", () => {
  const claimed = {
    ...exportRow({ status: "running", files: [] }),
    tables: ["public.projects", "public.empty"],
  };

  it("pages through each table, uploads NDJSON and completes", async () => {
    const pages: Record<string, unknown[]> = {
      "public.projects:": [{ rows: [{ id: 1 }, { id: 2 }], after: "(0,2)" }],
      "public.projects:(0,2)": [{ rows: [{ id: 3 }], after: null }],
      "public.empty:": [{ rows: [], after: null }],
    };
    const { transport, calls } = fakeTransport({
      claim_data_export: claimed,
      data_export_rows: (args: Record<string, unknown>) =>
        pages[
          `${String(args["table_name"])}:${String(args["after"] ?? "")}`
        ]![0],
      complete_data_export: (args: Record<string, unknown>) =>
        exportRow({ files: args["files"] }),
    });
    const storage = fakeStorage();
    const exporter = createDataExporter({
      transport,
      storage: storage.storage,
      pageSize: 2,
    });
    const done = await exporter.run("x1").orThrow();
    expect(done.files).toEqual([
      "x1/public.projects.ndjson",
      "x1/public.empty.ndjson",
    ]);
    const uploads = storage.calls.filter(([method]) => method === "upload");
    expect(await (uploads[0]![3] as Blob).text()).toBe(
      '{"id":1}\n{"id":2}\n{"id":3}\n',
    );
    expect((uploads[1]![3] as Blob).size).toBe(0);
    expect(
      calls.filter(([fn]) => fn === "data_export_rows").map(([, args]) => args),
    ).toEqual([
      {
        id: "x1",
        table_name: "public.projects",
        after: undefined,
        page_size: 2,
      },
      { id: "x1", table_name: "public.projects", after: "(0,2)", page_size: 2 },
      { id: "x1", table_name: "public.empty", after: undefined, page_size: 2 },
    ]);
  });

  it("writes CSV files with a header row when format is csv", async () => {
    const { transport } = fakeTransport({
      claim_data_export: claimed,
      data_export_rows: (args: Record<string, unknown>) =>
        args["table_name"] === "public.projects"
          ? {
              rows: [{ id: 1, name: "a,b" }, { id: 2, tags: ["x"] }, 3],
              after: null,
            }
          : { rows: [], after: null },
      complete_data_export: (args: Record<string, unknown>) =>
        exportRow({ files: args["files"] }),
    });
    const storage = fakeStorage();
    const done = await createDataExporter({
      transport,
      storage: storage.storage,
      format: "csv",
    })
      .run("x1")
      .orThrow();
    expect(done.files).toEqual([
      "x1/public.projects.csv",
      "x1/public.empty.csv",
    ]);
    const uploads = storage.calls.filter(([method]) => method === "upload");
    expect(await (uploads[0]![3] as Blob).text()).toBe(
      'id,name,tags,value\r\n1,"a,b",,\r\n2,,"[""x""]",\r\n,,,3\r\n',
    );
    expect((uploads[0]![3] as Blob).type).toBe("text/csv");
    expect((uploads[1]![3] as Blob).size).toBe(0);
  });

  it("marks the export failed when a page, an upload or the signal fails", async () => {
    const failures = [
      { data_export_rows: Object.assign(new Error("boom"), { code: "XX000" }) },
      { data_export_rows: { rows: "nope", after: null } },
    ];
    for (const failure of failures) {
      const { transport, calls } = fakeTransport({
        claim_data_export: claimed,
        fail_data_export: null,
        complete_data_export: exportRow(),
        ...failure,
      });
      const exporter = createDataExporter({
        transport,
        storage: fakeStorage().storage,
      });
      const result = await exporter.run("x1");
      const failed = calls.some(([fn]) => fn === "fail_data_export");
      expect(result.ok ? !failed : failed).toBe(true);
    }

    const { transport, calls } = fakeTransport({
      claim_data_export: claimed,
      data_export_rows: { rows: [], after: null },
      fail_data_export: null,
    });
    const uploadFails = await createDataExporter({
      transport,
      storage: fakeStorage({
        upload: {
          data: null,
          error: { message: "Payload too large", statusCode: "413" },
        },
      }).storage,
    }).run("x1");
    expect(uploadFails.ok ? undefined : uploadFails.error.kind).toBe(
      "invalid_input",
    );
    expect(calls.at(-1)![0]).toBe("fail_data_export");

    const controller = new AbortController();
    controller.abort();
    const aborted = await createDataExporter({
      transport: fakeTransport({
        claim_data_export: claimed,
        fail_data_export: null,
      }).transport,
      storage: fakeStorage().storage,
    }).run("x1", controller.signal);
    expect(aborted.ok ? undefined : aborted.error).toMatchObject({
      kind: "aborted",
      hint: "DATA_EXPORT_FAILED",
    });

    const thrown = await createDataExporter({
      transport: fakeTransport({
        claim_data_export: claimed,
        data_export_rows: { rows: [], after: null },
        fail_data_export: null,
      }).transport,
      storage: fakeStorage({
        upload: () => {
          throw new Error("disk full");
        },
      }).storage,
    }).run("x1");
    expect(thrown.ok ? undefined : thrown.error).toMatchObject({
      kind: "raised",
    });
  });

  it("returns not_found for an export it can't claim, and runs from jobs and events", async () => {
    const missing = createDataExporter({
      transport: fakeTransport({ claim_data_export: null }).transport,
      storage: fakeStorage().storage,
    });
    const result = await missing.run("x1");
    expect(result.ok ? undefined : result.error.hint).toBe(
      "DATA_EXPORT_NOT_FOUND",
    );
    await expect(
      missing.job(
        { exportId: "x1" },
        undefined as never,
        new AbortController().signal,
      ),
    ).rejects.toThrow(/No pending export/);

    const { transport, calls } = fakeTransport({
      claim_data_export: { ...claimed, tables: [] },
      complete_data_export: exportRow({ files: [] }),
    });
    await createDataExporter({ transport, storage: fakeStorage().storage })
      .sink()
      .send([
        {
          specversion: "1.0",
          id: "1",
          source: "/t",
          type: "dev.better-supabase.data_export.requested",
          data: { exportId: "x1" },
        },
        {
          specversion: "1.0",
          id: "2",
          source: "/t",
          type: "data_export.requested",
          data: {},
        },
        {
          specversion: "1.0",
          id: "3",
          source: "/t",
          type: "data_export.ready",
          data: { exportId: "x1" },
        },
        {
          specversion: "1.0",
          id: "4",
          source: "/t",
          type: "data_export.requested",
        },
      ]);
    expect(calls.map(([fn]) => fn)).toEqual([
      "claim_data_export",
      "complete_data_export",
    ]);
  });
});

describe("createOrganizationPurger", () => {
  const purged = {
    organizationId: "org-1",
    deleted: { "public.projects": "4" },
  };

  it("cancels billing, clears bucket prefixes page by page, then purges", async () => {
    const listing: Record<string, { name: string; id: string | null }[]> = {
      "org-1": [
        { name: "attachments", id: null },
        { name: "logo.png", id: "f0" },
      ],
      "org-1/attachments": Array.from({ length: 1000 }, (_, i) => ({
        name: `a${String(i)}`,
        id: `f${String(i + 1)}`,
      })),
    };
    const storage = fakeStorage({
      list: (path, options) => {
        const { offset } = options as { offset: number };
        return {
          data:
            offset === 0
              ? (listing[String(path)] ?? [])
              : [{ name: "last", id: "fz" }],
          error: null,
        };
      },
    });
    const cancelled: string[] = [];
    const { transport, calls } = fakeTransport({ purge_organization: purged });
    const purger = createOrganizationPurger({
      transport,
      storage: storage.storage,
      buckets: ["attachments"],
      billing: {
        cancelSubscription: (id) =>
          AsyncResult.from(() => {
            cancelled.push(id);
            return Promise.resolve(ok("sub_1"));
          }),
      },
    });
    const result = await purger.purge("org-1").orThrow();
    expect(result).toEqual({
      organizationId: "org-1",
      deleted: { "public.projects": 4 },
      removed: { attachments: 1002 },
    });
    expect(cancelled).toEqual(["org-1"]);
    const removes = storage.calls.filter(([method]) => method === "remove");
    expect(removes.map(([, paths]) => (paths as string[]).length)).toEqual([
      1000, 2,
    ]);
    expect(calls).toEqual([["purge_organization", { tenant: "org-1" }]]);
  });

  it("clears path templates and computed prefixes per bucket", async () => {
    const listed: string[] = [];
    const storage = fakeStorage({
      list: (path) => {
        listed.push(String(path));
        return { data: [{ name: "f", id: "1" }], error: null };
      },
    });
    const { transport } = fakeTransport({ purge_organization: purged });
    const result = await createOrganizationPurger({
      transport,
      storage: storage.storage,
      buckets: [
        { bucket: "files", path: "orgs/{organizationId}/files/" },
        {
          bucket: "media",
          path: (id) => [`public/${id}`, `private/${id}`],
        },
      ],
    })
      .purge("org-1")
      .orThrow();
    expect(listed).toEqual([
      "orgs/org-1/files",
      "public/org-1",
      "private/org-1",
    ]);
    expect(result.removed).toEqual({ files: 1, media: 2 });
    const unsafe = await createOrganizationPurger({
      transport,
      storage: storage.storage,
      buckets: [{ bucket: "files", path: "shared" }],
    }).purge("org-1");
    expect(unsafe).toMatchObject({
      error: { kind: "invalid_request", message: /other tenants/ },
    });
  });

  it("removes expired exports' files, then their rows", async () => {
    const storage = fakeStorage();
    const { transport, calls } = fakeTransport({
      expired_data_exports: [
        {
          id: "e1",
          bucket: "data-exports",
          files: ["e1/a.ndjson", "e1/b.ndjson", 3],
        },
        { id: "e2", bucket: "data-exports", files: [] },
      ],
      forget_data_exports: 2,
    });
    const purger = createOrganizationPurger({
      transport,
      storage: storage.storage,
    });
    expect(await purger.purgeExports({ limit: 5 }).orThrow()).toBe(2);
    expect(storage.calls.filter(([method]) => method === "remove")).toEqual([
      ["remove", ["e1/a.ndjson", "e1/b.ndjson"]],
    ]);
    expect(calls).toEqual([
      ["expired_data_exports", { max_rows: 5 }],
      ["forget_data_exports", { ids: ["e1", "e2"] }],
    ]);
    const none = createOrganizationPurger({
      transport: fakeTransport({ expired_data_exports: [] }).transport,
    });
    expect(await none.purgeExports().orThrow()).toBe(0);
    const noStorage = createOrganizationPurger({ transport });
    expect(await noStorage.purgeExports()).toMatchObject({
      error: { kind: "invalid_request" },
    });
  });

  it("stops at billing, storage and missing storage errors", async () => {
    const { transport, calls } = fakeTransport({ purge_organization: purged });
    const billingFails = await createOrganizationPurger({
      transport,
      billing: {
        cancelSubscription: () =>
          AsyncResult.from(() =>
            Promise.resolve(err(dbError("network", "Stripe down"))),
          ),
      },
    }).purge("org-1");
    expect(billingFails.ok ? undefined : billingFails.error.message).toBe(
      "Stripe down",
    );
    const noStorage = await createOrganizationPurger({
      transport,
      buckets: ["attachments"],
    }).purge("org-1");
    expect(noStorage.ok).toBe(false);
    const listFails = await createOrganizationPurger({
      transport,
      buckets: ["attachments"],
      storage: fakeStorage({
        list: { data: null, error: { message: "denied", statusCode: "403" } },
      }).storage,
    }).purge("org-1");
    expect(listFails.ok ? undefined : listFails.error.kind).toBe("forbidden");
    const removeFails = await createOrganizationPurger({
      transport,
      buckets: ["attachments"],
      storage: fakeStorage({
        list: { data: [{ name: "f", id: "1" }], error: null },
        remove: { data: null, error: { message: "denied", statusCode: "403" } },
      }).storage,
    }).purge("org-1");
    expect(removeFails.ok).toBe(false);
    expect(calls).toEqual([]);
  });

  it("purges what is due and stops at the first error", async () => {
    let purges = 0;
    const { transport } = fakeTransport({
      due_organization_deletions: [
        deletionRow(),
        deletionRow({ organization_id: "org-2" }),
      ],
      purge_organization: (args: Record<string, unknown>) => {
        purges += 1;
        return args["tenant"] === "org-2"
          ? Object.assign(new Error("No due deletion"), { code: "P0002" })
          : purged;
      },
    });
    const purger = createOrganizationPurger({ transport });
    const result = await purger.purgeDue({ limit: 5 });
    expect(result.ok).toBe(false);
    expect(purges).toBe(2);
    await expect(
      purger.job({}, undefined as never, new AbortController().signal),
    ).rejects.toThrow(/No due deletion/);

    const empty = createOrganizationPurger({
      transport: fakeTransport({ due_organization_deletions: [] }).transport,
    });
    await empty.job({}, undefined as never, new AbortController().signal);
    expect(await empty.purgeDue().orThrow()).toEqual([]);
  });
});
