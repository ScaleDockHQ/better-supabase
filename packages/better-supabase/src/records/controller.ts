import type { AuthPort, Controller } from "../blocks/controller.ts";
import type { RecordBindingResult } from "../blocks/record-bindings.ts";
import type {
  RecordSummary,
  RecordSummaryOptions,
  Subjects,
} from "../blocks/subjects/subjects.ts";
import type { DbError } from "../core/errors.ts";
import type { SubscriptionStatus } from "../realtime/index.ts";
import type { TopicPort } from "../realtime/watch-topic.ts";
import type { RecordRef } from "../schema/types.ts";
import type {
  LoadedBindings,
  LoadBindingsOptions,
  BindingBlocks,
  BindingName,
  BindingSource,
} from "./bindings.ts";

import { defineController, whileSignedIn } from "../blocks/controller.ts";
import { recordEventMatches } from "../blocks/record-bindings.ts";
import { findBinding, loadBindings } from "./bindings.ts";

export interface RecordControllerOptions<
  B extends BindingBlocks,
  N extends BindingName<B>,
> extends LoadBindingsOptions<B, N> {
  readonly source: BindingSource<B>;
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /** The record to follow; nothing loads without one. */
  readonly subject: RecordRef | null;
  readonly bindings: readonly N[];
  /**
   * The one private topic that hears of changes to the record, such as a
   * broadcast of its block events. A message whose event a binding lists in
   * `events` loads that binding again; any other message loads every binding.
   * Default `null`: bindings load again on `refresh` only.
   */
  readonly topic?: string | null;
  /**
   * The subjects client, to load `record_summary` (title, counts, unread) next
   * to the bindings.
   */
  readonly summary?: Pick<Subjects, "summary">;
  readonly summaryOptions?: RecordSummaryOptions;
  /**
   * Starts paused, for a page that mounts while the app is already offline.
   * `setOffline` keeps it current afterwards (ADR 0344).
   */
  readonly offline?: boolean;
}

export interface RecordSnapshot<B extends BindingBlocks, N extends string> {
  /** Each binding settled; `undefined` until the first load. */
  readonly bindings: Partial<LoadedBindings<B, N>> | undefined;
  /** The record's title, counts and unread state, with `summary`. */
  readonly summary: RecordSummary | undefined;
  readonly status: SubscriptionStatus;
  /** The error of the last summary load. */
  readonly error: DbError | undefined;
  /**
   * `true` while loads wait for a connection: the bindings keep their last data
   * and show no error. Absent until `offline` or `setOffline` is used.
   */
  readonly offline?: boolean;
}

export interface RecordActions<N extends string> {
  /** Loads the named bindings again, or every binding and the summary. */
  readonly refresh: (names?: readonly N[]) => Promise<void>;
  /**
   * Pauses loads (`true`) and keeps the names a pause held back, or resumes
   * (`false`) and loads them once. A binding whose load fails while offline
   * keeps its last data and loads again on reconnect. Calling it with the
   * current value changes nothing.
   */
  readonly setOffline: (offline: boolean) => void;
}

export type RecordController<
  B extends BindingBlocks,
  N extends string,
> = Controller<RecordSnapshot<B, N>, RecordActions<N>>;

/**
 * One record page's bindings for the signed-in user over one realtime
 * subscription (ADR 0030): it loads them with `loadBindings`, and loads a
 * binding again when `topic` carries one of its events.
 */
export function createRecordController<
  B extends BindingBlocks,
  const N extends BindingName<B>,
>(options: RecordControllerOptions<B, N>): RecordController<B, N> {
  const { source, subject, bindings } = options;
  const topic = options.topic ?? null;

  return defineController<RecordSnapshot<B, N>, RecordActions<N>>(
    {
      bindings: undefined,
      summary: undefined,
      status: "closed",
      error: undefined,
      ...(options.offline === undefined ? {} : { offline: options.offline }),
    },
    (state) => {
      const tickets = new Map<string, number>();
      let offline = options.offline === true;
      const held = new Set<N>();
      let heldSummary = false;

      const loadSummary = async (): Promise<void> => {
        if (subject === null || options.summary === undefined) {
          return;
        }

        if (offline) {
          heldSummary = true;

          return;
        }

        const ticket = (tickets.get("") ?? 0) + 1;
        tickets.set("", ticket);

        const result = await options.summary.summary({
          subject,
          sections: bindings,
          ...options.summaryOptions,
        });

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

        if (offline) {
          for (const name of names) {
            held.add(name);
          }

          return;
        }

        const mine = new Map(
          names.map((name) => {
            const ticket = (tickets.get(name) ?? 0) + 1;
            tickets.set(name, ticket);

            return [name, ticket] as const;
          }),
        );

        const loaded: Readonly<Record<string, RecordBindingResult<unknown>>> =
          await loadBindings(source, subject, names, options);

        const current = names.filter((name) => {
          if (tickets.get(name) !== mine.get(name)) {
            return false;
          }

          // The connection dropped mid-load: keep what the binding had.
          if (
            offline &&
            loaded[name]?.kind === "error" &&
            state.get().bindings?.[name] !== undefined
          ) {
            held.add(name);

            return false;
          }

          return true;
        });

        if (current.length === 0) {
          return;
        }

        state.set((snapshot) => ({
          // SAFETY: each entry is the settled result of the binding it names.
          bindings: {
            ...snapshot.bindings,
            ...Object.fromEntries(current.map((name) => [name, loaded[name]])),
          },
        }));
      };

      const refresh = async (names?: readonly N[]): Promise<void> => {
        await (names === undefined
          ? Promise.all([loadNamed(bindings), loadSummary()])
          : loadNamed(names));
      };

      const stale = (event: string): readonly N[] => {
        const matching = bindings.filter((name) =>
          (findBinding(source.blocks, name)?.binding.events ?? []).some(
            (pattern) => recordEventMatches(pattern, event),
          ),
        );

        return matching.length === 0 ? bindings : matching;
      };

      const setOffline = (next: boolean): void => {
        if (next === offline) {
          return;
        }

        offline = next;
        state.set({ offline: next });

        if (next) {
          return;
        }

        const names = [...held];
        const summary = heldSummary;
        held.clear();
        heldSummary = false;

        void Promise.all([
          loadNamed(names),
          summary ? loadSummary() : undefined,
        ]);
      };

      return {
        actions: { refresh, setOffline },
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
