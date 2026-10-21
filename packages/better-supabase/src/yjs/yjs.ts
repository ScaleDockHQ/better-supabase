import type {
  DocumentRef,
  Documents,
  DocumentState,
  OpenedDocument,
} from "../blocks/documents/documents.ts";
import type {
  PresenceMember,
  PresenceSubscription,
  RealtimeClient,
  SubscriptionStatus,
} from "../realtime/topic.ts";

import { fromBase64, toBase64 } from "../core/base64.ts";
import { isRecord } from "../core/block-helpers.ts";
import { importOptionalPeer } from "../core/optional-peer.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import { defineTopic } from "../realtime/topic.ts";

type PresenceState = Readonly<Record<string, unknown>>;

/** The part of a `Y.Doc` the provider uses. */
export interface YDocLike {
  on(
    event: "update",
    handler: (update: Uint8Array, origin: unknown) => void,
  ): void;
  off(
    event: "update",
    handler: (update: Uint8Array, origin: unknown) => void,
  ): void;
}

/** The functions the provider calls from the `yjs` package. */
export interface YjsLike {
  applyUpdate(doc: never, update: Uint8Array, origin?: unknown): void;
  mergeUpdates(updates: readonly Uint8Array[]): Uint8Array;
}

function isYjs(value: unknown): value is YjsLike {
  return (
    isRecord(value) &&
    typeof value["applyUpdate"] === "function" &&
    typeof value["mergeUpdates"] === "function"
  );
}

/**
 * Loads `yjs` on first use. The specifier is a variable so bundlers leave the
 * optional peer out of apps that pass the module in.
 */
async function loadYjs(given: YjsLike | undefined): Promise<YjsLike> {
  if (given !== undefined) {
    return given;
  }

  const module = await importOptionalPeer("yjs");

  if (isYjs(module)) {
    return module;
  }

  if (isRecord(module) && isYjs(module["default"])) {
    return module["default"];
  }

  throw new TypeError(
    "better-supabase/yjs needs the yjs package: pnpm add yjs, or pass it as options.yjs",
  );
}

export interface DocumentProviderOptions<P extends PresenceState> {
  /** The `better-supabase/blocks/documents` client. */
  readonly documents: Documents;
  /** A Supabase client signed in as the editor, for the private topic. */
  readonly client: RealtimeClient;
  readonly doc: YDocLike;
  readonly ref: DocumentRef;
  /** The `yjs` module. Default: imported on first connect. */
  readonly yjs?: YjsLike;
  /** Called with everyone on the document after each presence sync. */
  readonly onPresence?: (members: readonly PresenceMember<P>[]) => void;
  readonly onStatus?: (status: DocumentProviderStatus) => void;
  /**
   * Called when a push, pull or broadcast fails; the provider retries on
   * reconnect.
   */
  readonly onError?: (error: unknown) => void;
}

export type DocumentProviderStatus =
  | "connecting"
  | "synced"
  | "offline"
  | "closed";

export interface DocumentProvider<
  P extends PresenceState,
> extends AsyncDisposable {
  /** The opened document, once `connect` resolves. */
  readonly document: OpenedDocument | undefined;
  readonly status: DocumentProviderStatus;
  /** Loads the stored state, joins the topic and starts sending edits. */
  connect(): AsyncResult<OpenedDocument>;
  /** Shares a presence state (a cursor, a name) with the other editors. */
  track(state: P): AsyncResult<void>;
  /** Everyone from the last presence sync. */
  members(): readonly PresenceMember<P>[];
  /** Waits for local edits that are still being stored. */
  flush(): Promise<void>;
  /** Stops listening to the document and leaves the topic. */
  destroy(): Promise<void>;
}

const UPDATE_EVENT = "update";

function membersOf<P extends PresenceState>(
  members: readonly PresenceMember<PresenceState>[],
): readonly PresenceMember<P>[] {
  // SAFETY: the provider validates no presence schema; P is the shape the caller's editors track.
  return members as readonly PresenceMember<P>[];
}

interface Broadcast {
  readonly seq: number;
  readonly update: string;
}

function broadcastOf(value: unknown): Broadcast | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const { seq, update } = value;

  if (typeof seq !== "number" || typeof update !== "string") {
    return undefined;
  }

  return { seq, update };
}

/**
 * Syncs a `Y.Doc` with the documents module: it loads the snapshot and updates,
 * stores each local edit, broadcasts it on the document's private topic, and
 * pulls what it missed when the channel reconnects.
 */
