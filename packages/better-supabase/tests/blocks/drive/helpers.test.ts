import { describe, expect, it } from "vitest";

import { createDrive } from "../../../src/blocks/drive/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-01T00:00:00Z";

const FOLDER = {
  id: "f1",
  organizationId: "o",
  parentId: null,
  kind: "folder",
  name: "Projects",
  createdAt: AT,
  role: "owner",
};

const FILE = {
  ...FOLDER,
  id: "n1",
  parentId: "f1",
  kind: "file",
  name: "plan.pdf",
};

const ATTACHMENT = {
  id: "a1",
  organization_id: "o",
  subject_type: "drive_node",
  subject_id: "n1",
  bucket: "attachments",
  object_path: "o/a1",
  name: "plan.pdf",
  mime_type: "application/pdf",
  size: 3,
  status: "pending",
  metadata: {},
  created_at: AT,
};

const GRANT = (id: string, principalId: string) => ({
  id,
  nodeId: "f1",
  principalType: "user",
  principalId,
  role: "viewer",
  inherited: false,
});

const FLAGS = {
  role: "owner",
  read: true,
  comment: true,
  download: true,
  upload: true,
  write: true,
  share: true,
};

interface Reply {
  data: unknown;
  error: { message: string } | null;
}

function storage(upload: () => Promise<Reply>) {
  return {
    from: () => ({
      createSignedUploadUrl: () =>
        Promise.resolve({ data: { signedUrl: "u", token: "t" }, error: null }),
      createSignedUrl: () =>
        Promise.resolve({ data: { signedUrl: "d" }, error: null }),
      download: () => Promise.resolve({ data: new Blob(), error: null }),
      remove: () => Promise.resolve({ data: [], error: null }),
      upload,
    }),
  };
}

describe("drive.folder", () => {
  it("reads the node, children, crumbs, flags and grants in one call", async () => {
    const t = fieldsTransport({
      drive_get: () => FOLDER,
      drive_list: () => [FILE],
      drive_path: () => [{ id: "f1", name: "Projects", kind: "folder" }],
      drive_node_access: () => FLAGS,
      drive_grants: () => [GRANT("g1", "u1")],
    });

    const view = await createDrive({ transport: t })
      .folder({ organizationId: "o", nodeId: "f1" })
      .orThrow();

    expect(view.node?.name).toBe("Projects");
    expect(view.children.map((c) => c.id)).toEqual(["n1"]);
    expect(view.breadcrumbs.map((c) => c.name)).toEqual(["Projects"]);
    expect(view.access?.share).toBe(true);
    expect(view.grants).toHaveLength(1);
  });

  it("lists the root without a node", async () => {
    const t = fieldsTransport({ drive_list: () => [FOLDER] });

    const view = await createDrive({ transport: t })
      .folder({ organizationId: "o" })
      .orThrow();

    expect(view.node).toBeUndefined();
    expect(view.access).toBeUndefined();
    expect(t.calls.map(([fn]) => fn)).toEqual(["drive_list"]);
  });

  it("returns the first failure", async () => {
    const t = fieldsTransport({
      drive_get: () => FOLDER,
      drive_list: () => [],
      drive_path: () => [],
      drive_node_access: () => Promise.reject(new Error("boom")),
      drive_grants: () => [],
    });

    const view = await createDrive({ transport: t }).folder({
      organizationId: "o",
      nodeId: "f1",
    });

    expect(view.ok).toBe(false);
  });
});

describe("drive.can, search, shareMany and grantsWithNames", () => {
  it("can reads the flags", async () => {
    const t = fieldsTransport({
      drive_node_access: () => ({ ...FLAGS, role: null, write: false }),
    });

    const flags = await createDrive({ transport: t }).can("f1").orThrow();

    expect(flags).toMatchObject({ role: undefined, read: true, write: false });
  });

  it("search sends the query", async () => {
    const t = fieldsTransport({ drive_search: () => [FILE] });

    const found = await createDrive({ transport: t })
      .search({ organizationId: "o", query: "plan" })
      .orThrow();

    expect(found.map((n) => n.name)).toEqual(["plan.pdf"]);
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      query: "plan",
      page_size: 25,
    });
  });

  it("shareMany gives every grant on every node and stops at a failure", async () => {
    let calls = 0;

    const t = fieldsTransport({
      drive_share: () => {
        calls += 1;

        if (calls === 3) {
          throw new Error("denied");
        }

        return GRANT(`g${calls}`, "u1");
      },
    });

    const result = await createDrive({ transport: t }).shareMany({
      ids: ["a", "b"],
      grants: [
        { principal: { type: "user", id: "u1" }, role: "viewer" },
        { principal: { type: "team", id: "t1" }, role: "editor" },
      ],
    });

    expect(result.ok).toBe(false);
    expect(calls).toBe(3);
  });

  it("grantsWithNames asks once per principal", async () => {
    const t = fieldsTransport({
      drive_grants: () => [
        GRANT("g1", "u1"),
        GRANT("g2", "u1"),
        GRANT("g3", "u2"),
      ],
    });

    const asked: string[] = [];

    const named = await createDrive({ transport: t })
      .grantsWithNames({
        id: "f1",
        names: (principal) => {
          asked.push(principal.id);

          return principal.id === "u1" ? "Ana" : undefined;
        },
      })
      .orThrow();

    expect(named.map((g) => g.name)).toEqual(["Ana", "Ana", undefined]);
    expect(asked.toSorted()).toEqual(["u1", "u2"]);
  });
});

describe("drive.put", () => {
  it("uploads, stores and commits", async () => {
    const t = fieldsTransport({
      drive_create_file: () => ({ node: FILE, attachment: ATTACHMENT }),
      drive_commit: () => FILE,
    });

    const drive = createDrive({
      transport: t,
      storage: storage(() => Promise.resolve({ data: {}, error: null })),
    });

    const node = await drive
      .put({
        organizationId: "o",
        parentId: "f1",
        file: new Blob(["abc"], { type: "application/pdf" }),
        name: "plan.pdf",
      })
      .orThrow();

    expect(node.id).toBe("n1");
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "drive_create_file",
      "drive_commit",
    ]);
  });

  it("deletes the pending file when storage refuses the bytes", async () => {
    const t = fieldsTransport({
      drive_create_file: () => ({ node: FILE, attachment: ATTACHMENT }),
      drive_delete: () => true,
    });

    const drive = createDrive({
      transport: t,
      storage: storage(() =>
        Promise.resolve({ data: null, error: { message: "no" } }),
      ),
    });

    const result = await drive.put({
      organizationId: "o",
      file: new Blob(["abc"]),
      name: "plan.pdf",
    });

    expect(result.ok).toBe(false);
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "drive_create_file",
      "drive_delete",
    ]);
  });

  it("needs a name", async () => {
    const t = fieldsTransport({});

    const result = await createDrive({
      transport: t,
      storage: storage(() => Promise.resolve({ data: {}, error: null })),
    }).put({ organizationId: "o", file: new Blob(["x"]) });

    expect(result.ok ? undefined : result.error.kind).toBe("invalid_input");
  });
});
