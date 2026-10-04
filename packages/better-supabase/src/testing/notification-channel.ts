import type {
  NotificationChannel,
  NotificationMessage,
} from "../notifications/channel.ts";

import { temporal } from "../core/temporal-required.ts";
import { type ConformanceReport, conform, expect } from "./conformance.ts";

export interface TestNotificationChannelOptions {
  /** The recipient's email in the sample message. Defaults to `null`. */
  readonly email?: string | null;
  /**
   * The delivery ids the provider received, read after the kit sends. When
   * given, the kit checks that the sample message arrived.
   */
  readonly received?: () => Promise<readonly string[]>;
}

const STATUSES = new Set(["sent", "skipped"]);

function sample(channel: string, email: string | null): NotificationMessage {
  const createdAt = temporal().Instant.fromEpochMilliseconds(0);
  return Object.freeze({
    deliveryId: "00000000-0000-4000-8000-00000000c0f0",
    channel,
    attempts: 1,
    userId: "00000000-0000-4000-8000-0000000000aa",
    email,
    notification: Object.freeze({
      id: "00000000-0000-4000-8000-00000000c0f1",
      eventId: "00000000-0000-4000-8000-00000000c0f2",
      type: "conformance.check",
      data: Object.freeze({ title: "Conformance" }),
      tenant: null,
      actorId: null,
      subject: Object.freeze({ type: "task", id: "42", label: "Conformance" }),
      summary: "Conformance check",
      actionPath: "/",
      priority: null,
      createdAt,
      readAt: null,
      resolvedAt: null,
    }),
    text: Object.freeze({ title: "Conformance check" }),
  });
}

/**
 * Runs the `NotificationChannel` contract against `channel`: the API version,
 * a name, and one frozen sample message it must send without mutating.
 * Throws a `ConformanceError` listing every failed check.
 */
export function testNotificationChannel(
  channel: NotificationChannel,
  options: TestNotificationChannelOptions = {},
): Promise<ConformanceReport> {
  const message = sample(channel.name, options.email ?? null);
  return conform(`NotificationChannel "${channel.name}"`, [
    [
      "has apiVersion 1",
      () => {
        const version: unknown = channel.apiVersion;
        expect(version === 1, "apiVersion must be 1");
      },
    ],
    [
      "has a name",
      () => {
        expect(
          typeof channel.name === "string" && channel.name.length > 0,
          "name must be a non-empty string",
        );
      },
    ],
    [
      "sends a message without mutating it and returns a valid result",
      async () => {
        const result = await channel.send(message);
        if (result === undefined) return;
        expect(
          result.status === undefined || STATUSES.has(result.status),
          `status must be "sent" or "skipped", got ${String(result.status)}`,
        );
        for (const key of ["provider", "providerMessageId"] as const)
          expect(
            result[key] === undefined || typeof result[key] === "string",
            `${key} must be a string`,
          );
      },
    ],
    options.received && [
      "delivers the message",
      async () => {
        const ids = await options.received!();
        expect(
          ids.includes(message.deliveryId),
          `delivery ${message.deliveryId} was not received`,
        );
      },
    ],
  ]);
}
