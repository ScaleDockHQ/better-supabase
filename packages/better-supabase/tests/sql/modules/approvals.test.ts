import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (
  modules: readonly string[],
  module: string,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const USER = "00000000-0000-4000-8000-000000000001";

const invoices = {
  invoice: {
    send: {
      steps: [
        { approvers: { permission: "invoices.approve" }, required: 2 },
        { approvers: { users: [USER] }, required: "all" },
      ],
      expiresIn: "P7D",
      run: { transition: "sent" },
    },
  },
};

const machines = {
  invoice: {
    table: "public.invoices",
    column: "status",
    initial: "draft",
    transitions: { draft: ["sent", "void"] },
    requiresApproval: { draft: ["sent"] },
  },
};

describe("approvals module", () => {
  it("snapshots each policy and refuses unknown ones", () => {
    const sql = sqlOf(["approvals"], "approvals", {
      modules: {
        approvals: {
          options: {
            policies: {
              doc: { publish: { steps: [{ approvers: { role: "admin" } }] } },
            },
          },
        },
      },
    });

    expect(sql).toContain(
      `when 'doc:publish' then '{"steps":[{"approvers":{"role":"admin"},"required":1}]`,
    );
    expect(sql).toContain("APPROVAL_POLICY_UNKNOWN");
  });

  it("runs a state-machine transition the machine gates on approval", () => {
    const layout: Layout = {
      modules: {
        approvals: { options: { policies: invoices } },
        "state-machine": { options: { machines } },
      },
    };

    const approvals = sqlOf(
      ["approvals", "state-machine"],
      "approvals",
      layout,
    );

    expect(approvals).toContain(`"transition"(v_req."subject_type"`);
    expect(approvals).toContain(`"required":1`);

    const machine = sqlOf(
      ["approvals", "state-machine"],
      "state-machine",
      layout,
    );

    expect(machine).toContain("STATE_APPROVAL_REQUIRED");
    expect(machine).toContain(`"better_supabase"."approval_requests" a`);
  });

  it("checks policies when the config is built", () => {
    const build = (policies: unknown, modules = ["approvals"]): string =>
      sqlOf(modules, "approvals", {
        modules: { approvals: { options: { policies } } },
      });

    expect(() => build(invoices)).toThrow(/needs the state-machine module/);
    expect(() =>
      build({ doc: { publish: { steps: [{ approvers: {} }] } } }),
    ).toThrow(/names nobody/);
    expect(() =>
      build({
        doc: {
          publish: {
            steps: [{ approvers: { role: "admin" }, required: "all" }],
          },
        },
      }),
    ).toThrow(/needs approvers.users/);
    expect(() =>
      build({
        doc: {
          publish: { steps: [{ approvers: { users: [USER] }, required: 2 }] },
        },
      }),
    ).toThrow(/more than approvers.users/);
    expect(() =>
      build({
        doc: {
          publish: {
            steps: [{ approvers: { role: "admin" } }],
            expiresIn: "7 days",
          },
        },
      }),
    ).toThrow(/ISO 8601 duration/);
    expect(() =>
      build({
        doc: {
          publish: {
            steps: [{ approvers: { role: "admin" } }],
            run: { queue: "publish" },
          },
        },
      }),
    ).toThrow(/needs the queue block/);
  });

  it("enqueues the policy's job with the queue block", () => {
    const sql = sqlOf(["approvals", "queue"], "approvals", {
      modules: {
        approvals: {
          options: {
            policies: {
              doc: {
                publish: {
                  steps: [{ approvers: { role: "admin" } }],
                  run: { queue: "publish" },
                },
              },
            },
          },
        },
      },
    });

    expect(sql).toContain(`enqueue_job"(queue => 'publish'`);
  });

  it("refuses an approval gate on a transition the machine doesn't allow", () => {
    expect(() =>
      sqlOf(["approvals", "state-machine"], "state-machine", {
        modules: {
          "state-machine": {
            options: {
              machines: {
                invoice: {
                  ...machines.invoice,
                  requiresApproval: { draft: ["paid"] },
                },
              },
            },
          },
        },
      }),
    ).toThrow(/paid is not an allowed transition/);
  });

  it("notifies approvers only with the notifications module", () => {
    expect(sqlOf(["approvals"], "approvals")).not.toContain(
      "send_notification",
    );
    expect(sqlOf(["approvals", "notifications"], "approvals")).toContain(
      "'approval.' || approval_notify.kind",
    );
  });
});

describe("approvals approvers from the provider", () => {
  const eligible = (isApprover?: string): string =>
    sqlOf(["approvals"], "approvals", {
      modules: {
        permissions: { model: "provider" },
        approvals: {
          options: {
            policies: {
              invoice: {
                send: {
                  steps: [{ approvers: { role: "admin" }, required: 1 }],
                },
              },
            },
          },
        },
      },
      accessProvider: {
        ...moduleProvider,
        functions: {
          ...moduleProvider.functions,
          ...(isApprover === undefined ? {} : { isApprover }),
        },
      },
    });

  it("also asks isApprover with kind <subject type>.<action>, never for the requester", () => {
    expect(
      eligible("authz.is_approver({kind}, {subject}, {tenant}, '{scope}')"),
    ).toContain(
      `or (v_me is distinct from v_req."requested_by" and coalesce((authz.is_approver(v_req."subject_type" || '.' || v_req."action", v_req."subject_id"::text, v_req."tenant_id", 'organization')), false));`,
    );
  });

  it("passes the requester as {requester}", () => {
    expect(
      eligible("authz.is_approver({kind}, {subject}, {tenant}, {requester})"),
    ).toContain(
      `authz.is_approver(v_req."subject_type" || '.' || v_req."action", v_req."subject_id"::text, v_req."tenant_id", v_req."requested_by")`,
    );
  });

  it("keeps the built-in approvers without isApprover", () => {
    expect(eligible()).not.toContain("is_approver");
  });

  it("checks a delegate's membership with the provider's memberIdsFor", () => {
    expect(eligible()).toContain(
      "select t.id::text from authz.member_organization_ids_for(delegate_approval.to_user) as t(id)",
    );
  });
});
