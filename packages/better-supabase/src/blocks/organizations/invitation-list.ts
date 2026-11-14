import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type {
  EntityList,
  EntityListSurface,
  RequiredTenantOption,
} from "../../core/entity-list.ts";
import type { DbError } from "../../core/errors.ts";
import type { OrganizationInvitationRow } from "./organizations.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";

/**
 * What `invitationList` accepts (ADR 0923). The manifest declares the same
 * names. The open invitations of one organization are read in one call, so the
 * list filters, sorts and pages them in memory instead of in SQL.
 */
export const invitationListSurface: EntityListSurface = {
  sorts: ["expiresAt", "email"],
  facets: ["role"],
  filters: ["role"],
  search: ["email"],
};

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

const invalid = (message: string): DbError =>
  dbError("invalid_input", message, { hint: "INVITATION_INVALID" });

function unknownName(
  kind: string,
  names: readonly string[],
  allowed: readonly string[] | undefined,
): DbError | undefined {
  const bad = names.find((name) => !(allowed ?? []).includes(name));

  return bad === undefined
    ? undefined
    : invalid(`${kind} ${bad} is not declared for an invitation`);
}

function matching(
  rows: readonly OrganizationInvitationRow[],
  options: Pick<PageOptions, "q" | "filters">,
): readonly OrganizationInvitationRow[] {
  const q = options.q?.trim().toLowerCase() ?? "";
  const roles = options.filters?.["role"] ?? [];

  return rows.filter(
    (row) =>
      (q === "" || row.email.toLowerCase().includes(q)) &&
      (roles.length === 0 || roles.includes(row.role)),
  );
}

const keyOf = (row: OrganizationInvitationRow, by: string): string =>
  by === "email"
    ? row.email.toLowerCase()
    : (row.expiresAt?.toString() ?? "9999");

function ordered(
  rows: readonly OrganizationInvitationRow[],
  sort: NonNullable<PageOptions["sort"]> | undefined,
): readonly OrganizationInvitationRow[] {
  const by = sort?.by ?? "expiresAt";

  const sign =
    (sort?.direction ?? (by === "email" ? "asc" : "desc")) === "asc" ? 1 : -1;

  return rows.toSorted((a, b) => {
    const left = keyOf(a, by);
    const right = keyOf(b, by);

    if (left === right) {
      return sign * a.id.localeCompare(b.id);
    }

    return sign * (left < right ? -1 : 1);
  });
}

/**
 * The page, facet and count reads over the open invitations `read` returns (ADR
 * 0923). The cursor holds the offset of the next row and is valid for the sort
 * and filters it came from.
 */
export function invitationList(
  read: (
    organizationId: string,
  ) => AsyncResult<readonly OrganizationInvitationRow[]>,
): EntityList<OrganizationInvitationRow, RequiredTenantOption> {
  const checked = (
    options: Partial<PageOptions> & { readonly facets?: readonly string[] },
  ): DbError | undefined =>
    unknownName(
      "filter",
      Object.keys(options.filters ?? {}),
      invitationListSurface.filters,
    ) ??
    unknownName(
      "sort",
      options.sort === undefined ? [] : [options.sort.by],
      invitationListSurface.sorts,
    ) ??
    unknownName("facet", options.facets ?? [], invitationListSurface.facets);

  const rowsOf = (
    options: RequiredTenantOption &
      Partial<PageOptions> & { readonly facets?: readonly string[] },
  ): AsyncResult<readonly OrganizationInvitationRow[]> => {
    const problem = checked(options);

    return problem === undefined
      ? read(options.organizationId)
      : AsyncResult.err<readonly OrganizationInvitationRow[]>(problem);
  };

  return {
    page: (...args) =>
      AsyncResult.from(async () => {
        const [options] = args;
        const result = await rowsOf(options);

        if (!result.ok) {
          return result;
        }

        const all = ordered(matching(result.data, options), options.sort);
        const offset = Number(options.after?.[0] ?? 0);

        const limit = Math.min(
          Math.max(options.limit ?? DEFAULT_LIMIT, 1),
          MAX_LIMIT,
        );

        if (!Number.isInteger(offset) || offset < 0) {
          return err(invalid("The cursor is not one this list returned"));
        }

        const end = offset + limit;

        const page: ListPage<OrganizationInvitationRow> = {
          items: all.slice(offset, end),
          hasMore: end < all.length,
          nextCursor: end < all.length ? [String(end)] : null,
          total: all.length,
          totalCapped: false,
        };

        return ok(page);
      }),
    facets: (...args) =>
      AsyncResult.from(async () => {
        const [options] = args;
        const result = await rowsOf(options);

        if (!result.ok) {
          return result;
        }

        const counts = new Map<string, number>();

        for (const row of matching(result.data, options)) {
          counts.set(row.role, (counts.get(row.role) ?? 0) + 1);
        }

        const wanted = options.facets ?? invitationListSurface.facets ?? [];

        const facets: readonly FacetResult[] = wanted.map((facet) => ({
          facet,
          values: [...counts].map(([value, count]) => ({
            value,
            count: { value: count, exact: true },
          })),
        }));

        return ok(facets);
      }),
    count: (...args) =>
      AsyncResult.from(async () => {
        const [options] = args;
        const result = await rowsOf(options);

        if (!result.ok) {
          return result;
        }

        const count: Count = {
          value: matching(result.data, options).length,
          exact: true,
        };

        return ok(count);
      }),
  };
}
