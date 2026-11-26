"use server";

import type {
  EmployeeInput,
  PrivateDetailsInput,
} from "better-supabase/blocks/employees";
import type { JobInput } from "better-supabase/blocks/hiring";

import { ok } from "better-supabase";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

import { TIME_ZONE } from "./people-queries";

type Writable<T> = { -readonly [K in keyof T]: T[K] };

const Id = v.pipe(v.string(), v.uuid());

const Optional = (max: number) =>
  v.optional(
    v.pipe(
      v.string(),
      v.trim(),
      v.maxLength(max),
      v.transform((value) => (value === "" ? undefined : value)),
    ),
  );

const OptionalId = v.optional(v.union([v.literal(""), Id]), "");

const PlainDate = v.pipe(v.string(), v.isoDate());

/**
 * Adds an employee. Phone and personal email are private details, saved only
 * when the caller may see them (`employees.read_sensitive`).
 */
export const createEmployee = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      email: v.optional(
        v.union([v.literal(""), v.pipe(v.string(), v.trim(), v.email())]),
        "",
      ),
      jobTitle: Optional(200),
      managerId: OptionalId,
      startDate: v.optional(v.union([v.literal(""), PlainDate]), ""),
      phone: Optional(50),
      personalEmail: v.optional(
        v.union([v.literal(""), v.pipe(v.string(), v.trim(), v.email())]),
        "",
      ),
    }),
    requireTenant: true,
    permission: "employees.write",
    tags: () => [tags.people()],
    refresh: true,
  },
  async (input, { tenant, db }) => {
    const { employees } = db;

    const employee: Writable<EmployeeInput> = { name: input.name };

    if (input.email !== "") {
      employee.email = input.email;
    }

    if (input.jobTitle !== undefined) {
      employee.jobTitle = input.jobTitle;
    }

    if (input.managerId !== "") {
      employee.managerId = input.managerId;
    }

    if (input.startDate !== "") {
      employee.startDate = Temporal.PlainDate.from(input.startDate);
    }

    const created = await employees.create({
      organizationId: tenant,
      input: employee,
    });

    if (!created.ok) {
      return created;
    }

    const personalEmail =
      input.personalEmail === "" ? undefined : input.personalEmail;

    if (
      can(await getPermissions(), "employees.read_sensitive") &&
      (input.phone !== undefined || personalEmail !== undefined)
    ) {
      const details: Writable<PrivateDetailsInput> = {};

      if (input.phone !== undefined) {
        details.phone = input.phone;
      }

      if (personalEmail !== undefined) {
        details.personalEmail = personalEmail;
      }

      const saved = await employees.savePrivateDetails({
        employeeId: created.data.id,
        input: details,
      });

      if (!saved.ok) {
        return saved;
      }
    }

    return ok({ id: created.data.id, name: created.data.name });
  },
);

/**
 * An employee's private details; the block refuses callers without
 * `employees.read_sensitive`.
 */
export const getPrivateDetails = bsb.action(
  {
    input: v.object({ employeeId: Id }),
    requireTenant: true,
    permission: "employees.read_sensitive",
  },
  async ({ employeeId }, { db }) => {
    const details = await db.employees.privateDetails(employeeId);

    if (!details.ok) {
      return details;
    }

    const found = details.data;

    return ok(
      found
        ? {
            phone: found.phone ?? null,
            personalEmail: found.personalEmail ?? null,
            birthDate: found.birthDate?.toString() ?? null,
          }
        : null,
    );
  },
);

const Clock = v.pipe(v.string(), v.regex(/^([01]\d|2[0-3]):[0-5]\d$/));

/** Logs a block of time on a day of the caller's week, in the block's zone. */
export const logTime = bsb.action(
  {
    input: v.pipe(
      v.object({
        date: PlainDate,
        start: Clock,
        end: Clock,
        project: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
        billable: v.optional(v.literal("on")),
      }),
      v.check((input) => input.start < input.end, "End after the start"),
    ),
    requireTenant: true,
    permission: "time_entries.track",
    tags: () => [tags.people()],
    refresh: true,
  },
  async (input, { db }) => {
    const day = Temporal.PlainDate.from(input.date);

    const at = (time: string) =>
      day
        .toZonedDateTime({
          timeZone: TIME_ZONE,
          plainTime: Temporal.PlainTime.from(time),
        })
        .toInstant();

    const logged = await db.timeEntries.log({
      startedAt: at(input.start),
      endedAt: at(input.end),
      note: input.project,
      billable: input.billable === "on",
    });

    if (!logged.ok) {
      return logged;
    }

    return ok({ id: logged.data.id });
  },
);

