import type { CloudEvent, EventSink } from "../../events/cloud-event.ts";
import type { Search } from "./search.ts";

import { stripTypePrefix } from "../../events/cloud-event.ts";
import { isRecord, optionalText } from "../shared.ts";

/** What an event does to the index. */
export type SearchSinkAction = "remove" | "refresh";

/**
 * The events a soft-delete block emits, as `searchSink` handles them by
 * default: trashing or purging drops the subject, restoring reads it again.
 */
export const SEARCH_SINK_DEFAULTS: Readonly<Record<string, SearchSinkAction>> =
  {
    "subject.trashed": "remove",
    "subject.purged": "remove",
    "subject.restored": "refresh",
  };

export interface SearchSinkOptions {
  /**
   * Event type (without `typePrefix`) to its action. Default
   * `SEARCH_SINK_DEFAULTS`.
   */
  readonly on?: Readonly<Record<string, SearchSinkAction | undefined>>;
  /** Stripped from each event type. Defaults to `dev.better-supabase`. */
  readonly typePrefix?: string;
}

function subjectOf(
  event: CloudEvent,
): { readonly type: string; readonly id: string } | undefined {
  if (!isRecord(event.data)) {
    return undefined;
  }

  const type = optionalText(event.data["subjectType"]);
  const id = optionalText(event.data["subjectId"]);

  return type === undefined || id === undefined ? undefined : { type, id };
}

/**
 * An outbox sink that keeps the index in step with soft deletes the registry's
 * `deletedAt` column doesn't describe, such as a trash table:
 * `outbox.relay('search', searchSink(search))`. Build `search` with a service
 * transport. A subject type without a `search` entry is skipped.
 */
export function searchSink(
  search: Pick<Search, "remove" | "refresh">,
  options: SearchSinkOptions = {},
): EventSink {
  const actions = options.on ?? SEARCH_SINK_DEFAULTS;

  return {
    async send(events) {
      for (const event of events) {
        const action = actions[stripTypePrefix(event.type, options.typePrefix)];

        if (action === undefined) {
          continue;
        }

        const subject = subjectOf(event);

        if (subject === undefined) {
          continue;
        }

        const result =
          action === "remove"
            ? await search.remove(subject.type, subject.id)
            : await search.refresh(subject.type, subject.id);

        if (!result.ok && result.error.hint !== "SEARCH_SUBJECT_UNKNOWN") {
          throw new Error(
            `searchSink: ${action} ${subject.type}/${subject.id} failed: ${result.error.message}`,
          );
        }
      }
    },
  };
}
