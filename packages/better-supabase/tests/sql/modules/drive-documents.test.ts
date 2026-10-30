import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const MODULES = [
  "drive",
  "versions",
  "approvals",
  "state-machine",
  "numbering",
  "relations",
  "acknowledgements",
  "notifications",
];

const SUBJECTS = {
  drive_node: {
    table: "better_supabase.drive_nodes",
    idType: "uuid",
    tenant: "tenant_id",
    title: "name",
    deletedAt: "deleted_at",
    permissions: { read: "drive.read", write: "drive.manage" },
  },
};

const controlled = (control: Record<string, unknown> | undefined): Layout => ({
  subjects: SUBJECTS,
  modules: {
    drive: { options: control === undefined ? {} : { control } },
    acknowledgements: { on: { drive_node: {} } },
  },
});

const render = (
  control: Record<string, unknown> | undefined,
  modules: readonly string[] = MODULES,
) => renderBlocks(modules, controlled(control));

const sqlOf = (
  files: ReturnType<typeof renderBlocks>,
  module: string,
): string =>
  files
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("drive controlled documents", () => {
  it("adds nothing without options.control", () => {
    const files = render(undefined);
    const all = files.map((file) => file.contents).join("\n");

    expect(all).not.toContain("drive_document_save");
    expect(all).not.toContain("document_number");
    expect(sqlOf(files, "state-machine")).not.toContain("drive_node");
  });

  it("renders the document columns, functions and contributions", () => {
    const files = render({ types: ["sop", "policy"], releaseRole: "editor" });
    const tables = sqlOf(files, "drive");
    const functions = sqlOf(files, "drive-files");

    expect(tables).toContain("document_number");
    expect(tables).toContain("next_review_on");
    expect(functions).toContain("drive_document_save");
    expect(functions).toContain("drive_document_submit");
    expect(functions).toContain("drive_document_release");
    expect(functions).toContain("drive_document_obsolete");
    expect(functions).toContain("drive_document_review");
    expect(functions).toContain("drive_documents");
    expect(functions).toContain("notify_due_drive_reviews");
    expect(functions).toContain("drive_document_readable");
    expect(functions).toContain("'sop', 'policy'");

    expect(sqlOf(files, "state-machine")).toContain("in_review");
    expect(sqlOf(files, "numbering")).toContain("DOC-{n:5}");
    expect(sqlOf(files, "relations")).toContain("variant_of");
    expect(sqlOf(files, "approvals")).toContain("drive_document_decided");
    expect(sqlOf(files, "acknowledgements")).toContain("effective_version_id");
  });

  it("validates options.control", () => {
    expect(() => render({ types: [] })).toThrow(TypeError);
    expect(() => render({ types: ["Bad Type"] })).toThrow(TypeError);
    expect(() => render({ types: ["sop", "sop"] })).toThrow(TypeError);
    expect(() => render({ types: ["sop"], reviewMonths: 0 })).toThrow(
      TypeError,
    );
    expect(() => render({ types: ["sop"], reviewMonths: 1.5 })).toThrow(
      TypeError,
    );
    expect(() => render({ types: ["sop"], releaseRole: "boss" })).toThrow(
      TypeError,
    );
    expect(() => render({ types: ["sop"], releaseRole: 3 })).toThrow(TypeError);
    expect(() => render("sop" as unknown as Record<string, unknown>)).toThrow(
      TypeError,
    );
  });

  it("renders without acknowledgements, relations and notifications", () => {
    const files = render({ types: ["sop"] }, [
      "drive",
      "versions",
      "approvals",
      "state-machine",
      "numbering",
    ]);

    const functions = sqlOf(files, "drive-files");

    expect(functions).toContain("notify_due_drive_reviews");
    expect(functions).not.toContain("v_claims");
    expect(files.some((file) => file.module === "relations")).toBe(false);
  });

  it("needs numbering, versions, approvals and state-machine", () => {
    expect(() => render({ types: ["sop"] }, ["drive", "versions"])).toThrow(
      /needs the .*numbering/u,
    );
  });
});
