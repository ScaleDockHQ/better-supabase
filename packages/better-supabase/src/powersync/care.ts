import type { EngagementSubject } from "../blocks/activities/activities.ts";
import type {
  MedicationAdministrationInput,
  MedicationAsNeededInput,
} from "../blocks/medications/medications.ts";
import type {
  Observation,
  ObservationInput,
  ObservationValue,
} from "../blocks/observations/observations.ts";
import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type {
  CrudEntryLike,
  UploadFunction,
  UploadOutcome,
} from "./connector.ts";
import type { PowerSyncDatabaseLike } from "./executor.ts";

import { quoteSqliteIdent } from "../compile/sqlite.ts";
import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";
import { temporal } from "../core/temporal-required.ts";

type Row = Readonly<Record<string, unknown>>;

const text = (value: unknown): string | undefined =>
  typeof value === "string" && value !== "" ? value : undefined;

const unsupported = (message: string): Result<never> =>
  err(dbError("unsupported", message));

/** A change the server must never apply twice or out of order is refused here. */
const notReplayable = (what: string, op: string): Result<never> =>
  unsupported(
    `${what} takes the writes the care routes replay, not PowerSync op ${op}`,
  );

const CONFLICT_HINTS: ReadonlySet<string> = new Set([
  "MEDICATION_ADMINISTRATION_INVALID",
  "ACTIVITY_LOCKED",
  "ACTIVITY_NOT_FOUND",
  "OBSERVATION_NOT_FOUND",
  "MEDICATION_ADMINISTRATION_NOT_FOUND",
]);

/**
 * Overrides for `createUploadConnector({ classify })` that keep clinical
 * changes from vanishing. A dose that was already recorded, and a note or
 * observation that changed on the server meanwhile, are `conflict`s the UI can
 * show (`connector.rejected`); everything else keeps `uploadOutcome`'s
 * default.
 *
 * ```ts
 * createUploadConnector({ classify: careUploadOutcome, ... });
 * ```
 */
export function careUploadOutcome(
  error: DbError,
  _entry: CrudEntryLike,
): UploadOutcome | undefined {
  return error.hint !== undefined && CONFLICT_HINTS.has(error.hint)
    ? "conflict"
    : undefined;
}

/** The progress note functions the routes call. `activities` fits. */
export interface ProgressNoteWrites {
  log(
    organizationId: string,
    input: {
      readonly type: string;
      readonly title: string;
      readonly body?: string | null;
      readonly externalRef?: string | null;
      readonly category?: string | null;
    },
    subjects: readonly EngagementSubject[],
  ): PromiseLike<Result<unknown>>;
  update(
    id: string,
    input: {
      readonly title?: string;
      readonly body?: string | null;
      readonly category?: string | null;
    },
  ): PromiseLike<Result<unknown>>;
  amend(id: string, body: string): PromiseLike<Result<unknown>>;
  markError(id: string, reason: string): PromiseLike<Result<unknown>>;
}

export interface ProgressNoteRouteOptions {
  /** The synced links table. Default `engagement_subjects`. */
  readonly linksTable?: string;
  /** The tenant column, when `config.tenancy` renames it. Default `tenant_id`. */
  readonly tenantColumn?: string;
}

const isLocked = (result: Result<unknown>): boolean =>
  !result.ok && result.error.hint === "ACTIVITY_LOCKED";

/**
 * The upload route for the engagements of progress notes (activities of type
 * `note`).
 *
 * - A `PUT` logs the note on the records its local link rows name, with the local
 *   id as `externalRef` so a retried upload updates the note instead of adding
 *   a second one. The server picks the note's own id; the next sync replaces
 *   the local row with it. A note that is already locked counts as applied.
 * - A `PATCH` updates the title, body or category. When the note locked on the
 *   server in the meantime, a changed body is added as an addendum (`amend`),
 *   so the edit is kept and the locked text stays as written.
 * - A `PATCH` that sets `marked_error_reason` flags the note as entered in error.
 *   Deleting a note is refused: notes are never deleted.
 *
 * ```ts
 * createUploadConnector({
 *   classify: careUploadOutcome,
 *   tables: {
 *     activities: progressNoteRoute(bsb.activities, powersync),
 *     engagement_subjects: activityLinksRoute(),
 *   },
 * });
 * ```
 */
