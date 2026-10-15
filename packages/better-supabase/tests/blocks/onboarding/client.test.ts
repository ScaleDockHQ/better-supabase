import { describe, expect, it, vi } from "vitest";

import type { ChecklistProgress } from "../../../src/blocks/onboarding/onboarding.ts";

import { createOnboardingController } from "../../../src/blocks/onboarding/client.ts";
import {
  failed,
  fakeAuth,
  flush,
  held,
  mount,
  resolved,
} from "../../fixtures/ports.ts";

type Step = "invite" | "connect";

const progress = (completed: number): ChecklistProgress<Step> => ({
  steps: [],
  completed,
  total: 2,
  done: completed === 2,
  next: undefined,
});

function client() {
  return {
    progress: vi.fn((..._subject: string[]) => resolved(progress(0))),
    complete: vi.fn((_step: Step, ..._subject: string[]) => resolved(true)),
    reset: vi.fn((_step: Step, ..._subject: string[]) => resolved(true)),
  };
}

describe("createOnboardingController", () => {
  it("loads an organization checklist and completes and resets steps", async () => {
    const calls = client();
    const { view, unmount } = mount(
      createOnboardingController({
        client: calls,
        scope: "organization",
        auth: fakeAuth(),
        organizationId: "org-1",
      }),
    );
    await flush();
    expect(calls.progress).toHaveBeenCalledWith("org-1");
    expect(view().progress?.completed).toBe(0);
    calls.progress.mockReturnValue(resolved(progress(1)));
    await view().complete("invite");
    expect(calls.complete).toHaveBeenCalledWith("invite", "org-1");
    expect(view().progress?.completed).toBe(1);
    calls.reset.mockReturnValue(failed("denied"));
    await view().reset("invite");
    expect(view().error?.message).toBe("denied");
    calls.progress.mockReturnValue(failed("down"));
    await view().refresh();
    expect(view().error?.message).toBe("down");
    unmount();
  });

  it("loads a user checklist, waits for an organization and drops stale answers", async () => {
    const user = client();
    mount(
      createOnboardingController({
        client: user,
        scope: "user",
        auth: fakeAuth(),
      }),
    ).unmount();
    expect(user.progress).toHaveBeenCalledWith();

    const waiting = client();
    mount(
      createOnboardingController({
        client: waiting,
        scope: "organization",
        auth: fakeAuth(),
        organizationId: null,
      }),
    ).unmount();
    expect(waiting.progress).not.toHaveBeenCalled();

    const slow = client();
    const answer = held(progress(2));
    slow.progress.mockReturnValue(answer.result);
    const controller = createOnboardingController({
      client: slow,
      scope: "user",
      auth: fakeAuth(),
    });
    const mounted = mount(controller);
    await flush();
    mounted.unmount();
    answer.release();
    await flush();
    expect(controller.getSnapshot().progress).toBeUndefined();
  });
});
