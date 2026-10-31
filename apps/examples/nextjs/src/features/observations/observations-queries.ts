import "server-only";
import type {
  ObservationFlag,
  ObservationValue,
} from "better-supabase/blocks/observations";

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

/** One definition's latest value and recent series, serializable. */
export interface VitalRow {
  readonly key: string;
  readonly title: string;
  /** The value as text: `120/80` for blood pressure. */
  readonly value: string;
  readonly unit: string | null;
  readonly flag: ObservationFlag | null;
  readonly observedAt: string;
  /** The last 30 numeric values, oldest first. */
  readonly series: readonly number[];
}

export interface VitalsData {
  /** The customer the vitals belong to, or null when there is none. */
  readonly customer: { readonly id: string; readonly name: string } | null;
  readonly rows: readonly VitalRow[];
}

const SERIES_POINTS = 30;

function textOf(value: ObservationValue | null): string {
  if (value === null) {
    return "";
  }

  if (value instanceof Object) {
    return Object.values(value).join("/");
  }

  return String(value);
}

async function loadVitals(
  customerId: string | undefined,
): Promise<VitalsData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const [customer] = await db.customers
    .list({
      select: ["id", "name"],
      where: customerId === undefined ? {} : { id: customerId },
      orderBy: { name: "asc" },
      limit: 1,
    })
    .orThrow();

  if (customer === undefined) {
    return { customer: null, rows: [] };
  }

  const latest = await db.observations
    .latest("customer", customer.id)
    .orThrow();

  const rows = await Promise.all(
    Object.values(latest).map(async (observation): Promise<VitalRow> => {
      const numeric =
        observation.valueType === "number" ||
        observation.valueType === "integer";

      const points = numeric
        ? await db.observations
            .series("customer", customer.id, observation.definitionKey)
            .orThrow()
        : [];

      return {
        key: observation.definitionKey,
        title: observation.title,
        value: textOf(observation.value),
        unit: observation.unit ?? null,
        flag: observation.flag ?? null,
        observedAt: observation.observedAt.toString(),
        // A numeric definition's points hold numbers.
        series: points
          .slice(-SERIES_POINTS)
          .map((point) => Number(point.value)),
      };
    }),
  );

  return {
    customer: { id: customer.id, name: customer.name },
    rows: rows.toSorted((a, b) => a.title.localeCompare(b.title)),
  };
}

/**
 * The customer's latest vital signs, each with its recent values, or the first
 * customer's without an id.
 */
export function getVitals(customerId?: string): Promise<Loaded<VitalsData>> {
  return settle(() => loadVitals(customerId));
}
