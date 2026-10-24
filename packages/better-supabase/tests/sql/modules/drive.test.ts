import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { adoptedTables } from "../../../src/sql/adopted-columns.ts";
import { modulePath } from "../../../src/sql/paths.ts";
import {
  ORDER,
  SQL_MODULES,
  resolveBlocks,
} from "../../../src/sql/registry.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (
  modules: readonly string[],
  module: string,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const overApp = (
  modules: AnyBlocksConfig,
  blocks?: readonly string[],
): Layout => ({ modules, ownTables: ownTablesOf(modules, blocks) });

const withOptions = (options: Record<string, unknown>): Layout => ({
  modules: { drive: { options } },
});

const APP_MODULES = {
  drive: {
    tables: { nodes: "public.file_node", grants: "public.file_node_grant" },
    columns: {
      nodes: {
        tenant: "organization_id",
        attachment: null,
        path: null,
        rank: null,
        deletedAt: null,
      },
      grants: {
        tenant: "organization_id",
        node: "file_node_id",
        principalType: null,
        principalId: null,
        user: "user_id",
        team: "team_id",
        expiresAt: null,
        createdBy: null,
      },
    },
    options: { roles: ["viewer", "commenter", "editor"] },
  },
};

const APP_DRIVE: Layout = {
  modules: APP_MODULES,
  ownTables: ownTablesOf(APP_MODULES),
};

