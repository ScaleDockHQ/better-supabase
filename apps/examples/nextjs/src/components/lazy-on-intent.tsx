"use client";

import type { ReactNode } from "react";

import { Suspense, useEffect, useRef, useState } from "react";

type Intent = "none" | "hover" | "click";

export interface IntentHandlers {
  readonly onPointerEnter: () => void;
  readonly onFocus: () => void;
  readonly onClick: () => void;
}

function hovered(current: Intent): Intent {
  return current === "none" ? "hover" : current;
}

/**
 * Renders the closed trigger from `renderTrigger` until the pointer or focus
 * reaches it, then mounts `children`, a `React.lazy` component whose code loads
 * on that first intent. A click before the code arrived opens the real menu
 * once it mounts, so no click is lost.
 */
export function LazyOnIntent({
  renderTrigger,
  children,
  shortcut = false,
}: {
  renderTrigger: (handlers: IntentHandlers) => ReactNode;
  children: ReactNode;
  /**
   * Cmd+K or Ctrl+K counts as a click, and once the code mounts the same
   * shortcut is sent to it, for a menu that opens on the shortcut.
   */
  shortcut?: boolean;
}) {
  const [intent, setIntent] = useState<Intent>("none");

  useEffect(() => {
    if (!shortcut || intent !== "none") {
      return;
    }

    const listen = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setIntent("click");
      }
    };

    window.addEventListener("keydown", listen);

    return () => {
      window.removeEventListener("keydown", listen);
    };
  }, [shortcut, intent]);

  const closed = renderTrigger({
    onPointerEnter: () => {
      setIntent(hovered);
    },
    onFocus: () => {
      setIntent(hovered);
    },
    onClick: () => {
      setIntent("click");
    },
  });

  if (intent === "none") {
    return closed;
  }

  return (
    <Suspense fallback={closed}>
      {children}
      <OpenOnClick enabled={intent === "click"} shortcut={shortcut} />
    </Suspense>
  );
}

/** Opens the menu the user already clicked on, once it has mounted. */
function OpenOnClick({
  enabled,
  shortcut,
}: {
  enabled: boolean;
  shortcut: boolean;
}) {
  const anchor = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    if (!enabled) {
      return;
    }

    if (shortcut) {
      window.dispatchEvent(
        new KeyboardEvent("keydown", { key: "k", ctrlKey: true }),
      );

      return;
    }

    anchor.current?.parentElement
      ?.querySelector<HTMLElement>("[aria-haspopup]")
      ?.click();
  }, [enabled, shortcut]);

  return <span ref={anchor} hidden />;
}
