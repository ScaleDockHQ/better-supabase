import type { BlockOptions } from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  optionalInstant,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** An app table column an owner's kind of key encrypts. */
export interface EncryptedColumn {
  readonly table: string;
  readonly column: string;
}

/** Whether one owner has its Vault keys, and what they protect; never the keys. */
export interface FieldKeyStatus {
  /** `tenant:<id>`, `user:<id>` or `app`. */
  readonly owner: string;
  /** The data key exists, so values sealed for the owner can be read. */
  readonly hasKey: boolean;
  /** The lookup key exists, so equality lookups on the owner's rows work. */
  readonly hasLookupKey: boolean;
  /** When the data key was created; `undefined` without one. */
  readonly keyCreatedAt: Temporal.Instant | undefined;
  /** When `rotateKey` last replaced the data key; `undefined` until then. */
  readonly keyRotatedAt: Temporal.Instant | undefined;
  readonly lookupKeyCreatedAt: Temporal.Instant | undefined;
  /** The app table columns this kind of owner's key encrypts. */
  readonly columns: readonly EncryptedColumn[];
  /** How many encrypted custom fields the owner has. */
  readonly fields: number;
}

/** What `rotateKey` did. */
export interface FieldKeyRotation {
  readonly owner: string;
  /** How many stored rows were encrypted again under the new key. */
  readonly values: number;
  readonly rotatedAt: Temporal.Instant;
}

export interface FieldEncryption {
  /**
   * The owners the caller reaches (their tenants, or themselves) and whether
   * each has a data key and a lookup key, with the key dates and what they
   * encrypt. The service role sees every owner that has a key. It reads no key
   * material.
   */
  keyStatus(): AsyncResult<readonly FieldKeyStatus[]>;
  /**
   * Replaces the owner's data key and encrypts every stored value again in one
   * transaction. Needs `field_encryption.manage` in the tenant, or the service
   * role for a user's or the app's key.
   */
  rotateKey(owner: string): AsyncResult<FieldKeyRotation>;
}

export interface FieldEncryptionOptions
  extends
    Pick<BlockOptions, "transport" | "schema" | "mappers">,
    BlockTemporalOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<FieldEncryption>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

function statusOf(value: unknown): FieldKeyStatus {
  const status = recordOf(value, "field_key_status");

  return {
    owner: textOf(status["owner"]),
    hasKey: status["has_key"] === true,
    hasLookupKey: status["has_lookup_key"] === true,
    keyCreatedAt: optionalInstant(status["key_created_at"]),
    keyRotatedAt: optionalInstant(status["key_rotated_at"]),
    lookupKeyCreatedAt: optionalInstant(status["lookup_key_created_at"]),
    columns: recordsOf(status["columns"], "field_key_status").map((column) => ({
      table: textOf(column["table"]),
      column: textOf(column["column"]),
    })),
    fields: Number(status["fields"] ?? 0),
  };
}

function rotationOf(value: unknown): FieldKeyRotation {
  const row = recordOf(value, "rotate_field_key");

  return {
    owner: textOf(row["owner"]),
    values: Number(row["values"] ?? 0),
    rotatedAt: requiredInstant(row["rotated_at"], "rotated_at"),
  };
}

/**
 * The `field-encryption` block's client over `field_key_status`, which any
 * signed-in member can call, and `rotate_field_key`. The functions that
 * encrypt, decrypt and drop keys stay with the service role and the definer
 * functions of your tables.
 */
export function createFieldEncryption(
  options: FieldEncryptionOptions,
): FieldEncryption {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: FieldEncryption = {
    keyStatus: () =>
      call("field_key_status", {}, (value) =>
        recordsOf(value, "field_key_status").map(statusOf),
      ),
    rotateKey: (owner) => call("rotate_field_key", { owner }, rotationOf),
  };

  return withBlockHooks(client, options.hooks, {
    block: "field-encryption",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
