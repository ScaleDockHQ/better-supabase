import type { SessionStatusBody } from "../../server/session-status.ts";

/**
 * Why the session changed: Auth ended it or banned the user, the user signed
 * out, or the claims or support target behind the session changed.
 */
export type SessionChangeReason =
  | "ended"
  | "banned"
  | "signed_out"
  | "claims_changed";

export interface SessionWatchEvent {
  readonly reason: SessionChangeReason;
  /** The route's answer; `null` when another tab reported the change. */
  readonly status: SessionStatusBody | null;
  /** `check`: this tab saw it. `tab`: another tab of the app did. */
  readonly source: "check" | "tab";
}

export interface SessionWatchOptions {
  /** Where `sessionStatusRoute` is mounted. Defaults to `/api/session-status`. */
  readonly url?: string;
  /**
   * Milliseconds between checks while the page is visible. Defaults to 60000; 0
   * checks on focus and visibility only.
   */
  readonly intervalMs?: number;
  /**
   * The fingerprint the page rendered with, such as from the session status of
   * the server render. Without it the first check sets it.
   */
  readonly fingerprint?: string | null;
  /**
   * The `BroadcastChannel` that tells the app's other tabs, or `false` for
   * none. Defaults to `better-supabase:session`.
   */
  readonly channel?: string | false;
  readonly fetch?: typeof fetch;
  /** Called with every answer of the route, changed or not. */
  readonly onStatus?: (status: SessionStatusBody) => void;
}

export interface SessionWatcher {
  /** Checks now; a check already running is reused. */
  check(): Promise<SessionStatusBody | undefined>;
  stop(): void;
}

interface TabMessage {
  readonly type: "better-supabase:session";
  readonly reason: SessionChangeReason;
  readonly fingerprint: string | null;
}

const REASONS = new Set<string>([
  "ended",
  "banned",
  "signed_out",
  "claims_changed",
]);

function isTabMessage(value: unknown): value is TabMessage {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const message: Partial<Record<keyof TabMessage, unknown>> = value;

  return (
    message.type === "better-supabase:session" &&
    typeof message.reason === "string" &&
    REASONS.has(message.reason) &&
    (message.fingerprint === null || typeof message.fingerprint === "string")
  );
}

function isBody(value: unknown): value is SessionStatusBody {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const body: Partial<Record<keyof SessionStatusBody, unknown>> = value;

  return (
    typeof body.status === "string" &&
    (body.fingerprint === null || typeof body.fingerprint === "string")
  );
}

/**
 * Watches the session through `sessionStatusRoute`: checks when the window gets
 * focus or becomes visible and on an interval while visible, and calls
 * `onChange` when the session ended, the user was banned or signed out, or the
 * claims fingerprint changed. Each change is posted to the app's other tabs,
 * which call their own `onChange` with `source: "tab"`. Failed checks are
 * ignored and retried on the next trigger.
 */
export function watchSession(
  onChange: (event: SessionWatchEvent) => void,
  options: SessionWatchOptions = {},
): SessionWatcher {
  const url = options.url ?? "/api/session-status";
  const intervalMs = options.intervalMs ?? 60_000;
  const doFetch = options.fetch ?? globalThis.fetch.bind(globalThis);
  const channelName = options.channel ?? "better-supabase:session";
  let baseline: string | null | undefined = options.fingerprint;
  let running: Promise<SessionStatusBody | undefined> | undefined;
  let stopped = false;

  const channel =
    channelName !== false && typeof BroadcastChannel === "function"
      ? new BroadcastChannel(channelName)
      : undefined;

  const visible = (): boolean =>
    !("document" in globalThis) ||
    globalThis.document.visibilityState !== "hidden";

  const report = (reason: SessionChangeReason, status: SessionStatusBody) => {
    const message: TabMessage = {
      type: "better-supabase:session",
      reason,
      fingerprint: status.fingerprint,
    };

    // oxlint-disable-next-line unicorn/require-post-message-target-origin -- BroadcastChannel.postMessage takes no target origin (1 finding).
    channel?.postMessage(message);
    onChange({ reason, status, source: "check" });
  };

  const settle = (status: SessionStatusBody): void => {
    if (status.status === "expired") {
      return;
    }

    const next = status.status === "active" ? status.fingerprint : null;
    const previous = baseline;
    baseline = next;

    if (previous === undefined || previous === next) {
      return;
    }

    if (next === null) {
      report(
        status.status === "ended" || status.status === "banned"
          ? status.status
          : "signed_out",
        status,
      );

      return;
    }

    report("claims_changed", status);
  };

  const run = async (): Promise<SessionStatusBody | undefined> => {
    try {
      const response = await doFetch(url, {
        method: "GET",
        credentials: "same-origin",
        cache: "no-store",
        headers: { accept: "application/json" },
      });

      if (!response.ok) {
        await response.body?.cancel();

        return undefined;
      }

      const body: unknown = await response.json();

      if (!isBody(body) || stopped) {
        return undefined;
      }

      options.onStatus?.(body);
      settle(body);

      return body;
    } catch {
      return undefined;
    }
  };

  const check = (): Promise<SessionStatusBody | undefined> => {
    running ??= run().finally(() => {
      running = undefined;
    });

    return running;
  };

  const onVisible = (): void => {
    if (visible()) {
      void check();
    }
  };

  const onMessage = (event: MessageEvent<unknown>): void => {
    if (!isTabMessage(event.data)) {
      return;
    }

    baseline = event.data.fingerprint;
    onChange({ reason: event.data.reason, status: null, source: "tab" });
  };

  channel?.addEventListener("message", onMessage);

  if (typeof window !== "undefined") {
    window.addEventListener("focus", onVisible);
  }

  if (typeof document !== "undefined") {
    document.addEventListener("visibilitychange", onVisible);
  }

  const timer = intervalMs > 0 ? setInterval(onVisible, intervalMs) : undefined;

  void check();

  return {
    check,
    stop: () => {
      if (stopped) {
        return;
      }

      stopped = true;

      if (timer !== undefined) {
        clearInterval(timer);
      }

      if (typeof window !== "undefined") {
        window.removeEventListener("focus", onVisible);
      }

      if (typeof document !== "undefined") {
        document.removeEventListener("visibilitychange", onVisible);
      }

      channel?.removeEventListener("message", onMessage);
      channel?.close();
    },
  };
}
