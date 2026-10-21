import { describe, expect, it, vi } from "vitest";

import {
  type CheckoutStarted,
  createPlanPickerController,
  type PlanCatalog,
} from "../../../src/blocks/billing/client.ts";
import { dbError } from "../../../src/core/errors.ts";
import { err, ok, type Result } from "../../../src/core/result.ts";
import { fakeAuth, flush, mount, SIGNED_OUT } from "../../fixtures/ports.ts";

const plans = [
  { key: "free", name: "Free", priceCents: 0 },
  { key: "pro", name: "Pro", priceCents: 2900 },
];

function options() {
  return {
    auth: fakeAuth(),
    load: vi.fn(async (): Promise<PlanCatalog<(typeof plans)[number]>> => ({
      plans,
      current: "free",
    })),
    checkout: vi.fn(async (_plan: string): Promise<Result<CheckoutStarted>> =>
      ok({ url: "https://checkout.stripe.test/c/pay" }),
    ),
    open: vi.fn(),
  };
}

describe("createPlanPickerController", () => {
  it("loads the plans and opens Checkout for another plan", async () => {
    const calls = options();
    const { view, unmount } = mount(createPlanPickerController(calls));
    await flush();
    expect(view().plans?.map((plan) => plan.key)).toEqual(["free", "pro"]);
    expect(view().current).toBe("free");

    const started = view().choose("pro");
    expect(view().pending).toBe("pro");
    expect((await started).ok).toBe(true);
    expect(calls.checkout).toHaveBeenCalledExactlyOnceWith("pro");
    expect(calls.open).toHaveBeenCalledWith(
      "https://checkout.stripe.test/c/pay",
    );
    expect(view().pending).toBeUndefined();
    expect(calls.load).toHaveBeenCalledOnce();

    expect((await view().choose("free")).ok).toBe(true);
    expect(calls.checkout).toHaveBeenCalledExactlyOnceWith("pro");
    unmount();
  });

  it("reloads after a change without a URL and keeps failures in error", async () => {
    const calls = options();
    calls.checkout.mockResolvedValueOnce(ok({ url: undefined }));
    const { view, unmount } = mount(createPlanPickerController(calls));
    await flush();
    await view().choose("pro");
    expect(calls.open).not.toHaveBeenCalled();
    expect(calls.load).toHaveBeenCalledTimes(2);

    calls.checkout.mockResolvedValueOnce(
      err(dbError("unsupported", "No billing module")),
    );
    const refused = await view().choose("pro");
    expect(refused.ok).toBe(false);
    expect(view().error?.message).toBe("No billing module");
    expect(view().pending).toBeUndefined();

    calls.open.mockImplementationOnce(() => {
      throw new Error("blocked");
    });
    expect((await view().choose("pro")).ok).toBe(false);
    expect(view().error?.message).toBe("blocked");

    calls.load.mockRejectedValueOnce(new Error("offline"));
    await view().refresh();
    expect(view().error?.message).toBe("offline");
    unmount();
  });

  it("skips the first load with initial rows and waits for a session", async () => {
    const calls = options();

    const { view, unmount } = mount(
      createPlanPickerController({
        ...calls,
        initial: { plans: plans.slice(1), current: "pro" },
      }),
    );

    await flush();
    expect(calls.load).not.toHaveBeenCalled();
    expect(view().plans).toHaveLength(1);
    expect(view().current).toBe("pro");
    unmount();

    const signedOut = options();
    mount(
      createPlanPickerController({ ...signedOut, auth: fakeAuth(SIGNED_OUT) }),
    ).unmount();
    expect(signedOut.load).not.toHaveBeenCalled();
  });

  it("drops a load that answers after a newer one", async () => {
    const calls = options();
    let release = (): void => undefined;
    calls.load.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          release = () => {
            resolve({ plans: [], current: undefined });
          };
        }),
    );
    const controller = createPlanPickerController(calls);
    const { view, unmount } = mount(controller);
    await view().refresh();
    release();
    await flush();
    expect(view().plans).toHaveLength(2);
    unmount();
  });
});
