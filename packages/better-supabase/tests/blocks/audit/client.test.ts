import { describe, expect, it, vi } from "vitest";

import type {
  AuditListOptions,
  AuditPage,
  AuditRecord,
} from "../../../src/blocks/audit/audit-log.ts";

import { createAuditLogController } from "../../../src/blocks/audit/client.ts";
import {
  failed,
  fakeAuth,
  flush,
  mount,
  resolved,
  SIGNED_OUT,
  signedIn,
  OTHER,
} from "../../fixtures/ports.ts";

const entry = (id: string): AuditRecord => ({
  id,
  occurredAt: Temporal.Instant.from("2026-10-06T12:00:00Z"),
  eventType: "invitation.created",
});

function setup(organizationId: string | null = "org-1") {
  const auth = fakeAuth();
  const list = vi.fn((options?: AuditListOptions) =>
    resolved<AuditPage>(
      options?.cursor
        ? { entries: [entry("e3")], next: undefined }
        : {
            entries: [entry("e1"), entry("e2")],
            next: {
              occurredAt: Temporal.Instant.from("2026-10-06T12:00:00Z"),
              id: "e2",
            },
          },
    ),
  );
  const controller = createAuditLogController({
    client: { list },
    auth,
    organizationId,
    filters: { eventType: "invitation.created" },
    limit: 2,
  });
  return { auth, list, controller };
}

describe("createAuditLogController", () => {
  it("loads the newest page with the first filters, then older pages", async () => {
    const { list, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    expect(list).toHaveBeenCalledWith({
      organizationId: "org-1",
      order: "desc",
      eventType: "invitation.created",
      limit: 2,
    });
    expect(view().entries?.map((each) => each.id)).toEqual(["e1", "e2"]);
    expect(view().hasMore).toBe(true);
    expect(view().loading).toBe(false);
    await view().loadMore();
    expect(view().entries?.map((each) => each.id)).toEqual(["e1", "e2", "e3"]);
    expect(view().hasMore).toBe(false);
    await view().loadMore();
    expect(list).toHaveBeenCalledTimes(2);
    unmount();
  });

  it("loads the first page again for new filters, without empty ones", async () => {
    const { list, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    const filtering = view().setFilters({
      actorId: OTHER,
      eventType: "",
      search: "  ada ",
    });
    expect(view().entries).toBeUndefined();
    expect(view().loading).toBe(true);
    await filtering;
    expect(list).toHaveBeenLastCalledWith({
      organizationId: "org-1",
      order: "desc",
      actorId: OTHER,
      search: "ada",
      limit: 2,
    });
    expect(view().filters).toEqual({
      actorId: OTHER,
      eventType: "",
      search: "  ada ",
    });
    unmount();
  });

  it("keeps a failed page's error, and waits without an organization or a session", async () => {
    const { list, controller } = setup();
    list.mockReturnValueOnce(failed("no audit.read"));
    const { view, unmount } = mount(controller);
    await flush();
    expect(view().error?.message).toBe("no audit.read");
    expect(view().entries).toBeUndefined();
    unmount();

    const idle = setup(null);
    const idleView = mount(idle.controller);
    await idleView.view().refresh();
    expect(idle.list).not.toHaveBeenCalled();
    idleView.unmount();

    const signedOut = setup();
    signedOut.auth.set(SIGNED_OUT);
    const outView = mount(signedOut.controller);
    await flush();
    expect(signedOut.list).not.toHaveBeenCalled();
    signedOut.auth.set(signedIn());
    await flush();
    expect(signedOut.list).toHaveBeenCalledTimes(1);
    outView.unmount();
  });
});
