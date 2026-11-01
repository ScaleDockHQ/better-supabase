import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { BlockContext, UsingOptions } from "../../src/blocks/index.ts";
import type { AsyncResult } from "../../src/core/result.ts";
import type { StandardSchemaV1 } from "../../src/core/standard.ts";
import type { StorageApi } from "../../src/storage/storage-api.ts";

import { attachmentsBlock } from "../../src/blocks/attachments/index.ts";
import { dataLifecycleBlock } from "../../src/blocks/data-lifecycle/index.ts";
import { defineBlock, defineBlocks } from "../../src/blocks/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { instanceProperty } from "../../src/core/instance-property.ts";
import { err, ok } from "../../src/core/result.ts";
import { schema } from "../fixtures/generated-camel.ts";

/** A block whose client reports the tenant it acts in. */
const probe = defineBlock({
  name: "probe",
  create: (context: BlockContext) => ({
    tenant: (): string | undefined =>
      typeof context.tenant === "function"
        ? (context.tenant() ?? undefined)
        : context.tenant,
  }),
  category: "work",
});

const config = {
  probe: { schema: "better_supabase", api: "api", options: {} },
  "lead-scoring": { block: "probe", schema: "better_supabase", options: {} },
} as const;

const blockSet = defineBlocks(config, { probe, "lead-scoring": probe });

const rpc = vi.fn(async () => ok({ rows: [{ value: 1 }], count: null }));

const executor = {
  name: "fake",
  execute: async () => ok({ rows: [], count: 0 }),
  rpc,
};

const betterSupabase = defineSupabase(schema).blocks(blockSet);

type Rows = { readonly rows: readonly unknown[] };

/** Accepts `{ rows }` and types it. */
const VALUE: StandardSchemaV1<unknown, Rows> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) => {
      if (typeof value !== "object" || value === null || !("rows" in value)) {
        return { issues: [{ message: "no rows" }] };
      }

      // SAFETY: checked that `value` has `rows`.
      return { value: value as Rows };
    },
  },
};

/** Refuses everything. */
const NEVER: StandardSchemaV1<unknown, never> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: () => ({ issues: [{ message: "never" }] }),
  },
};

