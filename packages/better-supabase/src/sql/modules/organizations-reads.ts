import type { ExtraColumn, BlockSqlContext } from "../context.ts";

import {
  filterAny,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { columnsObject, membershipDisabledAt, fail } from "../shared.ts";
import { manyRoles, membershipRolesTable } from "./membership-roles.ts";
import { OPERATIONS, modulePermission } from "./permissions-model.ts";

/** The keys `list_my_organizations` returns, which no attribute may shadow. */
const MEMBERSHIP_KEYS: readonly string[] = [
  "id",
  "name",
  "slug",
  "role",
  "disabled_at",
  "attributes",
];

/** The columns your schema files add, which a managed organizations table gets. */
function organizationExtraColumns(
  ctx: BlockSqlContext,
): readonly ExtraColumn[] {
  return ctx.extraColumns("organizations", MEMBERSHIP_KEYS);
}

/**
 * The attribute columns, unquoted: `options.attributes` and the columns your
 * schema files add. `create_organization` and `update_organization` copy them
 * from `attrs`, and `list_my_organizations` returns them.
 */
export function organizationAttributes(
  ctx: BlockSqlContext,
): readonly string[] {
  const listed = ctx.list("attributes", []).map((column) => {
    if (!/^[A-Za-z_][A-Za-z0-9_$]*$/.test(column)) {
      throw new TypeError(
        `blocks.organizations.options.attributes: "${column}" is not a valid column`,
      );
    }

    return column;
  });

  return [
    ...new Set([
      ...listed,
      ...organizationExtraColumns(ctx).map((extra) => extra.name),
    ]),
  ];
}

/** Columns `reads` needs from `namesOf`. */
export interface OrganizationReadNames {
  readonly organization: string;
  readonly id: string;
  readonly m: string;
  readonly tenant: string;
  readonly user: string;
  readonly role: string;
}

export function organizationReads(
  ctx: BlockSqlContext,
  n: OrganizationReadNames,
): string {
  const name = ctx.col("organizations", "name");

  const slug = ctx.has("organizations", "slug")
    ? ctx.col("organizations", "slug")
    : undefined;

  const flags = (["deletedAt", "disabledAt"] as const)
    .filter((logical) => ctx.has("organizations", logical))
    .map((logical) => ` and o.${ctx.col("organizations", logical)} is null`)
    .join("");

  const invites = ctx.installed("invitations") ? invitationsRead(ctx) : "";
  const disabledAt = membershipDisabledAt(ctx);

  const disabledColumn =
    disabledAt === undefined ? "" : ",\n  disabled_at timestamptz";

  const disabledValue = disabledAt === undefined ? "" : `, m.${disabledAt}`;

  const members = ctx.of("memberships");
  const rolesColumn = manyRoles(members) ? ",\n  roles text[]" : "";

  const rolesValue = manyRoles(members)
    ? `, array(select r."role" from ${membershipRolesTable(members)} r where r.${n.tenant} = m.${n.tenant} and r.${n.user} = m.${n.user} order by r."role")`
    : "";

  const attributes = organizationAttributes(ctx).filter(
    (column) => !MEMBERSHIP_KEYS.includes(column),
  );

  const attributesColumn =
    attributes.length === 0 ? "" : ",\n  attributes jsonb";

  const attributesValue =
    attributes.length === 0 ? "" : `, ${columnsObject("o", attributes)}`;

  return `
drop function if exists ${ctx.fn("list_my_organizations")}();
create or replace function ${ctx.fn("list_my_organizations")}()
returns table (
  id ${ctx.idType},
  name text${slug === undefined ? "" : ",\n  slug text"},
  role text${rolesColumn}${disabledColumn}${attributesColumn}
)
language sql
stable
security definer
set search_path = ''
as $$
  select o.${n.id}, o.${name}${slug === undefined ? "" : `, o.${slug}`}, m.${n.role}::text${rolesValue}${disabledValue}${attributesValue}
  from ${n.m} m
  join ${n.organization} o on o.${n.id} = m.${n.tenant}
  where m.${n.user} = (select auth.uid())${flags}
    and not better_supabase.tenant_disabled(o.${n.id})
  order by o.${name}
$$;

drop function if exists ${ctx.fn("list_members")}(${ctx.idType});
create or replace function ${ctx.fn("list_members")}(organization ${ctx.idType})
returns table (user_id uuid, role text${`${rolesColumn}${disabledColumn}`.replaceAll(",\n  ", ", ")})
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, ${modulePermission(ctx, "listMembers", OPERATIONS["organizations.listMembers"])}), false) then
    ${fail("ORGANIZATION_FORBIDDEN", "Not allowed to list members")}
  end if;
  return query
  select m.${n.user}, m.${n.role}::text${rolesValue}${disabledValue}
  from ${n.m} m
  where m.${n.tenant} = organization
  order by m.${n.user};
end;
$$;
${invites}`;
}

function invitationsRead(ctx: BlockSqlContext): string {
  const invitations = ctx.of("invitations");
  const table = invitations.table("invitations");
  const id = invitations.col("invitations", "id");
  const tenant = invitations.col("invitations", "tenant");
  const email = invitations.col("invitations", "email");
  const role = invitations.col("invitations", "role");

  const open = ["acceptedAt", "declinedAt", "revokedAt"]
    .filter((logical) => invitations.has("invitations", logical))
    .map((logical) => `i.${invitations.col("invitations", logical)} is null`)
    .join(" and ");

  const expires = invitations.has("invitations", "expiresAt")
    ? invitations.col("invitations", "expiresAt")
    : undefined;

  return `
create or replace function ${ctx.fn("list_organization_invitations")}(organization ${ctx.idType})
returns table (
  id uuid,
  email text,
  role text${expires === undefined ? "" : ",\n  expires_at timestamptz"}
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, ${modulePermission(ctx.of("invitations"), "read", OPERATIONS["invitations.read"])}), false) then
    ${fail("ORGANIZATION_FORBIDDEN", "Not allowed to list invitations")}
  end if;
  return query
  select i.${id}, i.${email}, i.${role}::text${expires === undefined ? "" : `, i.${expires}`}
  from ${table} i
  where i.${tenant} = organization${open === "" ? "" : ` and ${open}`}${expires === undefined ? "" : ` and i.${expires} >= now()`}
  order by ${expires === undefined ? `i.${id}` : `i.${expires}`} desc;
end;
$$;
${invitationsPage(ctx, open, expires)}`;
}

/**
 * `page_organization_invitations`: the open invitations as a keyset page with
 * sorts, facets and a count (ADR 0749, 0923). It sits beside
 * `list_organization_invitations`, which the overview and upgraded apps keep.
 */
function invitationsPage(
  ctx: BlockSqlContext,
  open: string,
  expires: string | undefined,
): string {
  const invitations = ctx.of("invitations");
  const id = invitations.col("invitations", "id");
  const tenant = invitations.col("invitations", "tenant");
  const email = invitations.col("invitations", "email");
  const role = invitations.col("invitations", "role");

  const expiry =
    expires === undefined
      ? `'infinity'::timestamptz`
      : `coalesce(i.${expires}, 'infinity'::timestamptz)`;

  const byExpiry = [
    { expr: expiry, dir: "desc", type: "timestamptz" },
    { expr: `i.${id}`, dir: "desc", type: "uuid" },
  ] as const;

  const byEmail = [
    { expr: `lower(i.${email})`, dir: "asc", type: "text" },
    { expr: `i.${id}`, dir: "asc", type: "uuid" },
  ] as const;

  const list = {
    name: "page_organization_invitations",
    from: invitations.table("invitations"),
    alias: "i",
    where: [
      `i.${tenant} = page_organization_invitations.tenant`,
      ...(open === "" ? [] : [open]),
      ...(expires === undefined ? [] : [`i.${expires} >= now()`]),
      filterAny("role", `i.${role}::text`),
      `(v_search is null or i.${email} ilike v_search)`,
    ],
    keys: byExpiry,
    sorts: { expiresAt: byExpiry, email: byEmail },
    facets: { role: `i.${role}::text` },
    rowJson: `jsonb_build_object('id', i.${id}, 'email', i.${email}, 'role', i.${role}::text, 'expiresAt', ${expires === undefined ? "null" : `i.${expires}`})`,
    invalid: (message: string): string =>
      fail("INVITATION_INVALID", message, "22023"),
  } as const;

  return `
-- The open invitations of an organization as a keyset page, latest expiry
-- first. filters is { role (a value or a list), search, sort, direction, facet,
-- count, limit, after, offset, paged, total, totalCap } (ADR 0749, 0923).
create or replace function ${ctx.fn("page_organization_invitations")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_organization_invitations.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(list)}
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), tenant, ${modulePermission(invitations, "read", OPERATIONS["invitations.read"])}), false) then
    ${fail("ORGANIZATION_FORBIDDEN", "Not allowed to list invitations")}
  end if;
  ${listBody(list)}
end;
$$;
`;
}
