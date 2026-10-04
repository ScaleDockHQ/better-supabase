import { describe, expect, it } from "vitest";

import type { KitsConfig } from "../../../src/config/kits.ts";

import { moduleBody, renderKit, upgradePlan } from "../../../src/sql/kit.ts";

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
      'alter table "better_supabase"."invitations" alter column "organization_id" set not null;',
    );
    expect(sql).not.toContain('"prefill" jsonb');
    expect(sql).not.toContain("platform_invitations");
    expect(sql).toContain("valid_for > '30 days'::interval");
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
        tables: {
          invitations: "public.organization_invitations",
          platformInvitations: "public.organization_invitations",
        },
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
          requireConfirmedEmail: false,
        },
      },
    });
    expect(sql).not.toContain("create table if not exists");
    expect(sql).not.toContain("extensions.digest(token");
    expect(sql).toContain(
      "using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER'",
    );
    expect(sql).toContain(
      'insert into "public"."user_roles" ("user_id", "role_id")',
    );
    expect(sql).toContain(
      'delete from "public"."organization_invitations" i where i."id" = invitation_id',
    );
    expect(sql).not.toContain("email_confirmed_at is not null");
    expect(sql).toContain(
      `where i."token" = token and i."organization_id" is null\n  for update;`,
    );
    expect(sql).toContain(
      `where i."token" = token and i."organization_id" is not null\n  for update;`,
    );
  });

  it("keeps platform invitations in their own table, under a role ceiling", () => {
    const sql = body({
      access: { model: "catalog" },
      invitations: { options: { prefill: true, maxValidFor: "14 days" } },
    });
    expect(sql).toContain(
      'create table if not exists "better_supabase"."platform_invitations" (',
    );
    expect(sql).toContain(
      "better_supabase.platform_can_assign(auth.uid(), ((select r.",
    );
    expect(sql).toContain(
      'better_supabase.platform_can_assign(pinvite."invited_by", pinvite."role"::text)',
    );
    expect(sql).toContain(
      'better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text)',
    );
    expect(sql).toContain('"prefill" jsonb not null');
    expect(sql).toContain("valid_for > '14 days'::interval");
  });

  it("rejects removed and invalid options", () => {
    const options = (value: Record<string, unknown>) => () =>
      body({ invitations: { options: value } });
    expect(options({ errorCodes: { NOPE: "P0001" } })).toThrow(/errorCodes/);
    expect(options({ tokenStorage: "md5" })).toThrow(/tokenStorage/);
  });

  it("shows organization branding in the preview when organizations is installed", () => {
    const sql = moduleBody("invitations", {
      kits: {
        invitations: { options: { previewColumns: ["name", "logo_path"] } },
      },
    })!;
    expect(sql).toContain(
      "'organization', jsonb_build_object('id', i.\"organization_id\")",
    );
    const plan = upgradePlan([{ module: "invitations", version: 1 }], {});
    expect(plan.map((step) => step.module)).toContain("invitations");
  });

  it("skips the inviter re-check under the permdock model", () => {
    const accept = (kits: KitsConfig) =>
      renderKit(["access", "invitations"], { kits })
        .map((file) => file.contents)
        .join("\n");
    expect(accept({})).toContain("better_supabase.can_user(invite.");
    const permdock = accept({
      access: {
        model: "permdock",
        permdock: { schema: "permdock", scope: "organization" },
      },
    });
    expect(permdock).not.toContain("better_supabase.can_user(invite.");
    expect(permdock).toContain(
      "-- The permdock model answers for the caller only, so the inviter's",
    );
  });
});
