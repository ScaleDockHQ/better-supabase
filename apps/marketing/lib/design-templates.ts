import type { Preset, PresetName } from "better-supabase/preset";

import type { AppColumn, Design } from "./design";

import { applyNamedPreset } from "./create";

/** A starting design on Create: a named preset, the blocks its features add, and app tables. */
export interface DesignTemplate {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly preset: PresetName;
  /** Blocks the template's record features need beyond the preset's. */
  readonly blocks: readonly string[];
  readonly design: Design;
}

const USERS = "auth.users";

const required = (column: AppColumn): AppColumn => ({
  ...column,
  nullable: false,
});

const name: AppColumn = required({ type: "text" });

const user: AppColumn = {
  type: "uuid",
  references: { table: USERS, onDelete: "set null" },
};

function belongsTo(table: string): AppColumn {
  return required({
    type: "uuid",
    references: { table, onDelete: "cascade" },
  });
}

function options(values: readonly string[], fallback = values[0]): AppColumn {
  const column = required({ type: "text", options: values });

  return fallback === undefined
    ? column
    : { ...column, default: `'${fallback}'` };
}

export const DESIGN_TEMPLATES: readonly DesignTemplate[] = [
  {
    id: "projects-and-tasks",
    title: "Projects and tasks",
    description:
      "Projects with tasks you can order, assign and comment on, on the Projects preset.",
    preset: "projects",
    blocks: ["search"],
    design: {
      appTables: {
        projects: {
          columns: {
            name,
            status: options(["planned", "active", "done"]),
            owner_id: user,
            due_on: { type: "date" },
          },
          subject: { type: "project", title: "name", search: {} },
        },
        tasks: {
          columns: {
            project_id: belongsTo("projects"),
            title: name,
            status: options(["todo", "doing", "done"]),
            priority: options(["low", "medium", "high"], "medium"),
            assignee_id: user,
            due_on: { type: "date" },
            estimate_hours: { type: "numeric", min: 0 },
          },
          indexes: [["project_id", "status"]],
          subject: {
            type: "task",
            title: "title",
            rank: { group: "project_id" },
          },
        },
      },
    },
  },
  {
    id: "content-calendar",
    title: "Content calendar",
    description:
      "Posts per channel with a status and a publish time, tagged and discussed.",
    preset: "saas",
    blocks: ["tags", "comments"],
    design: {
      appTables: {
        channels: {
          columns: {
            name,
            color: { type: "text", format: "color" },
          },
          unique: [["name"]],
        },
        posts: {
          columns: {
            channel_id: belongsTo("channels"),
            title: name,
            body: { type: "text", format: "long_text" },
            status: options(["idea", "draft", "scheduled", "published"]),
            publish_at: { type: "timestamptz" },
            author_id: user,
            link: { type: "text", format: "url" },
          },
          indexes: [["publish_at"]],
          subject: { type: "post", title: "title" },
        },
      },
    },
  },
  {
    id: "asset-register",
    title: "Asset register",
    description:
      "Equipment with its serial number, location, holder and purchase cost, with files attached.",
    preset: "saas",
    blocks: ["attachments", "tags"],
    design: {
      appTables: {
        locations: {
          columns: {
            name,
            address: { type: "text", format: "long_text" },
          },
        },
        assets: {
          columns: {
            name,
            serial: { type: "text", unique: true },
            category: options(
              ["laptop", "monitor", "phone", "furniture", "vehicle", "other"],
              "other",
            ),
            location_id: {
              type: "uuid",
              references: { table: "locations", onDelete: "set null" },
            },
            holder_id: user,
            purchased_on: { type: "date" },
            cost: { type: "bigint", format: "currency", min: 0 },
            warranty_until: { type: "date" },
          },
          subject: { type: "asset", title: "name" },
        },
      },
    },
  },
  {
    id: "event-planning",
    title: "Event planning",
    description: "Events with an agenda and an attendee list you can check in.",
    preset: "saas",
    blocks: ["comments"],
    design: {
      appTables: {
        events: {
          columns: {
            name,
            starts_at: required({ type: "timestamptz" }),
            ends_at: { type: "timestamptz" },
            venue: { type: "text" },
            capacity: { type: "integer", min: 1 },
            status: options(["draft", "open", "closed"]),
          },
          subject: { type: "event", title: "name" },
        },
        agenda_items: {
          columns: {
            event_id: belongsTo("events"),
            title: name,
            starts_at: required({ type: "timestamptz" }),
            room: { type: "text" },
            speaker: { type: "text" },
          },
          indexes: [["event_id", "starts_at"]],
        },
        attendees: {
          columns: {
            event_id: belongsTo("events"),
            name,
            email: required({ type: "text", format: "email" }),
            ticket: options(["general", "vip", "speaker"]),
            checked_in: required({ type: "boolean", default: "false" }),
          },
          unique: [["event_id", "email"]],
        },
      },
    },
  },
  {
    id: "feedback-board",
    title: "Feedback board",
    description:
      "Ideas on boards with a status, comments and one vote per person.",
    preset: "saas",
    blocks: ["comments", "tags", "search"],
    design: {
      appTables: {
        boards: {
          columns: {
            name,
            description: { type: "text", format: "long_text" },
          },
        },
        ideas: {
          columns: {
            board_id: belongsTo("boards"),
            title: name,
            details: { type: "text", format: "long_text" },
            status: options([
              "new",
              "planned",
              "in_progress",
              "shipped",
              "declined",
            ]),
            author_id: user,
          },
          subject: {
            type: "idea",
            title: "title",
            search: { body: ["details"] },
          },
        },
        idea_votes: {
          columns: {
            idea_id: belongsTo("ideas"),
            member_id: required({
              type: "uuid",
              references: { table: USERS, onDelete: "cascade" },
            }),
          },
          unique: [["idea_id", "member_id"]],
        },
      },
    },
  },
  {
    id: "course-catalog",
    title: "Course catalog",
    description:
      "Courses in nested categories, with ordered lessons, a level and a price.",
    preset: "saas",
    blocks: ["attachments", "rank"],
    design: {
      appTables: {
        categories: {
          columns: {
            name,
            parent_id: {
              type: "uuid",
              references: { table: "categories", onDelete: "set null" },
            },
          },
        },
        courses: {
          columns: {
            title: name,
            summary: { type: "text", format: "long_text" },
            level: options(["beginner", "intermediate", "advanced"]),
            price: { type: "bigint", format: "currency", min: 0 },
            published: required({ type: "boolean", default: "false" }),
          },
          subject: { type: "course", title: "title" },
        },
        courses_categories: {
          columns: {
            course_id: belongsTo("courses"),
            category_id: belongsTo("categories"),
          },
          unique: [["course_id", "category_id"]],
        },
        lessons: {
          columns: {
            course_id: belongsTo("courses"),
            title: name,
            duration_minutes: { type: "integer", min: 1 },
            video_url: { type: "text", format: "url" },
          },
          subject: {
            type: "lesson",
            title: "title",
            rank: { group: "course_id" },
          },
        },
      },
    },
  },
];

/** The app table names a template adds, in order. */
export function templateTables(template: DesignTemplate): readonly string[] {
  return Object.keys(template.design.appTables ?? {});
}

/** The preset a template starts from: its named preset, the current stack, and its extra blocks. */
export function templatePreset(
  current: Preset,
  template: DesignTemplate,
): Preset {
  const next = applyNamedPreset(current, template.preset);
  const extra = template.blocks.filter((block) => !next.blocks.includes(block));

  return extra.length === 0
    ? next
    : { ...next, blocks: [...next.blocks, ...extra] };
}
