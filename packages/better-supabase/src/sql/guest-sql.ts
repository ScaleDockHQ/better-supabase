import type { BlockSqlLayout } from "./module-types.ts";

import { fillTemplate } from "../core/access-sql.ts";
import { userGrant } from "./shared.ts";

/**
 * One source of guest rows: a `select` of `(tenant, subject_type, subject_id)`
 * for `subjects`, with `action` (text) in scope, and of `(tenant, party_type,
 * party_id)` for `parties`. Every column is text.
 */
export interface GuestSource {
  readonly subjects?: string;
  readonly parties?: string;
}

/**
 * The provider's `portalSubjects` and `portalParties` as guest sources, under
 * the `provider` model only. Empty without them.
 */
export function providerGuestSource(layout: BlockSqlLayout): GuestSource {
  const provider = layout.accessProvider;

  if (layout.modules?.access?.model !== "provider" || !provider) {
    return {};
  }

  const { portalSubjects, portalParties } = provider.functions;

  return {
    ...(portalSubjects === undefined
      ? {}
      : {
          subjects: `select g.tenant::text, g.subject_type::text, g.subject_id::text from ${fillTemplate(
            "authorization.functions.portalSubjects",
            portalSubjects,
            { action: "portal_subjects.action" },
          )} as g(tenant, subject_type, subject_id)`,
        }),
    ...(portalParties === undefined
      ? {}
      : {
          parties: `select g.tenant::text, g.party_type::text, g.party_id::text from ${fillTemplate(
            "authorization.functions.portalParties",
            portalParties,
            {},
          )} as g(tenant, party_type, party_id)`,
        }),
  };
}

/**
 * The guest sets from the provider alone, rendered by `access`, with a leading
 * newline. Empty with the `guests` block installed (that module renders them,
 * adding its own grants) or when the provider has no portal templates.
 */
export function providerGuestFunctions(
  installed: readonly string[],
  layout: BlockSqlLayout,
): string {
  if (installed.includes("guests")) {
    return "";
  }

  const source = providerGuestSource(layout);

  return source.subjects === undefined && source.parties === undefined
    ? ""
    : `\n${guestFunctions([source])}`;
}

/** Whether the provider answers for guests under the `provider` model. */
export function providerAnswersForGuests(layout: BlockSqlLayout): boolean {
  const source = providerGuestSource(layout);

  return source.subjects !== undefined || source.parties !== undefined;
}

const union = (
  parts: readonly (string | undefined)[],
  empty: string,
): string => {
  const found = parts.filter((part): part is string => part !== undefined);

  return found.length === 0 ? empty : found.join("\n  union\n  ");
};

/**
 * `better_supabase.portal_subjects(action)` and `portal_parties()`, the sets
 * `ctx.scope.guest` and `ctx.scope.guestParty` read (ADR 0070), over every
 * source. A source without one of the two adds nothing to it.
 */
export function guestFunctions(sources: readonly GuestSource[]): string {
  const subjects = union(
    sources.map((source) => source.subjects),
    "select null::text, null::text, null::text where false",
  );

  const parties = union(
    sources.map((source) => source.parties),
    "select null::text, null::text, null::text where false",
  );

  return `
-- The records the caller reaches as a guest for action (read, comment or
-- upload). A guest is not a member: can() stays false for them, and policies
-- add this set through ctx.scope.guest.
create or replace function better_supabase.portal_subjects(action text)
returns table (tenant text, subject_type text, subject_id text)
language sql
stable
security definer
set search_path = ''
as $$
  ${subjects}
$$;
${userGrant("better_supabase.portal_subjects(text)")}

-- The parties (a company, a person) the caller acts for as a guest, for
-- portal reads such as a customer's own invoices.
create or replace function better_supabase.portal_parties()
returns table (tenant text, party_type text, party_id text)
language sql
stable
security definer
set search_path = ''
as $$
  ${parties}
$$;
${userGrant("better_supabase.portal_parties()")}
`;
}

/**
 * `sql`, or-ed with the guest checks that can pass. `ctx.scope.guest` renders
 * `false` without guests, so a layout without them keeps `sql` as it was.
 */
export function guestOr(sql: string, checks: readonly string[]): string {
  const live = checks.filter((check) => check !== "false");

  return live.length === 0 ? sql : `(${sql}) or ${live.join(" or ")}`;
}
