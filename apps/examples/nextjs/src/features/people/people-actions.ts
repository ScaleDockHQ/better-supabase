"use server";

import type {
  EmployeeInput,
  PrivateDetailsInput,
} from "better-supabase/blocks/employees";
import type { JobInput } from "better-supabase/blocks/hiring";

import { ok } from "better-supabase";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

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
 * when the caller may see them (`employees.view_sensitive`).
 */
export const createEmployee = bs.action(
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
    authorize: (session) => can(session, "employees.write"),
  },
  async (input, { tenant, supabase, session, auth }) => {
    const { employees } = blocks(supabase);

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

    const created = await employees.create(tenant, employee);

    if (!created.ok) {
      return created;
    }

    const personalEmail =
      input.personalEmail === "" ? undefined : input.personalEmail;

    if (
      can(session, "employees.view_sensitive") &&
      (input.phone !== undefined || personalEmail !== undefined)
    ) {
      const details: Writable<PrivateDetailsInput> = {};

      if (input.phone !== undefined) {
        details.phone = input.phone;
      }

      if (personalEmail !== undefined) {
        details.personalEmail = personalEmail;
      }

      const saved = await employees.savePrivateDetails(
        created.data.id,
        details,
      );

      if (!saved.ok) {
        return saved;
      }
    }

    refreshCaller(auth);

    return ok({ id: created.data.id, name: created.data.name });
  },
);

/**
 * An employee's private details; the block refuses callers without
 * `employees.view_sensitive`.
 */
export const getPrivateDetails = bs.action(
  {
    input: v.object({ employeeId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "employees.view_sensitive"),
  },
  async ({ employeeId }, { supabase }) => {
    const details = await blocks(supabase).employees.privateDetails(employeeId);

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
export const logTime = bs.action(
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
    authorize: (session) => can(session, "time_tracking.track"),
  },
  async (input, { tenant, supabase, auth }) => {
    const day = Temporal.PlainDate.from(input.date);

    const at = (time: string) =>
      day
        .toZonedDateTime({
          timeZone: TIME_ZONE,
          plainTime: Temporal.PlainTime.from(time),
        })
        .toInstant();

    const logged = await blocks(supabase, tenant).timeTracking.log({
      startedAt: at(input.start),
      endedAt: at(input.end),
      note: input.project,
      billable: input.billable === "on",
    });

    if (!logged.ok) {
      return logged;
    }

    refreshCaller(auth);

    return ok({ id: logged.data.id });
  },
);

/** Starts the caller's timer on a project, stopping the one that runs. */
export const startTimer = bs.action(
  {
    input: v.object({
      project: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "time_tracking.track"),
  },
  async ({ project }, { tenant, supabase, auth }) => {
    const started = await blocks(supabase, tenant).timeTracking.start({
      note: project,
    });

    if (!started.ok) {
      return started;
    }

    refreshCaller(auth);

    return ok({ id: started.data.id });
  },
);

export const stopTimer = bs.action(
  {
    input: v.object({}),
    requireTenant: true,
    authorize: (session) => can(session, "time_tracking.track"),
  },
  async (_input, { tenant, supabase, auth }) => {
    const stopped = await blocks(supabase, tenant).timeTracking.stop();

    if (!stopped.ok) {
      return stopped;
    }

    refreshCaller(auth);

    return ok({ id: stopped.data.id });
  },
);

/** Sends the caller's week for approval; the block refuses while a timer runs. */
export const submitTimesheet = bs.action(
  {
    input: v.object({ week: PlainDate }),
    requireTenant: true,
    authorize: (session) => can(session, "time_tracking.track"),
  },
  async ({ week }, { tenant, supabase, auth }) => {
    const submitted = await blocks(supabase, tenant).timeTracking.submit(
      Temporal.PlainDate.from(week),
    );

    if (!submitted.ok) {
      return submitted;
    }

    refreshCaller(auth);

    return ok({ status: submitted.data.status });
  },
);

/** Opens a new opening that takes applications right away. */
export const createOpening = bs.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      location: Optional(200),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "hiring.manage"),
  },
  async ({ title, location }, { tenant, supabase, auth }) => {
    const job: Writable<JobInput> = { title, status: "open" };

    if (location !== undefined) {
      job.location = location;
    }

    const saved = await blocks(supabase).hiring.saveJob(tenant, job);

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok({ id: saved.data.id, title: saved.data.title });
  },
);

/** Adds a customer as a candidate for an opening, in its first stage. */
export const addCandidate = bs.action(
  {
    input: v.object({ jobId: Id, candidateId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "hiring.write"),
  },
  async ({ jobId, candidateId }, { supabase, auth }) => {
    const applied = await blocks(supabase).hiring.apply(
      jobId,
      { type: "customer", id: candidateId },
      { source: "hiring-board" },
    );

    if (!applied.ok) {
      return applied;
    }

    refreshCaller(auth);

    return ok({ id: applied.data.id });
  },
);

/**
 * Moves an application to another open stage. `rank.move` sets the stage as the
 * row's group, which needs `application` in `config.subjects`.
 */
export const moveApplication = bs.action(
  {
    input: v.object({ applicationId: Id, stageId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "hiring.write"),
  },
  async ({ applicationId, stageId }, { supabase, auth }) => {
    const moved = await blocks(supabase).rank.move(
      "application",
      applicationId,
      { group: stageId },
    );

    if (!moved.ok) {
      return moved;
    }

    refreshCaller(auth);

    return ok({ applicationId });
  },
);

/** Hires or rejects a candidate, which moves the card to that stage. */
export const closeApplication = bs.action(
  {
    input: v.object({
      applicationId: Id,
      outcome: v.picklist(["hired", "rejected"]),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "hiring.write"),
  },
  async ({ applicationId, outcome }, { supabase, auth }) => {
    const { hiring } = blocks(supabase);

    const closed = await (outcome === "hired"
      ? hiring.hire(applicationId)
      : hiring.reject(applicationId));

    if (!closed.ok) {
      return closed;
    }

    refreshCaller(auth);

    return ok({ applicationId, outcome });
  },
);
