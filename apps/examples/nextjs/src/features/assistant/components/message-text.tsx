// #region recipe:chat-message-markdown
"use client";

import { code } from "@streamdown/code";
import { Streamdown } from "streamdown";

/**
 * Model output is untrusted: only these elements render (no images, raw HTML or
 * forms), and a link must be http, https or mailto.
 */
const ALLOWED_ELEMENTS = [
  "p",
  "br",
  "hr",
  "strong",
  "em",
  "del",
  "a",
  "ul",
  "ol",
  "li",
  "blockquote",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "code",
  "pre",
  "table",
  "thead",
  "tbody",
  "tr",
  "th",
  "td",
];

const SAFE_URL = /^(https?:|mailto:|#)/i;

const safeUrl = (url: string): string => (SAFE_URL.test(url) ? url : "");

const PLUGINS = { code };

/**
 * An answer's text as Markdown. While it streams, the caret follows the last
 * word; a stored answer renders once, in static mode.
 */
export function MessageText({
  text,
  animating,
}: {
  text: string;
  animating: boolean;
}) {
  return (
    <Streamdown
      mode={animating ? "streaming" : "static"}
      plugins={PLUGINS}
      isAnimating={animating}
      caret="block"
      allowedElements={ALLOWED_ELEMENTS}
      urlTransform={safeUrl}
      linkSafety={{ enabled: true }}
    >
      {text}
    </Streamdown>
  );
}
// #endregion recipe:chat-message-markdown
