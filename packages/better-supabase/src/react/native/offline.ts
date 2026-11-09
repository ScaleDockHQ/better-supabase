import type { ReactNode } from "react";

import { createElement, useEffect, useState } from "react";

import { OfflineContext } from "../offline.ts";

/** The part of `@react-native-community/netinfo` this boundary uses. */
export interface NetInfoLike {
  fetch(): Promise<{ readonly isConnected: boolean | null }>;
  addEventListener(
    listener: (state: { readonly isConnected: boolean | null }) => void,
  ): { remove(): void };
}

/**
 * Pauses data hooks while the device has no connection. Pass NetInfo from
 * `@react-native-community/netinfo`. Vite and React Native both use this;
 * Next.js keeps its own offline boundary.
 */
export function OfflineBoundary({
  netInfo,
  children,
}: {
  readonly netInfo: NetInfoLike;
  readonly children: ReactNode;
}): ReactNode {
  const [offline, setOffline] = useState(false);

  useEffect(() => {
    let active = true;

    const apply = (state: { readonly isConnected: boolean | null }): void => {
      if (active) {
        setOffline(state.isConnected === false);
      }
    };

    void netInfo.fetch().then(apply);
    const subscription = netInfo.addEventListener(apply);

    return () => {
      active = false;
      subscription.remove();
    };
  }, [netInfo]);

  return createElement(OfflineContext, { value: offline }, children);
}
