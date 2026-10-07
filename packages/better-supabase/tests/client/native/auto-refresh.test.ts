import { describe, expect, it } from "vitest";

import {
  type AppStateLike,
  autoRefreshOnForeground,
} from "../../../src/client/native/auto-refresh.ts";

function fakeAppState(currentState: string) {
  const listeners = new Set<(state: string) => void>();
  const appState: AppStateLike = {
    currentState,
    addEventListener: (_type, listener) => {
      listeners.add(listener);
      return { remove: () => listeners.delete(listener) };
    },
  };
  const change = (state: string): void => {
    for (const listener of listeners) listener(state);
  };
  return { appState, change, listeners };
}

function fakeSupabase() {
  const calls: string[] = [];
  return {
    calls,
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
  };
}

describe("autoRefreshOnForeground", () => {
  it("starts at once when the app is already active", () => {
    const { supabase, calls } = fakeSupabase();
    autoRefreshOnForeground(supabase, fakeAppState("active").appState);
    expect(calls).toEqual(["start"]);
  });

  it("waits for the foreground when the app starts in the background", () => {
    const { supabase, calls } = fakeSupabase();
    autoRefreshOnForeground(supabase, fakeAppState("background").appState);
    expect(calls).toEqual([]);
  });

  it("follows the app between foreground and background", () => {
    const { supabase, calls } = fakeSupabase();
    const { appState, change } = fakeAppState("background");
    autoRefreshOnForeground(supabase, appState);
    change("active");
    change("inactive");
    change("background");
    change("active");
    expect(calls).toEqual(["start", "stop", "stop", "start"]);
  });

  it("removes the listener and stops refreshing when unsubscribed", () => {
    const { supabase, calls } = fakeSupabase();
    const { appState, change, listeners } = fakeAppState("active");
    const unsubscribe = autoRefreshOnForeground(supabase, appState);
    unsubscribe();
    change("active");
    expect(listeners.size).toBe(0);
    expect(calls).toEqual(["start", "stop"]);
  });
});
