"use client";

import "./globals.css";

/**
 * An error in the root layout. It replaces the document, outside the
 * `[locale]` layout and its message provider, so the copy is English.
 */
export default function GlobalError({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  return (
    <html lang="en">
      <body className="flex min-h-svh items-center justify-center bg-background p-6 font-sans text-foreground antialiased">
        <main
          role="alert"
          className="flex max-w-sm flex-col items-center gap-3 text-center"
        >
          <h1 className="text-lg font-medium">Something went wrong</h1>
          <p className="text-sm text-muted-foreground">
            Try again in a moment.
            {error.digest === undefined ? null : ` Reference: ${error.digest}`}
          </p>
          <button
            type="button"
            onClick={retry}
            className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground"
          >
            Try again
          </button>
        </main>
      </body>
    </html>
  );
}