/** Starts the caller's timer on a project, stopping the one that runs. */
export const startTimer = bsb.blockAction(
  ({ db }) => db.timeEntries,
  "start",
  {
    input: v.object({
      project: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
    permission: "time_entries.track",
    tags: () => [tags.people()],
    refresh: true,
    args: ({ project }) => [{ note: project }],
  },
  (started) => ({ id: started.id }),
);

export const stopTimer = bsb.blockAction(
  ({ db }) => db.timeEntries,
  "stop",
  {
    input: v.object({}),
    requireTenant: true,
    permission: "time_entries.track",
    tags: () => [tags.people()],
    refresh: true,
    args: (_) => [],
  },
  (stopped) => ({ id: stopped.id }),
);

/** Sends the caller's week for approval; the block refuses while a timer runs. */
export const submitTimesheet = bsb.blockAction(
  ({ db }) => db.timeEntries,
  "submit",
  {
    input: v.object({ week: PlainDate }),
    requireTenant: true,
    permission: "time_entries.track",
    tags: () => [tags.people()],
    refresh: true,
    args: ({ week }) => [{ week: Temporal.PlainDate.from(week) }],
  },
  (submitted) => ({ status: submitted.status }),
);

/** Opens a new opening that takes applications right away. */
export const createOpening = bsb.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      location: Optional(200),
    }),
    requireTenant: true,
    permission: "hiring.manage",
    tags: () => [tags.people()],
    refresh: true,
  },
  async ({ title, location }, { tenant, db }) => {
    const job: Writable<JobInput> = { title, status: "open" };

    if (location !== undefined) {
      job.location = location;
    }

    const saved = await db.hiring.saveJob({ organizationId: tenant, job });

    if (!saved.ok) {
      return saved;
    }

    return ok({ id: saved.data.id, title: saved.data.title });
  },
);

/** Adds a customer as a candidate for an opening, in its first stage. */
export const addCandidate = bsb.blockAction(
  ({ db }) => db.hiring,
  "apply",
  {
    input: v.object({ jobId: Id, candidateId: Id }),
    requireTenant: true,
    permission: "hiring.write",
    tags: () => [tags.people()],
    refresh: true,
    args: ({ jobId, candidateId }) => [
      {
        jobId,
        candidate: { type: "customer", id: candidateId },
        source: "hiring-board",
      },
    ],
  },
  (applied) => ({ id: applied.id }),
);

/**
 * Moves an application to another open stage. `rank.move` sets the stage as the
 * row's group, which needs `application` in `config.recordTypes`.
 */
export const moveApplication = bsb.action(
  {
    input: v.object({ applicationId: Id, stageId: Id }),
    requireTenant: true,
    permission: "hiring.write",
    tags: () => [tags.people()],
    refresh: true,
  },
  async ({ applicationId, stageId }, { db }) => {
    const moved = await db.rank.move({
      subjectType: "application",
      subjectId: applicationId,
      target: { group: stageId },
    });

    if (!moved.ok) {
      return moved;
    }

    return ok({ applicationId });
  },
);

/** Hires or rejects a candidate, which moves the card to that stage. */
export const closeApplication = bsb.action(
  {
    input: v.object({
      applicationId: Id,
      outcome: v.picklist(["hired", "rejected"]),
    }),
    requireTenant: true,
    permission: "hiring.write",
    tags: () => [tags.people()],
    refresh: true,
  },
  async ({ applicationId, outcome }, { db }) => {
    const { hiring } = db;

    const closed = await (outcome === "hired"
      ? hiring.hire(applicationId)
      : hiring.reject({ applicationId }));

    if (!closed.ok) {
      return closed;
    }

    return ok({ applicationId, outcome });
  },
);