export function progressNoteRoute(
  notes: ProgressNoteWrites,
  database: PowerSyncDatabaseLike,
  options: ProgressNoteRouteOptions = {},
): UploadFunction {
  const links = quoteSqliteIdent(options.linksTable ?? "engagement_subjects");
  const tenant = options.tenantColumn ?? "tenant_id";

  return async (entry) => {
    const data = entry.opData ?? {};

    switch (entry.op) {
      case "PUT": {
        const organizationId = text(data[tenant]);
        const title = text(data["title"]);

        if (data["type"] !== "note" || !organizationId || !title) {
          return unsupported(
            `engagement ${entry.id} is not a note with an organization and a title; log other engagements on the server`,
          );
        }

        const subjects = (
          await database.getAll<Row>(
            `SELECT * FROM ${links} WHERE activity_id = ?`,
            [entry.id],
          )
        )
          .toSorted(
            (a, b) => Number(a["position"] ?? 0) - Number(b["position"] ?? 0),
          )
          .flatMap((row) => {
            const type = text(row["subject_type"]);
            const id = text(row["subject_id"]);

            return type && id ? [{ type, id }] : [];
          });

        const logged = await notes.log(
          organizationId,
          {
            type: "note",
            title,
            ...(data["body"] === undefined
              ? {}
              : { body: text(data["body"]) ?? null }),
            ...(data["category"] === undefined
              ? {}
              : { category: text(data["category"]) ?? null }),
            externalRef: entry.id,
          },
          subjects,
        );

        return isLocked(logged) ? ok(undefined) : logged;
      }

      case "PATCH": {
        const reason = text(data["marked_error_reason"]);

        if (reason !== undefined) {
          return notes.markError(entry.id, reason);
        }

        const patch = {
          ...(typeof data["title"] === "string"
            ? { title: data["title"] }
            : {}),
          ...(data["body"] === undefined
            ? {}
            : { body: text(data["body"]) ?? null }),
          ...(data["category"] === undefined
            ? {}
            : { category: text(data["category"]) ?? null }),
        };

        if (Object.keys(patch).length === 0) {
          return ok(undefined);
        }

        const updated = await notes.update(entry.id, patch);
        const addendum = text(data["body"]);

        return isLocked(updated) && addendum !== undefined
          ? notes.amend(entry.id, addendum)
          : updated;
      }

      default: {
        return notReplayable("a progress note", entry.op);
      }
    }
  };
}

/**
 * The upload route for the links of notes. The note's own upload carries its
 * records, so a link write has nothing left to replay.
 */
export function activityLinksRoute(): UploadFunction {
  return () => Promise.resolve(ok(undefined));
}

/** The observation functions the route calls. `observations` fits. */
export interface ObservationWrites {
  record(
    organizationId: string,
    input: ObservationInput,
  ): PromiseLike<Result<unknown>>;
  list(
    subjectType: string,
    subjectId: string,
    options?: { readonly definitionKey?: string; readonly limit?: number },
  ): PromiseLike<Result<readonly Observation[]>>;
  markError(
    observationId: string,
    reason: string,
  ): PromiseLike<Result<unknown>>;
}

export interface ObservationRouteOptions {
  /** The synced definitions table. Default `observation_definitions`. */
  readonly definitionsTable?: string;
  /** The tenant column. Default `tenant_id`. */
  readonly tenantColumn?: string;
}

function valueOf(data: Row, valueType: string): ObservationValue | undefined {
  if (valueType === "components") {
    const parsed: unknown =
      typeof data["components"] === "string"
        ? safeJson(data["components"])
        : data["components"];

    return typeof parsed === "object" && parsed !== null
      ? Object.fromEntries(
          Object.entries(parsed).flatMap(([key, part]) =>
            typeof part === "number" ? [[key, part]] : [],
          ),
        )
      : undefined;
  }

  if (valueType === "number" || valueType === "integer") {
    return typeof data["value_number"] === "number"
      ? data["value_number"]
      : undefined;
  }

  if (valueType === "boolean") {
    return data["value_code"] === "true"
      ? true
      : data["value_code"] === "false"
        ? false
        : undefined;
  }

  return valueType === "code"
    ? text(data["value_code"])
    : text(data["value_text"]);
}

function safeJson(value: string): unknown {
  try {
    return JSON.parse(value);
  } catch {
    return undefined;
  }
}

const sameValue = (a: unknown, b: unknown): boolean =>
  JSON.stringify(a) === JSON.stringify(b);

/**
 * The upload route for observations (vital signs).
 *
 * - A `PUT` records the reading on the definition the local row names. Before it
 *   records, it looks for the same reading (definition, time and value) on the
 *   record and counts that as applied, so an upload that reached the server but
 *   lost its answer doesn't add a duplicate. The server picks the observation's
 *   own id; the next sync replaces the local row with it.
 * - A `PATCH` that sets `reason` on a row with `status` `error` marks the
 *   observation as entered in error. Anything else is refused: amend an
 *   observation online, since an amendment is a new observation.
 * - Deleting an observation is refused.
 */
