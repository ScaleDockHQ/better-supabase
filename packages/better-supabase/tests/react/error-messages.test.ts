import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { dbError } from "../../src/core/errors.ts";
import {
  ErrorMessagesProvider,
  useErrorMessage,
} from "../../src/react/error-messages.ts";

function Probe() {
  const message = useErrorMessage();

  return createElement("p", null, message(dbError("not_found", "English")));
}

describe("useErrorMessage", () => {
  it("falls back to the error's own message", () => {
    expect(renderToStaticMarkup(createElement(Probe))).toBe("<p>English</p>");
  });

  it("uses the resolver of the nearest provider", () => {
    const html = renderToStaticMarkup(
      createElement(
        ErrorMessagesProvider,
        { messages: (error) => `nl ${error.kind}` },
        createElement(Probe),
      ),
    );

    expect(html).toBe("<p>nl not_found</p>");
  });
});
