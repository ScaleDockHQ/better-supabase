import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { builderFor } from "@/features/workflows/builder/builder-server";
import { bsb } from "@/lib/supabase/server";

import type { ChangeLifecycle } from "./change-request-lifecycle";

import {
  CHANGE_SUBJECT,
  CHANGE_WORKFLOW,
  getLifecycle,
} from "./change-request-lifecycle";
import { CHANGE_REQUESTS_TAG } from "./change-requests-cache";

export interface ChangeRequestRow {
  readonly id: string;
  readonly title: string;
  readonly status: string | null;
  readonly createdAt: string;
}

export interface ChangeRequestsData {
  /** `null` until the tenant publishes its `change-requests` workflow. */
  readonly lifecycle: (ChangeLifecycle & { readonly version: number }) | null;
  readonly rows: readonly ChangeRequestRow[];
}

/**
 * The organization's change requests, newest first, with the stages and moves
 * of its published `change-requests` workflow. `null` without a tenant.
 */
export async function getChangeRequests(): Promise<ChangeRequestsData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached({ tables: ["changeRequests"] });
  cacheTag(CHANGE_REQUESTS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const builder = builderFor(db.$client);

  const [resolved, rows] = await Promise.all([
    builder.definitions
      .resolve({ tenant, purpose: "lifecycle", subjectType: CHANGE_SUBJECT })
      .orThrow(),
    db.changeRequests
      .list({
        select: ["id", "title", "status", "createdAt"],
        orderBy: { createdAt: "desc" },
        limit: 100,
      })
      .orThrow(),
  ]);

  const version =
    resolved?.definition.slug === CHANGE_WORKFLOW
      ? await builder.versions.get(resolved.version.id).orThrow()
      : undefined;

  return {
    lifecycle:
      version?.graph === undefined
        ? null
        : { ...getLifecycle(version.graph), version: version.version },
    rows: rows.map((row) => ({
      id: row.id,
      title: row.title,
      status: row.status,
      createdAt: row.createdAt,
    })),
  };
}
