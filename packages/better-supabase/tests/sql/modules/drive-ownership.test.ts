import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";

import { driveSubject } from "../../../src/blocks/drive/index.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (
  blocks: readonly string[],
  module: string,
  layout: Layout = {},
): string =>
  renderBlocks(blocks, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const REQUESTS: SubjectsConfig = {
  drive_node: driveSubject({ accessRequests: true }),
};

const WITH_REQUESTS = ["drive", "access-requests", "subjects", "notifications"];

describe("drive access requests", () => {
  it("grants the requested role on the node until the request ends", () => {
    const sql = sqlOf(["drive"], "drive");

    expect(sql).toContain(
      `create or replace function "better_supabase"."drive_grant_access"(subject_id text, user_id uuid, action text, ends_at timestamptz)`,
    );
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."drive_grant_access"(text, uuid, text, timestamptz) from public, anon, authenticated;`,
    );
    expect(sql).toContain(`"access_request" boolean not null default false,`);
    expect(sql).toContain(
      `add column if not exists "access_request" boolean not null default false;`,
    );
    expect(sql).toContain(
      `create or replace function "better_supabase"."drive_access_approvers"(subject_id text)`,
    );
    expect(sql).toContain(`and dg."access_request";`);
  });

  it("asks the node's sharers through access-requests", () => {
    const sql = sqlOf(WITH_REQUESTS, "access-requests", { subjects: REQUESTS });

    expect(sql).toContain("'drive_node'");
    expect(sql).toContain(`"better_supabase"."drive_grant_access"`);
    expect(sql).toContain(`"better_supabase"."drive_access_approvers"(`);
    expect(sql).toContain(
      `create or replace function "better_supabase"."list_record_access_requests"(subject_type text, subject_id text, status text default null, page_size integer default null)`,
    );
  });

  it("contributes nothing without a team on the drive subject", () => {
    const sql = sqlOf(WITH_REQUESTS, "access-requests", {
      subjects: { drive_node: driveSubject() },
    });

    expect(sql).not.toContain("drive_grant_access");
  });

  it("needs grants to decide access", () => {
    expect(() =>
      sqlOf(WITH_REQUESTS, "access-requests", {
        subjects: REQUESTS,
        modules: {
          drive: { options: { roleFunctions: { node: "public.node_role" } } },
        },
      }),
    ).toThrow("not blocks.drive.options.roleFunctions.node");

    const modules = {
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
      },
    };

    expect(() =>
      sqlOf(WITH_REQUESTS, "access-requests", {
        subjects: {
          drive_node: driveSubject({
            schema: "public",
            table: "file_node",
            tenant: "organization_id",
            accessRequests: true,
          }),
        },
        modules,
        ownTables: ownTablesOf(modules),
      }),
    ).toThrow("blocks.drive.columns.grants.accessRequest and expiresAt");
  });
});

describe("drive ownership transfer", () => {
  it("moves the top-role grants and the drives a member owns", () => {
    const sql = sqlOf(["drive"], "drive", {
      modules: { drive: { options: { drives: true } } },
    });

    expect(sql).toContain(
      `create or replace function "better_supabase"."drive_transfer_ownership"(tenant uuid, from_user uuid, to_user uuid)`,
    );
    expect(sql).toContain("DRIVE_TRANSFER_INVALID");
    expect(sql).toContain("'nodes', v_nodes, 'drives', v_drives");
    expect(sql).toContain("with moved as (");
  });
});

describe("drive sharing policy", () => {
  it("renders nothing without the settings block", () => {
    const blocks = ["drive", "share-links", "guests"];

    expect(sqlOf(blocks, "drive")).not.toContain("drive_sharing");
    expect(sqlOf(blocks, "drive-files")).not.toContain("drive_sharing");
  });

  it("checks links and guest grants against drive.sharing", () => {
    const blocks = ["drive", "settings", "share-links", "guests"];
    const sql = sqlOf(blocks, "drive");
    const files = sqlOf(blocks, "drive-files");

    expect(sql).toContain(
      `create or replace function "better_supabase"."drive_sharing"(tenant uuid)`,
    );
    expect(sql).toContain(`'{"guests": true, "links": "anyone"}'::jsonb`);
    expect(files).toContain("this organization has turned off share links");
    expect(files).toContain(
      "sign in as a member of this organization to open this link",
    );
    expect(files).toContain(
      `create or replace function "better_supabase"."drive_guest_sharing"()`,
    );
    expect(files).toContain(
      "this organization has turned off sharing drive items with guests",
    );
  });
});
