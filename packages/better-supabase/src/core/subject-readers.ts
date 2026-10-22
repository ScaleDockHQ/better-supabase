import type { BlockTransport } from "./block-transport.ts";
import type {
  Subscriber,
  SubscriberEvent,
  SubscriberPolicy,
} from "./contracts/authorization-hooks.ts";

import { DEFAULT_BLOCK_SCHEMA } from "./block-helpers.ts";

export interface SubjectReadersOptions {
  /** The schema of the `subjects` module. Default `better_supabase`. */
  readonly schema?: string;
  /** The `config.records` action to check. Default `read`. */
  readonly action?: string;
}

/**
 * A registered subject's type and id, from `subjects/<type>/<id>` or
 * `<type>/<id>`.
 */
function parseSubject(
  subject: string,
  types: ReadonlySet<string>,
): { readonly type: string; readonly id: string } | undefined {
  const rest = subject.startsWith("subjects/")
    ? subject.slice("subjects/".length)
    : subject;

  const slash = rest.indexOf("/");

  if (slash <= 0 || slash === rest.length - 1) {
    return undefined;
  }

  const type = rest.slice(0, slash);

  return types.has(type) ? { type, id: rest.slice(slash + 1) } : undefined;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The default subscriber policy under an authorization provider: a subscriber
 * gets an event about a subject in `config.records` only when `can_subject_for`
 * says it may `read` the subject (the key in
 * `config.subjects.<type>.permissions`, never a share-link grant). Events
 * without a subject, or about a type the registry doesn't list, keep every
 * subscriber, so the block's own tenant check decides them. `transport` must
 * run as the service role.
 */
export function subjectReaders(
  transport: BlockTransport,
  options: SubjectReadersOptions = {},
): SubscriberPolicy {
  const schema = options.schema ?? DEFAULT_BLOCK_SCHEMA;
  const action = options.action ?? "read";
  let types: Promise<ReadonlySet<string>> | undefined;

  const registered = (): Promise<ReadonlySet<string>> =>
    (types ??= transport
      .call(schema, "subject_types", {})
      .then(
        (value) =>
          new Set(
            Array.isArray(value)
              ? value.filter((entry) => typeof entry === "string")
              : [],
          ),
      )
      .catch((cause: unknown) => {
        types = undefined;
        throw cause;
      }));

  return async <S extends Subscriber>(
    event: SubscriberEvent,
    subscribers: readonly S[],
  ): Promise<readonly S[]> => {
    if (typeof event.subject !== "string" || subscribers.length === 0) {
      return subscribers;
    }

    const subject = parseSubject(event.subject, await registered());

    if (subject === undefined) {
      return subscribers;
    }

    const allowed = await Promise.all(
      subscribers.map(async (subscriber) =>
        UUID.test(subscriber.principal)
          ? (await transport.call(schema, "can_subject_for", {
              member: subscriber.principal,
              subject_type: subject.type,
              subject_id: subject.id,
              action,
            })) === true
          : false,
      ),
    );

    return subscribers.filter((_, index) => allowed[index]);
  };
}
