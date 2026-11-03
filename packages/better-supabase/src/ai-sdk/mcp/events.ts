import type {
  Experimental_MCPEvent as MCPEvent,
  Experimental_MCPEventStore as MCPEventStore,
  Experimental_MCPEventSubscription as MCPEventSubscription,
  Experimental_MCPEventSubscriptionInfo as MCPEventSubscriptionInfo,
  Experimental_MCPEventWebhookOptions as MCPEventWebhookOptions,
} from "@ai-sdk/mcp";

import type { CredentialRef } from "../../credentials/provider.ts";
import type { VaultCredentials } from "../../credentials/vault.ts";

import { isRecord } from "../../core/block-helpers.ts";
import { DbException } from "../../core/errors.ts";

export interface PostgresMcpEventStoreOptions {
  /** `vaultCredentials({ transport })` with the service role. */
  readonly vault: VaultCredentials;
  /**
   * What the subscriptions belong to: one MCP server and one principal, such as
   * `<serverId>:<userId>`. Keys and ids are stored under it.
   */
  readonly scope: string;
  /** The Vault tenant, when the app stores secrets per tenant. */
  readonly tenant?: string;
}

const subject = { type: "app" as const };

/**
 * An `Experimental_MCPEventStore` that keeps each subscription, including its
 * signing secret, as one Vault secret, with a second secret that maps the
 * server's subscription id to the key. Nothing is readable by a browser or by
 * the `authenticated` role.
 *
 * `update` reads, merges and writes, so it isn't atomic: serialize updates to
 * one key (the webhook route does, per delivery) or run it in a queue.
 */
export function postgresMcpEventStore(
  options: PostgresMcpEventStoreOptions,
): MCPEventStore {
  const { vault } = options;

  const ref = (name: string): CredentialRef => ({
    provider: "vault",
    secret: `mcp-events:${options.scope}:${name}`,
    scope: "app",
    ...(options.tenant === undefined ? {} : { tenant: options.tenant }),
  });

  const read = async (name: string): Promise<string | undefined> => {
    const stored = await vault.getToken(ref(name), { subject, fresh: true });

    return stored.ok ? stored.data.token : undefined;
  };

  const write = async (name: string, value: string): Promise<void> => {
    const saved = await vault.set(ref(name), value, {
      subject,
      description: "MCP event subscription",
    });

    if (!saved.ok) {
      throw new DbException(saved.error);
    }
  };

  const remove = async (name: string): Promise<void> => {
    await vault.revoke(ref(name), { subject });
  };

  const parse = (
    text: string | undefined,
  ): MCPEventSubscription | undefined => {
    if (text === undefined) {
      return undefined;
    }

    try {
      const value: unknown = JSON.parse(text);

      // SAFETY: only this store writes the secret, as a subscription.
      return isRecord(value) ? (value as MCPEventSubscription) : undefined;
    } catch {
      return undefined;
    }
  };

  const get: MCPEventStore["get"] = async (key) =>
    parse(await read(`key:${key}`));

  return {
    get,
    getById: async (id) => {
      const key = await read(`id:${id}`);

      return key === undefined ? undefined : get(key);
    },
    set: async (subscription) => {
      await write(`key:${subscription.key}`, JSON.stringify(subscription));

      if (subscription.id !== undefined) {
        await write(`id:${subscription.id}`, subscription.key);
      }
    },
    update: async (key, patch) => {
      const current = await get(key);

      if (!current) {
        return;
      }

      const next = { ...current, ...patch };
      await write(`key:${key}`, JSON.stringify(next));

      if (next.id !== undefined && next.id !== current.id) {
        await write(`id:${next.id}`, key);
      }
    },
    delete: async (key) => {
      const current = await get(key);

      await remove(`key:${key}`);

      if (current?.id !== undefined) {
        await remove(`id:${current.id}`);
      }
    },
  };
}

export interface DedupeMcpEventsOptions {
  /**
   * Records `key` and returns `true` the first time, `false` for a repeat: an
   * `insert ... on conflict do nothing` on a table the app owns works.
   */
  readonly claim: (key: string) => Promise<boolean>;
}

type Handlers = Pick<
  MCPEventWebhookOptions,
  "onEvent" | "onGap" | "onTerminated"
>;

/**
 * Wraps the webhook handlers so a delivery the server sent twice runs once.
 * Events dedupe on subscription id and `eventId`, gaps and terminations on
 * subscription id and `messageId`, as the AI SDK asks.
 */
export function dedupeMcpEvents(
  handlers: Handlers,
  options: DedupeMcpEventsOptions,
): Handlers {
  const once = async (key: string, run: () => Promise<void>): Promise<void> => {
    if (await options.claim(key)) {
      await run();
    }
  };

  const { onGap, onTerminated } = handlers;

  return {
    onEvent: ({
      subscription,
      event,
    }: {
      subscription: MCPEventSubscriptionInfo;
      event: MCPEvent;
    }) =>
      once(`${subscription.id}:event:${event.eventId}`, () =>
        handlers.onEvent({ subscription, event }),
      ),
    ...(onGap
      ? {
          onGap: (args: Parameters<NonNullable<Handlers["onGap"]>>[0]) =>
            once(`${args.subscription.id}:gap:${args.messageId}`, () =>
              onGap(args),
            ),
        }
      : {}),
    ...(onTerminated
      ? {
          onTerminated: (
            args: Parameters<NonNullable<Handlers["onTerminated"]>>[0],
          ) =>
            once(`${args.subscription.id}:end:${args.messageId}`, () =>
              onTerminated(args),
            ),
        }
      : {}),
  };
}