describe("block instances on db", () => {
  it("puts each instance under its key in camel case", () => {
    const db = betterSupabase.connect(executor, { tenant: "org-1" });

    expect(db.probe.tenant()).toBe("org-1");
    expect(db.leadScoring.tenant()).toBe("org-1");
    expect(instanceProperty("lead-scoring")).toBe("leadScoring");
    expect(instanceProperty("billable_time")).toBe("billableTime");
  });

  it("builds a client once per db and acts in that db's organization", () => {
    const db = betterSupabase.connect(executor, { tenant: "org-1" });
    const other = db.$with({ tenant: "org-2" });

    expect(db.probe).toBe(db.probe);
    expect(other.probe).not.toBe(db.probe);
    expect(other.probe.tenant()).toBe("org-2");
  });

  it("keeps the tables next to the instances", () => {
    const db = betterSupabase.connect(executor, {});

    expect(db.customers).toBeDefined();
    expect(Object.keys(db)).not.toContain("probe");
  });

  it("calls the API schema through $api", async () => {
    const db = betterSupabase.connect(executor, {});

    const result = await db.$api("ping", { a: 1, b: undefined });

    expect(result.ok).toBe(true);
    expect(rpc).toHaveBeenCalledWith(
      "ping",
      { a: 1 },
      expect.objectContaining({ schema: "api" }),
    );
  });

  it("returns a database error from $api as a Result", async () => {
    const failing = {
      ...executor,
      rpc: async () => err(dbError("forbidden", "denied")),
    };

    const db = betterSupabase.connect(failing, {});
    const result = await db.$api("ping", {});

    expect(result).toMatchObject({
      ok: false,
      error: { kind: "forbidden", message: "denied" },
    });
    await expect(db.$api("ping").orThrow()).rejects.toThrow("denied");
  });

  it("validates the $api result against `returns`", async () => {
    const db = betterSupabase.connect(executor, {});

    const result = await db.$api("ping", {}, { returns: VALUE }).orThrow();

    expect(result).toEqual({ rows: [{ value: 1 }], count: null });

    const refused = await db.$api("ping", {}, { returns: NEVER });

    expect(refused).toMatchObject({ ok: false, error: { kind: "validation" } });
  });

  it("returns a database error from BlockSet.call as a Result", async () => {
    const failing = {
      ...executor,
      rpc: async () => err(dbError("raised", "boom")),
    };

    const db = betterSupabase.connect(failing, {});
    const result = await blockSet.call(db, "ping", {});

    expect(result).toMatchObject({ ok: false, error: { message: "boom" } });
    expect(
      await defineBlocks(
        { probe: { schema: "better_supabase", options: {} } },
        { probe },
      ).call(db, "ping", {}),
    ).toMatchObject({ ok: false, error: { kind: "unsupported" } });
  });

  it("keeps $apiResult as $api", async () => {
    const db = betterSupabase.connect(executor, {});

    // oxlint-disable-next-line typescript/no-deprecated -- the alias under test
    expect(await db.$apiResult("ping", { a: 1 })).toEqual(
      await db.$api("ping", { a: 1 }),
    );
  });

  it("passes the definition's temporal to every instance", () => {
    const seen: unknown[] = [];
    const temporal = globalThis.Temporal;

    const recorder = defineBlock({
      name: "recorder",
      create: (context: BlockContext) => {
        seen.push(context.temporal);

        return { ping: (): boolean => true };
      },
      category: "work",
    });

    const db = defineSupabase(schema, { temporal })
      .blocks(
        defineBlocks(
          {
            recorder: { schema: "better_supabase", options: {} },
            second: {
              block: "recorder",
              schema: "better_supabase",
              options: {},
            },
          },
          { recorder, second: recorder },
        ),
      )
      .connect(executor, {});

    expect(db.recorder.ping()).toBe(true);
    expect(db.second.ping()).toBe(true);
    expect(seen).toEqual([temporal, temporal]);
  });

  it("leaves a table its property and keeps the instance under $blocks", () => {
    const clash = defineSupabase(schema).blocks(
      defineBlocks(
        {
          customers: { block: "probe", schema: "better_supabase", options: {} },
        },
        { customers: probe },
      ),
    );

    const db = clash.connect(executor, {});

    expect(typeof db.customers.list).toBe("function");
    expect(db.$blocks.customers.tenant()).toBeUndefined();
    expect(Object.keys(db.$blocks)).toEqual(["customers"]);
  });

  it("types the instances by property", () => {
    const db = betterSupabase.connect(executor, {});

    expectTypeOf(db.leadScoring.tenant).returns.toEqualTypeOf<
      string | undefined
    >();
    // @ts-expect-error not an instance
    void db.leadscoring;
    expectTypeOf(db.$api("ping")).toEqualTypeOf<AsyncResult<unknown>>();
    expectTypeOf(db.$api("ping", {}, { returns: VALUE })).toEqualTypeOf<
      AsyncResult<{ readonly rows: readonly unknown[] }>
    >();
    expectTypeOf(blockSet.call(db, "ping", {})).toEqualTypeOf<
      AsyncResult<unknown>
    >();
    // @ts-expect-error a definition without blocks has no $api
    void defineSupabase(schema).connect(executor, {}).$api;
  });
});

