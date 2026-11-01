import type { ReadType } from "../../core/read-type.ts";
import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlRead } from "../reads.ts";

import { declareRead } from "../reads.ts";
import { fail } from "../shared.ts";

/** What `organization_overview` returns. */
export const ORGANIZATION_OVERVIEW_RESULT: ReadType = {
  id: "text",
  name: "text",
  slug: "text?",
  role: "text",
  seats: "number?",
  members: [
    { userId: "text", role: "text", roles: ["text"], disabledAt: "text?" },
  ],
  invitations: [
    { id: "text", email: "text", role: "text", expiresAt: "text?" },
  ],
};

/** The `organization_overview` JSON before timestamps become instants. */
export interface OrganizationOverviewRaw {
  readonly id: string;
  readonly name: string;
  readonly slug: string | null;
  readonly role: string;
  readonly seats: number | null;
  readonly members: readonly {
    readonly userId: string;
    readonly role: string;
    readonly roles: readonly string[];
    readonly disabledAt: string | null;
  }[];
  readonly invitations: readonly {
    readonly id: string;
    readonly email: string;
    readonly role: string;
    readonly expiresAt: string | null;
  }[];
}

export const ORGANIZATION_READS: readonly BlockSqlRead[] = [
  declareRead(
    "overview",
    "organization_overview",
    { organizationId: { param: "organization", type: "id" } },
    ORGANIZATION_OVERVIEW_RESULT,
    "An organization with the caller's role, its members with their roles, its open invitations and its billed seats.",
    ["organizations", "memberships", "invitations"],
  ),
];

/**
 * `organization_overview`: `list_my_organizations`, `list_members`,
 * `list_organization_invitations` and, with the billing block, the seat count
 * from `billing_status`. Each checks the caller, so a caller who may not list
 * members gets that error.
 */
export function organizationOverview(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const id = ctx.idType;

  const invitations =
    ctx.installed("invitations") && ctx.of("invitations").mode !== "custom"
      ? `coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', i.id, 'email', i.email, 'role', i.role, 'expiresAt', to_jsonb(i) -> 'expires_at')
          order by i.email)
        from ${fn("list_organization_invitations")}(organization_overview.organization) i
      ), '[]'::jsonb)`
      : "'[]'::jsonb";

  const seats =
    ctx.installed("billing") && ctx.of("billing").mode !== "custom"
      ? `begin
    v_seats := (${ctx.of("billing").fn("billing_status")}(organization_overview.organization) ->> 'seats')::integer;
  exception when others then
    v_seats := null;
  end;`
      : "";

  return `
-- The organization page in one call. It runs as the caller and reads through
-- the listing functions, so the permissions to list members and invitations
-- apply. Seats come from billing_status and are null when the caller may not
-- read billing.
create or replace function ${fn("organization_overview")}(organization ${id})
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_org jsonb;
  v_seats integer;
begin
  select to_jsonb(o) into v_org
  from ${fn("list_my_organizations")}() o
  where o.id = organization_overview.organization;
  if v_org is null then
    ${fail("ORGANIZATION_FORBIDDEN", "Not a member of this organization")}
  end if;
  ${seats}
  return jsonb_build_object(
    'id', v_org ->> 'id',
    'name', v_org ->> 'name',
    'slug', v_org -> 'slug',
    'role', v_org ->> 'role',
    'seats', v_seats,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', m.user_id, 'role', m.role,
        'roles', coalesce(to_jsonb(m) -> 'roles', jsonb_build_array(m.role)),
        'disabledAt', to_jsonb(m) -> 'disabled_at')
        order by m.user_id)
      from ${fn("list_members")}(organization_overview.organization) m
    ), '[]'::jsonb),
    'invitations', ${invitations}
  );
end;
$$;
`;
}
