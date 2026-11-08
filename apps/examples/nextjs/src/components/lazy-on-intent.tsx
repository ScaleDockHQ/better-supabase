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
}: {
  renderTrigger: (handlers: IntentHandlers) => ReactNode;
  children: ReactNode;
}) {
  const [intent, setIntent] = useState<Intent>("none");

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
      <OpenOnClick enabled={intent === "click"} />
    </Suspense>
  );
}

/** Opens the menu the user already clicked on, once it has mounted. */
function OpenOnClick({ enabled }: { enabled: boolean }) {
  const anchor = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    if (enabled) {
      anchor.current?.parentElement
        ?.querySelector<HTMLElement>("[aria-haspopup='menu']")
        ?.click();
    }
  }, [enabled]);

  return <span ref={anchor} hidden />;
}
