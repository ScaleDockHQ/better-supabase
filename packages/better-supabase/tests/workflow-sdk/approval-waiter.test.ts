import { beforeEach, describe, expect, it, vi } from "vitest";

interface FakeHook {
  token: string;
  then: Promise<unknown>["then"];
  dispose: () => void;
}

let resume: (payload: unknown) => void = () => undefined;
let wake: () => void = () => undefined;
const dispose = vi.fn();

const createHook = vi.fn((options: { token: string }): FakeHook => {
  const payload = new Promise<unknown>((resolve) => {
    resume = resolve;
  });

  // oxlint-disable-next-line unicorn/no-thenable -- a workflow Hook is a thenable
  return { token: options.token, then: payload.then.bind(payload), dispose };
});

const sleep = vi.fn(
  (_until: Date) =>
    new Promise<void>((resolve) => {
      wake = resolve;
    }),
);

const resumeHook = vi.fn(async (_token: string, _payload: unknown) => ({
  runId: "wrun_1",
}));

vi.mock("workflow", () => ({ createHook, sleep }));

vi.mock("workflow/api", () => ({ resumeHook }));

const { approvalWaiter, wakeOnApproval } =
  await import("../../src/workflow-sdk/approval-waiter.ts");

const LATER = "2999-01-01T00:00:00Z";

beforeEach(() => {
  createHook.mockClear();
  sleep.mockClear();
  dispose.mockClear();
  resumeHook.mockClear();
});

describe("approvalWaiter.wait", () => {
  it("resolves with the payload a wake sends", async () => {
    const waiting = approvalWaiter.wait<{ approved: boolean }>("apr_1", {
      expiresAt: Temporal.Instant.from(LATER),
    });

    await vi.waitFor(() => {
      expect(createHook).toHaveBeenCalledWith({ token: "apr_1" });
    });
    expect(createHook).toHaveBeenCalledWith({ token: "apr_1" });
    expect(sleep.mock.calls[0]?.[0]).toEqual(new Date(LATER));
    resume({ approved: true });
    expect(await waiting).toEqual({
      status: "resumed",
      payload: { approved: true },
    });
    expect(dispose).toHaveBeenCalledOnce();
  });

  it("expires when the sleep ends first", async () => {
    const waiting = approvalWaiter.wait("apr_2", { expiresAt: LATER });
    await vi.waitFor(() => {
      expect(sleep).toHaveBeenCalledWith(new Date(LATER));
    });
    wake();
    expect(await waiting).toEqual({ status: "expired" });
    expect(dispose).toHaveBeenCalledOnce();
  });

  it("expires at once for a past expiry, without a hook", async () => {
    expect(
      await approvalWaiter.wait("apr_3", { expiresAt: "2000-01-01T00:00:00Z" }),
    ).toEqual({ status: "expired" });
    expect(createHook).not.toHaveBeenCalled();
  });

  it("rejects an empty token and an expiry that is not RFC 3339", async () => {
    await expect(approvalWaiter.wait("", { expiresAt: LATER })).rejects.toThrow(
      TypeError,
    );
    await expect(
      approvalWaiter.wait("apr_4", { expiresAt: "tomorrow" }),
    ).rejects.toThrow("RFC 3339");
  });
});

describe("approvalWaiter.wake", () => {
  it("resumes the hook by token", async () => {
    await approvalWaiter.wake("apr_1", { approved: false });
    await approvalWaiter.wake("apr_2");
    expect(resumeHook.mock.calls).toEqual([
      ["apr_1", { approved: false }],
      ["apr_2", null],
    ]);
    await expect(approvalWaiter.wake("")).rejects.toThrow(TypeError);
  });
});

describe("wakeOnApproval", () => {
  it("wakes the run waiting on the request id with the outcome", async () => {
    const woken: unknown[] = [];

    const waiter = {
      wake: async (token: string, payload: unknown) => {
        woken.push([token, payload]);
      },
    };

    expect(
      await wakeOnApproval(
        { type: "approval.approved", payload: { id: "req-1" } },
        waiter,
      ),
    ).toBe(true);
    expect(
      await wakeOnApproval(
        { type: "approval.rejected", payload: { id: "req-2" } },
        waiter,
      ),
    ).toBe(true);
    expect(
      await wakeOnApproval(
        { type: "approval.requested", payload: { id: "req-3" } },
        waiter,
      ),
    ).toBe(false);
    expect(
      await wakeOnApproval({ type: "approval.expired", payload: {} }, waiter),
    ).toBe(false);
    expect(woken).toEqual([
      ["req-1", { approved: true, status: "approved", requestId: "req-1" }],
      ["req-2", { approved: false, status: "rejected", requestId: "req-2" }],
    ]);
  });

  it("ignores a request no run waits on, and rethrows anything else", async () => {
    const missing = Object.assign(new Error("Hook not found"), {
      name: "HookNotFoundError",
    });

    await expect(
      wakeOnApproval(
        { type: "approval.cancelled", payload: { id: "req-4" } },
        { wake: () => Promise.reject(missing) },
      ),
    ).resolves.toBe(true);
    await expect(
      wakeOnApproval(
        { type: "approval.cancelled", payload: { id: "req-4" } },
        { wake: () => Promise.reject(new Error("down")) },
      ),
    ).rejects.toThrow("down");
  });

  it("defaults to approvalWaiter", async () => {
    resumeHook.mockClear();
    await wakeOnApproval({ type: "approval.approved", payload: { id: "r" } });
    expect(resumeHook).toHaveBeenCalledWith("r", {
      approved: true,
      status: "approved",
      requestId: "r",
    });
  });
});