export function createDocumentProvider<P extends PresenceState = PresenceState>(
  options: DocumentProviderOptions<P>,
): DocumentProvider<P> {
  const { documents, client, doc } = options;
  const origin = Symbol("better-supabase/yjs");
  let yjs: YjsLike | undefined;
  let opened: OpenedDocument | undefined;

  let subscription:
    | PresenceSubscription<PresenceState, PresenceState>
    | undefined;

  let status: DocumentProviderStatus = "closed";
  let synced = 0;
  let joined = false;
  // After a failed push, edits wait for a reconnect or flush() instead of retrying each one.
  let stalled = false;
  const pending: Uint8Array[] = [];
  let sending: Promise<void> = Promise.resolve();

  const setStatus = (next: DocumentProviderStatus): void => {
    if (status === next) {
      return;
    }

    status = next;
    options.onStatus?.(next);
  };

  const fail = (error: unknown): void => {
    options.onError?.(error);
  };

  const apply = (update: Uint8Array): void => {
    // SAFETY: `doc` is the Y.Doc the caller passed; YjsLike types it as `never` so any Doc fits.
    yjs?.applyUpdate(doc as never, update, origin);
  };

  const applyState = (state: DocumentState): void => {
    if (state.snapshot !== undefined) {
      apply(state.snapshot);
      synced = Math.max(synced, state.snapshotSeq);
    }

    for (const item of state.updates) {
      apply(item.update);
      synced = Math.max(synced, item.seq);
    }
  };

  const send = (): Promise<void> => {
    sending = sending.then(async () => {
      if (opened === undefined || pending.length === 0 || yjs === undefined) {
        return;
      }

      const update =
        pending.length === 1 ? pending[0]! : yjs.mergeUpdates(pending);

      const count = pending.length;
      const pushed = await documents.push(opened.id, update);

      if (!pushed.ok) {
        stalled = true;
        fail(pushed.error);
        setStatus("offline");

        return;
      }

      stalled = false;
      pending.splice(0, count);
      const payload: Broadcast = { seq: pushed.data, update: toBase64(update) };

      const response = await subscription?.channel.send({
        type: "broadcast",
        event: UPDATE_EVENT,
        payload,
      });

      if (response !== undefined && response !== "ok") {
        fail(new Error(`broadcast failed: ${String(response)}`));
      }
    });

    return sending;
  };

  const onUpdate = (update: Uint8Array, from: unknown): void => {
    if (from === origin || opened === undefined || !opened.canWrite) {
      return;
    }

    pending.push(update);

    if (!stalled) {
      void send();
    }
  };

  const catchUp = async (): Promise<void> => {
    if (opened === undefined) {
      return;
    }

    const state = await documents.pull(opened.id, synced);

    if (!state.ok) {
      fail(state.error);

      return;
    }

    applyState(state.data);
    await send();
    setStatus("synced");
  };

  const onChannel = (next: SubscriptionStatus): void => {
    switch (next) {
      case "subscribed": {
        // The first join follows the open; later ones are reconnects.
        if (joined) {
          void catchUp();
        }

        joined = true;
        setStatus("synced");

        return;
      }

      case "closed":
      case "error": {
        if (status !== "closed") {
          setStatus("offline");
        }

        return;
      }

      case "joining": {
        return;
      }

      default: {
        const never: never = next;
        throw new TypeError(`unknown subscription status ${String(never)}`);
      }
    }
  };

  const provider: DocumentProvider<P> = {
    get document() {
      return opened;
    },
    get status() {
      return status;
    },
    connect: () =>
      AsyncResult.from(async () => {
        if (opened !== undefined) {
          return ok(opened);
        }

        setStatus("connecting");

        try {
          yjs = await loadYjs(options.yjs);
        } catch (cause) {
          setStatus("closed");
          throw cause;
        }

        const result = await documents.open(options.ref);

        if (!result.ok) {
          setStatus("closed");

          return err(result.error);
        }

        const current = result.data;
        opened = current;
        applyState(current);
        doc.on("update", onUpdate);
        const split = current.topic.lastIndexOf(":");

        const topic = defineTopic(
          `${current.topic.slice(0, split)}:{document}`,
          { private: true, send: true, presence: true, tenant: false },
        );

        subscription = topic.subscribe(
          client,
          { document: current.topic.slice(split + 1) },
          {
            [UPDATE_EVENT]: (payload: unknown) => {
              const message = broadcastOf(payload);

              if (message === undefined) {
                return;
              }

              apply(fromBase64(message.update));

              if (message.seq === synced + 1) {
                synced = message.seq;
              }
            },
          },
          {
            onStatus: onChannel,
            onPresence: (members) =>
              options.onPresence?.(membersOf<P>(members)),
          },
        );
        await subscription.ready.catch(fail);

        return ok(current);
      }),
    track: (state) =>
      subscription === undefined
        ? AsyncResult.from(() =>
            Promise.reject(
              new TypeError("connect() the provider before track()"),
            ),
          )
        : subscription.track(state),
    members: () => membersOf<P>(subscription?.members() ?? []),
    flush: () => {
      stalled = false;

      return send();
    },
    destroy: async () => {
      doc.off("update", onUpdate);
      await send().catch(fail);
      const current = subscription;
      subscription = undefined;
      opened = undefined;
      joined = false;
      setStatus("closed");
      await current?.unsubscribe();
    },
    [Symbol.asyncDispose]: () => provider.destroy(),
  };

  return provider;
}

export interface CompactDocumentOptions {
  readonly documents: Documents;
  readonly documentId: string;
  /** The `yjs` module. Default: imported on first use. */
  readonly yjs?: YjsLike;
}

/**
 * Merges a document's snapshot and updates into one state and stores it, for
 * the `documents.compact` job or a sweep over `documents.toCompact()`. Needs
 * the service role or `documents.manage`. Resolves false when there was nothing
 * to compact or a newer snapshot won.
 */
export function compactDocument(
  options: CompactDocumentOptions,
): AsyncResult<boolean> {
  return AsyncResult.from(async () => {
    const yjs = await loadYjs(options.yjs);
    const state = await options.documents.pull(options.documentId, 0);

    if (!state.ok) {
      return err(state.error);
    }

    const { snapshot, updates } = state.data;
    const last = updates.at(-1);

    if (last === undefined) {
      return ok(false);
    }

    const merged = yjs.mergeUpdates([
      ...(snapshot === undefined ? [] : [snapshot]),
      ...updates.map((item) => item.update),
    ]);

    return options.documents.compact(options.documentId, merged, last.seq);
  });
}
