import { describe, expect, it, vi } from "vitest";

import type {
  ApiKey,
  CreateApiKeyInput,
} from "../../../src/blocks/api-keys/api-keys.ts";

import { createApiKeysController } from "../../../src/blocks/api-keys/client.ts";
import {
  failed,
  fakeAuth,
  flush,
  held,
  mount,
  resolved,
} from "../../fixtures/ports.ts";

const key = (id: string, day: number): ApiKey => ({
  id,
  name: id,
  prefix: "bs",
  publicId: `p${id}`,
  scopes: [],
  createdAt: Temporal.Instant.from(`2026-10-0${String(day)}T00:00:00Z`),
  state: "active",
});

function setup(organizationId: string | null = "org-1") {
  const auth = fakeAuth();
  const list = vi.fn((_organizationId?: string) =>
    resolved<readonly ApiKey[]>([key("k1", 1), key("k2", 2)]),
  );
  const create = vi.fn((input: CreateApiKeyInput) =>
    resolved({ key: key(input.name, 3), token: "bs_secret" }),
  );
  const revoke = vi.fn((_id: string) => resolved(true));
  const onChanged = vi.fn();
  const controller = createApiKeysController({
    client: { list, create, revoke },
    auth,
    organizationId,
    onChanged,
  });
  return { list, create, revoke, onChanged, controller };
}

describe("createApiKeysController", () => {
  it("lists the organization's keys newest first", async () => {
    const { list, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    expect(list).toHaveBeenCalledWith("org-1");
    expect(view().keys?.map((each) => each.id)).toEqual(["k2", "k1"]);
    unmount();

    const personal = setup(null);
    const personalView = mount(personal.controller);
    await flush();
    expect(personal.list).toHaveBeenCalledWith(undefined);
    personalView.unmount();
  });

  it("creates a key, keeps its token until dismiss and loads the list again", async () => {
    const { list, create, onChanged, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    const creating = view().create({ name: "CI", personal: true });
    expect(view().creating).toBe(true);
    expect((await creating).ok).toBe(true);
    expect(create).toHaveBeenCalledWith({
      name: "CI",
      personal: true,
      organizationId: "org-1",
    });
    expect(view().created?.token).toBe("bs_secret");
    expect(view().creating).toBe(false);
    expect(onChanged).toHaveBeenCalledWith({
      kind: "created",
      key: expect.objectContaining({ id: "CI" }),
    });
    expect(list).toHaveBeenCalledTimes(2);
    view().dismiss();
    expect(view().created).toBeUndefined();

    create.mockReturnValueOnce(failed("no api_keys.own"));
    expect((await view().create({ name: "x" })).ok).toBe(false);
    expect(view().error?.message).toBe("no api_keys.own");
    unmount();
  });

  it("creates a personal key without an organization", async () => {
    const { create, controller } = setup(null);
    const { view, unmount } = mount(controller);
    await flush();
    await view().create({ name: "Mine", personal: true });
    expect(create).toHaveBeenCalledWith({ name: "Mine", personal: true });
    unmount();
  });

  it("revokes a key, and keeps list, revoke and onChanged errors", async () => {
    const { list, revoke, onChanged, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    const write = held(true);
    revoke.mockReturnValueOnce(write.result);
    const revoking = view().revoke("k1");
    expect(view().revoking).toEqual(["k1"]);
    write.release();
    expect((await revoking).ok).toBe(true);
    expect(view().revoking).toEqual([]);
    expect(onChanged).toHaveBeenCalledWith({ kind: "revoked", id: "k1" });

    revoke.mockReturnValueOnce(failed("not yours"));
    expect((await view().revoke("k2")).ok).toBe(false);
    expect(view().error?.message).toBe("not yours");

    onChanged.mockRejectedValueOnce(new Error("step failed"));
    await view().revoke("k2");
    expect(view().error?.message).toBe("step failed");

    list.mockReturnValueOnce(failed("forbidden"));
    await view().refresh();
    expect(view().error?.message).toBe("forbidden");
    unmount();
  });
});
