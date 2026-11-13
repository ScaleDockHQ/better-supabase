import type { BlockOptions } from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { blockCall, recordOf, recordsOf, textOf } from "../shared.ts";

/** Whether one owner has its Vault keys; never the keys themselves. */
export interface FieldKeyStatus {
  /** `tenant:<id>`, `user:<id>` or `app`. */
  readonly owner: string;
  /** The data key exists, so values sealed for the owner can be read. */
  readonly hasKey: boolean;
  /** The lookup key exists, so equality lookups on the owner's rows work. */
  readonly hasLookupKey: boolean;
}

export interface FieldEncryption {
  /**
   * The owners the caller reaches (their tenants, or themselves) and whether
   * each has a data key and a lookup key. The service role sees every owner
   * that has a key. It reads no key material.
   */
  keyStatus(): AsyncResult<readonly FieldKeyStatus[]>;
}

export interface FieldEncryptionOptions extends Pick<
  BlockOptions,
  "transport" | "schema" | "mappers"
> {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<FieldEncryption>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/**
 * The `field-encryption` block's client over `field_key_status`, which any
 * signed-in member can call. The functions that encrypt, decrypt and drop keys
 * stay with the service role and the definer functions of your tables.
 */
export function createFieldEncryption(
  options: FieldEncryptionOptions,
): FieldEncryption {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: FieldEncryption = {
    keyStatus: () =>
      call("field_key_status", {}, (value) =>
        recordsOf(value, "field_key_status").map((row) => {
          const status = recordOf(row, "field_key_status");

          return {
            owner: textOf(status["owner"]),
            hasKey: status["has_key"] === true,
            hasLookupKey: status["has_lookup_key"] === true,
          };
        }),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "field-encryption",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
