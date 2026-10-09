import { describe, expect, it } from "vitest";

import type { AppStateLike } from "../../../src/client/native/auto-refresh.ts";
import type {
  FocusManagerLike,
  NetInfoLike,
  OnlineManagerLike,
} from "../../../src/client/native/query.ts";

import { syncQueryWithApp } from "../../../src/client/native/query.ts";

function fakeAppState(currentState: string) {
  const listeners = new Set<(state: string) => void>();
  const appState: AppStateLike = {
    currentState,
    addEventListener: (_type, listener) => {
      listeners.add(listener);
      return { remove: () => listeners.delete(listener) };
    },
  };
  return {
    appState,
    listeners,
    change: (state: string) => {
      for (const listener of listeners) listener(state);
    },
  };
}

function fakeManager<V>() {
  const values: V[] = [];
  let cleanup: (() => void) | undefined;
  const manager = {
    setEventListener(
      setup: (set: (value: V) => void) => (() => void) | undefined,
    ) {
      cleanup?.();
      cleanup = setup((value) => values.push(value));
    },
  };
  return { manager, values };
}

describe("syncQueryWithApp", () => {
  it("reports focus from the app state and stops on cleanup", () => {
    const app = fakeAppState("background");
    const focus = fakeManager<boolean | undefined>();
    const stop = syncQueryWithApp({
      focusManager: focus.manager satisfies FocusManagerLike,
      appState: app.appState,
    });
    app.change("active");
    app.change("inactive");
    expect(focus.values).toEqual([false, true, false]);
    stop();
    expect(app.listeners.size).toBe(0);
  });

  it("reports online from NetInfo, treating an unreachable internet as offline", () => {
    const app = fakeAppState("active");
    const focus = fakeManager<boolean | undefined>();
    const online = fakeManager<boolean>();
    type State = Parameters<Parameters<NetInfoLike["addEventListener"]>[0]>[0];
    const listeners = new Set<(state: State) => void>();
    const netInfo: NetInfoLike = {
      addEventListener: (listener) => {
        listeners.add(listener);
        return () => listeners.delete(listener);
      },
    };
    const stop = syncQueryWithApp({
      focusManager: focus.manager,
      onlineManager: online.manager satisfies OnlineManagerLike,
      appState: app.appState,
      netInfo,
    });
    for (const listener of listeners) {
      listener({ isConnected: true, isInternetReachable: true });
      listener({ isConnected: true, isInternetReachable: false });
      listener({ isConnected: null });
    }
    expect(online.values).toEqual([true, false, false]);
    stop();
    expect(listeners.size).toBe(0);
  });

  it("refreshes the session only in the foreground", () => {
    const app = fakeAppState("active");
    const calls: string[] = [];
    const stop = syncQueryWithApp({
      focusManager: fakeManager<boolean | undefined>().manager,
      appState: app.appState,
      supabase: {
        auth: {
          startAutoRefresh: () => {
            calls.push("start");
            return Promise.resolve();
          },
          stopAutoRefresh: () => {
            calls.push("stop");
            return Promise.resolve();
          },
        },
      },
    });
    app.change("background");
    expect(calls).toEqual(["start", "stop"]);
    stop();
  });
});
