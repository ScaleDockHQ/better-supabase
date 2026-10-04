import { describe, expect, it } from "vitest";

import type { KitsConfig } from "../../../src/config/kits.ts";

import { moduleBody, upgradePlan } from "../../../src/sql/kit.ts";

const body = (kits: KitsConfig) => moduleBody("invitations", { kits })!;

describe("invitations module", () => {
  it("keeps the 0.4 table and create_invitation signature", () => {
    const sql = body({});
    expect(sql).toContain(
      'create table if not exists "better_supabase"."invitations" (',
    );
    expect(sql).toContain(
      'alter table "better_supabase"."invitations" add column if not exists "declined_at" timestamptz;',
    );
    expect(sql).toContain(
      'alter table "better_supabase"."invitations" alter column "org_id" drop not null;',
    );
    expect(sql).toContain(
      'drop function if exists "better_supabase"."create_invitation"(uuid, text, text, interval);',
    );
    expect(sql).toContain(
      `select "better_supabase"."invite_member"($1, $2, $3, $4) ->> 'token'`,
    );
    expect(sql).toContain(
      "check (\"role\" in ('owner', 'admin', 'member', 'viewer'))",
    );
    expect(sql).toContain("hint = 'INVITATION_INVITER_REVOKED'");
    expect(sql).toContain(
      'grant execute on function "better_supabase"."invitation_preview"(text) to anon, authenticated, service_role;',
    );
  });

  it("adopts CentraKit's organization_invitations with plain tokens and system invites", () => {
    const sql = body({
      access: {
        model: "catalog",
        tables: { platformAssignments: "public.user_roles" },
      },
      invitations: {
        mode: "adopt",
        tables: { invitations: "public.organization_invitations" },
        columns: {
          invitations: {
            tenant: "organization_id",
            role: "role_id",
            tokenHash: "token",
            acceptedBy: null,
            revokedAt: null,
          },
        },
        options: {
          tokenStorage: "plain",
          errorCodes: { INVITATION_ALREADY_MEMBER: "P0001" },
          requireConfirmedEmail: false,
        },
      },
    });
    expect(sql).not.toContain("create table if not exists");
    expect(sql).toContain('where i."token" = token\n  for update;');
    expect(sql).not.toContain("extensions.digest(token");
    expect(sql).toContain(
      "using errcode = 'P0001', hint = 'INVITATION_ALREADY_MEMBER'",
    );
    expect(sql).toContain(
      'insert into "public"."user_roles" ("user_id", "role_id")',
    );
    expect(sql).toContain(
      'delete from "public"."organization_invitations" i where i."id" = invitation_id',
    );
    expect(sql).not.toContain("email_confirmed_at is not null");
  });

  it("rejects unknown error codes, bad SQLSTATEs and token storage", () => {
    const options = (value: Record<string, unknown>) => () =>
      body({ invitations: { options: value } });
    expect(options({ errorCodes: { NOPE: "P0001" } })).toThrow(
      /unknown code "NOPE"/,
    );
    expect(options({ errorCodes: { INVITATION_SELF: "x" } })).toThrow(
      /five-character SQLSTATE/,
    );
    expect(options({ tokenStorage: "md5" })).toThrow(/tokenStorage/);
  });

  it("shows organization branding in the preview when organizations is installed", () => {
    const sql = moduleBody("invitations", {
      kits: {
        invitations: { options: { previewColumns: ["name", "logo_path"] } },
      },
    })!;
    expect(sql).toContain(
      "'organization', case when i.\"org_id\" is null then null else jsonb_build_object('id', i.\"org_id\") end",
    );
    const plan = upgradePlan([{ module: "invitations", version: 1 }], {});
    expect(plan.map((step) => step.module)).toContain("invitations");
  });
});
