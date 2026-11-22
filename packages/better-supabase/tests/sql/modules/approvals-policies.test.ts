import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const WHERE = "blocks.approvals.options.policies";
const USER = "11111111-1111-4111-8111-111111111111";
const ROLE = { approvers: { role: "admin" } };

const render = (policies: unknown, extra: readonly string[] = []): unknown =>
  renderBlocks(["approvals", ...extra], {
    modules: { approvals: { options: { policies } } },
  });

const publish = (policy: Record<string, unknown>): unknown => ({
  doc: { publish: { steps: [ROLE], ...policy } },
});

const step = (value: unknown): unknown => ({
  doc: { publish: { steps: [value] } },
});

describe("approval policy config errors", () => {
  it.each([
    [3, `${WHERE} must be an object`],
    [{ Bad: {} }, `${WHERE}.Bad has an invalid name`],
    [{ doc: 3 }, `${WHERE}.doc must be an object of action to policy`],
    [{ doc: { publish: 3 } }, `${WHERE}.doc.publish must be an object`],
    [
      { doc: { "Bad!": { steps: [ROLE] } } },
      `${WHERE}.doc.Bad! has an invalid name`,
    ],
    [
      { doc: { publish: { steps: [] } } },
      `${WHERE}.doc.publish.steps is empty, which needs blocks.approvals.options.tenantPolicies`,
    ],
    [step(3), `${WHERE}.doc.publish.steps.0 must be an object`],
    [
      step({ approvers: 3 }),
      `${WHERE}.doc.publish.steps.0.approvers must be an object with permission, role, team, users, manager or decider`,
    ],
    [
      step({ approvers: { role: "" } }),
      `${WHERE}.doc.publish.steps.0.approvers.role must be a string`,
    ],
    [
      step({ approvers: { users: [] } }),
      `${WHERE}.doc.publish.steps.0.approvers.users must be a list of user ids`,
    ],
    [
      step({ approvers: { role: "a", decider: false } }),
      `${WHERE}.doc.publish.steps.0.approvers.decider must be true`,
    ],
    [
      step({ ...ROLE, required: 0 }),
      `${WHERE}.doc.publish.steps.0.required must be a whole number or "all"`,
    ],
    [
      step({ approvers: { users: [USER] }, required: 2 }),
      `${WHERE}.doc.publish.steps.0.required is more than approvers.users`,
    ],
    [
      step({ ...ROLE, required: "all" }),
      `${WHERE}.doc.publish.steps.0.required "all" needs approvers.users or approvers.permission and nothing else`,
    ],
    [
      step({ ...ROLE, escalateAfter: "PT4H" }),
      `${WHERE}.doc.publish.steps.0 needs escalateAfter (an ISO 8601 duration such as PT4H) and escalateTo together`,
    ],
    [
      publish({ effects: ["Bad!"] }),
      `${WHERE}.doc.publish.effects must be a list of names`,
    ],
    [
      publish({ run: { foo: 1 } }),
      `${WHERE}.doc.publish.run must be { transition: "<status>" } or { queue: "<queue>" }`,
    ],
    [
      publish({ run: { transition: "done" } }),
      `${WHERE}.doc.publish.run needs the state-machine module`,
    ],
    [
      publish({ run: { queue: "publish" } }),
      `${WHERE}.doc.publish.run needs the queue block`,
    ],
    [
      publish({ selfApproval: "y" }),
      `${WHERE}.doc.publish.selfApproval must be a boolean`,
    ],
    [
      publish({ mode: "x" }),
      `${WHERE}.doc.publish.mode must be "confirm" or "authorize"`,
    ],
    [
      publish({ expiresIn: "7 days" }),
      `${WHERE}.doc.publish.expiresIn must be an ISO 8601 duration such as P7D`,
    ],
  ])("rejects %j", (policies, message) => {
    expect(() => render(policies)).toThrow(message);
  });

  it("needs a state-machine machine for the subject a transition runs on", () => {
    expect(() =>
      render(publish({ run: { transition: "done" } }), ["state-machine"]),
    ).toThrow(`${WHERE}.doc.publish.run: "doc" is not a state-machine machine`);
  });
});
