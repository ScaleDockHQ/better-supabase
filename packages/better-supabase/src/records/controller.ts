import type { AuthPort, Controller } from "../blocks/controller.ts";
import type { SectionResult } from "../blocks/sections.ts";
import type {
  RecordSummary,
  RecordSummaryOptions,
  Subjects,
} from "../blocks/subjects/subjects.ts";
import type { DbError } from "../core/errors.ts";
import type { SubscriptionStatus } from "../realtime/index.ts";
import type { TopicPort } from "../realtime/watch-topic.ts";
import type { SubjectRef } from "../schema/types.ts";
import type {
  LoadedSections,
  LoadSectionsOptions,
  SectionBlocks,
  SectionName,
  SectionSource,
} from "./sections.ts";

import { defineController, whileSignedIn } from "../blocks/controller.ts";
import { sectionEventMatches } from "../blocks/sections.ts";
import { findSection, loadSections } from "./sections.ts";

export interface RecordControllerOptions<
  B extends SectionBlocks,
  N extends SectionName<B>,
> extends LoadSectionsOptions<B, N> {
  readonly source: SectionSource<B>;
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /** The record to follow; nothing loads without one. */
  readonly subject: SubjectRef | null;
  readonly sections: readonly N[];
  /**
   * The one private topic that hears of changes to the record, such as a
   * broadcast of its block events. A message whose event a section lists in
   * `events` loads that section again; any other message loads every section.
   * Default `null`: sections load again on `refresh` only.
   */
  readonly topic?: string | null;
  /**
   * The subjects client, to load `record_summary` (title, counts, unread) next
   * to the sections.
   */
  readonly summary?: Pick<Subjects, "summary">;
  readonly summaryOptions?: RecordSummaryOptions;
}

export interface RecordSnapshot<B extends SectionBlocks, N extends string> {
  /** Each section settled; `undefined` until the first load. */
  readonly sections: Partial<LoadedSections<B, N>> | undefined;
  /** The record's title, counts and unread state, with `summary`. */
  readonly summary: RecordSummary | undefined;
  readonly status: SubscriptionStatus;
  /** The error of the last summary load. */
  readonly error: DbError | undefined;
}

export interface RecordActions<N extends string> {
  /** Loads the named sections again, or every section and the summary. */
  readonly refresh: (names?: readonly N[]) => Promise<void>;
}

export type RecordController<
  B extends SectionBlocks,
  N extends string,
> = Controller<RecordSnapshot<B, N>, RecordActions<N>>;

/**
 * One record page's sections for the signed-in user over one realtime
 * subscription (ADR 0030): it loads them with `loadSections`, and loads a
 * section again when `topic` carries one of its events.
 */
export function createRecordController<
  B extends SectionBlocks,
  const N extends SectionName<B>,
>(options: RecordControllerOptions<B, N>): RecordController<B, N> {
  const { source, subject, sections } = options;
  const topic = options.topic ?? null;

  return defineController<RecordSnapshot<B, N>, RecordActions<N>>(
    {
      sections: undefined,
      summary: undefined,
      status: "closed",
      error: undefined,
    },
    (state) => {
      const tickets = new Map<string, number>();

      const loadSummary = async (): Promise<void> => {
        if (subject === null || options.summary === undefined) {
          return;
        }

        const ticket = (tickets.get("") ?? 0) + 1;
        tickets.set("", ticket);

        const result = await options.summary.summary(
          subject,
          sections,
          options.summaryOptions,
        );

        if (tickets.get("") !== ticket) {
          return;
        }

        state.set(
          result.ok
            ? { summary: result.data, error: undefined }
            : { error: result.error },
        );
      };

      const loadNamed = async (names: readonly N[]): Promise<void> => {
        if (subject === null || names.length === 0) {
          return;
        }

        const mine = new Map(
          names.map((name) => {
            const ticket = (tickets.get(name) ?? 0) + 1;
            tickets.set(name, ticket);

            return [name, ticket] as const;
          }),
        );

        const loaded: Readonly<Record<string, SectionResult<unknown>>> =
          await loadSections(source, subject, names, options);

        const current = names.filter(
          (name) => tickets.get(name) === mine.get(name),
        );

        if (current.length === 0) {
          return;
        }

        state.set((snapshot) => ({
          // SAFETY: each entry is the settled result of the section it names.
          sections: {
            ...snapshot.sections,
            ...Object.fromEntries(current.map((name) => [name, loaded[name]])),
          },
        }));
      };

      const refresh = async (names?: readonly N[]): Promise<void> => {
        await (names === undefined
          ? Promise.all([loadNamed(sections), loadSummary()])
          : loadNamed(names));
      };

      const stale = (event: string): readonly N[] => {
        const matching = sections.filter((name) =>
          (findSection(source.blocks, name)?.section.events ?? []).some(
            (pattern) => sectionEventMatches(pattern, event),
          ),
        );

        return matching.length === 0 ? sections : matching;
      };

      return {
        actions: { refresh },
        start: () =>
          subject === null
            ? undefined
            : whileSignedIn(options.auth, () => {
                void refresh();

                if (topic === null) {
                  return;
                }

                const { leave } = options.ports.topic(topic, {
                  onMessage: (event) => {
                    void Promise.all([loadNamed(stale(event)), loadSummary()]);
                  },
                  onRejoin: () => void refresh(),
                  onStatus: (status) => {
                    state.set({ status });
                  },
                });

                return leave;
              }),
      };
    },
  );
}
