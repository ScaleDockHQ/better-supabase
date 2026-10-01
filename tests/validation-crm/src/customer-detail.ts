import { defineReadSet } from "better-supabase";

import type { CrmDb } from "./customers.ts";

import { sb } from "./latency.ts";

const CUSTOMER_COLUMNS = [
  "id",
  "companyName",
  "isBusiness",
  "status",
  "billingEmail",
  "website",
] as const;
const CONTACT_COLUMNS = ["id", "jobTitle", "isPrimary"] as const;
const PROFILE_COLUMNS = ["id", "firstName", "lastName", "displayName"] as const;
const METHOD_COLUMNS = ["id", "type", "value", "isPrimary"] as const;
const LOCATION_COLUMNS = [
  "id",
  "name",
  "addressLine1",
  "addressCity",
  "isPrimary",
] as const;

/**
 * The customer detail page as one embedded select: the customer, its
 * contacts with their contact methods, its locations, and how many quotes
 * and invoices it has. The original page ran a query per section.
 */
export function customerDetail(
  db: CrmDb,
  organizationId: string,
  customerId: number,
) {
  return db.customers.findFirst({
    where: { id: customerId, organizationId },
    select: CUSTOMER_COLUMNS,
    include: {
      customerContacts: {
        select: CONTACT_COLUMNS,
        orderBy: [{ isPrimary: "desc" }, { createdAt: "asc" }],
        include: {
          contactProfile: {
            select: PROFILE_COLUMNS,
            include: {
              contactMethods: {
                select: METHOD_COLUMNS,
                orderBy: [{ position: "asc" }],
              },
            },
          },
        },
      },
      customerLocationsByCustomer: {
        select: LOCATION_COLUMNS,
        orderBy: [{ isPrimary: "desc" }, { createdAt: "asc" }],
      },
      _count: { quotes: true, invoices: true },
    },
  });
}

/**
 * The same page as a read set, for pages that want each section on its own:
 * `gen` compiles it into `public.rs_customer_detail(p jsonb)`, and
 * `db.$many(customerDetailSet, params)` reads it with one GET.
 */
export const customerDetailSet = defineReadSet(
  sb,
  "customer_detail",
  { params: { organizationId: "uuid", customerId: "int8" } },
  (s, p) => ({
    customer: s.customers.findFirst({
      where: { id: p.customerId, organizationId: p.organizationId },
      select: CUSTOMER_COLUMNS,
    }),
    contacts: s.customerContacts.findMany({
      where: { customerId: p.customerId, organizationId: p.organizationId },
      select: CONTACT_COLUMNS,
      orderBy: [{ isPrimary: "desc" }, { createdAt: "asc" }],
      include: {
        contactProfile: {
          select: PROFILE_COLUMNS,
          include: { contactMethods: { select: METHOD_COLUMNS } },
        },
      },
    }),
    locations: s.customerLocations.findMany({
      where: { customerId: p.customerId, organizationId: p.organizationId },
      select: LOCATION_COLUMNS,
      orderBy: [{ isPrimary: "desc" }, { createdAt: "asc" }],
    }),
    quotes: s.quotes.count({
      where: { customerId: p.customerId, organizationId: p.organizationId },
    }),
    invoices: s.invoices.count({
      where: { customerId: p.customerId, organizationId: p.organizationId },
    }),
  }),
);
