import { describe, expect, it } from "vitest";

import { emitRecords } from "../../../src/cli/gen/records.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";

function config(extra: Record<string, unknown> = {}) {
  return resolveConfig(
    {
      records: {
        customer: { table: "customers" },
        project: {
          table: "projects",
          versions: { columns: ["name"], auto: true },
        },
        country: { table: "countries", tenant: false },
      },
      blocks: {
        memberships: {},
        permissions: {},
        comments: {},
        tags: {},
        versions: {},
        sla: {},
      },
      ...extra,
    },
    "/project",
  );
}

function contents(files: readonly { path: string; contents: string }[]) {
  return Object.fromEntries(files.map((file) => [file.path, file.contents]));
}

const CUSTOMER = "src/lib/supabase/records/customer.ts";
const PROJECT = "src/lib/supabase/records/project.ts";

describe("record types", () => {
  it("writes one file per record type with each block that serves it", () => {
    const files = contents(emitRecords(config()));

    expect(Object.keys(files).toSorted()).toEqual([
      CUSTOMER,
      "src/lib/supabase/records/index.ts",
      PROJECT,
    ]);

    expect(files[CUSTOMER]).toContain("    sla: slaBlock,");
    expect(files[CUSTOMER]).not.toContain("versions");
    expect(files[PROJECT]).toContain("    versions: versionsBlock,");
    expect(files[PROJECT]).toContain("    sla: slaBlock,");
  });

  it("matches the golden record type and index", () => {
    const files = contents(emitRecords(config()));

    expect(files[CUSTOMER]).toMatchSnapshot("record type");
    expect(files["src/lib/supabase/records/index.ts"]).toMatchSnapshot("index");
  });

  it("writes nothing with recordTypes: false or without binding blocks", () => {
    expect(emitRecords(config({ recordTypes: false }))).toEqual([]);

    const bare = resolveConfig(
      {
        records: { customer: { table: "customers" } },
        blocks: { memberships: {}, permissions: {} },
      },
      "/project",
    );

    expect(emitRecords(bare)).toEqual([]);
  });

  it("adds a block when it is installed", () => {
    const before = contents(emitRecords(config()));

    const after = contents(
      emitRecords(
        config({
          blocks: {
            memberships: {},
            permissions: {},
            comments: {},
            tags: {},
            versions: {},
            sla: {},
            "share-links": {},
          },
        }),
      ),
    );

    expect(before[CUSTOMER]).not.toContain("shareLinks");
    expect(after[CUSTOMER]).toContain("    shareLinks: shareLinksBlock,");
  });

  it("renders the same files twice", () => {
    expect(emitRecords(config())).toEqual(emitRecords(config()));
  });

  it("follows blocks.<instance>.on", () => {
    const files = emitRecords(
      config({ blocks: { memberships: {}, tags: { on: ["project"] } } }),
    ).map((file) => file.path);

    expect(files).toContain(PROJECT);
    expect(files).not.toContain(CUSTOMER);
  });
});
