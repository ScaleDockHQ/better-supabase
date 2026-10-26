import { describe, expect, it } from "vitest";

import { createCustomFields } from "../../../src/blocks/custom-fields/index.ts";

const EMPLOYEE = { type: "employees", id: "e1" };

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("createCustomFields", () => {
  it("sends the subject and the block's tenant", async () => {
    const fake = fakeTransport({
      read_field_values: [],
      set_field_value: { id: "v1" },
    });

    const fields = createCustomFields({
      transport: fake.transport,
      tenant: "org-1",
    });

    await fields.readValues(EMPLOYEE).orThrow();
    await fields.setValue(EMPLOYEE, "d1", "gold").orThrow();
    expect(fake.calls).toEqual([
      [
        "read_field_values",
        { tenant: "org-1", subject_type: "employees", subject_id: "e1" },
      ],
      [
        "set_field_value",
        {
          tenant: "org-1",
          subject_type: "employees",
          subject_id: "e1",
          definition: "d1",
          value: "gold",
        },
      ],
    ]);
  });

  it("fails without a tenant", async () => {
    const fake = fakeTransport({
      list_field_definitions: [],
      delete_field_definition: true,
    });

    const session: { tenant?: string } = {};

    const fields = createCustomFields({
      transport: fake.transport,
      tenant: () => session.tenant,
    });

    expect(await fields.listDefinitions("customer")).toMatchObject({
      ok: false,
      error: { kind: "invalid_request", hint: "TENANT_REQUIRED" },
    });
    expect(await fields.readValues(EMPLOYEE)).toMatchObject({ ok: false });
    expect(fake.calls).toHaveLength(0);
    expect(await fields.deleteDefinition("d1").orThrow()).toBe(true);
    session.tenant = "org-2";
    expect(await fields.listDefinitions("customer").orThrow()).toEqual([]);
    expect(fake.calls.at(-1)).toEqual([
      "list_field_definitions",
      { tenant: "org-2", entity: "customer" },
    ]);
  });

  it("encrypts a definition and lists whether one is encrypted", async () => {
    const fake = fakeTransport({
      encrypt_field_definition: true,
      list_field_definitions: [
        {
          id: "d1",
          entity: "contact",
          key: "notes",
          label: "Notes",
          type: "text",
          required: false,
          sensitive: false,
          encrypted: true,
        },
        {
          id: "d2",
          entity: "contact",
          key: "tier",
          label: "Tier",
          type: "option",
        },
      ],
    });

    const fields = createCustomFields({
      transport: fake.transport,
      tenant: "org-1",
    });

    expect(await fields.encryptDefinition("d1").orThrow()).toBe(true);
    expect(fake.calls[0]).toEqual([
      "encrypt_field_definition",
      { definition: "d1" },
    ]);
    expect(
      (await fields.listDefinitions("contact").orThrow()).map(
        (definition) => definition.encrypted,
      ),
    ).toEqual([true, false]);
  });

  it("sets, reads and deletes keyed values as typed rows", async () => {
    const row = {
      id: "v1",
      subjectType: "employees",
      subjectId: "e1",
      key: "badge",
      label: "Badge",
      type: "number",
      value: 7,
      rank: null,
      createdAt: "2026-01-01T00:00:00Z",
      updatedAt: null,
    };

    const fake = fakeTransport({
      set_field_value: row,
      read_field_values: [row],
      delete_field_value: true,
    });

    const fields = createCustomFields({
      transport: fake.transport,
      tenant: "org-1",
    });

    const saved = await fields
      .setField(EMPLOYEE, {
        key: "badge",
        label: "Badge",
        type: "number",
        value: 7,
      })
      .orThrow();

    expect(saved).toEqual({
      id: "v1",
      subject: EMPLOYEE,
      key: "badge",
      label: "Badge",
      type: "number",
      value: 7,
      createdAt: "2026-01-01T00:00:00Z",
    });
    expect(await fields.readFields(EMPLOYEE).orThrow()).toEqual([saved]);
    expect(await fields.deleteValue("v1").orThrow()).toBe(true);
    expect(fake.calls[0]).toEqual([
      "set_field_value",
      {
        tenant: "org-1",
        subject_type: "employees",
        subject_id: "e1",
        key: "badge",
        label: "Badge",
        type: "number",
        value: 7,
        rank: null,
        if_absent: false,
      },
    ]);
    expect(fake.calls[2]).toEqual(["delete_field_value", { value_id: "v1" }]);
  });
});