describe("block instances and the Db's storage", () => {
  const signed: unknown[][] = [];

  const bucketApi = (bucket: string) => ({
    createSignedUrl: (path: string, ttl: number) => {
      signed.push([bucket, path, ttl]);

      return Promise.resolve({
        data: { signedUrl: `https://s/${bucket}/${path}` },
        error: null,
      });
    },
  });

  // SAFETY: the blocks below only call createSignedUrl.
  const storage = { from: bucketApi } as unknown as StorageApi;

  const rows: Record<string, unknown> = {
    get_attachment: {
      id: "a1",
      organization_id: "org-1",
      subject_type: "project",
      subject_id: "p1",
      bucket: "attachments",
      object_path: "org-1/attachments/a1",
      name: "plan.pdf",
      mime_type: "application/pdf",
      size: "2048",
      status: "clean",
      uploaded_by: "u1",
      created_at: "2026-10-06T12:00:00Z",
      uploaded_at: "2026-10-06T12:00:05Z",
    },
    get_data_export: {
      id: "x1",
      subject: "user",
      user_id: "u1",
      status: "ready",
      bucket: "data-exports",
      files: ["x1/public.projects.ndjson"],
      requested_at: "2026-10-06T12:00:00Z",
      completed_at: "2026-10-06T12:01:00Z",
      expires_at: "2026-10-13T12:01:00Z",
    },
  };

  const files = {
    name: "fake",
    execute: async () => ok({ rows: [], count: 0 }),
    rpc: async (fn: string) => ok(rows[fn]),
  };

  const storageProbe = defineBlock({
    name: "probe",
    create: (context: BlockContext) => ({ storage: context.storage }),
    category: "work",
  });

  const fileBlocks = defineBlocks(
    {
      attachments: { schema: "better_supabase", options: {} },
      "data-lifecycle": { schema: "better_supabase", options: {} },
      probe: { schema: "better_supabase", options: {} },
    },
    {
      attachments: attachmentsBlock,
      "data-lifecycle": dataLifecycleBlock,
      probe: storageProbe,
    },
  );

  const withFiles = defineSupabase(schema).blocks(fileBlocks);

  it("signs attachment downloads through db.$storage", async () => {
    signed.length = 0;
    const db = withFiles.connect(files, { tenant: "org-1" }, { storage });

    const { signedUrl } = await db.$blocks.attachments
      .download({ id: "a1" })
      .orThrow();

    expect(signedUrl).toBe("https://s/attachments/org-1/attachments/a1");
    expect(signed).toEqual([["attachments", "org-1/attachments/a1", 300]]);
  });

  it("signs export files through db.$storage", async () => {
    signed.length = 0;
    const db = withFiles.connect(files, {}, { storage });

    const download = await db.$blocks.dataLifecycle.download("x1").orThrow();

    expect(download.files).toEqual([
      {
        table: "public.projects",
        url: "https://s/data-exports/x1/public.projects.ndjson",
      },
    ]);
    expect(signed[0]?.[0]).toBe("data-exports");
  });

  it("passes no storage when the Db has none, and an explicit one wins", () => {
    const bare = withFiles.connect(files, {});
    const db = withFiles.connect(files, {}, { storage });
    // SAFETY: only compared by identity.
    const other = { from: bucketApi } as unknown as StorageApi;

    expect(bare.$blocks.probe.storage).toBeUndefined();
    expect(db.$blocks.probe.storage).toBe(db.$storage);
    expect(fileBlocks.client(db, "probe").storage).toBe(db.$storage);
    expect(fileBlocks.client(db, "probe", { storage: other }).storage).toBe(
      other,
    );

    const pinned = defineSupabase(schema)
      .blocks(
        defineBlocks(
          { probe: { schema: "better_supabase", options: {} } },
          { probe: storageProbe.with({ storage: other }) },
        ),
      )
      .connect(files, {}, { storage });

    expect(pinned.probe.storage).toBe(other);
  });

  it("gives using creators the Db's storage", () => {
    const db = defineSupabase(schema)
      .blocks(
        defineBlocks(
          { probe: { schema: "better_supabase", options: {} } },
          {
            probe: storageProbe.using((options) => ({
              bucket: options.storage?.from("avatars"),
            })),
          },
        ),
      )
      .connect(files, {}, { storage });

    expect(db.probe.bucket).toBeDefined();
    expectTypeOf<UsingOptions<{}>["storage"]>().toEqualTypeOf<
      StorageApi | undefined
    >();
  });
});
