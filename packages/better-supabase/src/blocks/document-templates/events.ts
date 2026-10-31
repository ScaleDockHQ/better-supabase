import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What `document_template.created` and `document_template.updated` carry. */
export interface DocumentTemplateEventData {
  readonly organizationId: string;
  readonly templateId: string;
  readonly documentType: string;
  /** The entity the template belongs to; null for an organization template. */
  readonly legalEntityId: string | null;
  readonly language: string | null;
  readonly name: string;
  readonly version: number;
}

/** What `document_text_block.created` and `document_text_block.updated` carry. */
export interface DocumentTextBlockEventData {
  readonly organizationId: string;
  readonly textBlockId: string;
  readonly key: string;
  readonly legalEntityId: string | null;
  readonly language: string | null;
  readonly version: number;
}

/** What `document_snapshot.created` carries. */
export interface DocumentSnapshotEventData {
  readonly organizationId: string;
  readonly snapshotId: string;
  readonly documentType: string;
  readonly documentId: string;
  /** The version of the template the snapshot froze; null without a template. */
  readonly templateVersion: number | null;
}

/** The events of the `document-templates` block: type to data. */
export type DocumentTemplatesEvents = {
  readonly "document_template.created": DocumentTemplateEventData;
  readonly "document_template.updated": DocumentTemplateEventData;
  readonly "document_text_block.created": DocumentTextBlockEventData;
  readonly "document_text_block.updated": DocumentTextBlockEventData;
  readonly "document_snapshot.created": DocumentSnapshotEventData;
};

/**
 * The `document-templates` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const documentTemplatesEvents: Events<DocumentTemplatesEvents> =
  defineEvents({
    "document_template.created": event<DocumentTemplateEventData>(),
    "document_template.updated": event<DocumentTemplateEventData>(),
    "document_text_block.created": event<DocumentTextBlockEventData>(),
    "document_text_block.updated": event<DocumentTextBlockEventData>(),
    "document_snapshot.created": event<DocumentSnapshotEventData>(),
  });
