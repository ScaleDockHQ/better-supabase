import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../src/sql/registry.ts";
import { moduleBody } from "../../src/sql/render.ts";
import { moduleProvider } from "../fixtures/authorization-provider.ts";
import { entryOf } from "../fixtures/block-entry.ts";

/**
 * The SQL hooks each extensible block calls around its writes, named
 * `before_<entity>_<action>` and `after_<entity>_<action>` (ADR 0015).
 * `after_notify` predates the convention and keeps its name.
 */
const REQUIRED: Readonly<Record<string, readonly string[]>> = {
  organizations: [
    "before_organization_create",
    "after_organization_create",
    "before_organization_update",
    "after_organization_update",
  ],
  profiles: ["before_profile_update", "after_profile_update"],
  notifications: ["before_notification_send", "after_notify"],
  numbering: ["before_number_assign", "after_number_assign"],
  teams: ["before_team_create", "after_team_create"],
  tags: ["before_tag_apply", "after_tag_apply"],
  search: ["before_search_document_index", "after_search_document_index"],
  metrics: ["before_metric_rollup", "after_metric_rollup"],
  calendar: ["before_calendar_event_save", "after_calendar_event_save"],
  bookings: [
    "before_booking_reserve",
    "after_booking_reserve",
    "after_booking_confirm",
    "after_booking_cancel",
  ],
  versions: [
    "before_version_snapshot",
    "after_version_snapshot",
    "before_version_restore",
    "after_version_restore",
  ],
  trash: ["before_trash", "after_trash", "before_untrash", "after_untrash"],
  reactions: ["before_react", "after_react"],
  approvals: [
    "before_approval_request",
    "after_approval_request",
    "before_approval_decide",
    "after_approval_decide",
  ],
  "access-requests": [
    "before_access_request",
    "after_access_request",
    "before_access_grant",
    "after_access_grant",
  ],
  documents: ["before_document_create", "after_document_create"],
  accounting: [
    "before_accounting_entry_post",
    "after_accounting_entry_post",
    "before_accounting_entry_reverse",
    "after_accounting_entry_reverse",
  ],
  templates: [
    "before_template_save",
    "after_template_save",
    "before_template_apply",
    "after_template_apply",
  ],
  catalog: [
    "before_product_save",
    "after_product_save",
    "before_variant_save",
    "after_variant_save",
    "before_price_set",
    "after_price_set",
  ],
  inventory: [
    "before_stock_adjust",
    "after_stock_adjust",
    "before_stock_reserve",
    "after_stock_reserve",
  ],
  drive: [
    "before_drive_node_create",
    "after_drive_node_create",
    "before_drive_node_move",
    "after_drive_node_move",
    "before_drive_node_rename",
    "after_drive_node_rename",
    "before_drive_node_share",
    "after_drive_node_share",
  ],
  orders: [
    "before_order_place",
    "after_order_place",
    "before_fulfillment_create",
    "after_fulfillment_create",
    "before_refund_create",
    "after_refund_create",
  ],
  promotions: [
    "before_promotion_save",
    "after_promotion_save",
    "before_promotion_activate",
  ],
  forms: [
    "before_form_publish",
    "after_form_publish",
    "before_form_submission",
    "after_form_submission",
  ],
  acknowledgements: [
    "before_acknowledgement_assignment_create",
    "after_acknowledgement_assignment_create",
    "before_acknowledgement_create",
    "after_acknowledgement_create",
  ],
  signatures: [
    "before_signature_request",
    "after_signature_request",
    "before_signature_sign",
    "after_signature_sign",
  ],
  "time-tracking": [
    "before_time_entry_save",
    "after_time_entry_save",
    "before_timesheet_submit",
    "after_timesheet_submit",
  ],
  pipelines: [
    "before_pipeline_save",
    "after_pipeline_save",
    "before_pipeline_stage_save",
    "after_pipeline_stage_save",
    "before_pipeline_stage_change",
    "after_pipeline_stage_change",
  ],
  contacts: [
    "before_company_save",
    "after_company_save",
    "before_person_save",
    "after_person_save",
  ],
  activities: ["before_activity_log", "after_activity_log"],
  content: ["before_content_entry_publish", "after_content_entry_publish"],
  qualifications: [
    "before_qualification_type_save",
    "after_qualification_type_save",
    "before_qualification_grant",
    "after_qualification_grant",
    "before_qualification_revoke",
    "after_qualification_revoke",
  ],
  shifts: [
    "before_shift_save",
    "after_shift_save",
    "before_shift_cancel",
    "after_shift_cancel",
    "before_shift_assignment_create",
    "after_shift_assignment_create",
  ],
  consents: [
    "before_consent_record",
    "after_consent_record",
    "before_consent_withdraw",
    "after_consent_withdraw",
  ],
  medications: [
    "before_medication_order_prescribe",
    "after_medication_order_prescribe",
    "before_medication_order_stop",
    "after_medication_order_stop",
    "before_medication_administration_record",
    "after_medication_administration_record",
  ],
  collections: [
    "before_collection_create",
    "after_collection_create",
    "before_collection_add",
    "after_collection_add",
  ],
  deals: [
    "before_deal_create",
    "after_deal_create",
    "before_deal_update",
    "after_deal_update",
  ],
  tasks: [
    "before_task_create",
    "after_task_create",
    "before_task_update",
    "after_task_update",
  ],
  quotes: [
    "before_quote_send",
    "after_quote_send",
    "before_quote_accept",
    "after_quote_accept",
  ],
  hiring: ["before_application_hire", "after_application_hire"],
  employees: [
    "before_employee_create",
    "after_employee_create",
    "before_employee_update",
    "after_employee_update",
    "before_employee_offboard",
    "after_employee_offboard",
  ],
  invoices: [
    "before_invoice_issue",
    "after_invoice_issue",
    "before_invoice_payment",
    "after_invoice_payment",
  ],
  risks: [
    "before_risk_create",
    "after_risk_create",
    "before_risk_assess",
    "after_risk_assess",
    "before_risk_close",
    "after_risk_close",
  ],
  cases: [
    "before_case_open",
    "after_case_open",
    "before_case_close",
    "after_case_close",
  ],
  inspections: [
    "before_inspection_schedule",
    "after_inspection_schedule",
    "before_inspection_close",
    "after_inspection_close",
    "before_inspection_finding_create",
    "after_inspection_finding_create",
  ],
  dam: ["before_dam_usage_right_create", "after_dam_usage_right_create"],
  lims: [
    "before_lims_sample_register",
    "after_lims_sample_register",
    "before_lims_result_record",
    "after_lims_result_record",
  ],
  maintenance: [
    "before_maintenance_plan_create",
    "after_maintenance_plan_create",
  ],
  appraisals: ["before_appraisal_cycle_create", "after_appraisal_cycle_create"],
  meetings: [
    "before_meeting_create",
    "after_meeting_create",
    "before_meeting_hold",
    "after_meeting_hold",
    "after_meeting_decision",
  ],
  "document-templates": [
    "before_document_template_save",
    "after_document_template_save",
    "before_document_text_block_save",
    "after_document_text_block_save",
  ],
  "legal-entities": [
    "before_legal_entity_create",
    "after_legal_entity_create",
    "before_legal_entity_update",
    "after_legal_entity_update",
  ],
  manufacturing: [
    "before_production_order_release",
    "after_production_order_release",
    "before_production_order_complete",
    "after_production_order_complete",
  ],
  funding: [
    "before_funding_award_save",
    "after_funding_award_save",
    "before_funding_delivery_register",
    "after_funding_delivery_register",
    "before_funding_claim_build",
    "after_funding_claim_build",
  ],
  observations: [
    "before_observation_definition_save",
    "after_observation_definition_save",
    "before_observation_record",
    "after_observation_record",
    "before_observation_amend",
    "after_observation_amend",
    "before_observation_mark_error",
    "after_observation_mark_error",
  ],
  "care-plans": [
    "before_care_plan_create",
    "after_care_plan_create",
    "before_care_plan_publish",
    "after_care_plan_publish",
    "before_care_plan_evaluation_create",
    "after_care_plan_evaluation_create",
  ],
};

