import type {
  AuthorizationHooks,
  Subscriber,
  SubscriberEvent,
  SubscriberPolicy,
} from "../core/contracts/authorization-hooks.ts";
import type { TemplateValues } from "../core/template.ts";
import type { EventSchemas, TopicEvent, TopicPayload } from "./topic.ts";

import { dbError, type DbError } from "../core/errors.ts";
import { AsyncResult, err, ok, type Result } from "../core/result.ts";
import { allowedSubscribers } from "./subscribers.ts";

export interface TopicFanOutOptions<
  P extends string,
  E extends EventSchemas,
  K extends TopicEvent<E>,
  S extends Subscriber,
> {
  readonly subscribers: readonly S[];
  /**
   * The topic values of one subscriber, e.g. `(s) => ({ userId: s.principal
   * })`.
   */
  readonly values: (subscriber: S) => TemplateValues<P>;
  readonly event: K;
  readonly payload: TopicPayload<E, K>;
  /** What the subscriber policy reads about the event. */
  readonly source: SubscriberEvent;
  /**
   * Defaults to the topic's `subscribers`, then
   * `server.authorization.delivery.subscribers`. With `server.authorization`
   * and none of them, an event with a `subject` goes to no one
   * (`REALTIME_SUBSCRIBER_POLICY_REQUIRED`); pass `subjectReaders(transport)`.
   */
  readonly policy?: SubscriberPolicy;
  readonly server?: { readonly authorization?: AuthorizationHooks | undefined };
}

export interface FanOutResult<S> {
  readonly sent: readonly S[];
  /** Left out by the subscriber policy. */
  readonly skipped: readonly S[];
  /** Sends that failed, with their error. */
  readonly failed: readonly {
    readonly subscriber: S;
    readonly error: DbError;
  }[];
}

/** Runs the policy, then `send` for each subscriber it keeps, one at a time. */
export function fanOutTopic<S extends Subscriber>(
  fallback: SubscriberPolicy | undefined,
  options: {
    readonly subscribers: readonly S[];
    readonly source: SubscriberEvent;
    readonly policy?: SubscriberPolicy;
    readonly server?: {
      readonly authorization?: AuthorizationHooks | undefined;
    };
  },
  send: (subscriber: S) => PromiseLike<Result<void>>,
): AsyncResult<FanOutResult<S>> {
  return AsyncResult.from(async () => {
    const policy =
      options.policy ??
      fallback ??
      options.server?.authorization?.delivery?.subscribers;

    if (
      policy === undefined &&
      options.server?.authorization !== undefined &&
      typeof options.source.subject === "string"
    ) {
      return err(
        dbError(
          "forbidden",
          "An event with a subject needs a subscriber policy under an authorization provider, such as subjectReaders(transport)",
          { hint: "REALTIME_SUBSCRIBER_POLICY_REQUIRED" },
        ),
      );
    }

    const checked = await allowedSubscribers(
      policy,
      options.source,
      options.subscribers,
    );

    if (!checked.ok) {
      return err(
        dbError(
          "forbidden",
          "The subscriber policy failed, so the event went to no one",
          { hint: "REALTIME_SUBSCRIBER_POLICY_FAILED" },
        ),
      );
    }

    const allowed = new Set(checked.allowed);
    const sent: S[] = [];
    const failed: { subscriber: S; error: DbError }[] = [];

    for (const subscriber of checked.allowed) {
      const result = await send(subscriber);

      if (result.ok) {
        sent.push(subscriber);
      } else {
        failed.push({ subscriber, error: result.error });
      }
    }

    return ok({
      sent,
      skipped: options.subscribers.filter(
        (subscriber) => !allowed.has(subscriber),
      ),
      failed,
    });
  });
}
