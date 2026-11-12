import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { FieldEntity } from "@/features/custom-fields/custom-fields-types";

import { CUSTOM_FIELDS_TAG } from "@/features/custom-fields/custom-fields-cache";
import { FIELD_ENTITIES } from "@/features/custom-fields/custom-fields-types";
import { bsb } from "@/lib/supabase/server";

export interface EncryptedField {
  readonly id: string;
  readonly entity: FieldEntity;
  readonly key: string;
  readonly label: string;
  readonly type: string;
}

export interface EncryptionView {
  /** The owner whose Vault key encrypts the organization's values. */
  readonly keyOwner: string;
  readonly fields: readonly EncryptedField[];
  /** How many fields are not sensitive, so stored as plain values. */
  readonly plain: number;
}

/**
 * The custom fields whose values the field-encryption block seals with the
 * organization's data key (the sensitive ones). Throws on a failed read, so the
 * private cache never keeps an error.
 */
export async function getEncryptionView(): Promise<EncryptionView | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(CUSTOM_FIELDS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const lists = await Promise.all(
    FIELD_ENTITIES.map(async (entity) => {
      const definitions = await db.customFields
        .listDefinitions(entity)
        .orThrow();

      return definitions.map((definition) => ({ entity, definition }));
    }),
  );

  const all = lists.flat();

  return {
    keyOwner: `tenant:${tenant}`,
    fields: all
      .filter(({ definition }) => definition.sensitive)
      .map(({ entity, definition }) => ({
        id: definition.id,
        entity,
        key: definition.key,
        label: definition.label,
        type: definition.type,
      })),
    plain: all.filter(({ definition }) => !definition.sensitive).length,
  };
}
