import type { SupabaseClient } from "@supabase/supabase-js";

import {
  type AsyncResult,
  type Db,
  dbError,
  type WhereInput,
} from "better-supabase";

import type { Functions, Models } from "./generated.ts";

export type CrmDb = Db<Models, Functions, unknown, SupabaseClient>;

type CustomerWhere = WhereInput<Models, "customers">;
type CustomerStatus = Models["customers"]["Row"]["status"];

/** The filter of the customer list page. */
export interface CustomerListFilter {
  readonly q?: string;
  readonly statuses?: readonly CustomerStatus[];
  readonly types?: readonly ("business" | "private")[];
  readonly assigneeIds?: readonly string[];
  readonly unassigned?: boolean;
  readonly tagIds?: readonly string[];
  readonly sortBy?: "name" | "createdAt" | "updatedAt";
  readonly sortDirection?: "asc" | "desc";
  readonly page?: number;
  readonly size?: number;
}

export interface CustomerInput {
  readonly companyName: string | null;
  readonly isBusiness: boolean;
  readonly billingEmail?: string | null;
  readonly website?: string | null;
}

const SORT_COLUMN = {
  name: "sortName",
  createdAt: "createdAt",
  updatedAt: "updatedAt",
} as const;

const LIST_COLUMNS = [
  "id",
  "companyName",
  "isBusiness",
  "status",
  "sortName",
  "logoPath",
  "updatedAt",
] as const;

const escapeLike = (term: string): string =>
  term.replaceAll(/[%_\\]/g, (match) => `\\${match}`);

/** The overview filter: the original service ran up to four queries for ids before this one. */
function listWhere(
  organizationId: string,
  filter: CustomerListFilter,
): CustomerWhere {
  const where: CustomerWhere[] = [
    { organizationId },
    filter.statuses?.length
      ? { status: { in: filter.statuses } }
      : { status: { neq: "archived" } },
  ];
  if (filter.types?.length === 1)
    where.push({ isBusiness: filter.types[0] === "business" });

  const assigned = filter.assigneeIds?.length
    ? {
        customerAssigneesByCustomer: {
          some: { userId: { in: filter.assigneeIds } },
        },
      }
    : undefined;
  if (filter.unassigned) {
    const unassigned = { customerAssigneesByCustomer: { none: {} } };
    where.push(assigned ? { OR: [assigned, unassigned] } : unassigned);
  } else if (assigned) {
    where.push(assigned);
  }
  if (filter.tagIds?.length)
    where.push({ customerTags: { some: { tagId: { in: filter.tagIds } } } });

  const term = filter.q?.trim();
  if (term) {
    const like = `%${escapeLike(term)}%`;
    where.push({
      OR: [
        { companyName: { ilike: like } },
        { sortName: { ilike: like } },
        { billingEmail: { ilike: like } },
        {
          customerContacts: {
            some: {
              contactProfile: {
                OR: [
                  { firstName: { ilike: like } },
                  { lastName: { ilike: like } },
                  { displayName: { ilike: like } },
                ],
              },
            },
          },
        },
      ],
    });
  }
  return { AND: where };
}

export function createCustomersService(db: CrmDb) {
  return {
    /** One request: filters, sort, page, count, assignees, tags, primary contact and location. */
    listCustomers(organizationId: string, filter: CustomerListFilter = {}) {
      return db.customers.paginate({
        select: LIST_COLUMNS,
        where: listWhere(organizationId, filter),
        orderBy: [
          {
            [SORT_COLUMN[filter.sortBy ?? "name"]]:
              filter.sortDirection ?? "asc",
          },
          { id: "asc" },
        ],
        page: filter.page ?? 1,
        size: filter.size ?? 25,
        count: "estimated",
        include: {
          customerAssigneesByCustomer: { select: ["userId"] },
          customerTags: {
            select: ["tagId"],
            include: { tag: { select: ["id", "name", "color"] } },
          },
          customerContacts: {
            select: ["id", "jobTitle"],
            where: { isPrimary: true },
            limit: 1,
            include: {
              contactProfile: {
                select: ["firstName", "lastName", "displayName"],
              },
            },
          },
          customerLocationsByCustomer: {
            select: ["id", "name", "addressCity"],
            where: { isPrimary: true },
            limit: 1,
          },
        },
      });
    },

    getCustomer(organizationId: string, customerId: number) {
      return db.customers.findFirst({
        where: { id: customerId, organizationId },
        include: {
          customerContacts: {
            orderBy: [{ isPrimary: "desc" }, { createdAt: "asc" }],
            include: { contactProfile: true },
          },
          customerLocationsByCustomer: {
            orderBy: [{ isPrimary: "desc" }, { createdAt: "asc" }],
          },
          customerTags: { include: { tag: true } },
        },
      });
    },

    createCustomer(organizationId: string, input: CustomerInput) {
      return db.customers.create(
        { ...input, organizationId },
        { select: LIST_COLUMNS },
      );
    },

    updateCustomer(customerId: number, input: CustomerInput) {
      return db.customers.update(customerId, input, { select: LIST_COLUMNS });
    },

    archiveCustomer(
      customerId: number,
      reason: string | null = null,
    ): AsyncResult<void> {
      return db.customers
        .update(customerId, {
          status: "archived",
          archivedAt: new Date().toISOString(),
          archivedReason: reason,
        })
        .map(() => undefined);
    },

    unarchiveCustomer(customerId: number): AsyncResult<void> {
      return db.customers
        .update(customerId, {
          status: "active",
          archivedAt: null,
          archivedReason: null,
        })
        .map(() => undefined);
    },

    /** `CustomerInUseError`: a foreign key still points at the customer. */
    deleteCustomer(customerId: number): AsyncResult<void> {
      return db.customers
        .delete(customerId)
        .mapError((error) =>
          error.kind === "foreign_key"
            ? dbError("conflict", "This customer still has linked records.")
            : error,
        );
    },
  };
}

export type CustomersService = ReturnType<typeof createCustomersService>;
