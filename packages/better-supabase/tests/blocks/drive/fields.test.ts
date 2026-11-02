import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createDrive } from "../../../src/blocks/drive/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const FOLDER = {
  id: "f1",
  organizationId: "o",
  parentId: null,
  kind: "folder",
  name: "Projects",
  rank: "a0",
  createdBy: "u1",
  createdAt: "2026-10-01T00:00:00Z",
  updatedAt: "2026-10-01T00:00:00Z",
  deletedAt: null,
  fields: { client_code: "ACME" },
};

const Fields = v.object({ client_code: v.pipe(v.string(), v.toLowerCase()) });

describe("drive fields", () => {
  it("parses the fields of every node a call returns", async () => {
    const t = fieldsTransport({
      drive_get: () => FOLDER,
      drive_list: () => [FOLDER, { ...FOLDER, id: "f2" }],
      drive_link: () => ({
        link: { id: "l1", role: "viewer", nodeId: "f1", expiresAt: null },
        node: FOLDER,
        children: [{ ...FOLDER, id: "f3", parentId: "f1" }],
      }),
    });

    const drive = createDrive({ transport: t, fields: Fields });
    expect((await drive.get("f1").orThrow()).fields.client_code).toBe("acme");
    const list = await drive.list({ organizationId: "o" }).orThrow();
    expect(list.map((node) => node.fields.client_code)).toEqual([
      "acme",
      "acme",
    ]);
    const view = await drive.link({ token: "token" }).orThrow();
    expect(view.node.fields.client_code).toBe("acme");
    expect(view.children?.[0]?.fields.client_code).toBe("acme");
  });

  it("validates a new folder's fields before the call", async () => {
    const t = fieldsTransport({ drive_create_folder: () => FOLDER });

    const drive = createDrive({
      transport: t,
      fields: v.object({ client_code: v.pipe(v.string(), v.length(4)) }),
    });

    const refused = await drive.createFolder({
      organizationId: "o",
      folder: { name: "Projects", fields: { client_code: "ACMEX" } },
    });

    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");
    expect(t.calls).toEqual([]);
    await drive
      .createFolder({
        organizationId: "o",
        folder: { name: "Projects", fields: { client_code: "ACME" } },
      })
      .orThrow();
    expect(t.calls[0]?.[1]["fields"]).toEqual({ client_code: "ACME" });
  });
});
