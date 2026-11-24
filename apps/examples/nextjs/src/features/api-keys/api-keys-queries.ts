import "server-only";
import type { ApiKeyState } from "better-supabase/blocks/api-keys";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { bsb } from "@/lib/supabase/server";

import { API_KEYS_TAG } from "./api-keys-cache";

export interface ApiKeyDetail {
  readonly id: string;
  readonly name: string;
  readonly token: string;
  readonly state: ApiKeyState;
  readonly personal: boolean;
  readonly scopes: readonly string[];
  readonly rateLimit: number | undefined;
  readonly kind: string | undefined;
  /** ISO 8601. */
  readonly createdAt: string;
  readonly lastUsedAt: string | undefined;
  readonly expiresAt: string | undefined;
  /** In the future while a rotated key's grace period runs. */
  readonly graceEndsAt: string | undefined;
  readonly rotatedFrom: string | undefined;
  readonly successorId: string | undefined;
}

/**
 * One key of the organization; `undefined` when it does not exist, `null`
 * without an organization. The token shown is the prefix and public id: the
 * secret is only ever shown once, when the key is created or rotated.
 */
export async function loadApiKey(
  id: string,
): Promise<ApiKeyDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(API_KEYS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { items } = await db.apiKeys
    .keyPage({ organizationId: tenant, limit: 100 })
    .orThrow();

  const key = items.find((entry) => entry.id === id);

  if (key === undefined) {
    return undefined;
  }

  return {
    id: key.id,
    name: key.name,
    token: `${key.prefix}_${key.publicId}…`,
    state: key.state,
    personal: key.userId !== undefined,
    scopes: key.scopes,
    rateLimit: key.rateLimit,
    kind: key.kind,
    createdAt: key.createdAt.toString(),
    lastUsedAt: key.lastUsedAt?.toString(),
    expiresAt: key.expiresAt?.toString(),
    graceEndsAt: key.state === "grace" ? key.revokedAt?.toString() : undefined,
    rotatedFrom: key.rotatedFrom,
    successorId: key.successorId,
  };
}

export interface ApiKeyCounts {
  readonly active: number;
  readonly grace: number;
  readonly unused: number;
  readonly retired: number;
}

/** The counts of the keys overview; `null` without an organization. */
export async function loadApiKeyCounts(): Promise<ApiKeyCounts | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(API_KEYS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { items } = await db.apiKeys
    .keyPage({ organizationId: tenant, limit: 100 })
    .orThrow();

  const live = items.filter((key) => key.state === "active");

  return {
    active: live.length,
    grace: items.filter((key) => key.state === "grace").length,
    unused: live.filter((key) => key.lastUsedAt === undefined).length,
    retired: items.filter(
      (key) => key.state !== "active" && key.state !== "grace",
    ).length,
  };
}