/** Modules that call their hooks only for configured items. */
const OPTIONS: Readonly<Record<string, Record<string, unknown>>> = {
  metrics: {
    metrics: [
      { key: "orders", table: "orders", measure: "count", timeColumn: "at" },
    ],
  },
  pipelines: { on: { deal: { categories: { open: "open", won: "success" } } } },
};

/** The `config.subjects` entries the entries above name. */
const SUBJECTS = { deal: { table: "public.deals" } };

const NAMING = /^(before|after)_[a-z]+(_[a-z]+)*$/;

describe.each(Object.entries(REQUIRED))(
  "block SQL hooks of %s",
  (module, hooks) => {
    const declared = SQL_MODULES[module]?.names?.hooks ?? [];

    const sql = moduleBody(module, {
      modules:
        OPTIONS[module] === undefined
          ? {}
          : { [module]: entryOf(OPTIONS[module]) },
      subjects: SUBJECTS,
      accessProvider: moduleProvider,
    });

    it.each(hooks)("declares and calls %s", (hook) => {
      expect(declared).toContain(hook);
      expect(sql).toContain(`"public"."${hook}"(`);
    });

    it("names its before and after hooks by the convention", () => {
      const lifecycle = declared.filter((hook) =>
        /^(before|after)_/.test(hook),
      );

      expect(lifecycle.filter((hook) => !NAMING.test(hook))).toEqual([]);
    });
  },
);
