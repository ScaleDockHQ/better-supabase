import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";

import { COMMUNITY_TAG } from "@/features/community/community-cache";
import { CRM_TAG } from "@/features/crm/crm-cache";
import { CUSTOM_FIELDS_TAG } from "@/features/custom-fields/custom-fields-cache";
import { CUSTOMERS_TAG } from "@/features/customers/customers-cache";
import { DRIVE_TAG } from "@/features/drive/drive-cache";
import { FIELD_TAG } from "@/features/field/field-cache";
import { FORMS_TAG } from "@/features/forms/forms-cache";
import { MANUFACTURING_TAG } from "@/features/manufacturing/manufacturing-cache";
import { PEOPLE_TAG } from "@/features/people/people-cache";
import { PROJECTS_TAG } from "@/features/projects/projects-cache";
import { SEQUENCES_TAG } from "@/features/sequences/sequences-cache";
import { SHOP_TAG } from "@/features/shop/shop-cache";
import { TEMPLATES_TAG } from "@/features/templates/templates-cache";
import { WORK_TAG } from "@/features/work/work-cache";
import { bsb } from "@/lib/supabase/server";

export interface TrashEntry {
  readonly id: string;
  readonly subjectType: string;
  readonly title: string | null;
  readonly count: number;
  /** ISO 8601, so the cached value stays serializable. */
  readonly trashedAt: string;
  readonly purgeAfter: string | null;
}

export type TrashView =
  | { readonly kind: "ok"; readonly items: readonly TrashEntry[] }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/** The trash, newest first. A failed read throws, so Retry reads again. */
async function loadTrash(): Promise<readonly TrashEntry[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(
    DRIVE_TAG,
    CUSTOMERS_TAG,
    CRM_TAG,
    PROJECTS_TAG,
    WORK_TAG,
    SHOP_TAG,
    FORMS_TAG,
    TEMPLATES_TAG,
    PEOPLE_TAG,
    FIELD_TAG,
    MANUFACTURING_TAG,
    COMMUNITY_TAG,
    SEQUENCES_TAG,
    CUSTOM_FIELDS_TAG,
  );
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const items = await db.trash
    .list({ organizationId: tenant, pageSize: 100 })
    .orThrow();

  return items.map((item) => ({
    id: item.id,
    subjectType: item.subjectType,
    title: item.title ?? null,
    count: item.count,
    trashedAt: item.trashedAt.toString(),
    purgeAfter: item.purgeAfter?.toString() ?? null,
  }));
}

export async function getTrash(): Promise<TrashView> {
  try {
    const items = await loadTrash();

    return items === null ? { kind: "no-organization" } : { kind: "ok", items };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
