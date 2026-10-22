import "server-only";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { blocks } from "@/lib/blocks";
import { bsb } from "@/lib/supabase/server";

import type { FieldEntity, FieldRow } from "./custom-fields-types";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "no-organization" }
  | { readonly kind: "error" };

/**
 * One entity's field definitions in display order. Throws on a failed read, so
 * the private cache never keeps an error.
 */
async function loadFields(
  entity: FieldEntity,
): Promise<readonly FieldRow[] | null> {
  "use cache: private";
  const { session, supabase } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const definitions = await blocks(supabase, tenant)
    .customFields.listDefinitions(entity)
    .orThrow();

  return definitions.map((definition) => ({
    id: definition.id,
    key: definition.key,
    label: definition.label,
    type: definition.type,
    sensitive: definition.sensitive,
  }));
}

export async function getFields(
  entity: FieldEntity,
): Promise<Loaded<readonly FieldRow[]>> {
  try {
    const data = await loadFields(entity);

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
