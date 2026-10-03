"use client";

import { MoonIcon, SunIcon } from "lucide-react";
import { useTheme } from "next-themes";
import { useSyncExternalStore } from "react";

const subscribe = () => () => {};

/** `className` comes from the server so the button variants stay out of the client bundle. */
export function ThemeToggle({ className }: { readonly className: string }) {
  const { resolvedTheme, setTheme } = useTheme();
  // The theme is only known in the browser; the server render shows the default icon.
  const mounted = useSyncExternalStore(
    subscribe,
    () => true,
    () => false,
  );

  const isDark = mounted && resolvedTheme === "dark";

  return (
    <button
      type="button"
      data-slot="button"
      className={className}
      aria-label={isDark ? "Switch to light theme" : "Switch to dark theme"}
      onClick={() => {
        setTheme(isDark ? "light" : "dark");
      }}
    >
      {isDark ? (
        <SunIcon aria-hidden="true" />
      ) : (
        <MoonIcon aria-hidden="true" />
      )}
    </button>
  );
}
