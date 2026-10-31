import { describe, expect, it } from "vitest";

import type { PreviewRenderer } from "../../../src/blocks/drive/preview.ts";

import {
  createDam,
  damBlock,
  damUsageRightInputSchema,
} from "../../../src/blocks/dam/index.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const RENDITION = {
  id: "r1",
  organizationId: "org-1",
  nodeId: "n1",
  kind: "thumbnail",
  status: "ready",
  format: "webp",
  width: 200,
  height: 100,
  sizeBytes: 4,
  path: "org-1/n1/thumbnail",
  createdAt: AT,
  updatedAt: AT,
};

const RIGHT = {
  id: "u1",
  organizationId: "org-1",
  nodeId: "n1",
  licensee: "Acme",
  territory: "NL",
  channel: "web",
  startsOn: "2026-10-01",
  expiresOn: "2027-01-01",
  status: "active",
  note: "Launch",
  createdBy: "user-1",
  createdAt: AT,
};

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

const pageRenderer = (
  name: string,
  page: Blob | undefined,
): PreviewRenderer => ({
  apiVersion: 1,
  name,
  render: () =>
    page === undefined
      ? undefined
      : [{ body: page, contentType: "image/webp" }],
});

describe("createDam", () => {
  it("records and lists renditions", async () => {
    const t = fieldsTransport({
      record_rendition: () => RENDITION,
      list_renditions: () => [
        RENDITION,
        { ...RENDITION, kind: "web", width: undefined },
      ],
    });

    const dam = createDam({ transport: t, tenant: "org-1" });

    const recorded = await dam
      .recordRendition("n1", "thumbnail", { width: 200, height: 100 })
      .orThrow();

    const listed = await dam.listRenditions("n1").orThrow();

    expect(recorded).toMatchObject({
      kind: "thumbnail",
      width: 200,
      path: "org-1/n1/thumbnail",
    });
    expect(listed[1]?.width).toBeUndefined();
    expect(t.calls[0]).toEqual([
      "record_rendition",
      {
        tenant: "org-1",
        node_id: "n1",
        kind: "thumbnail",
        input: { width: 200, height: 100 },
      },
    ]);
    expect(t.calls[1]).toEqual([
      "list_renditions",
      { tenant: "org-1", node_id: "n1" },
    ]);
  });

  it("grants, lists, checks and revokes usage rights", async () => {
    const t = fieldsTransport({
      grant_usage_right: () => RIGHT,
      revoke_usage_right: () => ({
        ...RIGHT,
        status: "revoked",
        revokedAt: AT,
      }),
      list_usage_rights: () => [RIGHT],
      check_usage: () => ({
        allowed: true,
        rightId: "u1",
        expiresOn: "2027-01-01",
      }),
      notify_expiring_usage_rights: () => 2,
    });

    const dam = createDam({ transport: t, tenant: "org-1" });
    const { PlainDate } = temporal();

    const granted = await dam
      .grantRight({
        nodeId: "n1",
        licensee: "Acme",
        territory: "NL",
        expiresOn: PlainDate.from("2027-01-01"),
      })
      .orThrow();

    const revoked = await dam.revokeRight("u1").orThrow();

    const listed = await dam
      .listRights({ nodeId: "n1", expiringWithinDays: 30 })
      .orThrow();

    const check = await dam
      .checkUsage("n1", { on: PlainDate.from("2026-12-01"), territory: "NL" })
      .orThrow();

    const reported = await dam.notifyExpiring().orThrow();

    expect(granted.expiresOn?.toString()).toBe("2027-01-01");
    expect(granted.startsOn.toString()).toBe("2026-10-01");
    expect(revoked.revokedAt?.toString()).toBe(AT);
    expect(listed).toHaveLength(1);
    expect(check.allowed).toBe(true);
    expect(check.expiresOn?.toString()).toBe("2027-01-01");
    expect(reported).toBe(2);
    expect(t.calls[0]).toEqual([
      "grant_usage_right",
      {
        tenant: "org-1",
        input: {
          nodeId: "n1",
          licensee: "Acme",
          territory: "NL",
          expiresOn: "2027-01-01",
        },
      },
    ]);
    expect(t.calls[3]).toEqual([
      "check_usage",
      {
        tenant: "org-1",
        node_id: "n1",
        filters: { on: "2026-12-01", territory: "NL" },
      },
    ]);
    expect(t.calls[4]).toEqual(["notify_expiring_usage_rights", { days: 30 }]);
  });

  it("answers a file without a right as not allowed", async () => {
    const t = fieldsTransport({
      check_usage: () => ({ allowed: false, rightId: null, expiresOn: null }),
    });

    const check = await createDam({ transport: t, tenant: "org-1" })
      .checkUsage("n1")
      .orThrow();

    expect(check).toEqual({ allowed: false });
  });

  it("renders the configured kinds through preview renderers", async () => {
    const uploads: string[] = [];

    const t = fieldsTransport({
      record_rendition: (args) => ({
        ...RENDITION,
        kind: args["kind"],
        status: (args["input"] as { status?: string }).status ?? "ready",
      }),
    });

    const storage = {
      from: () => ({
        upload: (path: string) => {
          uploads.push(path);

          return Promise.resolve({ data: {}, error: null });
        },
      }),
    };

    const dam = createDam({
      transport: t,
      tenant: "org-1",
      // SAFETY: the test storage only implements the upload the render uses.
      storage: storage as never,
      renditions: {
        thumbnail: { renderer: pageRenderer("thumb", new Blob(["abcd"])) },
        skipped: { renderer: pageRenderer("skip", undefined) },
        broken: {
          renderer: {
            apiVersion: 1,
            name: "broken",
            render: () => {
              throw new Error("corrupt file");
            },
          },
        },
      },
    });

    const made = await dam
      .renderRenditions({
        nodeId: "n1",
        name: "a.png",
        mimeType: "image/png",
        file: new Blob(["x"]),
      })
      .orThrow();

    expect(made.map((rendition) => [rendition.kind, rendition.status])).toEqual(
      [
        ["thumbnail", "ready"],
        ["broken", "failed"],
      ],
    );
    expect(uploads).toEqual(["org-1/n1/thumbnail"]);
    expect(t.calls[0]?.[1]["input"]).toEqual({
      status: "ready",
      format: "webp",
      sizeBytes: 4,
      path: "org-1/n1/thumbnail",
    });
    expect(t.calls[1]?.[1]["input"]).toEqual({
      status: "failed",
      error: "corrupt file",
    });
  });

  it("refuses to render without storage or kinds", async () => {
    const dam = createDam({ transport: fieldsTransport({}), tenant: "org-1" });

    const result = await dam.renderRenditions({
      nodeId: "n1",
      name: "a.png",
      mimeType: "image/png",
      file: new Blob(["x"]),
    });

    expect(result.ok).toBe(false);
  });

  it("rejects a malformed row", async () => {
    const t = fieldsTransport({ grant_usage_right: () => ({ id: "u1" }) });
    await expect(
      createDam({ transport: t, tenant: "org-1" })
        .grantRight({ nodeId: "n1", licensee: "Acme" })
        .orThrow(),
    ).rejects.toThrow(/./);
  });

  it("has a manifest and an input schema with the SQL bounds", () => {
    expect(damBlock.name).toBe("dam");
    expect(
      validate(damUsageRightInputSchema, {
        nodeId: "0b6f5b1e-8c1e-4f77-9d57-6b2f0f5f4a11",
        licensee: "Acme",
      }).issues,
    ).toBeUndefined();
    expect(
      validate(damUsageRightInputSchema, {
        nodeId: "0b6f5b1e-8c1e-4f77-9d57-6b2f0f5f4a11",
        licensee: "",
      }).issues,
    ).toBeDefined();
  });
});
