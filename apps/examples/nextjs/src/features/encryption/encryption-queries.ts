import "server-only";
import type {
  EncryptedColumn,
  FieldKeyStatus,
} from "better-supabase/blocks/field-encryption";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { FieldEntity } from "@/features/custom-fields/custom-fields-types";

import { CUSTOM_FIELDS_TAG } from "@/features/custom-fields/custom-fields-cache";
import { FIELD_ENTITIES } from "@/features/custom-fields/custom-fields-types";
import { bsb } from "@/lib/supabase/server";

import { ENCRYPTION_TAG } from "./encryption-cache";

export interface EncryptedField {
  readonly id: string;
  readonly entity: FieldEntity;
  readonly key: string;
  readonly label: string;
  readonly type: string;
}

/** When a key was made and last rotated, as ISO strings for the cache. */
export interface EncryptionKeyDates {
  readonly createdAt: string;
  readonly rotatedAt: string | undefined;
}

export interface EncryptionView {
  /** The owner whose Vault key encrypts the organization's values. */
  readonly keyOwner: string;
  /** The data key, `undefined` before the first encrypted write. */
  readonly key: EncryptionKeyDates | undefined;
  /** The lookup key that hashes values for equality searches. */
  readonly lookupKey: EncryptionKeyDates | undefined;
  /** The app table columns the key encrypts. */
  readonly columns: readonly EncryptedColumn[];
  readonly fields: readonly EncryptedField[];
  /** How many fields are not sensitive, so stored as plain values. */
  readonly plain: number;
}

/** The data key's dates, as ISO strings for the cache. */
const keyOf = (
  status: FieldKeyStatus | undefined,
): EncryptionKeyDates | undefined =>
  status?.keyCreatedAt === undefined
    ? undefined
    : {
        createdAt: status.keyCreatedAt.toString(),
        rotatedAt: status.keyRotatedAt?.toString(),
      };

/** The lookup key's dates; a lookup key is never rotated. */
const lookupKeyOf = (
  status: FieldKeyStatus | undefined,
): EncryptionKeyDates | undefined =>
  status?.lookupKeyCreatedAt === undefined
    ? undefined
    : { createdAt: status.lookupKeyCreatedAt.toString(), rotatedAt: undefined };

/**
 * The organization's key status from the field-encryption block
 * (`field_key_status()`, no key material) and the custom fields whose values it
 * seals (the sensitive ones). Throws on a failed read, so the private cache
 * never keeps an error.
 */
export async function getEncryptionView(): Promise<EncryptionView | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(CUSTOM_FIELDS_TAG, ENCRYPTION_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const keyOwner = `tenant:${tenant}`;

  const [statuses, lists] = await Promise.all([
    db.fieldEncryption.keyStatus().orThrow(),
    Promise.all(
      FIELD_ENTITIES.map(async (entity) => {
        const definitions = await db.customFields
          .listDefinitions(entity)
          .orThrow();

        return definitions.map((definition) => ({ entity, definition }));
      }),
    ),
  ]);

  const all = lists.flat();
  const status = statuses.find((entry) => entry.owner === keyOwner);

  return {
    keyOwner,
    key: keyOf(status),
    lookupKey: lookupKeyOf(status),
    columns: status?.columns ?? [],
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