describe("drive module", () => {
  it("renders ahead of comments and keeps the later file numbers", () => {
    const names = resolveBlocks(["drive", "comments"]).map(
      (module) => module.name,
    );

    expect(names.indexOf("drive")).toBeLessThan(names.indexOf("comments"));
    expect(names.indexOf("drive-files")).toBeGreaterThan(
      names.indexOf("attachments"),
    );
    const drive = SQL_MODULES["drive"];
    const comments = SQL_MODULES["comments"];

    if (drive === undefined || comments === undefined) {
      throw new Error("missing");
    }

    const number = (path: string): number =>
      Number(/_(\d+)_[a-z_]+\.sql$/.exec(path)?.[1]);

    expect(number(modulePath(drive, {}))).toBe(
      number(modulePath(comments, {})) - 1,
    );
    expect(ORDER.at(-1)).toBe("rls-guard");
  });

  it("creates the node and grant tables and links files to attachments", () => {
    const core = sqlOf(["drive"], "drive");
    expect(core).toContain(
      `create table if not exists "better_supabase"."drive_nodes"`,
    );
    expect(core).toContain(
      `create table if not exists "better_supabase"."drive_grants"`,
    );
    expect(core).toContain("drive_subtree");
    expect(core).toContain("DRIVE_NAME_CONFLICT");
    const files = sqlOf(["drive"], "drive-files");
    expect(files).toContain("bsb_drive_nodes_attachment");
    expect(files).toContain("drive_create_file");
    expect(files).toContain("drive_commit");
    expect(files).toContain("as restrictive");
    expect(files).toContain("raise_actor_readonly");
  });

  it("uses versions, trash and share links when they are installed", () => {
    const alone = sqlOf(["drive"], "drive-files");
    expect(alone).not.toContain("version_insert");
    expect(alone).not.toContain("trash_cascade");

    const layout: Layout = {
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

    const full = sqlOf(
      ["drive", "versions", "trash", "share-links", "teams"],
      "drive-files",
      layout,
    );

    expect(full).toContain("version_insert");
    expect(full).toContain("trash_cascade");
    expect(full).toContain("trash_restore_batch");
  });

  it("runs over the app's node table without files and untyped user and team grants", () => {
    const names = resolveBlocks(["drive"], APP_DRIVE).map(
      (module) => module.name,
    );

    expect(names).not.toContain("attachments");
    const core = sqlOf(["drive"], "drive", APP_DRIVE);
    expect(core).not.toContain(`create table if not exists "public"`);
    expect(core).toContain(`"public"."file_node"`);
    expect(core).toContain(`"user_id"`);
    expect(core).toContain(`"team_id"`);
    expect(core).toContain("array['viewer', 'commenter', 'editor']::text[]");
    const files = sqlOf(["drive"], "drive-files", APP_DRIVE);
    expect(files).not.toContain("drive_create_file");
    expect(files).not.toContain("storage.objects");
  });

  it("needs a principal or a user column on grants", () => {
    expect(() =>
      sqlOf(
        ["drive"],
        "drive",
        overApp({
          drive: {
            columns: {
              grants: { principalType: null, principalId: null, user: null },
            },
          },
        }),
      ),
    ).toThrow(/columns\.grants/);
  });

  it("validates its options", () => {
    const fails =
      (options: Record<string, unknown>): (() => string) =>
      () =>
        sqlOf(["drive"], "drive", withOptions(options));

    expect(fails({ roles: [] })).toThrow(/options\.roles/);
    expect(fails({ roles: ["viewer", "viewer"] })).toThrow(/options\.roles/);
    expect(fails({ roles: ["Viewer"] })).toThrow(/options\.roles/);
    expect(fails({ writeRole: "admin" })).toThrow(/writeRole/);
    expect(fails({ memberRole: "admin" })).toThrow(/memberRole/);
    expect(fails({ subjectType: "Drive Node" })).toThrow(/subjectType/);
    expect(fails({ conflict: "skip" })).toThrow(/conflict/);
    expect(
      sqlOf(
        ["drive", "outbox"],
        "drive",
        withOptions({ subjectType: "file_node" }),
      ),
    ).toContain("'subjectType', 'file_node'");
  });

  it("installs neither part in custom mode", () => {
    const custom: Layout = { modules: { drive: { mode: "custom" } } };

    const names = resolveBlocks(["drive"], custom).map((module) => module.name);

    expect(names).not.toContain("drive-files");
    expect(names).not.toContain("attachments");
    expect(
      renderBlocks(["drive"], custom).some((file) =>
        file.module.startsWith("drive"),
      ),
    ).toBe(false);
  });

  it("lists the functions a custom drive provides", () => {
    const core = customContracts(["drive"], {
      modules: { drive: { mode: "custom" } },
    });

    expect(core.map((entry) => entry.module)).toEqual(["drive"]);
    expect(core[0]?.functions.map((fn) => fn.name)).toContain("drive_share");

    const files = customContracts(["drive"], {
      modules: { "drive-files": { mode: "custom" } },
    });

    expect(
      files
        .find((entry) => entry.module === "drive-files")
        ?.functions.map((fn) => fn.name),
    ).toEqual(["drive_create_file", "drive_commit"]);

    const noAttachment = customContracts(
      ["drive"],
      overApp(
        {
          drive: { columns: { nodes: { attachment: null } } },
          "drive-files": { mode: "custom" },
        },
        ["drive"],
      ),
    );

    expect(noAttachment.map((entry) => entry.functions)).toEqual([[]]);
  });

  it("checks only the grant columns the app's table uses", () => {
    const user = adoptedTables(APP_MODULES, APP_DRIVE.ownTables).find(
      (table) => table.logical === "grants",
    );

    expect(user?.columns).toMatchObject({ user: "user_id", team: "team_id" });

    const typedModules = {
      drive: { columns: { grants: { user: null, team: null } } },
    };

    const typed = adoptedTables(typedModules, ownTablesOf(typedModules)).find(
      (table) => table.logical === "grants",
    );

    expect(typed?.columns).toHaveProperty("principalType");
    expect(typed?.columns).not.toHaveProperty("user");
  });

  it("copies extra columns from the parent folder", () => {
    const core = sqlOf(
      ["drive"],
      "drive",
      withOptions({ extraColumns: { project_id: "uuid" } }),
    );

    expect(core).toContain(`'fields'`);
    expect(core).toContain(
      `coalesce(v_fields."project_id", v_parent."project_id")`,
    );
  });
});
