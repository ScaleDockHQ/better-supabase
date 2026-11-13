import type { AsyncResult as AsyncResultType } from "./result.ts";

import { dbError } from "./errors.ts";
import { AsyncResult, err, ok } from "./result.ts";
import { sha256Hex } from "./sha256.ts";

/** The longest `idempotencyKey`, as for the `Idempotency-Key` header. */
const IDEMPOTENCY_KEY_MAX = 255;

/**
 * What a block needs of the `idempotency` block (`createIdempotency` from
 * `better-supabase/blocks/queue`): the three calls of its protocol.
 */
export interface IdempotencyClaims {
  begin(input: {
    key: string;
    fingerprint: string;
    scope?: string | undefined;
  }): AsyncResultType<{
    state: "started" | "replay" | "running" | "mismatch";
    status: number | null;
    body: unknown;
    holder: string | undefined;
  }>;
  complete(input: {
    key: string;
    holder: string;
    status: number;
    body: unknown;
    scope?: string | undefined;
  }): AsyncResultType<boolean>;
  release(input: {
    key: string;
    holder: string;
    scope?: string | undefined;
  }): AsyncResultType<boolean>;
}

/** The option a block takes to claim `idempotencyKey`s. */
export interface IdempotencyOption {
  /** Claims the `idempotencyKey` of a create or action. */
  readonly idempotency?: IdempotencyClaims | undefined;
}

export interface IdempotentCall<T> {
  readonly claims: IdempotencyClaims | undefined;
  /** The caller's key; the call runs unclaimed when it is `undefined`. */
  readonly key: string | undefined;
  /** Separates keys of different tenants or callers. */
  readonly scope?: string | undefined;
  /** What the call is, so one key can't stand for two different calls. */
  readonly name: string;
  /** What the call sends; a retry must send the same. */
  readonly args: unknown;
  /** Makes the call and returns the raw, JSON-safe value of its response. */
  readonly run: () => AsyncResultType<unknown>;
  /** Turns the raw value (stored or fresh) into the method's data. */
  readonly decode: (raw: unknown) => T;
}

function fingerprintOf(name: string, args: unknown): Promise<string> {
  return sha256Hex(
    `${name}\n${JSON.stringify(args, (_key, value: unknown) =>
      typeof value === "bigint" ? `${value.toString()}n` : value,
    )}`,
  );
}

/**
 * Runs a create or action at most once per `idempotencyKey`, claimed through
 * the idempotency block: a retry with the same key and arguments gets the first
 * response, a retry that overlaps the first answers `conflict`
 * (`IDEMPOTENCY_KEY_IN_USE`), and the same key with other arguments answers
 * `validation` (`IDEMPOTENCY_KEY_REUSED`). A failed call releases the key so
 * the caller can retry. Without a key the call just runs.
 */
export function idempotentCall<T>(
  options: IdempotentCall<T>,
): AsyncResultType<T> {
  const { claims, key } = options;

  if (key === undefined) {
    return options.run().map(options.decode);
  }

  if (claims === undefined) {
    return AsyncResult.err(
      dbError(
        "invalid_input",
        "idempotencyKey needs the idempotency option: pass createIdempotency(...)",
        { hint: "IDEMPOTENCY_NOT_CONFIGURED" },
      ),
    );
  }

  if (key === "" || key.length > IDEMPOTENCY_KEY_MAX) {
    return AsyncResult.err(
      dbError(
        "invalid_input",
        `idempotencyKey must have 1 to ${String(IDEMPOTENCY_KEY_MAX)} characters`,
        { hint: "IDEMPOTENCY_KEY_INVALID" },
      ),
    );
  }

  const { scope } = options;

  return AsyncResult.from(async () => {
    const fingerprint = await fingerprintOf(options.name, options.args);
    const began = await claims.begin({ key, fingerprint, scope });

    if (!began.ok) {
      return began;
    }

    const { state, holder } = began.data;

    switch (state) {
      case "replay": {
        return ok(options.decode(began.data.body));
      }

      case "running": {
        return err(
          dbError(
            "conflict",
            "A call with this idempotency key is still running",
            { hint: "IDEMPOTENCY_KEY_IN_USE" },
          ),
        );
      }

      case "mismatch": {
        return err(
          dbError(
            "validation",
            "This idempotency key was used for a different call",
            {
              hint: "IDEMPOTENCY_KEY_REUSED",
              issues: [
                {
                  message: "Use a new key for a new call",
                  path: ["idempotencyKey"],
                },
              ],
            },
          ),
        );
      }

      case "started": {
        break;
      }

      default: {
        const unknown: never = state;
        throw new TypeError(`Unknown idempotency state ${String(unknown)}`);
      }
    }

    // `begin` returns the holder token whenever the state is `started`.
    const token = holder!;
    const ran = await options.run();

    if (!ran.ok) {
      await claims.release({ key, holder: token, scope });

      return ran;
    }

    await claims.complete({
      key,
      holder: token,
      status: 200,
      body: ran.data,
      scope,
    });

    return ok(options.decode(ran.data));
  });
}
