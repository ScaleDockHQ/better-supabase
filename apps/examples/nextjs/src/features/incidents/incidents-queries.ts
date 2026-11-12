import "server-only";
import type {
  IncidentSeverity,
  IncidentStatus,
} from "better-supabase/blocks/incidents";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { bsb } from "@/lib/supabase/server";

import { INCIDENTS_TAG } from "./incidents-cache";

export interface IncidentRow {
  readonly id: string;
  readonly title: string;
  readonly severity: IncidentSeverity;
  readonly status: IncidentStatus;
  readonly public: boolean;
  readonly impactCount: number;
  readonly startedAt: string;
  readonly resolvedAt: string | null;
}

/** The newest incidents of the organization, open and resolved. */
export async function getIncidents(): Promise<readonly IncidentRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(INCIDENTS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const rows = await db.incidents
    .list({ organizationId: tenant, pageSize: 50 })
    .orThrow();

  return rows.map((incident) => ({
    id: incident.id,
    title: incident.title,
    severity: incident.severity,
    status: incident.status,
    public: incident.public,
    impactCount: incident.impacts.length,
    startedAt: incident.startedAt.toString(),
    resolvedAt: incident.resolvedAt?.toString() ?? null,
  }));
}

export interface IncidentUpdateRow {
  readonly id: string;
  readonly status: IncidentStatus;
  readonly body: string;
  readonly public: boolean;
  readonly createdAt: string;
}

export interface IncidentDetailData extends IncidentRow {
  readonly description: string | null;
  readonly updates: readonly IncidentUpdateRow[];
  readonly postmortemStatus: "draft" | "published" | null;
}

/** One incident with its timeline; `null` when it does not exist. */
export async function getIncident(
  id: string,
): Promise<IncidentDetailData | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(INCIDENTS_TAG);

  const incident = await db.incidents.get(id).orThrow();

  if (!incident) {
    return null;
  }

  return {
    id: incident.id,
    title: incident.title,
    severity: incident.severity,
    status: incident.status,
    public: incident.public,
    impactCount: incident.impacts.length,
    startedAt: incident.startedAt.toString(),
    resolvedAt: incident.resolvedAt?.toString() ?? null,
    description: incident.description ?? null,
    updates: incident.updates.map((update) => ({
      id: update.id,
      status: update.status,
      body: update.body,
      public: update.public,
      createdAt: update.createdAt.toString(),
    })),
    postmortemStatus: incident.postmortem?.status ?? null,
  };
}