export function observationRoute(
  observations: ObservationWrites,
  database: PowerSyncDatabaseLike,
  options: ObservationRouteOptions = {},
): UploadFunction {
  const definitions = quoteSqliteIdent(
    options.definitionsTable ?? "observation_definitions",
  );

  const tenant = options.tenantColumn ?? "tenant_id";

  return async (entry) => {
    const data = entry.opData ?? {};

    if (entry.op === "PATCH") {
      const reason = text(data["reason"]);

      return data["status"] === "error" && reason !== undefined
        ? observations.markError(entry.id, reason)
        : unsupported(
            "an observation changes by amendment: amend it online, which records a new observation",
          );
    }

    if (entry.op !== "PUT") {
      return notReplayable("an observation", entry.op);
    }

    const organizationId = text(data[tenant]);
    const subjectType = text(data["subject_type"]);
    const subjectId = text(data["subject_id"]);

    const [definition] = await database.getAll<Row>(
      `SELECT "key", value_type FROM ${definitions} WHERE id = ?`,
      [data["definition_id"]],
    );

    const key = text(definition?.["key"]);
    const valueType = text(definition?.["value_type"]);

    if (!organizationId || !subjectType || !subjectId || !key || !valueType) {
      return err(
        dbError(
          "invalid_input",
          `observation ${entry.id} names no organization, record or synced definition`,
        ),
      );
    }

    const value = valueOf(data, valueType);

    if (value === undefined) {
      return err(
        dbError(
          "invalid_input",
          `observation ${entry.id} has no ${valueType} value`,
        ),
      );
    }

    const observedAt = temporal().Instant.from(
      text(data["observed_at"]) ?? new Date().toISOString(),
    );

    const known = await observations.list(subjectType, subjectId, {
      definitionKey: key,
      limit: 1000,
    });

    if (
      known.ok &&
      known.data.some(
        (each) =>
          each.observedAt.equals(observedAt) && sameValue(each.value, value),
      )
    ) {
      return ok(undefined);
    }

    const method = text(data["method"]);
    const device = text(data["device"]);
    const note = text(data["note"]);

    return observations.record(organizationId, {
      subjectType,
      subjectId,
      definitionKey: key,
      value,
      observedAt,
      ...(method === undefined ? {} : { method }),
      ...(device === undefined ? {} : { device }),
      ...(note === undefined ? {} : { note }),
    });
  };
}

/** The medication functions the route calls. `medications` fits. */
export interface MedicationWrites {
  recordAdministration(
    administrationId: string,
    input: MedicationAdministrationInput,
  ): PromiseLike<Result<unknown>>;
  recordAsNeeded(
    orderId: string,
    input: MedicationAsNeededInput,
  ): PromiseLike<Result<unknown>>;
}

const GIVEN = new Set(["given", "refused", "skipped"]);

/**
 * The upload route for `medication_administrations`: a nurse records a dose
 * offline and the route replays it.
 *
 * - A `PATCH` that sets `status` to `given`, `refused` or `skipped` on a planned
 *   dose records it with `recordAdministration`, with the dose, reason, second
 *   checker and note the row carries.
 * - A `PUT` of a dose without `scheduled_at` is an as-needed dose, recorded with
 *   `recordAsNeeded`. A `PUT` with `scheduled_at` is refused: the server plans
 *   scheduled doses.
 * - A dose someone else recorded first, or a dose the server refuses (a second
 *   checker is missing, the daily maximum is reached), is never retried or
 *   dropped quietly: with `careUploadOutcome` it lands in `connector.rejected`
 *   as a conflict for the nurse to resolve. Deleting a dose is refused.
 */
export function medicationAdministrationRoute(
  medications: MedicationWrites,
): UploadFunction {
  return async (entry) => {
    const data = entry.opData ?? {};

    const input = {
      ...(typeof data["dose"] === "number" ? { dose: data["dose"] } : {}),
      ...(text(data["checked_by"]) === undefined
        ? {}
        : { checkedBy: text(data["checked_by"])! }),
      ...(text(data["note"]) === undefined
        ? {}
        : { note: text(data["note"])! }),
    };

    switch (entry.op) {
      case "PATCH": {
        const status = text(data["status"]);

        if (status === undefined || !GIVEN.has(status)) {
          return unsupported(
            `dose ${entry.id} can only be recorded as given, refused or skipped`,
          );
        }

        return medications.recordAdministration(entry.id, {
          ...input,
          // SAFETY: GIVEN holds exactly the three statuses the type allows.
          status: status as MedicationAdministrationInput["status"],
          ...(text(data["reason"]) === undefined
            ? {}
            : { reason: text(data["reason"])! }),
        });
      }

      case "PUT": {
        const orderId = text(data["order_id"]);
        const reason = text(data["reason"]);

        if (text(data["scheduled_at"]) !== undefined) {
          return unsupported(
            "a scheduled dose is planned on the server; record it with a PATCH",
          );
        }

        if (!orderId || reason === undefined) {
          return err(
            dbError(
              "invalid_input",
              `as-needed dose ${entry.id} needs an order and a reason`,
            ),
          );
        }

        return medications.recordAsNeeded(orderId, { ...input, reason });
      }

      default: {
        return notReplayable("a medication dose", entry.op);
      }
    }
  };
}
