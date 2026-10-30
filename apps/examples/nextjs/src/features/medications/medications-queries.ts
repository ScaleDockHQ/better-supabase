import "server-only";
import type { MedicationAdministrationStatus } from "better-supabase/blocks/medications";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
async function settle<T>(load: () => Promise<T | null>): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** A dose on the chart, serializable. */
export interface ChartDose {
  readonly id: string;
  /** The planned time, or when an as-needed dose was given. */
  readonly at: string | null;
  readonly status: MedicationAdministrationStatus;
}

/** An order on the chart with today's doses, serializable. */
export interface ChartOrder {
  readonly id: string;
  readonly medication: string;
  readonly dose: string;
  readonly route: string | null;
  readonly asNeeded: boolean;
  readonly highRisk: boolean;
  readonly paused: boolean;
  readonly doses: readonly ChartDose[];
}

/** Today's chart of one customer. */
export interface CustomerChart {
  readonly customer: string;
  readonly orders: readonly ChartOrder[];
}

async function loadChart(): Promise<CustomerChart | "no-customer" | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [customer] = await db.customers
    .list({
      select: ["id", "name"],
      where: { organizationId: tenant },
      orderBy: { name: "asc" },
      limit: 1,
    })
    .orThrow();

  if (!customer) {
    return "no-customer";
  }

  const chart = await db.medications
    .chart({ type: "customer", id: customer.id })
    .orThrow();

  return {
    customer: customer.name,
    orders: chart.orders.map((order) => ({
      id: order.id,
      medication: order.medication.name,
      dose: `${order.dose} ${order.doseUnit}`,
      route: order.route ?? null,
      asNeeded: order.asNeeded,
      highRisk: order.medication.highRisk || order.requiresDoubleCheck,
      paused: order.status === "paused",
      doses: chart.administrations
        .filter((dose) => dose.orderId === order.id)
        .map((dose) => ({
          id: dose.id,
          at: (dose.scheduledAt ?? dose.administeredAt)?.toString() ?? null,
          status: dose.status,
        })),
    })),
  };
}

/**
 * Today's medication chart of the organization's first customer by name, or
 * `"no-customer"` when it has none.
 */
export function getCustomerChart(): Promise<
  Loaded<CustomerChart | "no-customer">
> {
  return settle(loadChart);
}
