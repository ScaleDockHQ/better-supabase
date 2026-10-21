import { describe, expect, it, vi } from "vitest";

import {
  expoPushToken,
  nativeDeepLinks,
  nativeFilePicker,
  nativePorts,
  nativeStorage,
} from "../../../src/client/native/ports.ts";

function notifications(status: string, requested = "granted") {
  return {
    getPermissionsAsync: vi.fn(async () => ({ status })),
    requestPermissionsAsync: vi.fn(async () => ({ status: requested })),
    getExpoPushTokenAsync: vi.fn(async (_options?: { projectId?: string }) => ({
      data: "ExponentPushToken[x]",
    })),
  };
}

describe("expoPushToken", () => {
  it("asks for permission, then returns the Expo token", async () => {
    const expo = notifications("undetermined");
    const port = expoPushToken(expo, { projectId: "p1" });
    expect(port.provider).toBe("expo");
    expect(await port.token()).toBe("ExponentPushToken[x]");
    expect(expo.getExpoPushTokenAsync).toHaveBeenCalledWith({
      projectId: "p1",
    });
    expect(await expoPushToken(notifications("granted")).token()).toBe(
      "ExponentPushToken[x]",
    );
  });

  it("resolves with null when the user denies or it may not ask", async () => {
    expect(
      await expoPushToken(notifications("undetermined", "denied")).token(),
    ).toBeNull();
    const quiet = notifications("undetermined");
    expect(await expoPushToken(quiet).token({ request: false })).toBeNull();
    expect(quiet.requestPermissionsAsync).not.toHaveBeenCalled();
  });
});

describe("nativeDeepLinks", () => {
  it("reads the initial URL and the ones that open the app later", async () => {
    let listener: ((event: { url: string }) => void) | undefined;
    const remove = vi.fn();

    const links = nativeDeepLinks({
      getInitialURL: async () => "app://start",
      addEventListener: (_type, next) => {
        listener = next;

        return { remove };
      },
    });

    expect(await links.initial()).toBe("app://start");
    const seen = vi.fn();
    const stop = links.subscribe(seen);
    listener?.({ url: "app://next" });
    expect(seen).toHaveBeenCalledWith("app://next");
    stop();
    expect(remove).toHaveBeenCalled();
  });
});

describe("nativeFilePicker", () => {
  it("maps picked documents and reads them as array buffers", async () => {
    const getDocumentAsync = vi.fn(async () => ({
      canceled: false as const,
      assets: [
        {
          uri: "file:///a.pdf",
          name: "a.pdf",
          mimeType: "application/pdf",
          size: 3,
        },
      ],
    }));

    const read = vi.fn(async () => new Response(new Uint8Array([1, 2, 3])));

    const [file] = await nativeFilePicker(
      { getDocumentAsync },
      read,
    )({ accept: ["application/pdf"], multiple: true });

    expect(getDocumentAsync).toHaveBeenCalledWith({
      type: ["application/pdf"],
      multiple: true,
      copyToCacheDirectory: true,
    });
    expect(file).toMatchObject({
      name: "a.pdf",
      type: "application/pdf",
      uri: "file:///a.pdf",
    });
    const bytes = await file!.read();
    expect(bytes).toBeInstanceOf(ArrayBuffer);
    expect(read).toHaveBeenCalledWith("file:///a.pdf");
  });

  it("resolves with no files on cancel and reads through fetch by default", async () => {
    const cancel = nativeFilePicker({
      getDocumentAsync: async () => ({ canceled: true as const, assets: null }),
    });

    expect(await cancel()).toEqual([]);
    const fetcher = vi.fn(async () => new Response("x"));
    vi.stubGlobal("fetch", fetcher);

    try {
      const [file] = await nativeFilePicker({
        getDocumentAsync: async () => ({
          canceled: false as const,
          assets: [{ uri: "file:///b", name: "b" }],
        }),
      })();

      await file!.read();
      expect(fetcher).toHaveBeenCalledWith("file:///b");
    } finally {
      vi.unstubAllGlobals();
    }
  });
});

describe("nativePorts", () => {
  it("builds a port for each module passed", async () => {
    const values = new Map<string, string>();

    const ports = nativePorts({
      supabase: { storage: { from: vi.fn() } } as never,
      storage: {
        getItem: async (key) => values.get(key) ?? null,
        setItem: async (key, value) => void values.set(key, value),
        removeItem: async (key) => void values.delete(key),
      },
      linking: {
        getInitialURL: async () => null,
        addEventListener: () => ({ remove: () => undefined }),
      },
      notifications: notifications("granted"),
      projectId: "p1",
      documentPicker: {
        getDocumentAsync: async () => ({
          canceled: true as const,
          assets: null,
        }),
      },
    });

    expect(Object.keys(ports).sort()).toEqual([
      "files",
      "links",
      "push",
      "storage",
      "upload",
    ]);
    await ports.storage?.set("a", "1");
    expect(values.get("a")).toBe("1");
    expect(nativePorts({})).toEqual({});
    expect(
      await nativeStorage({ getString: () => "v", set: () => undefined }).get(
        "k",
      ),
    ).toBe("v");
  });
});
