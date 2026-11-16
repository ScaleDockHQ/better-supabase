import type {
  AppDb,
  EntityListMap,
  EntityPager,
} from "@/lib/block-entity-page";

import { organizationPager } from "@/lib/block-entity-page";

import type { ContactSummary } from "./crm-queries";

/** The contacts lists' URL names on the contacts block's pages. */
export const contactsMap: EntityListMap = {
  sorts: {
    name: { by: "name" },
    newest: { by: "createdAt", direction: "desc" },
  },
  filters: { f: "lifecycle" },
  facets: { f: "lifecycle" },
};

/**
 * The contacts block's `companyPage` (`kind: "company"`) or `personPage`, as
 * the summary rows the lists show.
 */
export function contactsPager(
  db: AppDb,
  organizationId: string,
  kind: ContactSummary["kind"],
): EntityPager<ContactSummary> {
  const { contacts } = db.$blocks;

  if (kind === "company") {
    const pager = organizationPager(organizationId, {
      page: (options) => contacts.companyPage(options),
      facets: (options) => contacts.companyFacets(options),
    });

    return {
      facets: (options) => pager.facets(options),
      page: (options) =>
        pager
          .page(options)
          .map((page) => ({
            ...page,
            items: page.items.map((company): ContactSummary => ({
              id: company.id,
              kind: "company",
              name: company.name,
              lifecycle: company.lifecycle,
              detail: company.domain ?? null,
              supplierStatus: company.supplierStatus ?? null,
            })),
          })),
    };
  }

  const pager = organizationPager(organizationId, {
    page: (options) => contacts.personPage(options),
    facets: (options) => contacts.personFacets(options),
  });

  return {
    facets: (options) => pager.facets(options),
    page: (options) =>
      pager
        .page(options)
        .map((page) => ({
          ...page,
          items: page.items.map((person): ContactSummary => ({
            id: person.id,
            kind: "person",
            name: person.name,
            lifecycle: person.lifecycle,
            detail: person.email ?? null,
            supplierStatus: person.supplierStatus ?? null,
          })),
        })),
  };
}
