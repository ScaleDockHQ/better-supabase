import { describe, expect, it, vi } from "vitest";

import type {
  Checklist,
  ChecklistProgress,
} from "../../../src/blocks/onboarding/onboarding.ts";

import { createOnboardingController } from "../../../src/blocks/onboarding/client.ts";
import { defineChecklist } from "../../../src/blocks/onboarding/onboarding.ts";
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

const steps = [{ id: "invite" }, { id: "connect" }] as const;
const team = defineChecklist({ id: "team", scope: "organization", steps });
const profile = defineChecklist({ id: "profile", scope: "user", steps });

function client() {
  return {
    progress: vi.fn(
      (
        _checklist: Checklist<Step, "user" | "organization">,
        ..._subject: string[]
      ) => resolved(progress(0)),
    ),
    complete: vi.fn(
      (
        _checklist: Checklist<Step, "user" | "organization">,
        _step: Step,
        ..._subject: string[]
      ) => resolved(true),
    ),
    reset: vi.fn(
      (
        _checklist: Checklist<Step, "user" | "organization">,
        _step: Step,
        ..._subject: string[]
      ) => resolved(true),
    ),
  };
}

describe("createOnboardingController", () => {
  it("loads an organization checklist and completes and resets steps", async () => {
    const calls = client();

    const { view, unmount } = mount(
      createOnboardingController({
        client: calls,
        checklist: team,
        auth: fakeAuth(),
        organizationId: "org-1",
      }),
    );

    await flush();
    expect(calls.progress).toHaveBeenCalledWith(team, "org-1");
    expect(view().progress?.completed).toBe(0);
    calls.progress.mockReturnValue(resolved(progress(1)));
    await view().complete("invite");
    expect(calls.complete).toHaveBeenCalledWith(team, "invite", "org-1");
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
        checklist: profile,
        auth: fakeAuth(),
      }),
    ).unmount();
    expect(user.progress).toHaveBeenCalledWith(profile);

    const waiting = client();
    mount(
      createOnboardingController({
        client: waiting,
        checklist: team,
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
      checklist: profile,
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
