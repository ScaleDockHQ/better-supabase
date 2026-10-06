import { describe, expect, it, vi } from "vitest";

import { emitBlockEvent } from "../../src/core/block-events.ts";
import { EventHub } from "../../src/core/events.ts";
import {
  type CloudEvent,
  forwardBlockEvents,
  blockCloudEvent,
} from "../../src/events/index.ts";

const fixed = {
  id: () => "evt-1",
  source: "/crm",
};
const time = Temporal.Instant.from("2026-01-01T00:00:00Z");

describe("block CloudEvents", () => {
  it("maps a block event to a CloudEvent", () => {
    expect(
      blockCloudEvent(
        {
          type: "invitation.accepted",
          data: { invitationId: "i1", organizationId: "o1" },
          subject: "invitations/i1",
          tenant: "o1",
          actorId: "u1",
          time,
        },
        fixed,
      ),
    ).toEqual({
      specversion: "1.0",
      id: "evt-1",
      source: "/crm",
      type: "dev.better-supabase.invitation.accepted",
      subject: "invitations/i1",
      time: "2026-01-01T00:00:00Z",
      datacontenttype: "application/json",
      data: { invitationId: "i1", organizationId: "o1", actorId: "u1" },
      partitionkey: "o1",
    });
    const plain = blockCloudEvent(
      { type: "organization.created", data: { organizationId: "o1" }, time },
      { source: "/crm", typePrefix: "com.acme", now: () => time },
    );
    expect(plain.type).toBe("com.acme.organization.created");
    expect(plain).not.toHaveProperty("subject");
    expect(plain).not.toHaveProperty("partitionkey");
    expect(plain.id).toMatch(/^[\da-f-]{36}$/);
  });

  it("forwards matching block events and reports sink failures", async () => {
    const events = new EventHub();
    const sent: CloudEvent[][] = [];
    const stop = forwardBlockEvents(
      { events },
      { send: (batch) => void sent.push([...batch]) },
      { ...fixed, types: ["support.*", "organization.created"] },
    );
    emitBlockEvent(events, "support.started", {
      sessionId: "s1",
      adminId: "a1",
      targetUserId: "u1",
    });
    emitBlockEvent(events, "organization.created", { organizationId: "o1" });
    emitBlockEvent(events, "organization.switched", { organizationId: "o1" });
    stop();
    emitBlockEvent(events, "organization.created", { organizationId: "o2" });
    expect(sent.map((batch) => batch.map((event) => event.type))).toEqual([
      ["dev.better-supabase.support.started"],
      ["dev.better-supabase.organization.created"],
    ]);

    const onError = vi.fn();
    forwardBlockEvents(
      { events },
      { send: () => Promise.reject(new Error("down")) },
      { ...fixed, onError },
    );
    forwardBlockEvents(
      { events },
      {
        send: () => {
          throw new Error("sync");
        },
      },
      { ...fixed, onError },
    );
    emitBlockEvent(events, "webhook.failed", { endpointId: "e1" });
    await events.settled();
    expect(onError.mock.calls.map(([error]) => String(error))).toEqual([
      "Error: sync",
      "Error: down",
    ]);
  });

  it("logs sink failures without onError", async () => {
    const error = vi.fn();
    const events = new EventHub({
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error,
    });
    forwardBlockEvents(
      { events },
      { send: () => Promise.reject(new Error("down")) },
      fixed,
    );
    emitBlockEvent(events, "organization.created", { organizationId: "o1" });
    await events.settled();
    expect(error).toHaveBeenCalledWith("event sink failed", {
      cause: expect.any(Error),
    });
  });
});
