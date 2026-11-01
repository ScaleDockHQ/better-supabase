import { describe, expect, it, vi } from "vitest";

import { createCare } from "../../src/blocks/care/index.ts";
import { createCms } from "../../src/blocks/cms/index.ts";
import { createCommerce } from "../../src/blocks/commerce/index.ts";
import { createEvents } from "../../src/blocks/events/index.ts";
import { createGovernance } from "../../src/blocks/governance/index.ts";
import { createLearning } from "../../src/blocks/learning/index.ts";
import { createPeople } from "../../src/blocks/people/index.ts";
import { createProjects } from "../../src/blocks/projects/index.ts";
import { createSaas } from "../../src/blocks/saas/index.ts";
import { createService } from "../../src/blocks/service/index.ts";
import { createSupport } from "../../src/blocks/support/index.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";

const done = <T>(data: T): AsyncResult<T> =>
  new AsyncResult(Promise.resolve(ok(data)));

const failure = (): AsyncResult<never> =>
  new AsyncResult<never>(Promise.resolve(err(dbError("not_found", "no"))));

const step = <T>(order: string[], name: string, value: T): AsyncResult<T> => {
  order.push(name);

  return done(value);
};

// SAFETY: the helpers read only the methods the fakes define.
const parts = <T>(value: object): T => value as T;

describe("saas.inviteWithinSeats", () => {
  const build = (left: number | undefined) => {
    const invite = vi.fn(() => done({ token: "t" }));

    const saas = createSaas(
      parts({
        parts: {
          organizations: {
            members: () => done([{ id: "a" }, { id: "b" }]),
            invite,
          },
          entitlements: { seatsLeft: vi.fn(() => done(left)) },
        },
      }),
    );

    return { invite, saas };
  };

  const input = { organizationId: "o", email: "a@b.c", role: "member" };

  it("invites while a seat is left", async () => {
    const { invite, saas } = build(1);

    expect((await saas.inviteWithinSeats(input)).ok).toBe(true);
    expect(invite).toHaveBeenCalledOnce();
  });

  it("invites when the plan has no seat limit", async () => {
    const { invite, saas } = build(undefined);

    expect((await saas.inviteWithinSeats(input)).ok).toBe(true);
    expect(invite).toHaveBeenCalledOnce();
  });

  it("refuses without a seat and sends nothing", async () => {
    const { invite, saas } = build(0);

    expect((await saas.inviteWithinSeats(input)).ok).toBe(false);
    expect(invite).not.toHaveBeenCalled();
  });
});

describe("commerce.payAndFulfil", () => {
  it("books the payment, then fulfils", async () => {
    const markPaid = vi.fn(() => done({ id: "p" }));
    const fulfilAll = vi.fn(() => done({ id: "f", shipped: true }));

    const commerce = createCommerce(
      parts({ parts: { orders: { markPaid, fulfilAll } } }),
    );

    const result = await commerce.payAndFulfil({
      orderId: "o",
      tracking: { trackingNumber: "1" },
    });

    expect(result.data).toEqual({
      payment: { id: "p" },
      fulfillment: { id: "f", shipped: true },
    });
    expect(fulfilAll).toHaveBeenCalledWith({
      orderId: "o",
      tracking: { trackingNumber: "1" },
    });
  });

  it("does not fulfil an order whose payment failed", async () => {
    const fulfilAll = vi.fn(() => done({ id: "f", shipped: false }));

    const commerce = createCommerce(
      parts({ parts: { orders: { markPaid: () => failure(), fulfilAll } } }),
    );

    expect((await commerce.payAndFulfil({ orderId: "o" })).ok).toBe(false);
    expect(fulfilAll).not.toHaveBeenCalled();
  });
});

describe("support.openTicket", () => {
  const ticket = { title: "Broken" } as never;

  it("creates the ticket, then starts its SLA", async () => {
    const start = vi.fn(() => done([{ id: "c" }]));

    const support = createSupport(
      parts({
        parts: { tasks: { create: () => done({ id: "t1" }) }, sla: { start } },
      }),
    );

    const result = await support.openTicket({
      organizationId: "o",
      ticket,
      priority: "high",
    });

    expect(result.ok).toBe(true);
    expect(start).toHaveBeenCalledWith({
      subject: { type: "task", id: "t1" },
      priority: "high",
    });
  });

  it("returns a failed SLA start and keeps the ticket", async () => {
    const create = vi.fn(() => done({ id: "t1" }));

    const support = createSupport(
      parts({ parts: { tasks: { create }, sla: { start: () => failure() } } }),
    );

    expect((await support.openTicket({ organizationId: "o", ticket })).ok).toBe(
      false,
    );
    expect(create).toHaveBeenCalledOnce();
  });
});

