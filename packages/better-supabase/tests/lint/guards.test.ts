import { afterEach, describe, expect, it, vi } from "vitest";

import type { GuardViolation } from "../../src/lint/index.ts";

import { membershipsExtension } from "../../src/blocks/memberships/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { definePlugin, orderPlugins } from "../../src/core/plugin.ts";
import {
  recommendedGuards,
  guards,
  safeGuards,
  strictGuards,
} from "../../src/lint/index.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

function withReport(set = strictGuards()) {
  const violations: GuardViolation[] = [];
  const plugin = guards({ rules: set, report: (v) => violations.push(v) });

  return { plugin, violations };
}

const context = { tenant: "org-1" };

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("rules()", () => {
  it("fails unbounded, oversized and deep reads under strict()", async () => {
    const { plugin, violations } = withReport();
    const { client, requests } = capturingClient();
    const db = defineSupabase(schema).use(plugin).connect(client, context);

    const unbounded = await db.customers.list();
    expect(unbounded.error).toMatchObject({
      kind: "invalid_request",
      message: expect.stringContaining("noUnboundedList"),
    });
    await db.customers.list({ limit: 5000, orderBy: { name: "asc" } });
    await db.customers.list({
      limit: 1,
      include: {
        customerTags: {
          include: {
            tag: { include: { customerTags: { include: { customer: true } } } },
          },
        },
      },
    });
    expect(violations.map((v) => v.rule)).toEqual([
      "noUnboundedList",
      "maxLimit",
      "maxIncludeDepth",
    ]);
    expect(requests).toHaveLength(0);

    const fine = await db.customers.list({
      limit: 10,
      orderBy: { name: "asc" },
    });

    expect(fine.error).toBeNull();
    await db.customers.get("c1");
    await db.customers.count();
    expect(violations).toHaveLength(3);
  });

  it("reports warnings without failing the call", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { client, requests } = capturingClient();

    const db = defineSupabase(schema)
      .use(guards({ rules: recommendedGuards() }))
      .connect(client, context);

    const result = await db.customers.list();
    expect(result.error).toBeNull();
    expect(requests).toHaveLength(1);
    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining("noUnboundedList (customers)"),
    );
    warn.mockRestore();
  });

  it("sees the query before other plugins scope it", async () => {
    const { plugin, violations } = withReport(safeGuards());
    const { client } = capturingClient();

    const db = defineSupabase(schema)
      .use(membershipsExtension({ onMissing: "skip" }))
      .use(plugin)
      .connect(client);

    const result = await db.customers.list({ limit: 1 });
    expect(result.error?.message).toContain("requireTenantContext");
    expect(violations[0]).toMatchObject({
      rule: "requireTenantContext",
      table: "customers",
      operation: "select",
    });

    const claims = db.$with({ claims: { tenant_id: "org-1" } });
    expect((await claims.customers.list({ limit: 1 })).error).toBeNull();

    const service = db.$with({ actor: { id: "service", kind: "service" } });

    expect((await service.customers.list({ limit: 1 })).error).toBeNull();
  });

  it("refuses service connections in a browser", async () => {
    vi.stubGlobal("window", {});
    vi.stubGlobal("document", {});
    const { plugin } = withReport(safeGuards());
    const { client } = capturingClient();

    const db = defineSupabase(schema)
      .use(plugin)
      .connect(client, { actor: { id: "service", kind: "service" } });

    const result = await db.tags.list({ limit: 1 });
    expect(result.error?.message).toContain("noAdminInBrowser");
  });

  it("guards sensitive columns unless the call opts in", async () => {
    const meta = schema.meta;
    const contacts = meta.tables["contacts"]!;

    const marked = defineSchema({
      ...meta,
      tables: {
        ...meta.tables,
        contacts: {
          ...contacts,
          columns: {
            ...contacts.columns,
            email: { ...contacts.columns["email"]!, sensitive: true },
          },
        },
      },
    });

    const { plugin } = withReport(safeGuards());
    const { client } = capturingClient();

    const db = defineSupabase({ ...schema, meta: marked.meta })
      .use(plugin)
      .connect(client, context);

    const denied = await db.contacts.list({ limit: 1 });
    expect(denied.error?.message).toContain("contacts.email");
    const named = await db.contacts.list({ select: ["id"], limit: 1 });
    expect(named.error).toBeNull();
    const allowed = await db.contacts.list({ limit: 1, sensitive: true });
    expect(allowed.error).toBeNull();

    const { client: writes, last } = capturingClient(() => ({
      status: 201,
      body: [{ id: "k" }],
    }));

    const written = await defineSupabase({ ...schema, meta: marked.meta })
      .use(plugin)
      .connect(writes, context)
      .contacts.create({ organizationId: "org-1", email: "a@b.c" });

    expect(written.error).toBeNull();
    const select = last().params.get("select") ?? "";
    expect(select.split(",")).not.toContain("email");
    expect(select.split(",")).toContain("id");
  });

  it("allows aggregates, page's look-ahead row and app_metadata tenants", async () => {
    const { plugin, violations } = withReport({
      ...strictGuards(),
      maxLimit: ["error", 10],
    });

    const { client } = capturingClient();
    const db = defineSupabase(schema).use(plugin).connect(client, context);
    expect(
      (await db.customers.aggregate({ groupBy: ["status"], _count: true }))
        .error,
    ).toBeNull();
    expect((await db.customers.page({ size: 10 })).error).toBeNull();
    expect(
      (await db.customers.get({ where: { name: "Acme" } }, { optional: true }))
        .error,
    ).toBeNull();
    expect(violations).toEqual([]);

    const claims = defineSupabase(schema)
      .use(plugin)
      .connect(client, { claims: { app_metadata: { tenant_id: "org-1" } } });

    expect((await claims.customers.list({ limit: 1 })).error).toBeNull();
    expect(violations).toEqual([]);
  });

  it("runs before other pre plugins whatever the use() order", async () => {
    const { plugin, violations } = withReport();

    const early = definePlugin({
      name: "early",
      enforce: "pre",
      transformQuery: (op) =>
        op.kind === "select" ? { ...op, limit: undefined } : op,
    });

    const { client } = capturingClient();
    await defineSupabase(schema)
      .use(early)
      .use(plugin)
      .connect(client, context)
      .customers.list({ limit: 1 });
    expect(violations).toEqual([]);
  });

  it("orders by enforce, not by name", () => {
    const named = (name: string, enforce?: "first" | "pre" | "post") =>
      definePlugin({ name, ...(enforce ? { enforce } : {}) });

    const order = orderPlugins([
      named("rules"),
      named("late", "post"),
      named("checker", "first"),
      named("rewriter", "pre"),
      guards(),
    ]).map((plugin) => `${plugin.name}:${plugin.enforce ?? "normal"}`);

    expect(order).toEqual([
      "checker:first",
      "guards:first",
      "rewriter:pre",
      "rules:normal",
      "late:post",
    ]);
  });

  it("flags storage objects written to *_url columns", async () => {
    const meta = schema.meta;
    const customers = meta.tables["customers"]!;
    const text = { type: "text", nullable: true, hasDefault: false } as const;

    const marked = defineSchema({
      ...meta,
      tables: {
        ...meta.tables,
        customers: {
          ...customers,
          columns: {
            ...customers.columns,
            logoUrl: { ...text, db: "logo_url" },
            bannerUrl: { ...text, db: "banner_url", storage: "banners" },
          },
        },
      },
    });

    const { plugin, violations } = withReport(recommendedGuards());
    const { client } = capturingClient();

    const db = defineSupabase({ ...schema, meta: marked.meta })
      .use(plugin)
      .connect(client, context);

    const write = (set: Record<string, string>) =>
      db.customers.update("c1", set);

    await write({ logoUrl: "o1/c1/logo/1.webp" });
    await write({
      logoUrl:
        "https://abcdefghijklmnopqrst.supabase.co/storage/v1/object/sign/a/b.png?token=t",
    });
    await write({ logoUrl: "https://example.com/logo.png" });
    await write({ name: "Acme" });
    await db.customers.create({
      organizationId: "org-1",
      name: "Acme",
      bannerUrl: "o1/banner.png",
    } as never);
    expect(
      violations.map((v) => [v.rule, v.level, v.operation, v.message]),
    ).toEqual([
      [
        "storagePathColumns",
        "warn",
        "update",
        expect.stringContaining('store its path in "logo_path"'),
      ],
      ["storagePathColumns", "warn", "update", expect.any(String)],
      [
        "storagePathColumns",
        "warn",
        "insert",
        '"banner_url" holds paths in bucket "banners"; name it "banner_path"',
      ],
    ]);
  });

  it("recognizes paths of every bucket template, including rest placeholders", async () => {
    const meta = schema.meta;
    const customers = meta.tables["customers"]!;

    const marked = defineSchema({
      ...meta,
      buckets: {
        files: {
          id: "files",
          public: false,
          path: [
            "{organizationId}/exports/{exportId}.zip",
            "{organizationId}/archive/{...rest}",
          ],
        },
      },
      tables: {
        ...meta.tables,
        customers: {
          ...customers,
          columns: {
            ...customers.columns,
            fileUrl: {
              type: "text",
              nullable: true,
              hasDefault: false,
              db: "file_url",
            },
          },
        },
      },
    });

    const { plugin, violations } = withReport(recommendedGuards());
    const { client } = capturingClient();

    const db = defineSupabase({ ...schema, meta: marked.meta })
      .use(plugin)
      .connect(client, context);

    await db.customers.update("c1", { fileUrl: "o1/exports/e1.zip" } as never);
    await db.customers.update("c1", { fileUrl: "o1/archive/a/b.pdf" } as never);
    await db.customers.update("c1", { fileUrl: "o1/other/b.pdf" } as never);
    expect(violations.map((v) => v.rule)).toEqual([
      "storagePathColumns",
      "storagePathColumns",
    ]);
  });

  it("requires maxAffected on update and delete by filter under strict()", async () => {
    const { plugin, violations } = withReport();
    const { client, requests } = capturingClient(() => ({ status: 204 }));
    const db = defineSupabase(schema).use(plugin).connect(client, context);

    const unbounded = await db.tags.delete({ where: { color: "red" } });
    expect(unbounded.error).toMatchObject({
      kind: "invalid_request",
      message:
        "requireMaxAffected: delete by filter without maxAffected can change every row its where matches",
    });
    await db.tags.update(
      { where: { color: "red" } },
      { color: "blue" },
      { maxAffected: 5000 },
    );
    expect(violations.map((v) => v.message)).toEqual([
      "delete by filter without maxAffected can change every row its where matches",
      "maxAffected 5000 is above the maximum of 1000",
    ]);
    expect(requests).toHaveLength(0);

    await db.tags.delete({ where: { color: "red" } }, { maxAffected: 10 });
    await db.tags.update("t1", { color: "blue" });
    await db.tags.delete("t1");
    await db.tags.delete({ where: { id: "t1" } });
    expect(violations).toHaveLength(2);
    expect(requests).toHaveLength(4);
  });

  it("caps maxAffected with the rule's option and stays off in recommended()", async () => {
    const strictCap = withReport({ requireMaxAffected: ["error", 10] });
    const { client } = capturingClient(() => ({ status: 204 }));

    const capped = defineSupabase(schema)
      .use(strictCap.plugin)
      .connect(client, context);

    expect(
      (
        await capped.tags.delete(
          { where: { color: "red" } },
          { maxAffected: 11 },
        )
      ).error?.kind,
    ).toBe("invalid_request");
    const loose = withReport(recommendedGuards());

    const db = defineSupabase(schema)
      .use(loose.plugin)
      .connect(client, context);

    await db.tags.delete({ where: { color: "red" } });
    expect(loose.violations).toEqual([]);
  });

  it("keeps the repository guard for delete without where", async () => {
    const { plugin, violations } = withReport(safeGuards());
    const { client } = capturingClient();
    const db = defineSupabase(schema).use(plugin).connect(client, context);
    const result = await db.tags.delete({ where: {} });
    expect(result.error?.kind).toBe("invalid_request");
    expect(violations.map((v) => v.rule)).toEqual([]);
  });
});

describe("db.$table and db.$withoutPlugins", () => {
  it("looks repositories up by name", async () => {
    const { client } = capturingClient();
    const db = defineSupabase(schema).connect(client);
    expect(db.$table("tags")).toBe(db.tags);
    expect(() => db.$table("nope" as "tags")).toThrow('unknown table "nope"');
  });

  it("drops plugins, including executor wrappers", async () => {
    const wrapped = vi.fn();
    const { client, requests } = capturingClient();

    const db = defineSupabase(schema)
      .use(guards({ rules: strictGuards(), report: () => {} }))
      .use(
        definePlugin({
          name: "wrap",
          wrapExecutor: (executor) => ({
            name: "wrap",
            execute: (op, ctx) => {
              wrapped();

              return executor.execute(op, ctx);
            },
          }),
        }),
      )
      .connect(client, context);

    expect((await db.tags.list()).error?.kind).toBe("invalid_request");
    const raw = db.$withoutPlugins();
    expect((await raw.tags.list()).error).toBeNull();
    expect(wrapped).not.toHaveBeenCalled();
    expect(requests).toHaveLength(1);
    expect((await raw.$with({ tenant: "x" }).tags.list()).error).toBeNull();
  });
});
