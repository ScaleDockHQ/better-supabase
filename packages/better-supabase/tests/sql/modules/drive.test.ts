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
import { moduleProvider } from "../../fixtures/authorization-provider.ts";
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

const managed = (config: Record<string, unknown>): Layout => ({
  modules: { drive: config },
});

const APP_MODULES = {
  drive: {
    tables: { nodes: "public.file_node", grants: "public.file_node_grant" },
    columns: {
      nodes: {
        tenant: "organization_id",
        drive: null,
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

const DRIVE_APP_MODULES = {
  drive: {
    tables: {
      nodes: "public.file_nodes",
      grants: "public.file_node_grants",
      drives: "public.file_drives",
      driveGrants: "public.file_drive_grants",
      connections: "public.file_drive_connections",
    },
    columns: {
      nodes: {
        tenant: "organization_id",
        drive: "drive_id",
        attachment: null,
        path: null,
        rank: null,
        deletedAt: "deleted_at",
        legalHoldUntil: null,
      },
      grants: {
        tenant: "organization_id",
        node: "node_id",
        principalType: null,
        principalId: null,
        user: "user_id",
        team: "team_id",
        expiresAt: "expires_at",
        createdBy: "created_by",
      },
      driveGrants: {
        tenant: "organization_id",
        drive: "drive_id",
        principalType: null,
        principalId: null,
        user: "user_id",
        team: "team_id",
        expiresAt: "expires_at",
        createdBy: "created_by",
      },
      drives: {
        tenant: "organization_id",
        kind: "drive_type",
        owner: "owner_user_id",
        connection: "connection_id",
        createdBy: "created_by",
        updatedAt: "updated_at",
      },
      connections: {
        tenant: "organization_id",
        user: "user_id",
        provider: "provider",
        name: "name",
        status: "status",
        syncCursor: "sync_cursor",
        lastSyncedAt: "last_synced_at",
        lastSyncError: "last_sync_error",
        createdBy: "created_by",
        updatedAt: "updated_at",
      },
    },
    options: { drives: true, roles: ["viewer", "commenter", "editor"] },
  },
};

const DRIVE_APP: Layout = {
  modules: DRIVE_APP_MODULES,
  ownTables: ownTablesOf(DRIVE_APP_MODULES),
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

  it("keeps extracted text per file and a search view over it", () => {
    const core = sqlOf(["drive"], "drive");
    expect(core).toContain(
      `create table if not exists "better_supabase"."drive_node_texts"`,
    );
    expect(core).toContain(
      `"node_id" uuid primary key references "better_supabase"."drive_nodes" ("id") on delete cascade`,
    );
    expect(core).toContain("drive_node_texts_read");
    expect(core).toContain(
      `create or replace view "better_supabase"."drive_node_search" with (security_invoker = true)`,
    );
    expect(core).toContain(`left(t."content", 100000) as content`);

    const files = sqlOf(["drive"], "drive-files");
    expect(files).toContain("drive_text_source");
    expect(files).toContain("octet_length(v_content) > 1048576");
    expect(
      sqlOf(["drive"], "drive-files", withOptions({ maxTextBytes: 4096 })),
    ).toContain("octet_length(v_content) > 4096");
    expect(files).toContain(
      'revoke execute on function "better_supabase"."drive_set_text"(uuid, uuid, text, text) from public, anon, authenticated;',
    );
    expect(() =>
      sqlOf(["drive"], "drive-files", withOptions({ maxTextBytes: 10 })),
    ).toThrow(/maxTextBytes/);
  });

  it("searches a node's name alone without file content", () => {
    const core = sqlOf(["drive"], "drive", APP_DRIVE);

    expect(core).toContain("null::text as content");
    expect(core).not.toContain("drive_node_texts");
    expect(sqlOf(["drive"], "drive-files", APP_DRIVE)).not.toContain(
      "drive_set_text",
    );
  });

  it("checks the usage quota before an upload when one is set", () => {
    expect(sqlOf(["drive", "usage"], "drive-files")).not.toContain(
      "DRIVE_QUOTA_EXCEEDED",
    );

    const files = sqlOf(
      ["drive", "usage"],
      "drive-files",
      withOptions({ quota: { meter: "storage" } }),
    );

    expect(files.match(/DRIVE_QUOTA_EXCEEDED/g)).toHaveLength(2);
    expect(files).toContain(
      `"within_quota"(drive_create_file.tenant, 'storage', greatest(coalesce(drive_create_file.size, 0), 0))`,
    );
    expect(files).toContain(`errcode = '53400'`);
    expect(files).toContain(`detail = '{"meter":"storage"}'`);
    expect(() =>
      sqlOf(
        ["drive"],
        "drive-files",
        withOptions({ quota: { meter: "storage" } }),
      ),
    ).toThrow(/usage block/);
    expect(() =>
      sqlOf(
        ["drive", "usage"],
        "drive-files",
        withOptions({ quota: { meter: "Storage" } }),
      ),
    ).toThrow(/quota/);
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

  it("lets the upload role add files to a folder it can't read", () => {
    const modules = [
      "drive",
      "attachments",
      "share-links",
      "rate-limit",
    ] as const;

    const plain = sqlOf(modules, "drive") + sqlOf(modules, "drive-files");

    expect(plain).toContain("drive_can_upload");
    expect(plain).not.toContain("drive_uploaded_own");
    expect(plain).toContain("drive_request_files");
    expect(plain).toContain("drive_link_upload");
    expect(plain).toContain("'drive_link_upload'");

    const layout = withOptions({ uploadRole: "contributor" });
    const core = sqlOf(modules, "drive", layout);
    const files = sqlOf(modules, "drive-files", layout);

    expect(core).toContain("array['viewer', 'editor', 'owner', 'contributor']");
    expect(core).toContain("'the upload role is for folders'");
    expect(core).toContain("drive_uploaded_own");
    expect(files).toContain("{ id, attachment } and no node");
    expect(files).toContain("'committed', true");
    expect(files).toContain("drive_uploaded_own");

    const unlimited = sqlOf(
      ["drive", "attachments", "share-links"],
      "drive-files",
      layout,
    );

    expect(unlimited).toContain("drive_link_upload");
    expect(unlimited).not.toContain("hit_rate_limit");
    expect(sqlOf(["drive"], "drive-files", layout)).not.toContain(
      "drive_link_upload",
    );
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

  it("keeps a mapped drive column when drives are off", () => {
    const mapped = {
      drive: {
        tables: {
          nodes: "public.file_nodes",
          grants: "public.file_node_grants",
        },
        columns: {
          nodes: {
            tenant: "organization_id",
            drive: "drive_id",
            attachment: null,
            path: null,
            rank: null,
            deletedAt: null,
            legalHoldUntil: null,
          },
          grants: {
            tenant: "organization_id",
            node: "node_id",
            principalType: null,
            principalId: null,
            user: "user_id",
            team: "team_id",
            expiresAt: null,
            createdBy: null,
          },
        },
      },
    };

    const core = sqlOf(["drive"], "drive", overApp(mapped));

    expect(core).toContain(
      `insert into "public"."file_nodes" ("organization_id", "drive_id"`,
    );
    expect(core).toContain(`'driveId', ($1)."drive_id"`);
    expect(core).toContain(`v_drive := v_parent."drive_id"`);
    expect(core).toContain(`and x."drive_id" = drive_free_name.drive`);
  });

  it("shares drives through user and team columns", () => {
    const core = sqlOf(["drive"], "drive", DRIVE_APP);

    expect(core).toContain(
      `insert into "public"."file_drive_grants" ("organization_id", "drive_id", "user_id", "team_id", "role"`,
    );
    expect(core).toContain(
      `case when dg."user_id" is not null then 'user' else 'team' end = v_type`,
    );
    expect(core).toContain(
      `coalesce(dg."user_id"::text, dg."team_id"::text) = drive_share_drive.principal_id`,
    );
    expect(core).toContain(
      `jsonb_build_object('id', dg."id", 'driveId', dg."drive_id", 'principalType', case when dg."user_id" is not null then 'user' else 'team' end`,
    );
    expect(core).toContain(`dg."user_id" = v_uid or (dg."team_id" is not null`);
    expect(core).not.toContain(`"principal_type" text not null`);
  });

  it("matches drive grants through their own columns", () => {
    const modules = {
      drive: {
        ...DRIVE_APP_MODULES.drive,
        columns: {
          ...DRIVE_APP_MODULES.drive.columns,
          grants: {
            ...DRIVE_APP_MODULES.drive.columns.grants,
            user: "node_user_id",
            team: "node_team_id",
          },
          driveGrants: {
            ...DRIVE_APP_MODULES.drive.columns.driveGrants,
            user: "drive_user_id",
            team: "drive_team_id",
          },
        },
      },
    };

    const core = sqlOf(["drive"], "drive", overApp(modules));

    const functionSql = (name: string): string => {
      const at = core.indexOf(
        `create or replace function "better_supabase"."${name}"`,
      );

      return core.slice(at, core.indexOf("$$;", at));
    };

    const driveRole = functionSql("drive_drive_role");
    const nodeRole = functionSql("drive_role");
    const driveReadable = functionSql("drive_drive_readable_ids");
    const nodeReadable = functionSql("drive_readable_ids");

    expect(driveRole).toContain(`dg."drive_user_id" = v_uid`);
    expect(driveRole).toContain(`dg."drive_team_id" is not null`);
    expect(driveRole).not.toContain(`dg."node_user_id"`);
    expect(nodeRole).toContain(`dg."node_user_id" = v_uid`);
    expect(nodeRole).not.toContain(`dg."drive_user_id"`);
    expect(driveReadable).toContain(`dg."drive_user_id" = auth.uid()`);
    expect(driveReadable).not.toContain(`dg."node_user_id"`);
    expect(nodeReadable).toContain(`dg."node_user_id" = auth.uid()`);
    expect(nodeReadable).toContain(`dg."drive_user_id" = auth.uid()`);
  });

  it("creates drive grants with user and team columns when the app has none", () => {
    const core = sqlOf(
      ["drive"],
      "drive",
      managed({
        options: { drives: true },
        columns: {
          driveGrants: {
            principalType: null,
            principalId: null,
            user: "user_id",
            team: "team_id",
          },
        },
      }),
    );

    expect(core).toContain(
      `create table if not exists "better_supabase"."drive_drive_grants"`,
    );
    expect(core).toContain(`"user_id" uuid`);
    expect(core).toContain(`"team_id" uuid`);
    expect(core).toContain(
      `check (("user_id" is not null)::int + ("team_id" is not null)::int = 1)`,
    );
  });

  it("asks the app's role functions for a node or drive role", () => {
    const core = sqlOf(
      ["drive"],
      "drive",
      withOptions({
        drives: true,
        roleFunctions: {
          node: "public.file_node_role",
          drive: "public.file_drive_role",
        },
      }),
    );

    expect(core).toContain(`"public"."file_node_role"(drive_role.node, v_uid)`);
    expect(core).toContain(
      `"public"."file_drive_role"(drive_drive_role.drive, v_uid)`,
    );
    expect(core).toContain(`"public"."file_node_role"(x."id", auth.uid())`);
    expect(core).toContain(`"public"."file_drive_role"(d."id", auth.uid())`);
    expect(core).not.toContain(
      "if drive_insert_node.parent is null and auth.uid() is not null then",
    );
    expect(sqlOf(["drive"], "drive")).toContain(
      "if drive_insert_node.parent is null and auth.uid() is not null then",
    );
  });

  it("holds a node under a held folder", () => {
    expect(sqlOf(["drive"], "drive")).toContain(
      `or h."id" = any ("better_supabase"."drive_ancestors"(drive_node_held.node)))`,
    );
  });

  it("maps the provider's row grants to node and drive roles", () => {
    const layout: Layout = {
      modules: {
        permissions: { model: "provider" },
        drive: {
          options: {
            drives: true,
            roleFunctions: {
              node: {
                rows: "file_node",
                roles: { viewer: "fileNode.read", editor: "fileNode.update" },
              },
              drive: { rows: "drive", roles: { owner: "drive.manage" } },
            },
          },
        },
      },
      accessProvider: {
        ...moduleProvider,
        functions: {
          ...moduleProvider.functions,
          rowsWith: "authz.rows_{resource}({permission}, {ids})",
        },
      },
    };

    const core = sqlOf(["drive"], "drive", layout);

    expect(core).toContain(
      "return (select r from (select case when (v_uid = auth.uid() and drive_role.node::text in (select r.id::text from authz.rows_file_node('fileNode.update', array[drive_role.node::text]) as r(id))) then 'editor' when (v_uid = auth.uid() and drive_role.node::text in (select r.id::text from authz.rows_file_node('fileNode.read', array[drive_role.node::text]) as r(id))) then 'viewer' end) x(r)",
    );
    expect(core).toContain(
      "authz.rows_drive('drive.manage', array[drive_drive_role.drive::text])",
    );
    expect(core).toContain(
      `authz.rows_file_node('fileNode.read', array[x."id"::text])`,
    );

    const fails = (roles: unknown) => () =>
      sqlOf(["drive"], "drive", {
        ...layout,
        modules: {
          ...layout.modules,
          drive: {
            options: { roleFunctions: { node: { rows: "file_node", roles } } },
          },
        },
      });

    expect(fails({ admin: "x" })).toThrow(/rows, roles/u);
    expect(fails({})).toThrow(/rows, roles/u);
    expect(() =>
      sqlOf(
        ["drive"],
        "drive",
        withOptions({
          roleFunctions: {
            node: { rows: "file_node", roles: { viewer: "x" } },
          },
        }),
      ),
    ).toThrow(/rowsWith/u);
  });

  it("can leave read policies to the app", () => {
    const core = sqlOf(["drive"], "drive", withOptions({ readPolicy: false }));

    const full = sqlOf(
      ["drive"],
      "drive",
      withOptions({ drives: true, readPolicy: false }),
    );

    expect(core).not.toContain("drive_nodes_read");
    expect(core).not.toContain("drive_drives_read");
    expect(core).not.toContain("drive_drive_grants_read");
    expect(full).not.toContain("drive_nodes_read");
    expect(full).not.toContain("drive_drives_read");
    expect(full).not.toContain("drive_drive_grants_read");
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
    expect(fails({ drives: true, driveKinds: [] })).toThrow(/driveKinds/);
    expect(fails({ drives: true, driveKinds: ["shared", "shared"] })).toThrow(
      /driveKinds/,
    );
    expect(fails({ drives: true, driveKinds: ["Shared"] })).toThrow(
      /driveKinds/,
    );
    expect(fails({ drives: true, sources: [] })).toThrow(/sources/);
    expect(fails({ drives: true, sources: ["internal"] })).toThrow(/sources/);
    expect(fails({ drives: true, sources: ["request"] })).toThrow(/sources/);
    expect(fails({ uploadRole: 3 })).toThrow(/uploadRole/);
    expect(fails({ uploadRole: "Contributor" })).toThrow(/uploadRole/);
    expect(fails({ uploadRole: "viewer" })).toThrow(/uploadRole/);
    expect(() =>
      sqlOf(
        ["drive"],
        "drive",
        managed({
          options: { uploadRole: "contributor" },
          columns: { nodes: { createdBy: null } },
        }),
      ),
    ).toThrow(/uploadRole needs blocks\.drive\.columns\.nodes\.createdBy/);
    expect(fails({ drives: true, sources: ["Google Drive"] })).toThrow(
      /sources/,
    );
    expect(fails({ roleFunctions: "public.fn" })).toThrow(/roleFunctions/);
    expect(fails({ roleFunctions: { node: "file_node_role" } })).toThrow(
      /roleFunctions/,
    );
    expect(fails({ roleFunctions: { drive: "public.fn" } })).toThrow(
      /roleFunctions\.drive/,
    );
    expect(() =>
      sqlOf(
        ["drive"],
        "drive",
        managed({
          options: { drives: true },
          columns: {
            driveGrants: {
              principalType: null,
              principalId: null,
              user: null,
              team: null,
            },
          },
        }),
      ),
    ).toThrow(/driveGrants/);
    expect(
      sqlOf(
        ["drive", "outbox"],
        "drive",
        withOptions({ subjectType: "file_node" }),
      ),
    ).toContain("'subjectType', 'file_node'");
  });

  it("adds drives, drive grants and connections when drives are on", () => {
    const core = sqlOf(["drive"], "drive", withOptions({ drives: true }));

    expect(core).toContain(
      `create table if not exists "better_supabase"."drive_drives"`,
    );
    expect(core).toContain(
      `create table if not exists "better_supabase"."drive_drive_grants"`,
    );
    expect(core).toContain(
      `create table if not exists "better_supabase"."drive_connections"`,
    );
    expect(core).toContain("drive_create_drive");
    expect(core).toContain("drive_sync_batch");
    expect(core).toContain("drive_hold");

    const single = sqlOf(["drive"], "drive");
    expect(single).not.toContain("drive_drives");
    expect(single).not.toContain("drive_create_drive");
    expect(single).toContain("drive_hold");
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
