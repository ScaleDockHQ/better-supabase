import "server-only";
import { tenantOf } from "better-supabase/next";

import { getSession } from "@/features/user/user-queries";
import { bs } from "@/lib/supabase/server";

import { knowledge } from "./knowledge-server";

export interface DocumentRow {
  readonly id: string;
  readonly title: string;
  readonly status: "pending" | "ready" | "failed";
  readonly chunks: number;
  /** ISO 8601. */
  readonly createdAt: string;
}

/** The documents the caller can read in the active organization. Not cached: status changes as embedding runs. */
export async function getDocuments(): Promise<readonly DocumentRow[]> {
  const [session, { supabase }] = await Promise.all([
    getSession(),
    bs.context(),
  ]);
  const organizationId = tenantOf(session);
  if (!organizationId) return [];
  const documents = await knowledge(supabase)
    .documents.list(organizationId, { limit: 50 })
    .orThrow();
  return documents.map((document) => ({
    id: document.id,
    title: document.title,
    status: document.status,
    chunks: document.chunkCount,
    createdAt: document.createdAt.toString(),
  }));
}
