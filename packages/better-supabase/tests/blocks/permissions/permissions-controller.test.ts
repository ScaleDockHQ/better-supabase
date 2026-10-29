import { describe, expect, it, vi } from "vitest";

import {
  can,
  permissionFlags,
  permissionMatches,
} from "../../../src/blocks/permissions/permissions-controller.ts";

const set = { tenant: "org-1", keys: ["invoices.*", "customers.read"] };

describe("permissionMatches", () => {
  it("follows the SQL wildcards", () => {
    expect(permissionMatches("*", "anything")).toBe(true);
    expect(permissionMatches("invoices.*", "invoices.write")).toBe(true);
    expect(permissionMatches("invoices.*", "invoicesx.write")).toBe(false);
    expect(permissionMatches("customers.read", "customers.write")).toBe(false);
  });

  it("accepts an old key on either side until the next minor", () => {
    const warn = vi.spyOn(console, "warn").mockReturnValue(undefined);

    expect(permissionMatches("parties.*", "contacts.write")).toBe(true);
    expect(permissionMatches("contacts.read", "parties.read")).toBe(true);
    expect(permissionMatches("ai.read", "knowledge.read")).toBe(true);
    expect(permissionMatches("ai.read", "knowledge.write")).toBe(false);
    expect(permissionMatches("workflow.*", "workflow_editor.publish")).toBe(
      true,
    );
    expect(warn).toHaveBeenCalledOnce();

    warn.mockRestore();
  });
});

describe("can", () => {
  it("checks a key against the set, false without one", () => {
    expect(can(set, "invoices.void")).toBe(true);
    expect(can(set, "customers.read")).toBe(true);
    expect(can(set, "customers.write")).toBe(false);
    expect(can(undefined, "customers.read")).toBe(false);
  });
});

describe("permissionFlags", () => {
  it("maps each name to a can<Name> boolean", () => {
    const flags = permissionFlags(set, {
      edit: "customers.write",
      read: "customers.read",
    });

    expect(flags).toEqual({ canEdit: false, canRead: true });
  });
});