describe("projects.approveAndInvoice", () => {
  it("invoices only after the approval", async () => {
    const invoice = vi.fn(() => done({ id: "i" }));

    const projects = createProjects(
      parts({
        parts: {
          "time-tracking": { approve: () => done({ id: "ts" }) },
          "billable-time": { invoice },
        },
      }),
    );

    const result = await projects.approveAndInvoice({ timesheetId: "ts" });

    expect(result.data).toEqual({
      timesheet: { id: "ts" },
      invoice: { id: "i" },
    });
  });

  it("invoices nothing when the approval is refused", async () => {
    const invoice = vi.fn(() => done({ id: "i" }));

    const projects = createProjects(
      parts({
        parts: {
          "time-tracking": { approve: () => failure() },
          "billable-time": { invoice },
        },
      }),
    );

    expect((await projects.approveAndInvoice({ timesheetId: "ts" })).ok).toBe(
      false,
    );
    expect(invoice).not.toHaveBeenCalled();
  });
});

describe("service.completeVisit", () => {
  it("records parts and readings, then marks the work order done", async () => {
    const order: string[] = [];

    const service = createService(
      parts({
        parts: {
          dispatch: {
            recordPart: () => step(order, "part", { id: "p" }),
            setStatus: () => step(order, "status", { id: "w" }),
          },
          maintenance: {
            recordReading: () => step(order, "reading", { id: "m" }),
          },
        },
      }),
    );

    const result = await service.completeVisit({
      workOrderId: "w",
      parts: [{ name: "Filter", quantity: 1 }],
      readings: [{ meterId: "m", value: 10 }],
    });

    expect(order).toEqual(["part", "reading", "status"]);
    expect(result.data).toMatchObject({ parts: 1, readings: 1 });
  });

  it("leaves the work order open when a reading fails", async () => {
    const setStatus = vi.fn(() => done({ id: "w" }));

    const service = createService(
      parts({
        parts: {
          dispatch: { recordPart: () => done({}), setStatus },
          maintenance: { recordReading: () => failure() },
        },
      }),
    );

    const result = await service.completeVisit({
      workOrderId: "w",
      readings: [{ meterId: "m", value: 1 }],
    });

    expect(result.ok).toBe(false);
    expect(setStatus).not.toHaveBeenCalled();
  });
});

describe("people", () => {
  it("onboards by enrolling the new employee", async () => {
    const enroll = vi.fn(() => done({ id: "e1" }));

    const people = createPeople(
      parts({
        parts: {
          employees: { create: () => done({ id: "emp" }) },
          enrollments: { enroll },
          shifts: {},
        },
      }),
    );

    const result = await people.onboard({
      organizationId: "o",
      employee: { name: "Ann" },
      program: "onboarding",
    });

    expect(result.ok).toBe(true);
    expect(enroll).toHaveBeenCalledWith({
      program: "onboarding",
      subject: { type: "employee", id: "emp" },
    });
  });

  it("offboards, then cancels enrollments and unassigns shifts", async () => {
    const cancel = vi.fn(() => done({}));
    const unassign = vi.fn(() => done({}));

    const people = createPeople(
      parts({
        parts: {
          employees: { offboard: () => done({ id: "emp" }) },
          enrollments: { cancel },
          shifts: { unassign },
        },
      }),
    );

    const result = await people.offboard({
      employeeId: "emp",
      reason: "left",
      enrollmentIds: ["a", "b"],
      assignmentIds: ["x"],
    });

    expect(result.data).toMatchObject({ enrollments: 2, assignments: 1 });
    expect(cancel).toHaveBeenCalledTimes(2);
    expect(unassign).toHaveBeenCalledWith({
      assignmentId: "x",
      reason: "left",
    });
  });

  it("stops before the shifts when a cancel fails", async () => {
    const unassign = vi.fn(() => done({}));

    const people = createPeople(
      parts({
        parts: {
          employees: { offboard: () => done({ id: "emp" }) },
          enrollments: { cancel: () => failure() },
          shifts: { unassign },
        },
      }),
    );

    const result = await people.offboard({
      employeeId: "emp",
      enrollmentIds: ["a"],
      assignmentIds: ["x"],
    });

    expect(result.ok).toBe(false);
    expect(unassign).not.toHaveBeenCalled();
  });
});

describe("learning.assign", () => {
  it("enrolls in the course only without a program", async () => {
    const enroll = vi.fn(() => done({ id: "e" }));

    const learning = createLearning(
      parts({
        parts: {
          courses: { enroll: () => done({ id: "l" }) },
          enrollments: { enroll },
        },
      }),
    );

    const result = await learning.assign({ courseId: "c" });

    expect(result.data).toEqual({ learner: { id: "l" }, enrollment: null });
    expect(enroll).not.toHaveBeenCalled();
  });

  it("also enrolls in the program", async () => {
    const enroll = vi.fn(() => done({ id: "e" }));

    const learning = createLearning(
      parts({
        parts: {
          courses: { enroll: () => done({ id: "l" }) },
          enrollments: { enroll },
        },
      }),
    );

    const result = await learning.assign({
      courseId: "c",
      program: "p",
      subject: { type: "user", id: "u" },
    });

    expect(result.data?.enrollment).toEqual({ id: "e" });
  });
});

