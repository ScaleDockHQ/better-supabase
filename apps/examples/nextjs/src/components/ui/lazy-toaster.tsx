"use client";

import dynamic from "next/dynamic";
import { useEffect, useState } from "react";

const Toaster = dynamic(
  () => import("@/components/ui/sonner").then((mod) => mod.Toaster),
  { ssr: false },
);

/**
 * Mounts the toaster after the first paint, so its code stays out of the first
 * load. A toast fired before it mounts is rare: toasts answer an action.
 */
export function LazyToaster() {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const id = window.setTimeout(() => setReady(true), 0);

    return () => window.clearTimeout(id);
  }, []);

  return ready ? <Toaster /> : null;
}
