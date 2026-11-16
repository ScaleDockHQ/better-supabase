import { describe, expect, it } from "vitest";

import { createImpersonation } from "../../../src/blocks/impersonation/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";

const SESSION = {
  id: "s1",
  admin_id: "a1",
  target_user_id: "u1",
  reason: "support ticket",
  read_only: true,
  tenant: null,
  started_at: AT,
  expires_at: AT,
  ended_at: AT,
  ended_by: "admin",
  metadata: { ticket: 7 },
};

describe("support session pages", () => {
  it("maps the rows of the page and the get", async () => {
    const transport = fieldsTransport({
      page_support_sessions: () => ({ items: [SESSION], hasMore: false }),
      get_support_session: () => SESSION,
    });

    const impersonation = createImpersonation({ transport });
    const page = await impersonation.sessionPage().orThrow();

    expect(page.items[0]).toMatchObject({
      id: "s1",
      endedBy: "admin",
      metadata: { ticket: 7 },
    });
    expect((await impersonation.getSession("s1").orThrow()).readOnly).toBe(
      true,
    );
    expect(transport.calls[0]).toEqual([
      "page_support_sessions",
      { filters: { paged: true } },
    ]);
  });
});
