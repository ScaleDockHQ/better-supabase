import type * as ReactModule from "react";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type {
  AttachmentSend,
  UseAttachmentUploadOptions,
} from "../../../../src/blocks/attachments/react/index.ts";
import type { ClientLike } from "../../../../src/react/hooks.ts";

import { useAttachmentUpload } from "../../../../src/blocks/attachments/react/index.ts";
import { ok } from "../../../../src/core/result.ts";
import { BetterSupabaseProvider } from "../../../../src/react/hooks.ts";
import { renderHook as render } from "../../../fixtures/hook-runtime.ts";

vi.mock("react", async (importOriginal) => ({
  ...(await importOriginal<typeof ReactModule>()),
  ...(await import("../../../fixtures/hook-runtime.ts")).reactHooks,
}));

const row = (overrides: Record<string, unknown> = {}) => ({
  id: "a1",
  organization_id: "org",
  subject_type: "task",
  subject_id: "t1",
  bucket: "attachments",
  object_path: "org/a1",
  name: "plan.pdf",
  mime_type: "application/pdf",
  size: "4",
  status: "pending",
  scan_detail: null,
  uploaded_by: "u1",
  created_at: "2026-10-22T08:00:00Z",
  uploaded_at: null,
  scanned_at: null,
  ...overrides,
});

const rpc = {
  replies: {} as Record<string, unknown>,
  calls: [] as { fn: string; args: Record<string, unknown> }[],
};

const supabase = {
  schema: () => ({
    rpc: (fn: string, args: Record<string, unknown>) => {
      rpc.calls.push({ fn, args });

      return Promise.resolve({ data: rpc.replies[fn] ?? null, error: null });
    },
  }),
  storage: {
    from: () => ({
      createSignedUploadUrl: (path: string) =>
        Promise.resolve({
          data: { signedUrl: `https://storage.test/${path}`, token: "t" },
          error: null,
        }),
    }),
  },
};

// SAFETY: the hook reads only `supabase`, `auth` and `tenant` from the client.
const client = {
  supabase,
  auth: { current: () => null, subscribe: () => () => undefined },
  ports: {},
  tenant: "org",
} as unknown as ClientLike;

const renderHook = <R>(hook: () => R) =>
  render(hook, undefined, () => {
    void BetterSupabaseProvider({ client });
  });

const sent: string[] = [];

const send: AttachmentSend = (ticket, _body, progress) => {
  sent.push(ticket.signedUrl);
  progress(1);

  return Promise.resolve(ok(null));
};

const file = { file: new Blob(["data"]), name: "plan.pdf" };

const upload = (options: Partial<UseAttachmentUploadOptions>) =>
  renderHook(() =>
    useAttachmentUpload({
      subject: { type: "task", id: "t1" },
      send,
      pollInterval: 10,
      ...options,
    }),
  );

beforeEach(() => {
  vi.useFakeTimers();
  sent.length = 0;
  rpc.calls = [];
  rpc.replies = {
    create_attachment: row(),
    confirm_attachment: row({ uploaded_at: "2026-10-22T08:00:01Z" }),
    get_attachment: row({
      status: "clean",
      uploaded_at: "2026-10-22T08:00:01Z",
    }),
  };
});

afterEach(() => {
  vi.useRealTimers();
});

describe("useAttachmentUpload", () => {
  it("uploads through the browser client and waits for the scan", async () => {
    const onUploaded = vi.fn();
    const view = upload({ onUploaded });

    view.result.add([file]);
    await vi.advanceTimersByTimeAsync(0);

    expect(view.result.uploads[0]?.status).toBe("scanning");
    expect(rpc.calls[0]).toMatchObject({
      fn: "create_attachment",
      args: { tenant: "org", subject_type: "task", subject_id: "t1" },
    });
    expect(sent).toEqual(["https://storage.test/org/a1"]);

    await vi.advanceTimersByTimeAsync(20);

    expect(view.result.uploads[0]?.status).toBe("done");
    expect(rpc.calls.map((call) => call.fn)).toEqual([
      "create_attachment",
      "confirm_attachment",
      "get_attachment",
    ]);
    expect(onUploaded).toHaveBeenCalledWith("a1");
    view.unmount();
  });

  it("takes the app's start, confirm and refresh", async () => {
    const start = vi.fn(() =>
      Promise.resolve(ok({ id: "s1", signedUrl: "https://signed.test/s1" })),
    );

    const confirm = vi.fn(() =>
      Promise.resolve(ok({ status: "pending" as const })),
    );

    const refresh = vi.fn(() =>
      Promise.resolve(ok({ status: "clean" as const })),
    );

    const view = upload({ subject: null, start, confirm, refresh });

    view.result.add([file]);
    await vi.advanceTimersByTimeAsync(20);

    expect(start).toHaveBeenCalledWith(
      expect.objectContaining({ name: "plan.pdf", size: 4 }),
    );
    expect(confirm).toHaveBeenCalledWith("s1");
    expect(refresh).toHaveBeenCalledWith("s1");
    expect(view.result.uploads[0]?.status).toBe("done");
    expect(rpc.calls).toEqual([]);
  });

  it("ends at confirm with the app's start or with refresh: false", async () => {
    const start = vi.fn(() =>
      Promise.resolve(ok({ id: "s1", signedUrl: "https://signed.test/s1" })),
    );

    const own = upload({ start });

    own.result.add([file]);
    await vi.advanceTimersByTimeAsync(0);

    expect(own.result.uploads[0]?.status).toBe("done");
    expect(rpc.calls.map((call) => call.fn)).toEqual(["confirm_attachment"]);
    own.unmount();

    rpc.calls = [];

    const unwatched = renderHook(() =>
      useAttachmentUpload({
        subject: { type: "task", id: "t1" },
        send,
        refresh: false,
      }),
    );

    unwatched.result.add([file]);
    await vi.advanceTimersByTimeAsync(0);

    expect(unwatched.result.uploads[0]?.status).toBe("done");
    expect(rpc.calls.map((call) => call.fn)).toEqual([
      "create_attachment",
      "confirm_attachment",
    ]);
  });
});
