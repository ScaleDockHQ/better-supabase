import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const LAYOUT: Layout = {
  subjects: {
    drive_node: {
      table: "better_supabase.drive_nodes",
      idType: "uuid",
      tenant: "tenant_id",
      title: "name",
      deletedAt: "deleted_at",
      permissions: { read: "drive.read", write: "drive.manage" },
    },
  },
};

const sqlOf = (modules: readonly string[]): string =>
  renderBlocks(modules, LAYOUT)
    .filter((file) => file.module === "drive-files")
    .map((file) => file.contents)
    .join("\n");

const BASE = ["drive", "versions", "trash", "share-links", "teams"] as const;

describe("drive retention per label and the changes feed", () => {
  it("renders the sweep with labels, the bin and data-lifecycle", () => {
    const sql = sqlOf([...BASE, "tags", "data-lifecycle"]);

    expect(sql).toContain("drive_retention_kind");
    expect(sql).toContain("drive_retention_sweep");
    expect(sql).toContain("retention_for");
    expect(sql).toContain("is_held");
    expect(sql).toContain("drive_trash");
  });

  it("renders no sweep without data-lifecycle or without labels", () => {
    expect(sqlOf([...BASE, "tags"])).not.toContain("drive_retention_sweep");
    expect(sqlOf([...BASE, "data-lifecycle"])).not.toContain(
      "drive_retention_sweep",
    );
  });

  it("renders the changes feed and the bin touch trigger", () => {
    const sql = sqlOf(BASE);

    expect(sql).toContain("drive_changes");
    expect(sql).toContain("drive_node_bin_touch");
    expect(sql).toContain("DRIVE_CURSOR_INVALID");
  });
});