describe("events.sellTicket", () => {
  const slot = {
    serviceId: "s",
    resourceId: "r",
    startsAt: Temporal.Instant.from("2026-12-01T09:00:00Z"),
  };

  it("confirms the booking and issues a ticket for it", async () => {
    const issue = vi.fn(() => done({ id: "pass" }));
    const hold = vi.fn(() => done({ id: "b" }));

    const events = createEvents(
      parts({ parts: { bookings: { hold }, passes: { issue } } }),
    );

    const result = await events.sellTicket({
      ...slot,
      customer: { name: "Ann", email: "a@b.c" },
    });

    expect(result.ok).toBe(true);
    expect(hold).toHaveBeenCalledWith(
      expect.objectContaining({ confirm: true }),
    );
    expect(issue).toHaveBeenCalledWith({
      holderName: "Ann",
      holderEmail: "a@b.c",
      bookingId: "b",
    });
  });

  it("issues no pass when the booking is refused", async () => {
    const issue = vi.fn(() => done({ id: "pass" }));

    const events = createEvents(
      parts({
        parts: { bookings: { hold: () => failure() }, passes: { issue } },
      }),
    );

    expect((await events.sellTicket(slot)).ok).toBe(false);
    expect(issue).not.toHaveBeenCalled();
  });
});

describe("cms.publishWithVersion", () => {
  const subject = { type: "content", id: "e" };

  it("keeps a version, then publishes", async () => {
    const snapshot = vi.fn(() => done({ id: "v1" }));
    const publish = vi.fn(() => done({ id: "e" }));

    const cms = createCms(
      parts({ parts: { versions: { snapshot }, content: { publish } } }),
    );

    const result = await cms.publishWithVersion({
      entryId: "e",
      subject,
      label: "Launch",
    });

    expect(result.ok).toBe(true);
    expect(snapshot).toHaveBeenCalledWith({
      subject,
      input: { label: "Launch" },
    });
  });

  it("does not publish when the snapshot fails", async () => {
    const publish = vi.fn(() => done({ id: "e" }));

    const cms = createCms(
      parts({
        parts: {
          versions: { snapshot: () => failure() },
          content: { publish },
        },
      }),
    );

    expect((await cms.publishWithVersion({ entryId: "e", subject })).ok).toBe(
      false,
    );
    expect(publish).not.toHaveBeenCalled();
  });
});

describe("care.prescribeWithConsent", () => {
  const input = {
    organizationId: "o",
    subject: { type: "person", id: "p" },
    purposeKey: "medication",
    medicationId: "m",
    order: {} as never,
  };

  it("prescribes while the consent is active", async () => {
    const prescribe = vi.fn(() => done({ id: "rx" }));

    const care = createCare(
      parts({
        parts: {
          consents: { require: () => done(true) },
          medications: { prescribe },
        },
      }),
    );

    expect((await care.prescribeWithConsent(input)).ok).toBe(true);
    expect(prescribe).toHaveBeenCalledOnce();
  });

  it("prescribes nothing without the consent", async () => {
    const prescribe = vi.fn(() => done({ id: "rx" }));

    const care = createCare(
      parts({
        parts: {
          consents: { require: () => failure() },
          medications: { prescribe },
        },
      }),
    );

    expect((await care.prescribeWithConsent(input)).ok).toBe(false);
    expect(prescribe).not.toHaveBeenCalled();
  });
});

describe("governance.exportSubject", () => {
  it("requests the export, then audits it with a stable key", async () => {
    const record = vi.fn(() => done("audit-1"));

    const governance = createGovernance(
      parts({
        parts: {
          "data-lifecycle": { requestSubjectExport: () => done({ id: "x1" }) },
          audit: { record },
        },
      }),
    );

    const result = await governance.exportSubject({
      subjectType: "contact",
      subjectId: "c1",
    });

    expect(result.data).toEqual({ export: { id: "x1" }, auditId: "audit-1" });
    expect(record).toHaveBeenCalledWith({
      eventType: "data.subject_exported",
      targetType: "contact",
      record: "c1",
      idempotencyKey: "data.subject_exported:x1",
    });
  });

  it("writes no audit entry when the export is refused", async () => {
    const record = vi.fn(() => done("a"));

    const governance = createGovernance(
      parts({
        parts: {
          "data-lifecycle": { requestSubjectExport: () => failure() },
          audit: { record },
        },
      }),
    );

    expect(
      (await governance.exportSubject({ subjectType: "c", subjectId: "1" })).ok,
    ).toBe(false);
    expect(record).not.toHaveBeenCalled();
  });
});
