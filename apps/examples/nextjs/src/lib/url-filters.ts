import { useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";

/**
 * A list filter kept in the URL, as `useState` would give it. The value follows
 * every change at once and the URL catches up after `wait` milliseconds, so a
 * shared link carries the filter without a history entry per letter. A value
 * equal to `fallback` leaves the query string. A back or forward step puts the
 * URL's value in.
 */
export function useUrlParam(
  key: string,
  fallback: string,
  wait = 0,
): readonly [string, (value: string) => void] {
  const fromUrl = useSearchParams().get(key) ?? fallback;
  const [value, setValue] = useState(fromUrl);
  const [seen, setSeen] = useState(fromUrl);
  const [written, setWritten] = useState(fromUrl);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);

  if (fromUrl !== seen) {
    setSeen(fromUrl);

    if (fromUrl !== written) {
      setWritten(fromUrl);
      setValue(fromUrl);
    }
  }

  useEffect(
    () => () => {
      clearTimeout(timer.current);
    },
    [],
  );

  return [
    value,
    (next) => {
      setValue(next);
      clearTimeout(timer.current);

      timer.current = setTimeout(() => {
        const query = new URLSearchParams(window.location.search);
        setWritten(next);

        if (next === fallback) {
          query.delete(key);
        } else {
          query.set(key, next);
        }

        const search = query.toString();

        // Next keeps `useSearchParams` in step with `history.replaceState`.
        window.history.replaceState(
          null,
          "",
          search === ""
            ? window.location.pathname
            : `${window.location.pathname}?${search}`,
        );
      }, wait);
    },
  ];
}

/** `?q=` for a list's search box. */
export function useSearchParam(): readonly [string, (value: string) => void] {
  return useUrlParam("q", "", 250);
}
