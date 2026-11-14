import "server-only";
import { cacheTag } from "next/cache";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { CRM_TAG } from "@/features/crm/crm-cache";
import { DRIVE_TAG } from "@/features/drive/drive-cache";
import { bsb } from "@/lib/supabase/server";

import type { Loaded } from "../records/records-queries";

import {
  epoch,
  epochOrNull,
  mapped,
  visible,
} from "../records/records-queries";
import { customerPage } from "./customer-record";
import { CUSTOMERS_TAG } from "./customers-cache";

export interface ShareLinkRow {
  readonly id: string;
  readonly role: string;
  /** Epoch milliseconds; `null` for a link without an expiry. */
  readonly expiresAt: number | null;
  readonly revokedAt: number | null;
  /** Past its expiry when the list was read. */
  readonly expired: boolean;
}

/** The share links the caller created or may read, revoked ones last. */
export async function getShareLinks(
  customerId: string,
): Promise<Loaded<readonly ShareLinkRow[]>> {
  const { bindings } = await customerPage.load(customerId, {
    bindings: ["shareLinks"],
  });

  const now = Temporal.Now.instant().epochMilliseconds;

  return visible(
    mapped(bindings.shareLinks, (link) => {
      const expiresAt = epochOrNull(link.expiresAt);

      return {
        id: link.id,
        role: link.role,
        expiresAt,
        revokedAt: epochOrNull(link.revokedAt),
        expired: expiresAt !== null && expiresAt <= now,
      };
    }),
  );
}

export interface VersionRow {
  readonly id: string;
  readonly number: number;
  readonly label: string | null;
  readonly source: "manual" | "auto" | "restore";
  readonly createdAt: number;
}

/** The customer's saved versions, newest first. */
export async function getVersions(
  customerId: string,
): Promise<Loaded<readonly VersionRow[]>> {
  const { bindings } = await customerPage.load(customerId, {
    bindings: ["versions"],
    options: { versions: { pageSize: 20 } },
  });

  return visible(
    mapped(bindings.versions, (version) => ({
      id: version.id,
      number: version.number,
      label: version.label ?? null,
      source: version.source,
      createdAt: epoch(version.createdAt),
    })),
  );
}

export interface SlaClockRow {
  readonly id: string;
  readonly metric: "first_response" | "next_response" | "resolution";
  readonly state: "running" | "paused" | "met" | "breached";
  readonly dueAt: number;
  /** Until the due time; negative once breached, `null` once met. */
  readonly secondsLeft: number | null;
}

/** The customer's SLA clocks, with the time left on each open one. */
export async function getSlaClocks(
  customerId: string,
): Promise<Loaded<readonly SlaClockRow[]>> {
  const { bindings } = await customerPage.load(customerId, {
    bindings: ["sla"],
  });

  return visible(
    mapped(bindings.sla, (clock) => ({
      id: clock.id,
      metric: clock.metric,
      state: clock.state,
      dueAt: epoch(clock.dueAt),
      secondsLeft: clock.secondsLeft ?? null,
    })),
  );
}

const Row = v.object({ name: v.string(), status: v.string() });

export interface SharedCustomer {
  readonly name: string;
  readonly status: string;
  /** ISO 8601. */
  readonly expiresAt: string | null;
}

/**
 * The customer a share link points to, for a visitor without a session.
 * `resolve` checks the token's hash, revocation and expiry; only then does the
 * service role read the two columns the page shows.
 */
export async function getSharedCustomer(
  token: string,
): Promise<SharedCustomer | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(CUSTOMERS_TAG, CRM_TAG, DRIVE_TAG);

  const link = await db.shareLinks.resolve({ token }).orThrow();

  if (link?.subject.type !== "customer") {
    return null;
  }

  const { data, error } = await bsb
    .admin()
    .$client.from("customers")
    .select("name, status")
    .eq("id", link.subject.id)
    .eq("organization_id", link.organizationId)
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  if (!data) {
    return null;
  }

  const row = v.parse(Row, data);

  return {
    name: row.name,
    status: row.status,
    expiresAt: link.expiresAt?.toString() ?? null,
  };
}
