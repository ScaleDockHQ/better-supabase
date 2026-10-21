import { afterEach, describe, expect, it, vi } from "vitest";

import {
  webDeepLinks,
  webFilePicker,
  webKeyboard,
  webPorts,
  webPushToken,
  webStorage,
} from "../../src/client/web-ports.ts";

afterEach(() => {
  vi.unstubAllGlobals();
});

function fakeTarget() {
  const listeners = new Map<string, Set<(event: unknown) => void>>();

  return {
    addEventListener: vi.fn(
      (type: string, listener: (event: unknown) => void) => {
        if (!listeners.has(type)) {
          listeners.set(type, new Set());
        }

        listeners.get(type)!.add(listener);
      },
    ),
    removeEventListener: vi.fn(
      (type: string, listener: (event: unknown) => void) => {
        listeners.get(type)?.delete(listener);
      },
    ),
    dispatch: (type: string, event: unknown = {}) => {
      for (const listener of listeners.get(type) ?? []) {
        listener(event);
      }
    },
    count: (type: string) => listeners.get(type)?.size ?? 0,
  };
}

function fakeStorageGlobal() {
  const items = new Map<string, string>();

  return {
    getItem: (key: string) => items.get(key) ?? null,
    setItem: (key: string, value: string) => void items.set(key, value),
    removeItem: (key: string) => void items.delete(key),
    items,
  };
}

describe("webStorage", () => {
  it("reads and writes localStorage and sessionStorage", async () => {
    const local = fakeStorageGlobal();
    const session = fakeStorageGlobal();
    vi.stubGlobal("localStorage", local);
    vi.stubGlobal("sessionStorage", session);
    await webStorage().set("a", "1");
    expect(local.items.get("a")).toBe("1");
    expect(await webStorage().get("a")).toBe("1");
    await webStorage().remove("a");
    expect(local.items.size).toBe(0);
    await webStorage("session").set("s", "2");
    expect(await webStorage("session").get("s")).toBe("2");
    await webStorage("session").remove("s");
    expect(session.items.size).toBe(0);
  });

  it("does nothing where storage is missing, blocked or full", async () => {
    vi.stubGlobal("localStorage", undefined);
    vi.stubGlobal("sessionStorage", undefined);
    expect(await webStorage().get("a")).toBeNull();
    expect(await webStorage("session").get("a")).toBeNull();
    await webStorage().set("a", "1");
    await webStorage().remove("a");

    vi.stubGlobal("localStorage", {
      getItem: () => {
        throw new DOMException("denied", "SecurityError");
      },
      setItem: () => {
        throw new DOMException("full", "QuotaExceededError");
      },
    });
    expect(await webStorage().get("a")).toBeNull();
    await webStorage().set("a", "1");

    Object.defineProperty(globalThis, "localStorage", {
      configurable: true,
      get: () => {
        throw new DOMException("denied", "SecurityError");
      },
    });

    try {
      expect(await webStorage().get("a")).toBeNull();
    } finally {
      Reflect.deleteProperty(globalThis, "localStorage");
    }
  });
});

describe("webKeyboard", () => {
  it("runs on the exact combination and stops when released", () => {
    const target = fakeTarget();
    vi.stubGlobal("window", target);
    const run = vi.fn();
    const release = webKeyboard()({ key: "k", mod: true }, run);

    const press = (init: Record<string, unknown>) => {
      const preventDefault = vi.fn();
      target.dispatch("keydown", {
        key: "k",
        metaKey: false,
        ctrlKey: false,
        shiftKey: false,
        altKey: false,
        preventDefault,
        ...init,
      });

      return preventDefault;
    };

    target.dispatch("keydown", {});
    target.dispatch("keydown", null);
    expect(press({ key: "j", metaKey: true })).not.toHaveBeenCalled();
    expect(press({})).not.toHaveBeenCalled();
    expect(press({ metaKey: true, shiftKey: true })).not.toHaveBeenCalled();
    expect(press({ ctrlKey: true, altKey: true })).not.toHaveBeenCalled();
    expect(press({ metaKey: true })).toHaveBeenCalledWith();
    expect(press({ key: "K", ctrlKey: true })).toHaveBeenCalledWith();
    expect(run).toHaveBeenCalledTimes(2);
    release();
    expect(target.count("keydown")).toBe(0);

    const plain = vi.fn();
    webKeyboard()({ key: "/", shift: true, alt: true }, plain);
    press({ key: "/", shiftKey: true, altKey: true });
    expect(plain).toHaveBeenCalledOnce();
  });

  it("binds nothing outside a browser", () => {
    const release = webKeyboard()({ key: "k" }, () => undefined);
    expect(release).toBeTypeOf("function");
    release();
  });
});

