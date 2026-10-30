import { describe, expect, it, vi } from "vitest";

import {
  currentEventTypes,
  currentPermissionKeys,
  EVENT_TYPE_RENAMES,
  EVENT_TYPE_SPLITS,
  isOldEventType,
  isOldPermissionKey,
  legacyEventType,
  PERMISSION_KEY_RENAMES,
  PERMISSION_KEY_SPLITS,
  renamed,
  upgradePermissionKey,
} from "../../src/core/renames.ts";
import {
  DEFAULT_ROLES,
  OPERATIONS,
} from "../../src/sql/modules/permissions-model.ts";

const KEY = /^[a-z][a-z_]*\.(?:\*|[a-z][a-z_]*)$/;

describe("renames", () => {
  it("maps old names to new ones and leaves the rest", () => {
    expect(renamed(PERMISSION_KEY_RENAMES, "parties.read")).toBe(
      "contacts.read",
    );
    expect(renamed(PERMISSION_KEY_RENAMES, "contacts.read")).toBe(
      "contacts.read",
    );
    expect(renamed(PERMISSION_KEY_RENAMES, "toString")).toBe("toString");
  });

  it("only renames to keys that follow the convention", () => {
    for (const next of [
      ...Object.values(PERMISSION_KEY_RENAMES),
      ...Object.values(PERMISSION_KEY_SPLITS).flat(),
    ]) {
      expect(next).toMatch(KEY);
      expect(isOldPermissionKey(next)).toBe(false);
    }
  });

  it("lists no old key in the operations or the default roles", () => {
    const keys = [
      ...Object.values(OPERATIONS),
      ...Object.values(DEFAULT_ROLES).flat(),
    ];

    expect(keys.filter((key) => isOldPermissionKey(key))).toEqual([]);
    expect(keys.filter((key) => key !== "*" && !KEY.test(key))).toEqual([]);
  });

  it("expands an old key to every key it granted", () => {
    expect(currentPermissionKeys("parties.read")).toEqual(["contacts.read"]);
    expect(currentPermissionKeys("workflow.run")).toEqual([
      "workflows.run",
      "workflow_editor.run",
    ]);
    expect(currentPermissionKeys("ai.share")).toEqual(["agents.publish"]);
    expect(currentPermissionKeys("members.invite")).toEqual([
      "members.invite",
      "waitlist.invite",
    ]);
    expect(currentPermissionKeys("contacts.read")).toEqual(["contacts.read"]);
  });

  it("keeps the keys that still exist", () => {
    expect(isOldPermissionKey("members.invite")).toBe(false);
    expect(isOldPermissionKey("organization.*")).toBe(false);
    expect(isOldPermissionKey("ai.read")).toBe(true);
    expect(isOldPermissionKey("rules.edit")).toBe(true);
  });

  it("warns once per old key", () => {
    const warn = vi.fn<(message: string) => void>();

    expect(upgradePermissionKey("targets.read", warn)).toEqual(["goals.read"]);
    upgradePermissionKey("targets.read", warn);
    upgradePermissionKey("goals.read", warn);

    expect(warn).toHaveBeenCalledOnce();
    expect(warn.mock.calls[0]?.[0]).toContain('"goals.read"');
    expect(warn.mock.calls[0]?.[0]).toContain("codemod 0.46");
  });
});

const EVENT = /^[a-z][a-z_]*\.(?:\*|[a-z][a-z_]*)$/;

describe("event type renames", () => {
  it("only renames to types that follow the convention", () => {
    const next = [
      ...Object.values(EVENT_TYPE_RENAMES),
      ...Object.values(EVENT_TYPE_SPLITS).flat(),
    ];

    expect(next.filter((type) => !EVENT.test(type))).toEqual([]);
    expect(next.filter(isOldEventType)).toEqual([]);
  });

  it("lists every type a subscriber to an old type needs", () => {
    expect(currentEventTypes("work_item.created")).toEqual(["task.created"]);
    expect(currentEventTypes("agent.saved")).toEqual([
      "agent.created",
      "agent.updated",
    ]);
    expect(currentEventTypes("leave.*")).toEqual([
      "leave_request.*",
      "leave_balance.*",
    ]);
    expect(currentEventTypes("drive.*")).toEqual(["drive.*", "drive_node.*"]);
    expect(currentEventTypes("task.created")).toEqual(["task.created"]);
  });

  it("keeps the wildcards that still match current types", () => {
    expect(isOldEventType("drive.*")).toBe(false);
    expect(isOldEventType("organization.*")).toBe(false);
    expect(isOldEventType("sla.breached")).toBe(false);
    expect(isOldEventType("party.enriched")).toBe(true);
    expect(isOldEventType("toString")).toBe(false);
  });

  it("names the old type of a renamed or split event", () => {
    expect(legacyEventType("task.created")).toBe("work_item.created");
    expect(legacyEventType("agent.updated")).toBe("agent.saved");
    expect(legacyEventType("person.enriched")).toBe("party.enriched");
    expect(legacyEventType("member.joined")).toBe("member.joined");
  });
});
