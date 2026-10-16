import { toStandardJsonSchema as json } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  createSettingsController,
  settingFields,
} from "../../../src/blocks/settings/client.ts";
import {
  createSettings,
  defineSettings,
} from "../../../src/blocks/settings/index.ts";
import { fakeAuth, flush, mount } from "../../fixtures/ports.ts";

const settings = defineSettings({
  user: {
    weeklyDigest: {
      schema: json(
        v.pipe(
          v.boolean(),
          v.title("Weekly digest"),
          v.description("A summary by email"),
        ),
      ),
      default: true,
    },
    pageSize: { schema: json(v.pipe(v.number(), v.integer())), default: 25 },
    signature: { schema: json(v.string()), default: "" },
    filters: { schema: json(v.object({ status: v.string() })) },
  },
  organization: {
    weekStart: {
      schema: json(v.picklist(["monday", "sunday"])),
      default: "monday",
    },
    defaultRole: { schema: v.picklist(["member", "admin"]), default: "member" },
    seats: { schema: v.number(), default: 5 },
    beta: { schema: v.boolean() },
  },
});

/** Stores values per function and tenant, like the settings module. */
function fakeTransport() {
  const stored = new Map<string, Record<string, unknown>>();
  const keyOf = (fn: string, args: Record<string, unknown>) =>
    `${fn.includes("organization") ? "organization" : "user"}:${String(args["tenant"] ?? "")}`;
  const call = vi.fn(
    async (_schema: string, fn: string, args: Record<string, unknown>) => {
      const key = keyOf(fn, args);
      const values = stored.get(key) ?? {};
      if (fn.startsWith("get_")) return values;
      if (fn.startsWith("set_")) {
        const { value } = args["value"] as { value: unknown };
        stored.set(key, { ...values, [String(args["key"])]: value });
        return null;
      }
      const removed = String(args["key"]) in values;
      const { [String(args["key"])]: _gone, ...rest } = values;
      stored.set(key, rest);
      return removed;
    },
  );
  const transport: BlockTransport = { call };
  return { transport, call };
}

describe("settingFields", () => {
  it("reads kinds and choices from Standard JSON Schema, else from the default", () => {
    expect(settingFields(settings.schemas.user)).toEqual([
      {
        key: "weeklyDigest",
        kind: "boolean",
        choices: [],
        title: "Weekly digest",
        description: "A summary by email",
        default: true,
      },
      {
        key: "pageSize",
        kind: "number",
        choices: [],
        title: undefined,
        description: undefined,
        default: 25,
      },
      expect.objectContaining({ key: "signature", kind: "text" }),
      expect.objectContaining({ key: "filters", kind: "json" }),
    ]);
    expect(
      settingFields(settings.schemas.organization).map((field) => [
        field.key,
        field.kind,
        field.choices,
      ]),
    ).toEqual([
      ["weekStart", "choice", ["monday", "sunday"]],
      ["defaultRole", "text", []],
      ["seats", "number", []],
      ["beta", "json", []],
    ]);
  });

  it("falls back when a converter throws", () => {
    const broken = {
      "~standard": {
        version: 1,
        vendor: "test",
        validate: (value: unknown) => ({ value }),
        jsonSchema: {
          input: () => {
            throw new Error("unsupported");
          },
        },
      },
    } as const;
    expect(
      settingFields({ flag: { schema: broken, default: false } })[0]?.kind,
    ).toBe("boolean");
  });
});

describe("createSettingsController", () => {
  it("loads, sets and resets the caller's own settings", async () => {
    const { transport } = fakeTransport();
    const client = createSettings({ settings, transport });
    const controller = createSettingsController({
      entries: settings.schemas.user,
      auth: fakeAuth(),
      user: client,
    });
    expect(controller.getSnapshot().fields).toHaveLength(4);
    const { view, unmount } = mount(controller);
    await flush();
    expect(view().values).toMatchObject({ weeklyDigest: true, pageSize: 25 });
    expectTypeOf(view().values?.weeklyDigest).toEqualTypeOf<
      boolean | undefined
    >();

    const saving = view().set("weeklyDigest", false);
    expect(view().saving).toBe("weeklyDigest");
    expect((await saving).ok).toBe(true);
    expect(view().values?.weeklyDigest).toBe(false);
    expect(view().saving).toBeUndefined();

    const invalid = await view().set("pageSize", 2.5);
    expect(invalid.ok).toBe(false);
    expect(view().error?.kind).toBe("validation");
    expect(view().values?.pageSize).toBe(25);

    expect((await view().reset("weeklyDigest")).ok).toBe(true);
    expect(view().values?.weeklyDigest).toBe(true);

    expect((await view().setField("pageSize", 50)).ok).toBe(true);
    expect(view().values?.pageSize).toBe(50);
    expect((await view().setField("pageSize", "many")).ok).toBe(false);
    expect(view().values?.pageSize).toBe(50);
    unmount();
  });

  it("edits an organization's settings once it has one", async () => {
    const { transport, call } = fakeTransport();
    const client = createSettings({ settings, transport, schema: "api" });
    const waiting = createSettingsController({
      entries: settings.schemas.organization,
      auth: fakeAuth(),
      organization: client,
      organizationId: null,
    });
    const idle = mount(waiting);
    await flush();
    expect(call).not.toHaveBeenCalled();
    expect((await idle.view().set("seats", 3)).ok).toBe(false);
    expect((await idle.view().reset("seats")).ok).toBe(false);
    await idle.view().refresh();
    idle.unmount();

    const { view, unmount } = mount(
      createSettingsController({
        entries: settings.schemas.organization,
        auth: fakeAuth(),
        organization: client,
        organizationId: "org-1",
      }),
    );
    await flush();
    expect(call).toHaveBeenCalledWith("api", "get_organization_settings", {
      tenant: "org-1",
    });
    await view().set("weekStart", "sunday");
    expect(view().values?.weekStart).toBe("sunday");

    call.mockRejectedValueOnce(new Error("offline"));
    expect((await view().reset("weekStart")).ok).toBe(false);
    expect(view().error?.message).toBe("offline");
    call.mockRejectedValueOnce(new Error("down"));
    await view().refresh();
    expect(view().error?.message).toBe("down");
    unmount();
  });

  it("needs a user or an organization client", () => {
    expect(() =>
      createSettingsController({
        entries: settings.schemas.user,
        auth: fakeAuth(),
      }),
    ).toThrow("needs `user` or `organization`");
  });

  it("keeps values unset when a write lands before the first load", async () => {
    const { transport } = fakeTransport();
    const controller = createSettingsController({
      entries: settings.schemas.user,
      auth: fakeAuth(),
      user: createSettings({ settings, transport }),
    });
    expect((await controller.actions.set("signature", "Hi")).ok).toBe(true);
    expect(controller.getSnapshot().values).toBeUndefined();
  });
});
