import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { TenantProvider, useTenant } from "../../src/react/tenant.ts";

function Slug() {
  return <span>{useTenant<{ id: string; slug: string }>().slug}</span>;
}

describe("TenantProvider and useTenant", () => {
  it("gives a client component the record without props", () => {
    expect(
      renderToString(
        <TenantProvider value={{ id: "org-1", slug: "acme" }}>
          <Slug />
        </TenantProvider>,
      ),
    ).toContain("acme");
  });

  it("throws outside a provider", () => {
    expect(() => renderToString(<Slug />)).toThrow("TenantProvider");
  });
});
