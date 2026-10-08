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
      <body className="bg-background text-foreground flex min-h-svh items-center justify-center p-6 font-sans antialiased">
        <main
          role="alert"
          className="flex max-w-sm flex-col items-center gap-3 text-center"
        >
          <h1 className="text-lg font-medium">Something went wrong</h1>
          <p className="text-muted-foreground text-sm">
            Try again in a moment.
            {error.digest === undefined ? null : ` Reference: ${error.digest}`}
          </p>
          <button
            type="button"
            onClick={retry}
            className="bg-primary text-primary-foreground rounded-md px-4 py-2 text-sm font-medium"
          >
            Try again
          </button>
        </main>
      </body>
    </html>
  );
}
