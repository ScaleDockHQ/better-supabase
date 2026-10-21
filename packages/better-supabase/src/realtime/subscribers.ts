import type {
  Subscriber,
  SubscriberEvent,
  SubscriberPolicy,
} from "../core/contracts/authorization-hooks.ts";

/** The subset of `subscribers` that may read `event`, or the policy's failure. */
export type AllowedSubscribers<S extends Subscriber> =
  | { readonly ok: true; readonly allowed: readonly S[] }
  | { readonly ok: false; readonly cause: unknown };

/**
 * Runs `policy` and keeps the subscribers passed in whose `kind` and
 * `principal` it returned, so a policy can narrow a fan-out but never widen it.
 * Without a policy every subscriber stays. A throw or rejection allows no one.
 */
export async function allowedSubscribers<S extends Subscriber>(
  policy: SubscriberPolicy | undefined,
  event: SubscriberEvent,
  subscribers: readonly S[],
): Promise<AllowedSubscribers<S>> {
  if (policy === undefined || subscribers.length === 0) {
    return { ok: true, allowed: subscribers };
  }

  let kept: Set<string>;

  try {
    const returned: unknown = await policy(event, subscribers);

    if (!Array.isArray(returned)) {
      throw new TypeError("The subscriber policy did not return an array");
    }

    kept = new Set(
      returned.flatMap((entry: unknown) =>
        typeof entry === "object" &&
        entry !== null &&
        "principal" in entry &&
        typeof entry.principal === "string"
          ? [
              keyOf({
                principal: entry.principal,
                ...("kind" in entry &&
                (entry.kind === "user" || entry.kind === "service")
                  ? { kind: entry.kind }
                  : {}),
              }),
            ]
          : [],
      ),
    );
  } catch (cause) {
    return { ok: false, cause };
  }

  return {
    ok: true,
    allowed: subscribers.filter((subscriber) => kept.has(keyOf(subscriber))),
  };
}

const keyOf = (subscriber: Subscriber): string =>
  `${subscriber.kind ?? "user"}:${subscriber.principal}`;
