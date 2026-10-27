"use client";

import { useEffect } from "react";

/** The same URL as the push opt-in, so both resolve to one registration. */
const WORKER_URL = "/sw.js";

/**
 * Registers `public/sw.js` in production builds. `next dev` skips it: the
 * worker's cache of `/_next/static` would serve stale chunks between edits.
 */
export function ServiceWorkerRegistrar() {
  useEffect(() => {
    if (
      process.env.NODE_ENV !== "production" ||
      !("serviceWorker" in navigator)
    ) {
      return;
    }

    navigator.serviceWorker
      .register(WORKER_URL, { scope: "/", updateViaCache: "none" })
      .catch(() => {
        console.warn("Service worker registration failed");
      });
  }, []);

  return null;
}