describe("webFilePicker", () => {
  function fakeDocument() {
    const inputs: (ReturnType<typeof fakeTarget> & Record<string, unknown>)[] =
      [];

    return {
      inputs,
      createElement: () => {
        const input = Object.assign(fakeTarget(), {
          type: "",
          multiple: false,
          accept: "",
          files: null as File[] | null,
          click: vi.fn(),
        });

        inputs.push(input);

        return input;
      },
    };
  }

  it("resolves with the chosen files, or none on cancel", async () => {
    const doc = fakeDocument();
    vi.stubGlobal("document", doc);

    const picking = webFilePicker()({
      accept: ["image/*", ".pdf"],
      multiple: true,
    });

    const input = doc.inputs[0]!;
    expect(input).toMatchObject({
      type: "file",
      multiple: true,
      accept: "image/*,.pdf",
    });
    expect(input["click"]).toHaveBeenCalledWith();
    const chosen = new File(["abc"], "a.txt", { type: "text/plain" });
    input["files"] = [chosen, new File(["x"], "b.bin")];
    input.dispatch("change");
    const [first, second] = await picking;
    expect(first).toMatchObject({
      name: "a.txt",
      type: "text/plain",
      size: 3,
      uri: undefined,
    });
    expect(await first!.read()).toBe(chosen);
    expect(second?.type).toBeUndefined();

    const cancelled = webFilePicker()();
    doc.inputs[1]!.dispatch("cancel");
    expect(await cancelled).toEqual([]);
    const empty = webFilePicker()();
    doc.inputs[2]!.dispatch("change");
    expect(await empty).toEqual([]);
    expect(doc.inputs[2]).toMatchObject({ multiple: false, accept: "" });
  });

  it("resolves with nothing outside a browser", async () => {
    expect(await webFilePicker()()).toEqual([]);
  });
});

describe("webDeepLinks", () => {
  it("reports the current URL and its changes", async () => {
    const target = Object.assign(fakeTarget(), {
      location: { href: "https://app.test/a" },
    });

    vi.stubGlobal("window", target);
    const links = webDeepLinks();
    expect(await links.initial()).toBe("https://app.test/a");
    const listener = vi.fn();
    const stop = links.subscribe(listener);
    target.location.href = "https://app.test/b";
    target.dispatch("popstate");
    target.dispatch("hashchange");
    expect(listener).toHaveBeenCalledWith("https://app.test/b");
    expect(listener).toHaveBeenCalledTimes(2);
    stop();
    expect(target.count("popstate") + target.count("hashchange")).toBe(0);
  });

  it("has no URL outside a browser", async () => {
    const links = webDeepLinks();
    expect(await links.initial()).toBeNull();
    const stop = links.subscribe(() => undefined);
    expect(stop).toBeTypeOf("function");
    stop();
  });
});

describe("webPushToken", () => {
  function fakePush(permission: string, existing: unknown = null) {
    const subscribe = vi.fn(async (_options: unknown) => ({ endpoint: "new" }));

    const registration = {
      pushManager: { getSubscription: vi.fn(async () => existing), subscribe },
    };

    const requestPermission = vi.fn(async () => "granted");
    vi.stubGlobal("Notification", { permission, requestPermission });
    vi.stubGlobal("navigator", {
      serviceWorker: { ready: Promise.resolve(registration) },
    });

    return { subscribe, requestPermission, registration };
  }

  it("subscribes after asking for permission", async () => {
    const push = fakePush("default");
    const port = webPushToken({ vapidPublicKey: "AQID-_8" });
    expect(port.provider).toBe("webpush");
    expect(await port.token()).toBe(JSON.stringify({ endpoint: "new" }));
    expect(push.requestPermission).toHaveBeenCalledWith();

    const options = push.subscribe.mock.calls[0]?.[0] as {
      applicationServerKey: Uint8Array;
    };

    expect([...options.applicationServerKey]).toEqual([1, 2, 3, 251, 255]);
  });

  it("reuses a subscription from the given worker", async () => {
    const push = fakePush("granted", { endpoint: "old" });
    const registration = vi.fn(async () => push.registration as never);
    expect(
      await webPushToken({ vapidPublicKey: "AQID", registration }).token(),
    ).toBe(JSON.stringify({ endpoint: "old" }));
    expect(registration).toHaveBeenCalledWith();
  });

  it("resolves with null when denied, not asked, or unsupported", async () => {
    fakePush("denied");
    expect(await webPushToken({ vapidPublicKey: "AQID" }).token()).toBeNull();
    const push = fakePush("default");
    expect(
      await webPushToken({ vapidPublicKey: "AQID" }).token({ request: false }),
    ).toBeNull();
    expect(push.requestPermission).not.toHaveBeenCalled();
    vi.stubGlobal("navigator", {});
    expect(await webPushToken({ vapidPublicKey: "AQID" }).token()).toBeNull();
    vi.stubGlobal("navigator", undefined);
    expect(await webPushToken({ vapidPublicKey: "AQID" }).token()).toBeNull();
    vi.stubGlobal("Notification", undefined);
    expect(await webPushToken({ vapidPublicKey: "AQID" }).token()).toBeNull();
  });
});

describe("webPorts", () => {
  it("bundles the web defaults", () => {
    expect(Object.keys(webPorts()).toSorted()).toEqual([
      "files",
      "keyboard",
      "links",
      "storage",
    ]);
  });
});
