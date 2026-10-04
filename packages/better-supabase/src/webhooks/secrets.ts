import type { KitTransport } from "../core/kit-transport.ts";

export interface RotateSecretOptions {
  /** How long older secrets keep signing, e.g. `'24 hours'` (the default). */
  readonly overlap?: string;
  /** Use this secret instead of a generated one, e.g. when migrating. */
  readonly secret?: string;
}

/**
 * Where endpoint signing secrets live. `sqlSecretStore` (Vault or a
 * column, set in `kits.webhooks-out.options.secretStorage`) is the default;
 * implement it for a KMS or a secrets manager.
 */
export interface WebhookSecretStore {
  readonly apiVersion: 1;
  /** The live secrets of an endpoint, newest first. */
  secrets(endpointId: string): Promise<readonly string[]>;
  /** Creates a new secret and returns it once. */
  rotate?(endpointId: string, options?: RotateSecretOptions): Promise<string>;
}

/** The kit's `webhook_secrets` and `rotate_webhook_secret` functions. */
export function sqlSecretStore(
  transport: KitTransport,
  options: { readonly schema?: string } = {},
): WebhookSecretStore {
  const schema = options.schema ?? "better_supabase";
  return {
    apiVersion: 1,
    async secrets(endpointId) {
      const value = await transport.call(schema, "webhook_secrets", {
        endpoint: endpointId,
      });
      return Array.isArray(value)
        ? value.filter((entry): entry is string => typeof entry === "string")
        : [];
    },
    async rotate(endpointId, rotateOptions = {}) {
      const value = await transport.call(schema, "rotate_webhook_secret", {
        endpoint: endpointId,
        overlap: rotateOptions.overlap,
        secret: rotateOptions.secret,
      });
      return String(value);
    },
  };
}
