import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import {
  moduleBody,
  renderModules,
  upgradePlan,
} from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig) =>
  moduleBody("invitations", { modules })!;

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
    expect(sql).toMatch(
      /insert into "public"\."organization_invitations" \("email", "role_id", "token", "invited_by", "expires_at", "prefill"\)\n    values \(lower\(btrim\(invitee_email\)\), \(select r\.[^\n]*limit 1\), token, auth\.uid\(\), now\(\) \+ valid_for, coalesce\(prefill, '\{\}'\)\)/,
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
      modules: {
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
    const accept = (modules: ModulesConfig) =>
      renderModules(["access", "invitations"], { modules })
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

describe("platform invitations under the permdock model", () => {
  const PERMDOCK: ModulesConfig = {
    access: {
      model: "permdock",
      permdock: { schema: "authz", scope: "organization" },
    },
  };
  const roles = {
    table: "public.user_roles",
    user: "user_id",
    role: "role_id",
  };

  it("assigns the app's platform role table on accept", () => {
    const sql = body({
      ...PERMDOCK,
      invitations: {
        options: {
          platformRoles: {
            ...roles,
            through: { table: "public.app_roles", id: "id", column: "key" },
            canAssign: "authz.can_grant({user}, {role})",
          },
        },
      },
    });
    expect(sql).toContain(
      'create table if not exists "better_supabase"."platform_invitations"',
    );
    expect(sql).toContain(
      'insert into "public"."user_roles" ("user_id", "role_id")',
    );
    expect(sql).toContain(
      `coalesce((authz.can_grant(auth.uid(), (select r."key"::text from "public"."app_roles" r`,
    );
    expect(sql).toContain("better_supabase.is_platform('platform.invite')");
    expect(sql).not.toContain("platform_can_assign");
  });

  it("checks the inviter at accept with canAssignFor when canAssign reads the caller", () => {
    const forUser = {
      ...PERMDOCK,
      access: {
        model: "permdock" as const,
        permdock: { schema: "authz", scope: "organization", forUser: true },
      },
    };
    const sql = (platformRoles: Record<string, unknown>) =>
      body({ ...forUser, invitations: { options: { platformRoles } } });
    const callerOnly = sql({
      ...roles,
      canAssign: "authz.can_grant({role})",
    });
    expect(callerOnly).toContain(
      "coalesce((authz.can_grant(((invitee_role))::text)), false)",
    );
    expect(callerOnly).toContain("better_supabase.platform_can(pinvite.");
    expect(callerOnly).not.toMatch(/can_grant\([^;]*pinvite/);
    const withFor = sql({
      ...roles,
      canAssign: "authz.can_grant({role})",
      canAssignFor: "authz.can_grant_for({user}, {role})",
    });
    expect(withFor).toContain(
      'and coalesce((authz.can_grant_for(pinvite."invited_by", (pinvite."role")::text)), false)',
    );
    expect(() =>
      sql({ ...roles, canAssignFor: "authz.can_grant({role})" }),
    ).toThrow(/canAssignFor/);
    expect(body({ ...forUser })).toContain(
      'create or replace function "better_supabase"."accept_invitation_by_id"(invitation_id uuid)',
    );
    expect(body({ ...forUser })).toContain(
      'create or replace function "better_supabase"."decline_invitation_by_id"(invitation_id uuid)',
    );
  });

  it("refuses platform invitations without platformRoles and checks its shape", () => {
    expect(body(PERMDOCK)).toContain("INVITATION_SCOPE_UNSUPPORTED");
    const plain = body({
      ...PERMDOCK,
      invitations: { options: { platformRoles: roles } },
    });
    expect(plain).toContain(
      "No platform role ceiling: holding the invite permission is enough.",
    );
    expect(() =>
      body({
        ...PERMDOCK,
        invitations: { options: { platformRoles: "public.user_roles" } },
      }),
    ).toThrow(/platformRoles must be/);
    expect(() =>
      body({
        ...PERMDOCK,
        invitations: {
          options: { platformRoles: { ...roles, through: { table: "x" } } },
        },
      }),
    ).toThrow(/through must be/);
    expect(() =>
      body({
        ...PERMDOCK,
        invitations: {
          options: { platformRoles: { ...roles, table: "user_roles" } },
        },
      }),
    ).toThrow(/must be "schema.table"/);
  });
});

describe("update_invitation", () => {
  it("edits an open invitation with the invite checks and keeps the token", () => {
    const sql = body({ invitations: { options: { prefill: true } } });
    expect(sql).toContain(
      'create or replace function "better_supabase"."update_invitation"(\n  invitation_id uuid,\n  invitee_email text default null,\n  invitee_role text default null,\n  prefill jsonb default null\n)',
    );
    expect(sql).toContain(
      'grant execute on function "better_supabase"."update_invitation"(uuid, text, text, jsonb) to authenticated, service_role;',
    );
    expect(sql).toContain('updated."prefill" := prefill;');
    const fn = sql.slice(sql.indexOf('"update_invitation"('));
    expect(fn.slice(0, fn.indexOf("$$;"))).not.toContain("token_hash");
    expect(body({})).not.toContain('updated."prefill" := prefill;');
  });
});

describe("invitation_preview_extra", () => {
  it("merges the app's keys into the preview when the hook exists", () => {
    const sql = body({
      invitations: {
        hooks: { functions: { invitation_preview_extra: "app.preview" } },
      },
    });
    expect(sql).toContain(`to_regprocedure('"app"."preview"(uuid)')`);
    expect(sql).toContain("preview := preview || coalesce(extra, '{}');");
  });
});
