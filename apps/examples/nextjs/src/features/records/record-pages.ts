import "server-only";
import { attachmentsBlock } from "better-supabase/blocks/attachments";
import { commentsBlock } from "better-supabase/blocks/comments";
import { permissionsBlock } from "better-supabase/blocks/permissions";
import { relationsBlock } from "better-supabase/blocks/relations";
import { defineRecordType } from "better-supabase/records";

import { permissions } from "@/lib/supabase/blocks/permissions";
import {
  attachmentsConfig,
  commentsConfig,
  relationsConfig,
} from "@/lib/supabase/blocks/slices";
import { bsbCore } from "@/lib/supabase/server-core";

import type { RecordType } from "./record-subject";

/**
 * The record type behind the shared sections: the three blocks every record
 * page binds, for any subject type. `gen` writes one record type per subject
 * with the blocks that bind to it, and a deal gets none because its own block
 * registers it, so the sections take this one and the subject's type.
 */
function sectionRecord<const T extends RecordType>(type: T) {
  return defineRecordType({
    type,
    blocks: {
      attachments: attachmentsBlock,
      comments: commentsBlock,
      relations: relationsBlock,
    },
    config: {
      attachments: attachmentsConfig,
      comments: commentsConfig,
      relations: relationsConfig,
    },
    permissions,
    access: permissionsBlock,
  });
}

/**
 * `load`, `timeline` and one Server Action per binding write, for each record
 * type that shows the shared sections.
 */
export const recordPages = {
  customer: bsbCore.record(sectionRecord("customer")),
  company: bsbCore.record(sectionRecord("company")),
  person: bsbCore.record(sectionRecord("person")),
  deal: bsbCore.record(sectionRecord("deal")),
} as const;
