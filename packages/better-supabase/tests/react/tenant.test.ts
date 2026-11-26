import { createElement } from "react";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { TenantProvider, useTenant } from "../../src/react/tenant.ts";

function Slug() {
  return createElement(
    "span",
    null,
    useTenant<{ id: string; slug: string }>().slug,
  );
}

describe("TenantProvider and useTenant", () => {
  it("gives a client component the record without props", () => {
    expect(
      renderToString(
        createElement(
          TenantProvider,
          { value: { id: "org-1", slug: "acme" } } as never,
          createElement(Slug),
        ),
      ),
    ).toContain("acme");
  });

  it("throws outside a provider", () => {
    expect(() => renderToString(createElement(Slug))).toThrow("TenantProvider");
  });
});
