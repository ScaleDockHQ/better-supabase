"use client";

import { lazy, Suspense } from "react";

const MessageText = lazy(() =>
  import("./message-text").then((mod) => ({ default: mod.MessageText })),
);

/**
 * An answer's text. Markdown, syntax highlighting and the HTML parser load when
 * the first answer renders; the plain text shows until they arrive.
 */
export function MessageTextLazy({
  text,
  animating,
}: {
  text: string;
  animating: boolean;
}) {
  return (
    <Suspense fallback={<p className="whitespace-pre-wrap">{text}</p>}>
      <MessageText text={text} animating={animating} />
    </Suspense>
  );
}
