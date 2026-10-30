import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { SettingsDefinition } from "../settings/settings.ts";

import { defineSettings } from "../settings/settings.ts";
import { isRecord } from "../shared.ts";

/** Who may open a share link: anyone, signed-in members, or nobody. */
export type DriveLinkPolicy = "anyone" | "organization" | "none";

/** The `drive.sharing` organization setting. */
export interface DriveSharing {
  /** Whether members may share items with guests. */
  readonly guests: boolean;
  /** Who may open the organization's share links. */
  readonly links: DriveLinkPolicy;
}

const LINKS: readonly DriveLinkPolicy[] = ["anyone", "organization", "none"];

const SHARING_JSON_SCHEMA: Readonly<Record<string, unknown>> = {
  type: "object",
  additionalProperties: false,
  required: ["guests", "links"],
  properties: {
    guests: { type: "boolean" },
    links: { type: "string", enum: LINKS },
  },
};

const isLink = (value: unknown): value is DriveLinkPolicy =>
  LINKS.some((link) => link === value);

type SharingSchema = StandardSchemaV1<DriveSharing> & {
  readonly "~standard": {
    readonly jsonSchema: {
      readonly input: () => Readonly<Record<string, unknown>>;
      readonly output: () => Readonly<Record<string, unknown>>;
    };
  };
};

/** The schema of `drive.sharing`, with its JSON Schema for the settings UI. */
export const driveSharingSchema: SharingSchema = {
  "~standard": {
    version: 1,
    vendor: "better-supabase",
    validate: (value) =>
      isRecord(value) &&
      typeof value["guests"] === "boolean" &&
      isLink(value["links"])
        ? { value: { guests: value["guests"], links: value["links"] } }
        : {
            issues: [
              {
                message:
                  'drive.sharing is { guests: boolean, links: "anyone" | "organization" | "none" }',
              },
            ],
          },
    jsonSchema: {
      input: () => SHARING_JSON_SCHEMA,
      output: () => SHARING_JSON_SCHEMA,
    },
  },
};

/**
 * The drive's organization settings. Spread
 * `driveSettings.schemas.organization` into the app's `defineSettings()`:
 * `drive.sharing` turns off guest sharing, or limits share links to signed-in
 * members or turns them off. The drive reads the stored value in SQL, so the
 * policy holds for every client.
 */
export const driveSettings: SettingsDefinition<
  Record<never, never>,
  {
    readonly "drive.sharing": {
      readonly schema: SharingSchema;
      readonly default: DriveSharing;
    };
  }
> = defineSettings({
  organization: {
    "drive.sharing": {
      schema: driveSharingSchema,
      default: { guests: true, links: "anyone" },
    },
  },
});
