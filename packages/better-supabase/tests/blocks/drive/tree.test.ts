import { describe, expect, it } from "vitest";

import type { DriveNode } from "../../../src/blocks/drive/index.ts";

import {
  DRIVE_ROOT,
  driveTree,
  fileTypeCategory,
  nodeType,
} from "../../../src/blocks/drive/index.ts";

const node = (
  id: string,
  parentId: string | null,
  kind: DriveNode["kind"],
  name: string,
  mimeType?: string,
): DriveNode => ({
  id,
  organizationId: "o",
  parentId,
  kind,
  name,
  rank: undefined,
  createdBy: undefined,
  createdAt: Temporal.Instant.from("2026-10-01T00:00:00Z"),
  updatedAt: undefined,
  deletedAt: undefined,
  attachmentId: undefined,
  file:
    mimeType === undefined
      ? undefined
      : { mimeType, size: 1, status: "clean", uploadedAt: undefined },
  fields: {},
  role: undefined,
  starredAt: undefined,
  openedAt: undefined,
});

describe("fileTypeCategory", () => {
  it("reads the MIME type, then the extension", () => {
    expect(fileTypeCategory("image/png", "a.png")).toBe("image");
    expect(fileTypeCategory("video/mp4")).toBe("video");
    expect(fileTypeCategory("audio/mpeg")).toBe("audio");
    expect(fileTypeCategory("application/pdf; charset=binary")).toBe("pdf");
    expect(
      fileTypeCategory(
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      ),
    ).toBe("spreadsheet");
    expect(fileTypeCategory("application/vnd.ms-powerpoint")).toBe(
      "presentation",
    );
    expect(fileTypeCategory("application/msword")).toBe("document");
    expect(fileTypeCategory("application/zip")).toBe("archive");
    expect(fileTypeCategory("application/json")).toBe("code");
    expect(fileTypeCategory("text/plain", "notes.txt")).toBe("text");
    expect(fileTypeCategory("text/plain", "query.sql")).toBe("code");
    expect(fileTypeCategory("text/csv", "rows.csv")).toBe("spreadsheet");
    expect(fileTypeCategory("inode/directory")).toBe("folder");
    expect(fileTypeCategory("application/octet-stream", "deck.KEY")).toBe(
      "presentation",
    );
    expect(fileTypeCategory(undefined, "archive.7z")).toBe("archive");
    expect(fileTypeCategory(undefined, "README")).toBe("other");
    expect(fileTypeCategory("application/x-unknown", "a.bin")).toBe("other");
    expect(fileTypeCategory("application/x-unknown", "a.md")).toBe("text");
  });

  it("names folders and files", () => {
    expect(nodeType(node("f", null, "folder", "Docs"))).toBe("folder");
    expect(nodeType(node("n", null, "file", "a.pdf", "application/pdf"))).toBe(
      "pdf",
    );
    expect(nodeType(node("n", null, "file", "a.ts"))).toBe("code");
  });
});

describe("driveTree", () => {
  const nodes = [
    node("f1", null, "folder", "Projects"),
    node("n1", "f1", "file", "plan.pdf"),
    node("f2", "f1", "folder", "Launch"),
    node("n2", null, "file", "notes.txt"),
  ];

  it("groups loaded nodes under the root and their folders", () => {
    const tree = driveTree(nodes);
    expect(tree.rootItemId).toBe(DRIVE_ROOT);
    expect(tree.getChildren(DRIVE_ROOT)).toEqual(["f1", "n2"]);
    expect(tree.getChildren("f1")).toEqual(["n1", "f2"]);
    expect(tree.getChildren("f2")).toEqual([]);
    expect(tree.isFolder(DRIVE_ROOT)).toBe(true);
    expect(tree.isFolder("f2")).toBe(true);
    expect(tree.isFolder("n1")).toBe(false);
    expect(tree.name("f1")).toBe("Projects");
    expect(tree.name("missing")).toBe("");
    expect(tree.getItem("n1")?.name).toBe("plan.pdf");
    tree.getChildren("f1").push("x");
    expect(tree.getChildren("f1")).toEqual(["n1", "f2"]);
  });

  it("roots the tree at a folder", () => {
    const tree = driveTree(nodes.slice(1, 3), "f1");
    expect(tree.rootItemId).toBe("f1");
    expect(tree.getChildren("f1")).toEqual(["n1", "f2"]);
    expect(tree.isFolder("f1")).toBe(true);
  });
});
