import "server-only";
import type {
  ComponentImpact,
  ComponentStatus,
  IncidentStatus,
} from "better-supabase/blocks/incidents";

import { unstable_rethrow } from "next/navigation";

import { blocks } from "@/lib/blocks";
import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "missing" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
export async function settle<T>(
  load: () => Promise<T | null>,
): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "missing" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** Days of uptime history the page shows. */
export const UPTIME_DAYS = 30;

/** A published status page, with dates and instants as ISO strings. */
export interface StatusPageView {
  readonly title: string;
  readonly description: string | null;
  readonly status: ComponentStatus;
  readonly components: readonly {
    readonly id: string;
    readonly name: string;
    readonly status: ComponentStatus;
    readonly uptimePercent: number;
    readonly uptime: readonly {
      readonly date: string;
      readonly status: ComponentStatus;
      readonly downMinutes: number;
    }[];
  }[];
  readonly incidents: readonly {
    readonly id: string;
    readonly title: string;
    readonly status: IncidentStatus;
    readonly startedAt: string;
    readonly components: readonly {
      readonly name: string;
      readonly impact: ComponentImpact;
    }[];
    readonly updates: readonly {
      readonly status: IncidentStatus;
      readonly body: string;
      readonly createdAt: string;
    }[];
  }[];
}

/**
 * The status page published at `slug`, read through the incidents block's
 * public function: it works signed out and returns only public fields.
 */
export async function loadStatusPage(
  slug: string,
): Promise<StatusPageView | null> {
  "use cache: private";
  const { supabase } = await bsb.cached();

  const page = await blocks(supabase)
    .incidents.publicStatusPage(slug, UPTIME_DAYS)
    .orThrow();

  if (!page) {
    return null;
  }

  return {
    title: page.title,
    description: page.description ?? null,
    status: page.status,
    components: page.components.map((component) => ({
      id: component.id,
      name: component.name,
      status: component.status,
      uptimePercent: component.uptimePercent,
      uptime: component.uptime.map((day) => ({
        date: day.date.toString(),
        status: day.status,
        downMinutes: day.downMinutes,
      })),
    })),
    incidents: page.incidents.map((incident) => ({
      id: incident.id,
      title: incident.title,
      status: incident.status,
      startedAt: incident.startedAt.toString(),
      components: incident.components.map(({ name, impact }) => ({
        name,
        impact,
      })),
      updates: incident.updates.map((update) => ({
        status: update.status,
        body: update.body,
        createdAt: update.createdAt.toString(),
      })),
    })),
  };
}
