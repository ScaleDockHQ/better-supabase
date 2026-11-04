export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "13"
  }
  api: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      notification_preferences: {
        Row: {
          cadence: string
          channel: string
          created_at: string
          enabled: boolean
          id: string
          organization_id: string | null
          type: string
          updated_at: string
          user_id: string
        }
        ComputedFields: never
        Insert: {
          cadence?: string | null
          channel?: string | null
          created_at?: string | null
          enabled?: boolean | null
          id?: string | null
          organization_id?: string | null
          type?: string | null
          updated_at?: string | null
          user_id?: string | null
        }
        Update: {
          cadence?: string | null
          channel?: string | null
          created_at?: string | null
          enabled?: boolean | null
          id?: string | null
          organization_id?: string | null
          type?: string | null
          updated_at?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      notification_recipients: {
        Row: {
          created_at: string
          delivered_at: string
          dismissed_at: string | null
          event_id: string
          id: string
          organization_id: string | null
          read_at: string | null
          resolution: Json | null
          resolved_at: string | null
          user_id: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string | null
          delivered_at?: string | null
          dismissed_at?: string | null
          event_id?: string | null
          id?: string | null
          organization_id?: string | null
          read_at?: string | null
          resolution?: Json | null
          resolved_at?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          delivered_at?: string | null
          dismissed_at?: string | null
          event_id?: string | null
          id?: string | null
          organization_id?: string | null
          read_at?: string | null
          resolution?: Json | null
          resolved_at?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      accept_guest_invite: { Args: { token: string }; Returns: Json }
      accept_invitation: { Args: { token: string }; Returns: string }
      accept_invitation_by_id: {
        Args: { invitation_id: string }
        Returns: string
      }
      accepting_invitation: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
      accounting_balance_sheet: {
        Args: { as_of?: string; dimensions?: Json; tenant: string }
        Returns: Json
      }
      accounting_budget_vs_actual: {
        Args: { budget_id: string; period_number?: number }
        Returns: Json
      }
      accounting_column_balance: {
        Args: {
          dimensions?: Json
          rollup?: boolean
          since?: string
          tenant: string
          until?: string
        }
        Returns: Json
      }
      accounting_fx_rate: {
        Args: { base: string; on_date: string; quote: string; tenant: string }
        Returns: number
      }
      accounting_general_ledger: {
        Args: { account_id: string; since?: string; until?: string }
        Returns: Json
      }
      accounting_journal_listing: {
        Args: {
          journal_id?: string
          since?: string
          tenant: string
          until?: string
        }
        Returns: Json
      }
      accounting_period_close_blockers: {
        Args: { period_id: string }
        Returns: string[]
      }
      accounting_period_trial_balance: {
        Args: { dimensions?: Json; period_id: string }
        Returns: Json
      }
      accounting_profit_and_loss: {
        Args: {
          dimensions?: Json
          since?: string
          tenant: string
          until?: string
        }
        Returns: Json
      }
      accounting_tax_report: {
        Args: { since: string; tenant: string; until: string }
        Returns: Json
      }
      accounting_trial_balance: {
        Args: {
          dimensions?: Json
          since?: string
          tenant: string
          until?: string
        }
        Returns: Json
      }
      accrue_commission: {
        Args: {
          basis: number
          currency: string
          occurred_on?: string
          seller_id: string
          source_id: string
          source_type: string
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      acknowledge: {
        Args: {
          signature_id?: string
          subject_id: string
          subject_type: string
          version_id?: string
        }
        Returns: Json
      }
      acknowledgement_status: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      acknowledgements_of: {
        Args: { subject_id: string; subject_type: string; version_id?: string }
        Returns: Json
      }
      acquire_workflow_semaphore: {
        Args: { holder: string; key: string; max: number; ttl?: string }
        Returns: boolean
      }
      acting_member: { Args: Record<PropertyKey, never>; Returns: string }
      activate_bom: { Args: { bom_id: string }; Returns: Json }
      activate_lease: { Args: { lease_id: string }; Returns: Json }
      active_announcements: { Args: { tenant?: string }; Returns: Json }
      activities_of: {
        Args: {
          before: string
          page_size: number
          subject_id: string
          subject_type: string
          types: string[]
        }
        Returns: Json
      }
      activity_notes: { Args: { engagement: string }; Returns: Json }
      activity_recordings: { Args: { engagement: string }; Returns: Json }
      activity_transcript: {
        Args: { after: number; page_size: number; recording: string }
        Returns: Json
      }
      activity_with_transcripts: { Args: { engagement: string }; Returns: Json }
      actor_may_write: { Args: Record<PropertyKey, never>; Returns: boolean }
      add_ai_chat_participant: {
        Args: {
          chat: string
          fields?: Json
          participant: string
          participant_role?: string
        }
        Returns: Json
      }
      add_ai_chat_party: {
        Args: {
          chat: string
          participant_role?: string
          party: string
          party_kind: string
        }
        Returns: Json
      }
      add_booking_exception: {
        Args: {
          available: boolean
          ends_at: string
          reason: string
          resource: string
          starts_at: string
        }
        Returns: Json
      }
      add_care_plan_action: {
        Args: { goal_id: string; input: Json }
        Returns: Json
      }
      add_care_plan_goal: {
        Args: { input: Json; problem_id: string }
        Returns: Json
      }
      add_care_plan_problem: {
        Args: { input: Json; plan_id: string }
        Returns: Json
      }
      add_control_evidence: {
        Args: {
          attachment_id?: string
          control_id: string
          note?: string
          task_id?: string
          valid_until?: string
        }
        Returns: Json
      }
      add_conversation_members: {
        Args: { conversation: string; users: string[] }
        Returns: number
      }
      add_employee_contract: {
        Args: { attrs: Json; employee: string }
        Returns: Json
      }
      add_expense_line: {
        Args: {
          amount: number
          category_id: string
          currency?: string
          description: string
          dimensions?: Json
          merchant?: string
          report_id: string
          spent_on: string
        }
        Returns: Json
      }
      add_incident_postmortem_action: {
        Args: {
          assignee_id?: string
          due_at?: string
          postmortem_id: string
          title: string
        }
        Returns: Json
      }
      add_inspection_finding: {
        Args: {
          clause?: string
          control_id?: string
          description?: string
          evidence?: string
          inspection_id: string
          title: string
          type: string
        }
        Returns: Json
      }
      add_invoice_charge: {
        Args: {
          actor?: Json
          amount: number
          currency: string
          description: string
          invoice: string
        }
        Returns: Json
      }
      add_meeting_action_item: {
        Args: {
          agenda_item_id?: string
          assignees?: string[]
          decision_id?: string
          meeting_id: string
          task: Json
        }
        Returns: Json
      }
      add_organization_domain: {
        Args: { domain: string; tenant: string }
        Returns: Json
      }
      add_person_identity: {
        Args: {
          address: string
          channel: string
          person: string
          verified?: boolean
        }
        Returns: Json
      }
      add_product_media: {
        Args: {
          alt: Json
          attachment: string
          product: string
          variant: string
        }
        Returns: Json
      }
      add_qualification_requirement: {
        Args: { target_type: string; target_value: string; type_id: string }
        Returns: Json
      }
      add_signing_key: {
        Args: {
          alg: string
          kid: string
          owner_id: string
          owner_type: string
          private_jwk: string
          public_jwk: Json
        }
        Returns: Json
      }
      add_subject_member: {
        Args: {
          ends_on?: string
          role?: string
          starts_on?: string
          subject_id: string
          subject_type: string
          team_id?: string
          user_id?: string
        }
        Returns: Json
      }
      add_team_member: {
        Args: { member: string; team: string }
        Returns: boolean
      }
      add_to_cart: {
        Args: { cart: string; quantity: number; variant: string }
        Returns: Json
      }
      add_to_collection: {
        Args: { collection: string; product: string; rank: string }
        Returns: string
      }
      adjust_stock: {
        Args: {
          detail?: Json
          location: string
          note: string
          quantity: number
          reason: string
          variant: string
        }
        Returns: Json
      }
      advance_workflow_schedule: {
        Args: { fired: string; next_run: string; schedule: string }
        Returns: boolean
      }
      ai_cache_delete: {
        Args: { key?: string; model?: string; tenant?: string }
        Returns: number
      }
      ai_cache_get: { Args: { key: string }; Returns: Json }
      ai_cache_set: {
        Args: {
          key: string
          kind?: string
          model?: string
          tenant?: string
          ttl: number
          value: Json
        }
        Returns: Json
      }
      ai_chat_can_read: { Args: { chat: string }; Returns: boolean }
      ai_chat_share_summaries: { Args: { chats: string[] }; Returns: Json }
      ai_message_path: {
        Args: { chat: string; include_native?: boolean; leaf?: string }
        Returns: Json
      }
      ai_message_siblings: {
        Args: { chat: string; message_id: string }
        Returns: Json
      }
      ai_provider_keys_for: {
        Args: { providers?: string[]; tenant: string }
        Returns: Json
      }
      ai_sandbox_for: {
        Args: { chat_id: string; provider: string }
        Returns: Json
      }
      ai_tool_policies_for: { Args: { tenant: string }; Returns: Json }
      allocate_payment: {
        Args: { actor?: Json; allocations: Json; payment: Json; tenant: string }
        Returns: Json
      }
      allocate_stock: {
        Args: {
          backorder?: boolean
          document_id: string
          document_type: string
          line_id: string
          location: string
          quantity: number
          tenant: string
          variant: string
        }
        Returns: Json
      }
      allocate_username: {
        Args: { base: string; user_id?: string }
        Returns: string
      }
      allowed_ai_models: { Args: { tenant?: string }; Returns: Json }
      amend_activity: {
        Args: { body: string; engagement: string }
        Returns: Json
      }
      amend_observation: {
        Args: { changes: Json; observation_id: string; reason: string }
        Returns: Json
      }
      ancestors: {
        Args: {
          kind: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      anonymize_due: { Args: { max_rows?: number }; Returns: Json }
      answer_ai_pending_input: {
        Args: { answer: Json; id: string }
        Returns: Json
      }
      api_key_tenant: { Args: Record<PropertyKey, never>; Returns: string }
      append_ai_user_message: {
        Args: {
          chat: string
          message: Json
          message_id?: string
          trigger?: string
        }
        Returns: Json
      }
      application_detail: { Args: { application: string }; Returns: Json }
      apply_bank_rules: { Args: { account_id: string }; Returns: Json }
      apply_oscal_profile: {
        Args: { document: Json; framework_id: string }
        Returns: Json
      }
      apply_party_credit: {
        Args: {
          actor?: Json
          amount: number
          invoice: string
          party_id: string
        }
        Returns: Json
      }
      apply_promotion_code: {
        Args: { cart: string; code: string }
        Returns: Json
      }
      apply_to_job: {
        Args: { candidate: Json; job: string; owner: string; source: string }
        Returns: Json
      }
      appraisal_review_hidden: { Args: { review_id: string }; Returns: boolean }
      approval_eligible: { Args: { request_id: string }; Returns: boolean }
      approval_eligible_ids: { Args: { tenant?: string }; Returns: string[] }
      approval_policy: {
        Args: { action: string; subject_type: string }
        Returns: Json
      }
      approval_requirement: {
        Args: {
          action: string
          subject?: Json
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      approve_funding_deliveries: {
        Args: { approved?: boolean; ids: string[] }
        Returns: number
      }
      approve_inspection_program: {
        Args: { program_id: string }
        Returns: Json
      }
      approve_medication_order: {
        Args: { order_id: string; signature_id: string }
        Returns: Json
      }
      approve_purchase_invoice: {
        Args: { comment?: string; invoice: string }
        Returns: Json
      }
      archive_accounting_account: {
        Args: { account_id: string; archived?: boolean }
        Returns: Json
      }
      archive_asset_location: { Args: { location_id: string }; Returns: Json }
      archive_care_plan: { Args: { plan_id: string }; Returns: Json }
      archive_case_kind: { Args: { kind_id: string }; Returns: Json }
      archive_channel: {
        Args: { archived?: boolean; channel: string }
        Returns: boolean
      }
      archive_company: {
        Args: { archived: boolean; id: string }
        Returns: boolean
      }
      archive_compliance_policy: { Args: { policy_id: string }; Returns: Json }
      archive_consent_purpose: { Args: { purpose_id: string }; Returns: Json }
      archive_content_entry: { Args: { entry_id: string }; Returns: Json }
      archive_conversation: {
        Args: { archived?: boolean; conversation: string }
        Returns: boolean
      }
      archive_deal: {
        Args: { archived: boolean; deal: string }
        Returns: boolean
      }
      archive_donation_fund: { Args: { fund_id: string }; Returns: Json }
      archive_expense_category: { Args: { category_id: string }; Returns: Json }
      archive_lims_method: { Args: { method_id: string }; Returns: Json }
      archive_maintenance_request: {
        Args: { archived: boolean; work_item: string }
        Returns: boolean
      }
      archive_medication: { Args: { medication_id: string }; Returns: Json }
      archive_observation_definition: {
        Args: { definition_id: string }
        Returns: Json
      }
      archive_person: {
        Args: { archived: boolean; id: string }
        Returns: boolean
      }
      archive_pipeline: { Args: { pipeline: string }; Returns: boolean }
      archive_pipeline_stage: { Args: { stage: string }; Returns: boolean }
      archive_qualification_type: { Args: { type_id: string }; Returns: Json }
      archive_shift_template: { Args: { template_id: string }; Returns: Json }
      archive_team: { Args: { team: string }; Returns: boolean }
      archive_work_item: {
        Args: { archived: boolean; work_item: string }
        Returns: boolean
      }
      as_column_type: {
        Args: { target: unknown; value: string }
        Returns: unknown
      }
      assess_risk: {
        Args: {
          inherent_impact: number
          inherent_likelihood: number
          rationale?: string
          residual_impact: number
          residual_likelihood: number
          risk_id: string
        }
        Returns: Json
      }
      asset_assignment_history: {
        Args: { asset_id: string; page_size?: number }
        Returns: Json
      }
      asset_locations_at: {
        Args: { latitude: number; longitude: number; tenant: string }
        Returns: Json
      }
      assets_near: {
        Args: {
          kind?: string
          latitude: number
          longitude: number
          page_size?: number
          radius_meters: number
          tenant: string
        }
        Returns: Json
      }
      assign_acknowledgement: {
        Args: {
          due_in_days?: number
          principal_id: string
          principal_type: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      assign_asset: {
        Args: {
          asset_id: string
          assignee_id: string
          assignee_type: string
          note?: string
        }
        Returns: Json
      }
      assign_comment: {
        Args: { assignee?: string; attrs?: Json; message: string }
        Returns: string
      }
      assign_commission_plan: {
        Args: {
          ends_on?: string
          plan_id: string
          seller_id: string
          starts_on?: string
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      assign_conversation: {
        Args: { assignee: string; conversation: string; team?: string }
        Returns: Json
      }
      assign_shift: {
        Args: { shift_id: string; user_id: string }
        Returns: Json
      }
      assign_subject: {
        Args: {
          subject?: Json
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      assignment_history: {
        Args: {
          max_count?: number
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      attach_activity_recording: {
        Args: { engagement: string; file: string; language: string }
        Returns: Json
      }
      attach_ai_run: {
        Args: { external_run_id: string; run: string }
        Returns: boolean
      }
      attach_template_workflow: {
        Args: {
          definition: string
          enabled: boolean
          inputs: Json
          template_id: string
        }
        Returns: Json
      }
      attachment_fields_error: {
        Args: { data: Json; fields: Json }
        Returns: string
      }
      attachment_schema_error: { Args: { fields: Json }; Returns: string }
      attribute_referral: {
        Args: {
          code: string
          referred_email?: string
          referred_org?: string
          referred_user?: string
          tenant: string
        }
        Returns: Json
      }
      audit_entries_correlated: { Args: { correlation: string }; Returns: Json }
      audit_event: {
        Args: {
          actor_id?: string
          actor_kind?: string
          actor_label?: string
          category?: string
          correlation_id?: string
          event_type: string
          idempotency_key?: string
          impersonated_by?: string
          impersonation_reason?: string
          ip?: unknown
          metadata?: Json
          outcome?: string
          record_id?: string
          request_id?: string
          restricted?: Json
          scope?: string
          session_id?: string
          source?: string
          summary?: string
          support_session?: string
          target_label?: string
          target_type?: string
          tenant?: string
          user_agent?: string
        }
        Returns: string
      }
      audit_event_many: { Args: { events: Json }; Returns: Json }
      audit_event_trusted: {
        Args: {
          actor_id?: string
          actor_kind?: string
          actor_label?: string
          category?: string
          correlation_id?: string
          event_type: string
          idempotency_key?: string
          impersonated_by?: string
          impersonation_reason?: string
          ip?: unknown
          metadata?: Json
          outcome?: string
          record_id?: string
          request_id?: string
          restricted?: Json
          scope?: string
          session_id?: string
          source?: string
          summary?: string
          support_session?: string
          target_label?: string
          target_type?: string
          tenant?: string
          user_agent?: string
        }
        Returns: string
      }
      audit_events_tenants: { Args: { older_than?: string }; Returns: string[] }
      audit_read_tenants: {
        Args: Record<PropertyKey, never>
        Returns: string[]
      }
      audit_reads_all: { Args: Record<PropertyKey, never>; Returns: boolean }
      audit_revert_source: { Args: { entries: string[] }; Returns: Json }
      authz_version: { Args: { p_user: string }; Returns: number }
      available_slots: {
        Args: {
          range_end: string
          range_start: string
          resource?: string
          service: string
          tz?: string
        }
        Returns: Json
      }
      award_rfq: {
        Args: { location?: string; quote_id: string; rfq_id: string }
        Returns: Json
      }
      backfill_profiles: { Args: Record<PropertyKey, never>; Returns: number }
      ban_user: {
        Args: {
          expires_at?: string
          reason?: string
          tenant: string
          user_id: string
        }
        Returns: Json
      }
      bank_reconciliation_board: {
        Args: { account_id: string; line_limit?: number }
        Returns: Json
      }
      bank_reconciliation_status: {
        Args: { account_id: string; as_of?: string }
        Returns: Json
      }
      begin_import_session: { Args: { run: string }; Returns: string }
      bill_usage_period: {
        Args: {
          attrs?: Json
          currency?: string
          period_end: string
          period_start: string
          tenant: string
        }
        Returns: Json
      }
      bom_where_used: { Args: { variant_id: string }; Returns: Json }
      book_series: {
        Args: {
          customer: Json
          resource: string
          rule: Json
          service: string
          skip_conflicts?: boolean
          starts_at: string
        }
        Returns: Json
      }
      book_with_credit: {
        Args: {
          customer?: Json
          pass_id: string
          resource: string
          service: string
          starts_at: string
        }
        Returns: Json
      }
      booking_series_starts: {
        Args: { first_start: string; rule: Json; tz: string }
        Returns: string[]
      }
      booking_slots: {
        Args: {
          only_resource: string
          range_end: string
          range_start: string
          service: string
          tz: string
        }
        Returns: {
          ends_at: string
          local_start: string
          resource_id: string
          seats: number
          starts_at: string
        }[]
      }
      bootstrap_islands: { Args: { args?: Json }; Returns: Json }
      bsb_valid_bsn: { Args: { value: string }; Returns: boolean }
      bsb_valid_iban: { Args: { value: string }; Returns: boolean }
      build_commission_statement: {
        Args: {
          currency: string
          ends_on: string
          seller_id: string
          starts_on: string
          tenant: string
        }
        Returns: Json
      }
      build_funding_claim: {
        Args: {
          format: string
          funder_id: string
          period_end: string
          period_start: string
          tenant: string
        }
        Returns: Json
      }
      bulk_apply: {
        Args: {
          action: string
          args: Json
          atomic: boolean
          ids: string[]
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      bulk_row: {
        Args: {
          action: string
          args: Json
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: undefined
      }
      bulk_run: { Args: { run_id: string }; Returns: Json }
      bulk_step: { Args: { run_id: string; size: number }; Returns: Json }
      bump_authz_versions: { Args: { p_users: string[] }; Returns: undefined }
      bump_kitchen_ticket: {
        Args: { order_id: string; state: string; station: string }
        Returns: number
      }
      calendar_busy_blocks: {
        Args: {
          range_end: string
          range_start: string
          tenant: string
          user_ids: string[]
        }
        Returns: {
          declines: boolean
          ends_at: string
          event_id: string
          kind: string
          starts_at: string
          user_id: string
        }[]
      }
      calendar_feed: { Args: { token: string }; Returns: Json }
      calendar_free_busy: {
        Args: {
          range_end: string
          range_start: string
          tenant: string
          user_ids: string[]
        }
        Returns: Json
      }
      calendar_rule_starts: {
        Args: {
          dtstart: string
          range_end: string
          range_start: string
          rrule: string
          tz: string
        }
        Returns: string[]
      }
      calibrate_appraisal: {
        Args: { appraisal_id: string; rating: number; reason: string }
        Returns: Json
      }
      calibrate_appraisal_competencies: {
        Args: { appraisal_id: string; competencies: Json; reason: string }
        Returns: Json
      }
      caller_authz_version: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      can: {
        Args: { permission: string; scope: string; scope_id: string }
        Returns: boolean
      }
      can_assign: { Args: { role: string; tenant: string }; Returns: boolean }
      can_assign_as: {
        Args: { member: string; role: string; tenant: string }
        Returns: boolean
      }
      can_conversation: {
        Args: { action: string; conversation: string }
        Returns: boolean
      }
      can_subject: {
        Args: { action: string; subject_id: string; subject_type: string }
        Returns: boolean
      }
      can_subject_for: {
        Args: {
          action: string
          member: string
          subject_id: string
          subject_type: string
        }
        Returns: boolean
      }
      can_user: {
        Args: {
          member: string
          permission: string
          scope: string
          scope_id: string
        }
        Returns: boolean
      }
      cancel_approval: { Args: { request_id: string }; Returns: Json }
      cancel_booking: {
        Args: { booking: string; reason?: string }
        Returns: Json
      }
      cancel_booking_series: {
        Args: { booking: string; reason?: string; scope?: string }
        Returns: number
      }
      cancel_calendar_occurrence: {
        Args: { event_id: string; original_start: string }
        Returns: boolean
      }
      cancel_case: { Args: { case_id: string; reason?: string }; Returns: Json }
      cancel_enrollment: { Args: { enrollment_id: string }; Returns: Json }
      cancel_expense_report: { Args: { report_id: string }; Returns: Json }
      cancel_fulfillment: { Args: { fulfillment: string }; Returns: boolean }
      cancel_import_run: { Args: { id: string }; Returns: boolean }
      cancel_inbox_message: { Args: { scheduled: string }; Returns: boolean }
      cancel_inspection: {
        Args: { inspection_id: string; reason?: string }
        Returns: Json
      }
      cancel_meeting: {
        Args: { meeting_id: string; reason?: string }
        Returns: Json
      }
      cancel_order: {
        Args: { order_id: string; reason?: string }
        Returns: boolean
      }
      cancel_organization_deletion: { Args: { tenant: string }; Returns: Json }
      cancel_payment_batch: { Args: { batch_id: string }; Returns: Json }
      cancel_pick_wave: { Args: { wave_id: string }; Returns: Json }
      cancel_prescription: {
        Args: { prescription_id: string; reason?: string }
        Returns: Json
      }
      cancel_production_order: {
        Args: { order_id: string; reason?: string }
        Returns: Json
      }
      cancel_purchase_order: {
        Args: { purchase_order: string }
        Returns: boolean
      }
      cancel_rfq: { Args: { reason: string; rfq_id: string }; Returns: Json }
      cancel_shift: {
        Args: { reason?: string; shift_id: string }
        Returns: Json
      }
      cancel_shipment: { Args: { shipment_id: string }; Returns: Json }
      cancel_signature_request: { Args: { request_id: string }; Returns: Json }
      cancel_stock_count: { Args: { count: string }; Returns: boolean }
      cancel_transfer: { Args: { transfer: string }; Returns: boolean }
      cap_allows: { Args: { permission: string }; Returns: boolean }
      care_decision_context: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: Json
      }
      care_plan_action_end: {
        Args: { action_id: string; reason: string }
        Returns: undefined
      }
      care_plan_action_request_approval: {
        Args: { action_id: string }
        Returns: string
      }
      care_plan_action_start: {
        Args: { action_id: string }
        Returns: undefined
      }
      care_plan_json: { Args: { plan_id: string }; Returns: Json }
      case_blockers_of: { Args: { target: unknown }; Returns: string[] }
      case_close_approved: { Args: { case_id: string }; Returns: undefined }
      case_close_blockers: { Args: { case_id: string }; Returns: string[] }
      case_from_submission: { Args: { submission_id: string }; Returns: Json }
      case_stats: {
        Args: {
          group_by?: string
          kind?: string
          since?: string
          tenant: string
          until?: string
        }
        Returns: Json
      }
      change_booking: {
        Args: {
          access_token: string
          booking: string
          reason: string
          to_status: string
        }
        Returns: Json
      }
      change_sequence_enrollment: {
        Args: { action: string; enrollment_id: string }
        Returns: Json
      }
      channel_price: {
        Args: { as_of?: string; channel: string; variant: string }
        Returns: Json
      }
      channel_products: {
        Args: {
          after?: string
          channel: string
          locale?: string
          page_size?: number
        }
        Returns: Json
      }
      channels_for_record: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      check_connector_fingerprint: {
        Args: { fingerprint: string; server_id: string; tools?: Json }
        Returns: string
      }
      check_expense_report: { Args: { report_id: string }; Returns: Json }
      check_in_pass: {
        Args: {
          gate?: string
          method?: string
          nonce?: string
          pass_id: string
          resource_id?: string
        }
        Returns: Json
      }
      check_sla_clocks: { Args: Record<PropertyKey, never>; Returns: number }
      check_sso_provider: {
        Args: { actor?: string; domains: string[]; tenant: string }
        Returns: undefined
      }
      check_usage: {
        Args: { filters?: Json; node_id: string; tenant: string }
        Returns: Json
      }
      check_workflow_alerts: { Args: { batch?: number }; Returns: number }
      claim_ai_chat_stream: {
        Args: {
          chat: string
          engine?: string
          external_run_id?: string
          message_id?: string
          model?: string
          stream: string
        }
        Returns: Json
      }
      claim_attachment_upload: { Args: { id: string }; Returns: Json }
      claim_data_export: { Args: { id: string }; Returns: Json }
      claim_due_ai_tasks: { Args: { batch?: number }; Returns: Json }
      claim_due_workflow_schedules: {
        Args: { batch?: number; lease?: number }
        Returns: Json
      }
      claim_notification_deliveries: {
        Args: {
          channel: string
          lease?: string
          max_attempts?: number
          max_items?: number
        }
        Returns: Json
      }
      claim_notification_digests: {
        Args: { lease?: string; max_attempts?: number; max_items?: number }
        Returns: Json
      }
      claim_template_occurrence: {
        Args: { occurrence_at: string; schedule_id: string }
        Returns: Json
      }
      claim_time_for_invoice: {
        Args: { entry_ids: Json; invoice: string; tenant: string }
        Returns: Json
      }
      claim_webhook_deliveries: {
        Args: { lease?: string; max_attempts?: number; max_items?: number }
        Returns: Json
      }
      claim_workflow_run_dispatch: {
        Args: { lease?: number; run: string }
        Returns: Json
      }
      claim_workflow_start_requests: {
        Args: { batch?: number; lease?: number }
        Returns: Json
      }
      close_accounting_period: { Args: { period_id: string }; Returns: Json }
      close_application: {
        Args: { application: string; outcome: string; reason: string }
        Returns: Json
      }
      close_appraisal_cycle: { Args: { cycle_id: string }; Returns: Json }
      close_case: { Args: { case_id: string; note?: string }; Returns: Json }
      close_deal: {
        Args: { deal: string; outcome: string; reason: string }
        Returns: Json
      }
      close_fiscal_year: {
        Args: { fiscal_year: number; tenant: string }
        Returns: Json
      }
      close_inspection: { Args: { inspection_id: string }; Returns: Json }
      close_inspection_program: { Args: { program_id: string }; Returns: Json }
      close_period: { Args: { period_id: string }; Returns: Json }
      close_rfq: { Args: { rfq_id: string }; Returns: Json }
      close_risk: { Args: { reason: string; risk_id: string }; Returns: Json }
      close_till_session: {
        Args: { input: Json; session_id: string }
        Returns: Json
      }
      comment_conversation: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: string
      }
      comment_counts: {
        Args: { subject_ids: string[]; subject_type: string; tenant: string }
        Returns: Json
      }
      commission_accrue: {
        Args: {
          basis: number
          currency: string
          occurred_on?: string
          seller_id: string
          source_id: string
          source_type: string
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      commission_amount: {
        Args: {
          basis: number
          kind: string
          prior: number
          rate_bps: number
          tiers: Json
        }
        Returns: number
      }
      commission_close_range: {
        Args: { ends_on: string; starts_on: string; tenant: string }
        Returns: undefined
      }
      commission_payroll_lines: {
        Args: { from_date: string; tenant: string; to_date: string }
        Returns: Json
      }
      commission_plan_for: {
        Args: {
          on_date: string
          seller_id: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: string
      }
      commission_statement_build: {
        Args: {
          currency: string
          ends_on: string
          seller_id: string
          starts_on: string
          tenant: string
        }
        Returns: string
      }
      commission_statement_finalize: {
        Args: { statement_id: string }
        Returns: Json
      }
      commission_tiers_valid: { Args: { tiers: Json }; Returns: boolean }
      commit_reservation: { Args: { reservation: string }; Returns: Json }
      compact_document: {
        Args: { document_id: string; state: string; through_seq: number }
        Returns: boolean
      }
      company_people_of: { Args: { company: string }; Returns: Json }
      compare_rfq: { Args: { rfq_id: string }; Returns: Json }
      complete_activity: {
        Args: { done: boolean; engagement: string; outcome: string }
        Returns: Json
      }
      complete_course_lesson: {
        Args: { done?: boolean; lesson_id: string }
        Returns: Json
      }
      complete_data_export: {
        Args: { files: string[]; id: string }
        Returns: Json
      }
      complete_enrollment_step: {
        Args: { enrollment_id: string; step: string }
        Returns: Json
      }
      complete_inspection: {
        Args: { inspection_id: string; summary?: string }
        Returns: Json
      }
      complete_notification_delivery: {
        Args: {
          delivery: string
          error?: string
          max_attempts?: number
          provider?: string
          provider_message_id?: string
          status: string
          template_key?: string
        }
        Returns: string
      }
      complete_notification_digest: {
        Args: {
          digest: string
          error?: string
          max_attempts?: number
          provider_message_id?: string
          status: string
        }
        Returns: string
      }
      complete_onboarding_step: {
        Args: { checklist: string; step: string; tenant?: string }
        Returns: boolean
      }
      complete_pick_list: { Args: { pick_list_id: string }; Returns: Json }
      complete_production_order: {
        Args: { lot?: Json; order_id: string; produced: number; scrap?: number }
        Returns: Json
      }
      complete_push_receipts: { Args: { receipts: Json }; Returns: Json }
      complete_refund: {
        Args: { provider_reference?: string; refund: string; status: string }
        Returns: Json
      }
      complete_sample: { Args: { sample_id: string }; Returns: Json }
      complete_webhook_delivery: {
        Args: { delivery: string; outcome: Json }
        Returns: string
      }
      compute_score: {
        Args: {
          model_key: string
          subject: Json
          subject_id: string
          subject_type: string
          tenant: string
          time_zone?: string
        }
        Returns: Json
      }
      confirm_ai_file: {
        Args: { file_id: string; sha256?: string }
        Returns: Json
      }
      confirm_attachment: { Args: { id: string }; Returns: Json }
      confirm_booking: { Args: { booking: string }; Returns: Json }
      connect_mail_account: {
        Args: {
          address: string
          credential_ref: Json
          provider: string
          share: string
          tenant: string
        }
        Returns: Json
      }
      consent_active: {
        Args: { purpose_key: string; subject_id: string; subject_type: string }
        Returns: boolean
      }
      consume_approval: {
        Args: { fingerprint?: string; request_id: string }
        Returns: Json
      }
      consume_quota: {
        Args: {
          actor?: string
          idempotency_key?: string
          metadata?: Json
          meter: string
          quantity?: number
          source?: string
          tenant: string
        }
        Returns: Json
      }
      control_posture: {
        Args: { framework_id?: string; tenant: string }
        Returns: Json
      }
      conversation_read_at: {
        Args: { conversation: string; member?: string }
        Returns: string
      }
      converted_into: {
        Args: {
          into_type: string
          origin_id: string
          origin_type: string
          tenant: string
        }
        Returns: string
      }
      copy_comments: {
        Args: {
          from_id: string
          from_type: string
          tenant: string
          to_id: string
          to_type: string
        }
        Returns: number
      }
      count_audit_events: {
        Args: {
          for_actor_kinds?: string[]
          for_actors?: string[]
          for_categories?: string[]
          for_correlation_ids?: string[]
          for_event_types?: string[]
          for_outcomes?: string[]
          for_records?: string[]
          for_sources?: string[]
          for_target_types?: string[]
          for_tenants?: string[]
          search?: string
          since?: string
          until?: string
        }
        Returns: number
      }
      count_stock: {
        Args: {
          counted: number
          detail?: Json
          location: string
          note: string
          variant: string
        }
        Returns: Json
      }
      course_lesson: { Args: { lesson_id: string }; Returns: Json }
      course_outline: { Args: { course_id: string }; Returns: Json }
      course_progress: {
        Args: { course_id: string; user_id?: string }
        Returns: Json
      }
      create_ai_chat: { Args: { fields?: Json; tenant: string }; Returns: Json }
      create_ai_chat_link: { Args: { chat: string }; Returns: Json }
      create_ai_document: {
        Args: {
          chat_id?: string
          content?: string
          kind: string
          message_id?: string
          owner?: string
          storage_path?: string
          tenant: string
          title: string
        }
        Returns: Json
      }
      create_api_key: {
        Args: {
          expires_at?: string
          kind?: string
          name: string
          personal?: boolean
          prefix?: string
          public_id: string
          rate_limit?: number
          scopes?: string[]
          secret_hash: string
          tenant?: string
        }
        Returns: Json
      }
      create_appraisal_cycle: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      create_asset: {
        Args: {
          kind: string
          latitude?: number
          location_id?: string
          longitude?: number
          metadata?: Json
          name: string
          serial_number?: string
          tag?: string
          tenant: string
        }
        Returns: Json
      }
      create_asset_location: {
        Args: {
          address?: Json
          area?: Json
          code?: string
          kind: string
          latitude?: number
          longitude?: number
          metadata?: Json
          name: string
          parent_id?: string
          tenant: string
        }
        Returns: Json
      }
      create_attachment: {
        Args: {
          document_type?: string
          external_id?: string
          height?: number
          metadata?: Json
          mime_type: string
          name: string
          pages?: number
          size: number
          source?: string
          source_path?: string
          subject_id?: string
          subject_type?: string
          tenant: string
          width?: number
        }
        Returns: Json
      }
      create_calendar: {
        Args: {
          name: string
          owner_id: string
          owner_type: string
          tenant: string
          tz: string
        }
        Returns: Json
      }
      create_care_plan: { Args: { input: Json; tenant: string }; Returns: Json }
      create_cart: {
        Args: {
          currency: string
          email?: string
          price_list?: string
          tenant: string
        }
        Returns: Json
      }
      create_case_action: {
        Args: {
          assignee_id?: string
          case_id: string
          due_at?: string
          required?: boolean
          title: string
          type: string
        }
        Returns: Json
      }
      create_channel: {
        Args: { attrs?: Json; members?: string[]; name: string; tenant: string }
        Returns: Json
      }
      create_comment: {
        Args: {
          attachments?: string[]
          attrs?: Json
          body: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      create_content_entry: {
        Args: { attrs: Json; tenant: string }
        Returns: Json
      }
      create_contract: { Args: { attrs: Json; tenant: string }; Returns: Json }
      create_count_plan: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      create_deal: {
        Args: { attrs: Json; contacts: Json; tenant: string }
        Returns: Json
      }
      create_employee: { Args: { attrs: Json; tenant: string }; Returns: Json }
      create_expense_report: {
        Args: { currency: string; note?: string; tenant: string; title: string }
        Returns: Json
      }
      create_form: {
        Args: {
          description?: string
          fields?: Json
          key: string
          tenant: string
          title: string
        }
        Returns: Json
      }
      create_from_requirements: {
        Args: { items: Json; tenant: string }
        Returns: Json
      }
      create_fulfillment: {
        Args: {
          carrier?: string
          lines?: Json
          location?: string
          order_id: string
          tracking_number?: string
          tracking_url?: string
        }
        Returns: Json
      }
      create_inbox: {
        Args: {
          address?: string
          bot_mode?: string
          channel?: string
          name: string
          settings?: Json
          tenant: string
        }
        Returns: Json
      }
      create_inbox_attachment: {
        Args: {
          conversation: string
          mime_type: string
          name: string
          size: number
        }
        Returns: Json
      }
      create_inbox_team: {
        Args: { name: string; tenant: string }
        Returns: Json
      }
      create_invitation: {
        Args: {
          invitee_email: string
          invitee_role?: string
          organization: string
          valid_for?: string
        }
        Returns: string
      }
      create_invite_code: {
        Args: {
          code: string
          expires_at?: string
          max_uses?: number
          role?: string
          tenant?: string
        }
        Returns: Json
      }
      create_invoice: {
        Args: { attrs: Json; lines: Json; tenant: string }
        Returns: Json
      }
      create_knowledge_collection: {
        Args: {
          description?: string
          name: string
          priority?: number
          tenant: string
          visibility?: string
        }
        Returns: Json
      }
      create_knowledge_document: {
        Args: {
          collection_id?: string
          file_id?: string
          metadata?: Json
          owner?: string
          scope?: string
          scope_id?: string
          source?: string
          subject_id?: string
          subject_type?: string
          tenant: string
          title: string
        }
        Returns: Json
      }
      create_lease: {
        Args: {
          currency: string
          deposit?: number
          ends_on?: string
          frequency?: string
          metadata?: Json
          party_id: string
          party_type: string
          rent: number
          starts_on: string
          tenant: string
          title?: string
          unit_id: string
        }
        Returns: Json
      }
      create_legal_entity: {
        Args: {
          address?: Json
          bic?: string
          coc_number?: string
          code: string
          default_currency?: string
          fiscal?: Json
          iban?: string
          is_default?: boolean
          logo_attachment_id?: string
          name: string
          tenant: string
          vat_number?: string
        }
        Returns: Json
      }
      create_maintenance_meter: {
        Args: { asset_id?: string; name: string; tenant: string; unit: string }
        Returns: Json
      }
      create_maintenance_plan: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      create_maintenance_request: {
        Args: { assignees: string[]; attrs: Json; tenant: string }
        Returns: Json
      }
      create_meeting: { Args: { input: Json; tenant: string }; Returns: Json }
      create_organization: { Args: { attrs: Json }; Returns: string }
      create_payment_batch: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      create_payroll_run: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      create_period: {
        Args: {
          ends_on: string
          kind: string
          starts_on: string
          tenant: string
        }
        Returns: Json
      }
      create_pick_list: { Args: { input: Json; tenant: string }; Returns: Json }
      create_pick_wave: { Args: { input: Json; tenant: string }; Returns: Json }
      create_pledge: {
        Args: {
          amount: number
          currency: string
          donor_id: string
          donor_type: string
          ends_on?: string
          frequency?: string
          fund_id?: string
          note?: string
          provider?: string
          provider_customer?: string
          starts_on?: string
          tenant: string
        }
        Returns: Json
      }
      create_post: { Args: { board_id: string; post: Json }; Returns: Json }
      create_prescription: {
        Args: { attrs?: Json; order_id: string; tenant: string }
        Returns: Json
      }
      create_production_order: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      create_promotion_codes: {
        Args: {
          codes?: string[]
          count?: number
          prefix?: string
          promotion: string
          usage_limit?: number
        }
        Returns: Json
      }
      create_quote: {
        Args: { attrs: Json; lines: Json; tenant: string }
        Returns: Json
      }
      create_quote_variant: {
        Args: { attrs?: Json; label: string; quote: string }
        Returns: Json
      }
      create_referral_code: {
        Args: {
          code?: string
          expires_at?: string
          invitation_id?: string
          max_uses?: number
          referrer_id?: string
          reward_amount?: number
          reward_unit?: string
          tenant: string
        }
        Returns: Json
      }
      create_refund: {
        Args: {
          amount?: number
          order_id: string
          reason?: string
          return_id?: string
        }
        Returns: Json
      }
      create_rfq: {
        Args: { input: Json; lines?: Json; tenant: string }
        Returns: Json
      }
      create_risk: { Args: { input: Json; tenant: string }; Returns: Json }
      create_share_link: {
        Args: {
          download_allowed?: boolean
          expires_at?: string
          max_uses?: number
          password?: string
          role: string
          subject_id: string
          subject_type: string
          tenant: string
          version_id?: string
        }
        Returns: Json
      }
      create_shipment: {
        Args: {
          from_address: Json
          from_location_id?: string
          packages: Json
          reference?: string
          subject_id?: string
          subject_type?: string
          tenant: string
          to_address: Json
        }
        Returns: Json
      }
      create_signature_request: {
        Args: {
          approval_request_id?: string
          meaning?: string
          message?: string
          sign_order?: string
          signers: string[]
          subject_id: string
          subject_type: string
          tenant: string
          version_id?: string
        }
        Returns: Json
      }
      create_tag: {
        Args: {
          color: string
          description: string
          kind: string
          name: string
          tenant: string
        }
        Returns: Json
      }
      create_team: {
        Args: {
          description: string
          name: string
          slug?: string
          tenant: string
        }
        Returns: Json
      }
      create_till: { Args: { input: Json; tenant: string }; Returns: Json }
      create_transfer: {
        Args: {
          from_location: string
          lines: Json
          note: string
          tenant: string
          to_location: string
        }
        Returns: Json
      }
      create_webhook_endpoint: {
        Args: { fields: Json; tenant: string }
        Returns: Json
      }
      create_work_item: {
        Args: { assignees: string[]; attrs: Json; tenant: string }
        Returns: Json
      }
      create_work_order: {
        Args: {
          address?: string
          asset_id?: string
          booking_id?: string
          description?: string
          ends_at?: string
          location_id?: string
          priority?: string
          starts_at?: string
          subject_id?: string
          subject_type?: string
          technician?: string
          tenant: string
          title: string
        }
        Returns: Json
      }
      create_workflow_schedule: {
        Args: {
          cron: string
          name: string
          next_run: string
          payload?: Json
          tenant?: string
          timezone?: string
          workflow: string
        }
        Returns: Json
      }
      credential_delete: {
        Args: { name: string; provider: string }
        Returns: boolean
      }
      credential_get: {
        Args: { name: string; provider: string }
        Returns: string
      }
      credential_set: {
        Args: {
          description?: string
          name: string
          provider: string
          secret: string
        }
        Returns: string
      }
      credit_invoice: {
        Args: {
          fixed_number?: string
          invoice: string
          issued_on?: string
          lines: Json
          note: string
        }
        Returns: Json
      }
      currency_minor_units: { Args: { code: string }; Returns: number }
      data_export_rows: {
        Args: {
          after?: string
          id: string
          page_size?: number
          table_name: string
        }
        Returns: Json
      }
      data_lifecycle_credentials: {
        Args: Record<PropertyKey, never>
        Returns: {
          col: string
          name: string
          tbl: string
          user_col: string
        }[]
      }
      data_lifecycle_tables: {
        Args: Record<PropertyKey, never>
        Returns: {
          col: string
          exported: boolean
          name: string
          omit: string[]
          purge: boolean
          subject: string
          tbl: string
        }[]
      }
      data_restore_tables: { Args: Record<PropertyKey, never>; Returns: Json }
      deal_board: { Args: { pipeline: string }; Returns: Json }
      deal_forecast: {
        Args: {
          currency: string
          owner: string
          pipeline: string
          since: string
          target: number
          tenant: string
          until: string
        }
        Returns: Json
      }
      deal_health: { Args: { pipeline: string }; Returns: Json }
      decide_ai_tool_approval: {
        Args: { approval_id: string; approved: boolean; reason?: string }
        Returns: Json
      }
      decide_appeal: {
        Args: { appeal_id: string; outcome: string; reason?: string }
        Returns: Json
      }
      decide_approval: {
        Args: {
          comment?: string
          decided_by?: string
          decision: string
          request_id: string
        }
        Returns: Json
      }
      decide_approval_items: {
        Args: { decided_by?: string; decisions: Json; request_id: string }
        Returns: Json
      }
      decide_care_alert: {
        Args: { alert_id: string; decision: string; reason?: string }
        Returns: Json
      }
      decide_connector_fingerprint: {
        Args: { approved: boolean; fingerprint: string; server_id: string }
        Returns: boolean
      }
      decide_document_suggestion: {
        Args: { decision: string; note?: string; suggestion_id: string }
        Returns: Json
      }
      decide_meeting_decision: {
        Args: { decision_id: string; status?: string }
        Returns: Json
      }
      decide_notice: {
        Args: { decision: string; notice_id: string; outcome?: string }
        Returns: Json
      }
      decide_purchase_requisition: {
        Args: { approve: boolean; requisition: string }
        Returns: Json
      }
      decide_quote: {
        Args: {
          actor?: Json
          by: string
          decision: string
          note: string
          quote: string
          selected?: Json
        }
        Returns: Json
      }
      decide_shift_request: {
        Args: { approve: boolean; assignment_id: string }
        Returns: Json
      }
      decide_shift_swap: {
        Args: { approval_id?: string; approve: boolean; swap_id: string }
        Returns: Json
      }
      decide_waitlist_entry: {
        Args: { approve: boolean; id: string }
        Returns: Json
      }
      decline_invitation: { Args: { token: string }; Returns: boolean }
      decline_invitation_by_id: {
        Args: { invitation_id: string }
        Returns: boolean
      }
      decline_rfq_supplier: { Args: { invitation_id: string }; Returns: Json }
      decline_signature_request: {
        Args: { reason?: string; request_id: string }
        Returns: Json
      }
      default_pipeline: {
        Args: { scope_id: string; subject_type: string; tenant: string }
        Returns: string
      }
      default_service_principal: { Args: { tenant: string }; Returns: string }
      define_attachment_document_type: {
        Args: { fields?: Json; key: string; name: string; tenant: string }
        Returns: Json
      }
      delegate_approval: {
        Args: { comment?: string; request_id: string; to_user: string }
        Returns: Json
      }
      delete_accounting_entry: { Args: { entry_id: string }; Returns: Json }
      delete_activity: { Args: { engagement: string }; Returns: boolean }
      delete_agent: { Args: { id: string }; Returns: boolean }
      delete_ai_chat: { Args: { chat: string }; Returns: boolean }
      delete_ai_document: { Args: { document_id: string }; Returns: boolean }
      delete_ai_file: { Args: { file_id: string }; Returns: Json }
      delete_ai_project: { Args: { id: string }; Returns: boolean }
      delete_ai_provider_key: { Args: { id: string }; Returns: Json }
      delete_ai_provider_keys: { Args: { tenant: string }; Returns: Json }
      delete_ai_task: { Args: { id: string }; Returns: boolean }
      delete_announcement: { Args: { id: string }; Returns: boolean }
      delete_attachment: { Args: { id: string }; Returns: boolean }
      delete_attachment_document_type: {
        Args: { key: string; tenant: string }
        Returns: boolean
      }
      delete_bank_rule: { Args: { rule_id: string }; Returns: undefined }
      delete_booking_exception: {
        Args: { exception_id: string }
        Returns: boolean
      }
      delete_calendar: { Args: { calendar_id: string }; Returns: boolean }
      delete_calendar_event: { Args: { event_id: string }; Returns: boolean }
      delete_care_rule: { Args: { rule_id: string }; Returns: Json }
      delete_catalog_channel: { Args: { channel: string }; Returns: boolean }
      delete_category: { Args: { category: string }; Returns: boolean }
      delete_collection: { Args: { collection: string }; Returns: boolean }
      delete_connector_server: { Args: { id: string }; Returns: Json }
      delete_contract_obligation: {
        Args: { obligation_id: string }
        Returns: Json
      }
      delete_course: { Args: { course_id: string }; Returns: boolean }
      delete_course_lesson: { Args: { lesson_id: string }; Returns: boolean }
      delete_course_module: { Args: { module_id: string }; Returns: boolean }
      delete_custom_emoji: { Args: { emoji_id: string }; Returns: boolean }
      delete_deal: { Args: { deal: string }; Returns: boolean }
      delete_discount_group: { Args: { group: string }; Returns: boolean }
      delete_discount_rule: { Args: { rule: string }; Returns: boolean }
      delete_employee: { Args: { employee: string }; Returns: Json }
      delete_enrollment_program: {
        Args: { program_id: string }
        Returns: boolean
      }
      delete_field_definition: {
        Args: { definition: string }
        Returns: boolean
      }
      delete_flag: { Args: { key: string }; Returns: boolean }
      delete_flag_segment: { Args: { name: string }; Returns: boolean }
      delete_form_submission: {
        Args: { submission_id: string }
        Returns: boolean
      }
      delete_funding_claim: { Args: { claim_id: string }; Returns: boolean }
      delete_inspection_finding: { Args: { finding_id: string }; Returns: Json }
      delete_intrastat_line: { Args: { line: string }; Returns: boolean }
      delete_invoice: { Args: { invoice: string }; Returns: boolean }
      delete_kitchen_station: { Args: { station: string }; Returns: boolean }
      delete_knowledge_collection: {
        Args: { collection_id: string }
        Returns: boolean
      }
      delete_knowledge_document: {
        Args: { document_id: string }
        Returns: boolean
      }
      delete_location: { Args: { location: string }; Returns: boolean }
      delete_maintenance_plan: { Args: { plan_id: string }; Returns: Json }
      delete_maintenance_request: {
        Args: { work_item: string }
        Returns: boolean
      }
      delete_maintenance_request_checklist_item: {
        Args: { checklist_item: string }
        Returns: boolean
      }
      delete_meeting: { Args: { meeting_id: string }; Returns: Json }
      delete_meeting_agenda_item: { Args: { item_id: string }; Returns: Json }
      delete_message: { Args: { message: string }; Returns: boolean }
      delete_message_template: { Args: { template: string }; Returns: boolean }
      delete_organization: { Args: { organization: string }; Returns: boolean }
      delete_payment_term: { Args: { id: string }; Returns: boolean }
      delete_payroll_run: { Args: { run_id: string }; Returns: undefined }
      delete_post: { Args: { post_id: string }; Returns: boolean }
      delete_price: { Args: { price: string }; Returns: boolean }
      delete_price_list: { Args: { price_list: string }; Returns: boolean }
      delete_product: { Args: { product: string }; Returns: boolean }
      delete_product_identifier: {
        Args: { identifier: string }
        Returns: boolean
      }
      delete_product_option: { Args: { option: string }; Returns: boolean }
      delete_product_relation: {
        Args: { from_variant: string; kind: string; to_variant: string }
        Returns: boolean
      }
      delete_promotion: { Args: { promotion: string }; Returns: boolean }
      delete_promotion_code: { Args: { code: string }; Returns: boolean }
      delete_putaway_rule: { Args: { rule_id: string }; Returns: boolean }
      delete_reminder: { Args: { reminder: string }; Returns: boolean }
      delete_score_model: { Args: { model_id: string }; Returns: boolean }
      delete_sequence: { Args: { sequence_id: string }; Returns: boolean }
      delete_shipping_rate: { Args: { rate: string }; Returns: boolean }
      delete_signing_keys: {
        Args: { owner_id: string; owner_type: string }
        Returns: number
      }
      delete_status_component: { Args: { component_id: string }; Returns: Json }
      delete_supplier_item: { Args: { item: string }; Returns: boolean }
      delete_supplier_item_mapping: {
        Args: { supplier: string; tenant: string }
        Returns: boolean
      }
      delete_tag: { Args: { tag_id: string }; Returns: boolean }
      delete_team: { Args: { team: string }; Returns: boolean }
      delete_time_entry: { Args: { entry_id: string }; Returns: Json }
      delete_time_rate: { Args: { rate_id: string }; Returns: Json }
      delete_variant: { Args: { variant: string }; Returns: boolean }
      delete_version: { Args: { version_id: string }; Returns: boolean }
      delete_view: { Args: { view_id: string }; Returns: boolean }
      delete_webhook_endpoint: { Args: { endpoint: string }; Returns: boolean }
      delete_work_item: { Args: { work_item: string }; Returns: boolean }
      delete_work_item_checklist_item: {
        Args: { checklist_item: string }
        Returns: boolean
      }
      deliver_fulfillment: { Args: { fulfillment: string }; Returns: boolean }
      deposit_till_cash: {
        Args: { input: Json; session_id: string }
        Returns: Json
      }
      descendants: {
        Args: {
          kind: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      detach_template_workflow: {
        Args: { definition: string; template_id: string }
        Returns: boolean
      }
      disable_service_principal: {
        Args: { created_by?: string; principal: string }
        Returns: boolean
      }
      discard_inbox_draft: { Args: { draft: string }; Returns: boolean }
      disconnect_mail_account: {
        Args: { account: string; purge: boolean }
        Returns: boolean
      }
      discount_group_updated_at: {
        Args: { subject_id: string }
        Returns: string
      }
      discount_rule_updated_at: {
        Args: { subject_id: string }
        Returns: string
      }
      dismiss_announcement: { Args: { id: string }; Returns: boolean }
      dismiss_notifications: { Args: { ids: string[] }; Returns: Json }
      dispatch_board: {
        Args: {
          from_date: string
          technicians?: string[]
          tenant: string
          to_date: string
        }
        Returns: Json
      }
      dispatch_webhook: {
        Args: {
          endpoint: string
          event_id?: string
          event_type: string
          payload: Json
          run_id?: string
        }
        Returns: string
      }
      dispose_asset: {
        Args: {
          amount?: number
          asset_id: string
          currency?: string
          disposed_on: string
        }
        Returns: Json
      }
      document_access: {
        Args: { document_id: string; write: boolean }
        Returns: boolean
      }
      document_address: { Args: { address: Json }; Returns: Json }
      document_delivery_preference_updated_at: {
        Args: { subject_id: string }
        Returns: string
      }
      document_entity: {
        Args: { legal_entity?: string; tenant: string }
        Returns: Json
      }
      document_party: {
        Args: {
          address?: Json
          buyer?: Json
          company_id: string
          contact_id: string
          email?: string
          tenant: string
        }
        Returns: Json
      }
      document_render_live: {
        Args: {
          document_id: string
          document_type: string
          language?: string
          template_name?: string
          tenant: string
        }
        Returns: Json
      }
      document_slot_rank: {
        Args: {
          entity: string
          language: string
          wanted_entity: string
          wanted_language: string
        }
        Returns: number
      }
      document_tax_summary: { Args: { lines: Json }; Returns: Json }
      document_template_contract: {
        Args: { document_type?: string }
        Returns: Json
      }
      document_template_updated_at: {
        Args: { subject_id: string }
        Returns: string
      }
      document_text_block_updated_at: {
        Args: { subject_id: string }
        Returns: string
      }
      document_topic_access: {
        Args: { topic: string; write: boolean }
        Returns: boolean
      }
      document_totals_by_billing_party: {
        Args: { document: string }
        Returns: Json
      }
      document_variables: {
        Args: { document_id: string; document_type: string; tenant: string }
        Returns: Json
      }
      document_variables_delivery_note: {
        Args: { document_id: string; tenant: string }
        Returns: Json
      }
      document_variables_dunning_letter: {
        Args: { document_id: string; tenant: string }
        Returns: Json
      }
      document_variables_invoice: {
        Args: { credit_note: boolean; document_id: string; tenant: string }
        Returns: Json
      }
      document_variables_order: {
        Args: { document_id: string; tenant: string }
        Returns: Json
      }
      document_variables_quote: {
        Args: { document_id: string; tenant: string }
        Returns: Json
      }
      document_variables_statement: {
        Args: { document_id: string; tenant: string }
        Returns: Json
      }
      document_visible: {
        Args: { document_id: string; document_type: string; tenant: string }
        Returns: boolean
      }
      documents_to_compact: {
        Args: { max_documents?: number; min_updates?: number }
        Returns: string[]
      }
      drive_approvals: { Args: { node: string }; Returns: Json }
      drive_attachment_allowed: {
        Args: { subject_id: string; subject_type: string; write: boolean }
        Returns: boolean
      }
      drive_bin: {
        Args: { before?: string; page_size?: number; tenant: string }
        Returns: Json
      }
      drive_can: { Args: { node: string; role: string }; Returns: boolean }
      drive_can_comment: { Args: { node: string }; Returns: boolean }
      drive_can_download: { Args: { node: string }; Returns: boolean }
      drive_can_upload: { Args: { folder: string }; Returns: boolean }
      drive_changes: {
        Args: {
          after?: string
          drive?: string
          page_size?: number
          tenant: string
        }
        Returns: Json
      }
      drive_commit: {
        Args: { attachment: string; node: string }
        Returns: Json
      }
      drive_create_file: {
        Args: {
          conflict?: string
          drive?: string
          fields?: Json
          mime_type: string
          name: string
          parent: string
          size: number
          tenant: string
        }
        Returns: Json
      }
      drive_create_folder: {
        Args: {
          conflict?: string
          drive?: string
          fields?: Json
          name: string
          parent: string
          tenant: string
        }
        Returns: Json
      }
      drive_delete: { Args: { node: string }; Returns: boolean }
      drive_document_obsolete: {
        Args: { node: string; reason: string }
        Returns: Json
      }
      drive_document_release: {
        Args: { attachment: string; node: string }
        Returns: Json
      }
      drive_document_review: {
        Args: { node: string; note?: string; outcome: string }
        Returns: Json
      }
      drive_document_save: {
        Args: {
          document_type: string
          node: string
          owner_id?: string
          review_interval_months?: number
        }
        Returns: Json
      }
      drive_document_submit: {
        Args: { attachment?: string; node: string; reason?: string }
        Returns: Json
      }
      drive_documents: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      drive_download_blocked: { Args: { node: string }; Returns: boolean }
      drive_get: { Args: { node: string }; Returns: Json }
      drive_grants: { Args: { node: string }; Returns: Json }
      drive_hold: { Args: { node: string; until: string }; Returns: Json }
      drive_label: {
        Args: { applied?: boolean; node: string; tag: string }
        Returns: Json
      }
      drive_labeled: {
        Args: { page_size?: number; tag: string; tenant: string }
        Returns: Json
      }
      drive_link: { Args: { node?: string; token: string }; Returns: Json }
      drive_link_upload: {
        Args: {
          mime_type: string
          name: string
          password?: string
          size: number
          token: string
        }
        Returns: Json
      }
      drive_list: {
        Args: {
          drive?: string
          page_size?: number
          parent?: string
          skip?: number
          tenant: string
        }
        Returns: Json
      }
      drive_lock: {
        Args: { node: string; note?: string; until?: string }
        Returns: Json
      }
      drive_marked: {
        Args: { page_size?: number; recent?: boolean; tenant: string }
        Returns: Json
      }
      drive_move: {
        Args: {
          conflict?: string
          drive?: string
          node: string
          parent: string
          rank?: string
        }
        Returns: Json
      }
      drive_node_access: { Args: { node: string }; Returns: Json }
      drive_node_held: { Args: { node: string }; Returns: boolean }
      drive_node_readable: { Args: { node: string }; Returns: boolean }
      drive_node_writable: { Args: { node: string }; Returns: boolean }
      drive_object_allowed: {
        Args: { action: string; bucket: string; path: string }
        Returns: boolean
      }
      drive_open: { Args: { node: string }; Returns: Json }
      drive_path: { Args: { node: string }; Returns: Json }
      drive_previews: { Args: { node: string }; Returns: Json }
      drive_prune: { Args: { max_objects?: number }; Returns: Json }
      drive_purge: { Args: { item: string }; Returns: number }
      drive_readable_ids: {
        Args: Record<PropertyKey, never>
        Returns: string[]
      }
      drive_release_hold: { Args: { node: string }; Returns: Json }
      drive_rename: {
        Args: { conflict?: string; name: string; node: string }
        Returns: Json
      }
      drive_request_approval: {
        Args: { attachment?: string; node: string; reason?: string }
        Returns: Json
      }
      drive_request_files: {
        Args: {
          expires_at?: string
          folder: string
          max_uses?: number
          password?: string
        }
        Returns: Json
      }
      drive_restore: {
        Args: { conflict?: string; item: string }
        Returns: Json
      }
      drive_restore_revision: {
        Args: { node: string; version: string }
        Returns: Json
      }
      drive_retention_kind: { Args: { label: string }; Returns: string }
      drive_retention_sweep: {
        Args: { batch_size?: number; tenant?: string }
        Returns: number
      }
      drive_revisions: { Args: { node: string }; Returns: Json }
      drive_role: { Args: { node: string }; Returns: string }
      drive_search: {
        Args: { page_size?: number; query: string; tenant: string }
        Returns: Json
      }
      drive_set_download_blocked: {
        Args: { blocked: boolean; target_id: string; target_type: string }
        Returns: Json
      }
      drive_set_previews: {
        Args: { attachment: string; node: string; pages: number }
        Returns: Json
      }
      drive_set_text: {
        Args: {
          attachment: string
          content: string
          extractor?: string
          node: string
        }
        Returns: boolean
      }
      drive_share: {
        Args: {
          expires_at?: string
          node: string
          principal_id: string
          principal_type: string
          role: string
        }
        Returns: Json
      }
      drive_share_link_allowed: {
        Args: { node: string; role: string; tenant: string }
        Returns: boolean
      }
      drive_shared: {
        Args: { page_size?: number; tenant: string }
        Returns: Json
      }
      drive_star: {
        Args: { node: string; starred?: boolean }
        Returns: boolean
      }
      drive_text_source: {
        Args: { attachment?: string; node?: string }
        Returns: Json
      }
      drive_transfer_ownership: {
        Args: { from_user: string; tenant: string; to_user: string }
        Returns: Json
      }
      drive_trash: { Args: { node: string }; Returns: Json }
      drive_unlock: { Args: { force?: boolean; node: string }; Returns: Json }
      drive_unshare: {
        Args: { node: string; principal_id: string; principal_type: string }
        Returns: boolean
      }
      drive_upload_revision: {
        Args: { mime_type: string; node: string; size: number }
        Returns: Json
      }
      drive_uploaded_own: { Args: { node: string }; Returns: boolean }
      drop_field_key: { Args: { owner: string }; Returns: boolean }
      due_ai_batches: {
        Args: { batch?: number; lease_seconds?: number }
        Returns: Json
      }
      due_care_plan_reviews: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      due_mail_accounts: {
        Args: { max_count: number; stale_after: string }
        Returns: Json
      }
      due_organization_deletions: { Args: { max_rows?: number }; Returns: Json }
      due_pledge_installments: {
        Args: { max_rows?: number; tenant: string; through?: string }
        Returns: Json
      }
      due_template_occurrences: {
        Args: { range_end: string; range_start: string }
        Returns: Json
      }
      duplicate_view: {
        Args: { name: string; scope: string; team: string; view_id: string }
        Returns: Json
      }
      edit_inbox_message: {
        Args: { body?: string; message: string; remove?: boolean }
        Returns: Json
      }
      edit_message: {
        Args: { attrs?: Json; body: string; message: string }
        Returns: Json
      }
      emit_event: {
        Args: {
          event_type: string
          key?: string
          payload?: Json
          source?: string
          subject?: string
          tenant?: string
        }
        Returns: string
      }
      employee_contracts: { Args: { employee: string }; Returns: Json }
      employee_from_application: {
        Args: { application: string; attrs: Json }
        Returns: Json
      }
      employee_private_details: { Args: { employee: string }; Returns: Json }
      encrypt_field_definition: {
        Args: { definition: string }
        Returns: boolean
      }
      end_access: { Args: { request_id: string }; Returns: Json }
      end_care_plan_action: {
        Args: { action_id: string; reason?: string }
        Returns: Json
      }
      end_commission_assignment: {
        Args: { assignment_id: string }
        Returns: Json
      }
      end_funding_award: {
        Args: { award_id: string; canceled?: boolean; ends_on?: string }
        Returns: Json
      }
      end_my_session: { Args: { session: string }; Returns: boolean }
      end_sessions: { Args: { p_user: string }; Returns: number }
      end_subject_member: {
        Args: { ends_on?: string; member_id: string }
        Returns: Json
      }
      engagement_guest_readable: {
        Args: { engagement: string }
        Returns: boolean
      }
      enqueue_import_chunks: {
        Args: { chunks: number; entity: string; run: string }
        Returns: number
      }
      enrichment_due: {
        Args: {
          max_count?: number
          provider: string
          stale_after?: string
          subject_type?: string
        }
        Returns: Json
      }
      enrichment_target: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      enrichments_of: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      enroll: {
        Args: {
          program: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      enroll_in_course: {
        Args: { course_id: string; user_id?: string }
        Returns: Json
      }
      enroll_in_sequence: {
        Args: {
          attrs?: Json
          sequence_id: string
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      enrollment: {
        Args: {
          program: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      enrollment_programs: { Args: { tenant: string }; Returns: Json }
      ensure_case_kinds: { Args: { tenant: string }; Returns: undefined }
      ensure_risk_matrix: { Args: { tenant: string }; Returns: string }
      entitlement_value: {
        Args: { key: string; tenant: string }
        Returns: Json
      }
      escalate_approvals: { Args: { max_requests?: number }; Returns: number }
      evaluate_care_rules: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: Json
      }
      expire_access_grants: { Args: { max_grants?: number }; Returns: number }
      expire_approvals: { Args: { max_requests?: number }; Returns: number }
      expire_booking_holds: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      expire_booking_holds_in: {
        Args: { during: unknown; resource: string }
        Returns: number
      }
      expire_consents: { Args: Record<PropertyKey, never>; Returns: number }
      expire_lots: { Args: { as_of: string; tenant: string }; Returns: number }
      expire_orders: { Args: { max_rows?: number }; Returns: number }
      expire_quotes: { Args: Record<PropertyKey, never>; Returns: number }
      expire_reservations: { Args: { max_rows: number }; Returns: number }
      expired_data_exports: { Args: { max_rows?: number }; Returns: Json }
      expiring_ai_provider_files: {
        Args: { batch?: number; horizon?: string }
        Returns: Json
      }
      expiring_connector_grants: {
        Args: { before: string; max_rows?: number }
        Returns: Json
      }
      expiring_lots: { Args: { before: string; tenant: string }; Returns: Json }
      explode_bom: {
        Args: { quantity: number; variant_id: string }
        Returns: Json
      }
      export_oscal_assessment_results: {
        Args: { framework_id: string; title?: string }
        Returns: Json
      }
      extend_data_subject_request: {
        Args: { id: string; reason: string }
        Returns: Json
      }
      fail_activity_recording: {
        Args: { error: string; recording: string }
        Returns: boolean
      }
      fail_data_export: { Args: { error: string; id: string }; Returns: Json }
      fail_knowledge_document: {
        Args: { document_id: string; error: string }
        Returns: boolean
      }
      feature_claims: { Args: { user_id: string }; Returns: Json }
      field_decrypt: { Args: { owner: string; value: string }; Returns: string }
      field_encrypt: { Args: { owner: string; value: string }; Returns: string }
      field_history: {
        Args: {
          before?: number
          field?: string
          max_count?: number
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      field_lookup: { Args: { owner: string; value: string }; Returns: string }
      file_appeal: {
        Args: { notice_id?: string; reasons?: string; statement_id?: string }
        Returns: Json
      }
      finalize_commission_statement: {
        Args: { statement_id: string }
        Returns: Json
      }
      find_channel: { Args: { name: string; tenant: string }; Returns: Json }
      find_e_endpoint_party: {
        Args: { endpoint_id: string; scheme: string; tenant: string }
        Returns: Json
      }
      find_person_by_identity: {
        Args: { address: string; channel: string; tenant: string }
        Returns: Json
      }
      find_variants_by_identifier: {
        Args: { party?: string; tenant: string; type?: string; value: string }
        Returns: Json
      }
      finish_ai_sandbox_stop: {
        Args: { error?: string; id: string; stopped: boolean }
        Returns: boolean
      }
      finish_ai_task_run: {
        Args: {
          chat_id?: string
          error?: string
          id: string
          succeeded: boolean
        }
        Returns: boolean
      }
      finish_import: {
        Args: { count: number; error: string; id: string; status: string }
        Returns: boolean
      }
      finish_import_run: { Args: { run: string }; Returns: Json }
      finish_production_operation: {
        Args: { minutes?: number; operation_id: string }
        Returns: Json
      }
      finish_template_occurrence: {
        Args: {
          application_id: string
          occurrence_at: string
          schedule_id: string
        }
        Returns: boolean
      }
      flag_bucket: { Args: { flag: string; target: string }; Returns: number }
      flag_condition_matches: {
        Args: {
          condition: Json
          context_values: Json
          member: string
          plans: string[]
          role: string
          tenant: string
        }
        Returns: boolean
      }
      flag_definitions: { Args: Record<PropertyKey, never>; Returns: Json }
      flag_enabled: { Args: { key: string; tenant?: string }; Returns: boolean }
      flag_evaluation: {
        Args: { contexts?: Json; key: string; member?: string; tenant?: string }
        Returns: Json
      }
      flag_history: { Args: { key: string }; Returns: Json }
      flag_rollout_percentage: {
        Args: { at?: string; percentage: number; schedule: Json }
        Returns: number
      }
      follow: {
        Args: { following?: boolean; target_id: string; target_type: string }
        Returns: boolean
      }
      forecast_changes: {
        Args: { from_snapshot: string; to_snapshot: string }
        Returns: Json
      }
      forecast_snapshot: { Args: { snapshot: string }; Returns: Json }
      forecast_snapshots: {
        Args: {
          max_count?: number
          pipeline?: string
          since?: string
          tenant: string
          until?: string
        }
        Returns: Json
      }
      forget_data_exports: { Args: { ids: string[] }; Returns: number }
      fork_template: { Args: { source: string; tenant: string }; Returns: Json }
      fork_workflow_definition: {
        Args: { slug: string; source: string; tenant: string }
        Returns: Json
      }
      form_nps: {
        Args: {
          bucket?: string
          field?: string
          form_id: string
          since?: string
          until?: string
        }
        Returns: Json
      }
      freeze_document: {
        Args: {
          document_id: string
          document_type: string
          language?: string
          template_name?: string
          tenant: string
        }
        Returns: Json
      }
      fulfil_data_subject_request: {
        Args: { id: string; resolution?: string }
        Returns: Json
      }
      fulfill_allocation: {
        Args: { allocation: string; detail?: Json; quantity: number }
        Returns: Json
      }
      funding_award_usage: { Args: { award_id: string }; Returns: Json }
      generate_maintenance_work_orders: {
        Args: { tenant: string }
        Returns: Json
      }
      generate_shifts: {
        Args: {
          from_date: string
          template_id: string
          tenant: string
          until_date: string
        }
        Returns: Json
      }
      get_access_request: { Args: { request_id: string }; Returns: Json }
      get_accounting_budget: { Args: { budget_id: string }; Returns: Json }
      get_accounting_entry: { Args: { entry_id: string }; Returns: Json }
      get_accounting_settings: { Args: { tenant: string }; Returns: Json }
      get_activity_recording: { Args: { recording: string }; Returns: Json }
      get_agent: {
        Args: { id?: string; slug?: string; tenant?: string }
        Returns: Json
      }
      get_ai_batch: { Args: { id: string }; Returns: Json }
      get_ai_chat: { Args: { chat: string }; Returns: Json }
      get_ai_chat_by_link: { Args: { token: string }; Returns: Json }
      get_ai_document: { Args: { document_id: string }; Returns: Json }
      get_ai_file: { Args: { file_id: string }; Returns: Json }
      get_ai_file_by_path: {
        Args: { bucket: string; path: string }
        Returns: Json
      }
      get_ai_provider_file: {
        Args: { file_id: string; provider: string }
        Returns: Json
      }
      get_ai_run: { Args: { run: string }; Returns: Json }
      get_ai_tool_approvals: {
        Args: { chat: string; ids?: string[] }
        Returns: Json
      }
      get_appraisal: { Args: { appraisal_id: string }; Returns: Json }
      get_approval: { Args: { request_id: string }; Returns: Json }
      get_asset: { Args: { asset_id: string }; Returns: Json }
      get_asset_location: { Args: { location_id: string }; Returns: Json }
      get_attachment: { Args: { id: string }; Returns: Json }
      get_bank_transaction: { Args: { transaction_id: string }; Returns: Json }
      get_bom: { Args: { bom_id: string }; Returns: Json }
      get_booking_series: { Args: { series_id: string }; Returns: Json }
      get_care_plan: { Args: { plan_id: string }; Returns: Json }
      get_case: { Args: { case_id: string }; Returns: Json }
      get_channel: { Args: { channel: string }; Returns: Json }
      get_comment: { Args: { message: string }; Returns: Json }
      get_commission_statement: {
        Args: { statement_id: string }
        Returns: Json
      }
      get_connector: { Args: { id: string; owner?: string }; Returns: Json }
      get_connector_session: {
        Args: { chat_key?: string; server_id: string }
        Returns: Json
      }
      get_content_entry: { Args: { entry_id: string }; Returns: Json }
      get_contract: { Args: { contract_id: string }; Returns: Json }
      get_control: { Args: { control_id: string }; Returns: Json }
      get_conversation: { Args: { conversation: string }; Returns: Json }
      get_cycle_count_variance: { Args: { count_id: string }; Returns: Json }
      get_data_export: { Args: { id: string }; Returns: Json }
      get_document_template: { Args: { template_id: string }; Returns: Json }
      get_document_version: {
        Args: { document_id: string; version_id: string }
        Returns: string
      }
      get_expense_report: { Args: { report_id: string }; Returns: Json }
      get_form: { Args: { form_id: string }; Returns: Json }
      get_form_submission: { Args: { submission_id: string }; Returns: Json }
      get_form_version: { Args: { version_id: string }; Returns: Json }
      get_funding_claim: { Args: { claim_id: string }; Returns: Json }
      get_gift: { Args: { gift_id: string }; Returns: Json }
      get_import_run: { Args: { id: string }; Returns: Json }
      get_inbox_message: { Args: { message: string }; Returns: Json }
      get_incident: { Args: { incident_id: string }; Returns: Json }
      get_incident_regulatory_profile: {
        Args: { incident_id: string }
        Returns: Json
      }
      get_inspection: { Args: { inspection_id: string }; Returns: Json }
      get_knowledge_document: { Args: { document_id: string }; Returns: Json }
      get_lease: { Args: { lease_id: string }; Returns: Json }
      get_legal_entity: { Args: { legal_entity_id: string }; Returns: Json }
      get_legal_entity_settings: {
        Args: { legal_entity_id: string }
        Returns: Json
      }
      get_mail_account: { Args: { account: string }; Returns: Json }
      get_mail_thread: { Args: { thread: string }; Returns: Json }
      get_maintenance_request: { Args: { work_item: string }; Returns: Json }
      get_meeting: { Args: { meeting_id: string }; Returns: Json }
      get_message: { Args: { message: string }; Returns: Json }
      get_notification: { Args: { id: string }; Returns: Json }
      get_order: { Args: { order_id: string }; Returns: Json }
      get_organization_settings: { Args: { tenant: string }; Returns: Json }
      get_pass: { Args: { pass_id: string }; Returns: Json }
      get_payment_batch: { Args: { batch_id: string }; Returns: Json }
      get_payroll_run: { Args: { run_id: string }; Returns: Json }
      get_pick_list: { Args: { pick_list_id: string }; Returns: Json }
      get_platform_settings: { Args: Record<PropertyKey, never>; Returns: Json }
      get_post: { Args: { post_id: string }; Returns: Json }
      get_prescription: { Args: { prescription_id: string }; Returns: Json }
      get_production_order: { Args: { order_id: string }; Returns: Json }
      get_public_form: { Args: { token: string }; Returns: Json }
      get_purchase_requisition: { Args: { requisition: string }; Returns: Json }
      get_quote: { Args: { quote: string }; Returns: Json }
      get_rfq: { Args: { rfq_id: string }; Returns: Json }
      get_risk: { Args: { risk_id: string }; Returns: Json }
      get_sample: { Args: { sample_id: string }; Returns: Json }
      get_score_model: { Args: { model_id: string }; Returns: Json }
      get_sequence: { Args: { sequence_id: string }; Returns: Json }
      get_shared_ai_chat: { Args: { token: string }; Returns: Json }
      get_shared_version: { Args: { token: string }; Returns: Json }
      get_shipment: { Args: { shipment_id: string }; Returns: Json }
      get_signature_request: { Args: { request_id: string }; Returns: Json }
      get_status_page: { Args: { tenant: string }; Returns: Json }
      get_till_session: { Args: { session_id: string }; Returns: Json }
      get_timesheet: {
        Args: { tenant: string; user_id?: string; week: string }
        Returns: Json
      }
      get_user_settings: { Args: Record<PropertyKey, never>; Returns: Json }
      get_version: { Args: { version_id: string }; Returns: Json }
      get_work_item: { Args: { work_item: string }; Returns: Json }
      get_work_order: { Args: { work_order_id: string }; Returns: Json }
      goal_progress: {
        Args: { on_date: string; owner: string; tenant: string }
        Returns: Json
      }
      grant_guest_access: {
        Args: {
          actions?: string[]
          expires_at?: string
          guest_id: string
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      grant_qualification: {
        Args: {
          evidence_attachment_id?: string
          evidence_note?: string
          granted_on?: string
          holder_id: string
          holder_type: string
          tenant: string
          type_key: string
        }
        Returns: Json
      }
      grant_usage_right: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      guest_can: {
        Args: { action?: string; subject_id: string; subject_type: string }
        Returns: boolean
      }
      hand_over_to_collection: {
        Args: { agency_party_id: string; invoice_ids: string[]; note?: string }
        Returns: Json
      }
      has_entitlement: {
        Args: { key: string; tenant: string }
        Returns: boolean
      }
      has_scope: { Args: { scope: string }; Returns: boolean }
      has_subject_role: {
        Args: { roles: string[]; subject_id: string; subject_type: string }
        Returns: boolean
      }
      hold_booking: {
        Args: {
          confirm?: boolean
          customer: Json
          resource: string
          service: string
          starts_at: string
        }
        Returns: Json
      }
      hold_meeting: {
        Args: { meeting_id: string; summary?: string }
        Returns: Json
      }
      idle_ai_sandboxes: {
        Args: { batch?: number; lease_seconds?: number }
        Returns: Json
      }
      ignore_bank_transaction: {
        Args: { ignored?: boolean; transaction_id: string }
        Returns: Json
      }
      import_accounting_account: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_accounting_entry: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_accounting_journal: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_accounting_opening_balance: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_apply_batch: {
        Args: { entity: string; items: Json; run: string }
        Returns: Json
      }
      import_attachment: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_bank_statement: {
        Args: { account_id: string; statement: Json }
        Returns: Json
      }
      import_calendar_events: {
        Args: { calendar_id: string; source: Json }
        Returns: Json
      }
      import_credit_note: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_discount_group: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_discount_rule: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_document_delivery_preference: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_document_template: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_document_text_block: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_field_value: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_invoice: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_medication: { Args: { item: Json; tenant: string }; Returns: Json }
      import_medication_orders: {
        Args: { items: Json; tenant: string }
        Returns: Json
      }
      import_open_item: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_order: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_oscal_catalog: {
        Args: { document: Json; key?: string; tenant: string }
        Returns: Json
      }
      import_payment_term: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_product_identifier: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_quote: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_resolve: {
        Args: { entity: string; keys: Json; run: string }
        Returns: Json
      }
      import_run: { Args: Record<PropertyKey, never>; Returns: string }
      import_stock_count: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_supplier_item: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_upsert_batch: {
        Args: { entity: string; items: Json; run: string }
        Returns: Json
      }
      inbox_counts: { Args: { tenant: string }; Returns: Json }
      inbox_file_failed: {
        Args: { attachment: string; detail?: string }
        Returns: boolean
      }
      ingest_mail: {
        Args: { account: string; messages: Json; next_cursor: string }
        Returns: Json
      }
      ingest_observations: {
        Args: { items: Json; tenant: string }
        Returns: Json
      }
      ingest_tracking_events: {
        Args: { carrier: string; events: Json; tracking_number: string }
        Returns: Json
      }
      inspection_role: { Args: { inspection_id: string }; Returns: string }
      inspection_set_team: {
        Args: { inspection_id: string; team: Json; tenant: string }
        Returns: string
      }
      inspection_team_with_lead: {
        Args: { lead_id: string; team: Json }
        Returns: Json
      }
      install_agent: {
        Args: { agent_id: string; installed?: boolean; tenant: string }
        Returns: boolean
      }
      install_default_rules: { Args: { tenant: string }; Returns: number }
      install_field_pack: {
        Args: { pack: Json; tenant: string }
        Returns: Json
      }
      instrument_status: {
        Args: { asset_id: string; on_date?: string; tenant: string }
        Returns: Json
      }
      inventory_overview: {
        Args: { expiry_days?: number; row_limit?: number; tenant: string }
        Returns: Json
      }
      invitation_preview: { Args: { token: string }; Returns: Json }
      invite_guest: {
        Args: {
          email: string
          expires_at?: string
          name?: string
          party_id?: string
          party_type?: string
          tenant: string
        }
        Returns: Json
      }
      invite_member: {
        Args: {
          invitee_email: string
          invitee_role: string
          prefill?: Json
          tenant: string
          valid_for?: string
        }
        Returns: Json
      }
      invite_rfq_supplier: {
        Args: { rfq_id: string; supplier_id: string; supplier_type: string }
        Returns: Json
      }
      invite_to_channel: {
        Args: { channel: string; users: string[] }
        Returns: number
      }
      invoice_aging: {
        Args: {
          as_of: string
          currency: string
          direction?: string
          tenant: string
        }
        Returns: Json
      }
      invoice_approval_state: { Args: { invoice: string }; Returns: Json }
      invoice_e_endpoints: { Args: { invoice: string }; Returns: Json }
      invoice_from_quote: {
        Args: {
          deposit_amount?: number
          deposit_bps: number
          deposit_description?: string
          quote: string
        }
        Returns: Json
      }
      invoice_from_sources: {
        Args: { options?: Json; party: Json; source_refs: Json; tenant: string }
        Returns: Json
      }
      invoice_from_time: {
        Args: { attrs: Json; group_by?: string; scope?: Json; tenant: string }
        Returns: Json
      }
      invoice_funding_claim: {
        Args: { attrs?: Json; claim_id: string }
        Returns: Json
      }
      invoice_summaries: { Args: { tenant: string }; Returns: Json }
      invoice_updated_at: { Args: { subject_id: string }; Returns: string }
      is_approved: {
        Args: { action: string; subject_id: string; subject_type: string }
        Returns: boolean
      }
      is_held: { Args: { kind: string; tenant?: string }; Returns: boolean }
      is_platform: { Args: { permission: string }; Returns: boolean }
      is_subject_member: {
        Args: { subject_id: string; subject_type: string }
        Returns: boolean
      }
      is_trashed: {
        Args: { subject_id: string; subject_type: string }
        Returns: boolean
      }
      issue_consent_receipt: { Args: { consent_id: string }; Returns: Json }
      issue_gift_receipt: { Args: { gift_id: string }; Returns: Json }
      issue_invoice: {
        Args: {
          actor?: Json
          due_on?: string
          fixed_number?: string
          invoice: string
          issued_on: string
        }
        Returns: Json
      }
      issue_pass: {
        Args: {
          booking_id?: string
          holder_email?: string
          holder_name?: string
          holder_user?: string
          kind?: string
          resource_id?: string
          subject_id?: string
          subject_type?: string
          tenant: string
          uses_allowed?: number
          valid_from?: string
          valid_until?: string
        }
        Returns: Json
      }
      issue_statement: {
        Args: {
          automated_decision?: boolean
          automated_detection?: boolean
          facts: string
          item_id: string
          legal_ground?: string
          redress?: string[]
          restriction: string
          terms_ground?: string
        }
        Returns: Json
      }
      issue_yearly_receipt: {
        Args: {
          currency: string
          donor_id: string
          donor_type: string
          tenant: string
          year: number
        }
        Returns: Json
      }
      join_channel: { Args: { channel: string }; Returns: boolean }
      join_waitlist: {
        Args: { email: string; metadata?: Json; referrer?: string }
        Returns: Json
      }
      kitchen_queue: {
        Args: {
          page_size: number
          states: string[]
          station: string
          tenant: string
        }
        Returns: Json
      }
      kitchen_stations: { Args: { tenant: string }; Returns: Json }
      knowledge_collection_readable: {
        Args: { collection_id: string }
        Returns: boolean
      }
      knowledge_search: {
        Args: {
          collections?: string[]
          filter?: Json
          k?: number
          priority_order?: boolean
          query_embedding?: string
          query_text?: string
          scopes?: Json
          tenant: string
        }
        Returns: Json
      }
      knowledge_subject_readable: {
        Args: { subject_id: string; subject_type: string }
        Returns: boolean
      }
      label_version: {
        Args: { label: string; version_id: string }
        Returns: boolean
      }
      last_sign_ins: {
        Args: { p_users: string[] }
        Returns: {
          last_sign_in_at: string
          user_id: string
        }[]
      }
      latest_observations: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      lead_fields: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: Json
      }
      leave_channel: { Args: { channel: string }; Returns: boolean }
      leave_organization: { Args: { organization: string }; Returns: boolean }
      legal_entities_disable_check: { Args: { tenant: string }; Returns: Json }
      legal_entity_of: {
        Args: { id?: string; tenant: string }
        Returns: string
      }
      link: {
        Args: {
          data: Json
          kind: string
          source_id: string
          source_type: string
          target_id: string
          target_type: string
          tenant: string
        }
        Returns: Json
      }
      link_case_action: {
        Args: {
          case_id: string
          required?: boolean
          task_id: string
          type: string
        }
        Returns: Json
      }
      link_mail_thread: {
        Args: { subjects: Json; thread: string }
        Returns: Json
      }
      list_access_requests: {
        Args: {
          before?: string
          mine?: boolean
          page_size?: number
          status?: string
          tenant: string
        }
        Returns: Json
      }
      list_accounting_accounts: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_accounting_budgets: {
        Args: { fiscal_year?: number; tenant: string }
        Returns: Json
      }
      list_accounting_dimensions: { Args: { tenant: string }; Returns: Json }
      list_accounting_entries: {
        Args: {
          journal_id?: string
          page_size?: number
          since?: string
          status?: string
          tenant: string
          until?: string
        }
        Returns: Json
      }
      list_accounting_journals: { Args: { tenant: string }; Returns: Json }
      list_accounting_opening_balances: {
        Args: { fiscal_year: number; tenant: string }
        Returns: Json
      }
      list_accounting_periods: {
        Args: { fiscal_year?: number; tenant: string }
        Returns: Json
      }
      list_acknowledgement_assignments: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      list_activity: {
        Args: {
          before?: string
          max_rows?: number
          sources?: string[]
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      list_agents: {
        Args: {
          filter?: string
          max_rows?: number
          search?: string
          tenant: string
        }
        Returns: Json
      }
      list_ai_batch_items: {
        Args: { after?: string; id: string; max_rows?: number }
        Returns: Json
      }
      list_ai_batches: {
        Args: { max_rows?: number; status?: string; tenant: string }
        Returns: Json
      }
      list_ai_chat_participants: { Args: { chat: string }; Returns: Json }
      list_ai_chat_shares: { Args: { chat: string }; Returns: Json }
      list_ai_chats: {
        Args: {
          after?: string
          archived?: boolean
          pinned?: boolean
          project?: string
          search?: string
          size?: number
          tenant?: string
        }
        Returns: Json
      }
      list_ai_document_versions: {
        Args: { document_id: string }
        Returns: Json
      }
      list_ai_files: { Args: { chat_id: string }; Returns: Json }
      list_ai_moderation_events: {
        Args: { size?: number; tenant: string }
        Returns: Json
      }
      list_ai_projects: { Args: { tenant: string }; Returns: Json }
      list_ai_provider_keys: { Args: { tenant: string }; Returns: Json }
      list_ai_run_steps: { Args: { run: string }; Returns: Json }
      list_ai_runs: {
        Args: { active?: boolean; chat?: string; size?: number }
        Returns: Json
      }
      list_ai_sandboxes: {
        Args: { chat_id?: string; tenant: string }
        Returns: Json
      }
      list_ai_suggestions: {
        Args: { document_id: string; open_only?: boolean }
        Returns: Json
      }
      list_ai_task_runs: {
        Args: { max_rows?: number; task_id: string }
        Returns: Json
      }
      list_ai_tasks: { Args: { mine?: boolean; tenant: string }; Returns: Json }
      list_allocations: {
        Args: { document_id: string; document_type: string; tenant: string }
        Returns: Json
      }
      list_announcements: { Args: Record<PropertyKey, never>; Returns: Json }
      list_api_keys: { Args: { tenant?: string }; Returns: Json }
      list_applications:
        | { Args: { job: string; state?: string }; Returns: Json }
        | { Args: { tenant: string }; Returns: Json }
      list_appraisal_cycles: { Args: { tenant: string }; Returns: Json }
      list_appraisals: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_approval_policies: {
        Args: { page_size?: number; subject_type?: string; tenant: string }
        Returns: Json
      }
      list_approvals: {
        Args: {
          assigned?: boolean
          before?: string
          page_size?: number
          status?: string
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      list_asset_depreciations: {
        Args: { asset_id: string; page_size?: number }
        Returns: Json
      }
      list_asset_locations: {
        Args: {
          include_archived?: boolean
          page_size?: number
          parent_id?: string
          tenant: string
        }
        Returns: Json
      }
      list_assets: {
        Args: {
          assignee_id?: string
          assignee_type?: string
          before?: string
          include_sublocations?: boolean
          kind?: string
          location_id?: string
          page_size?: number
          query?: string
          status?: string
          tenant: string
        }
        Returns: Json
      }
      list_assignment_queues: {
        Args: { subject_type?: string; tenant: string }
        Returns: Json
      }
      list_attachment_document_types: {
        Args: { tenant: string }
        Returns: Json
      }
      list_attachment_versions: { Args: { id: string }; Returns: Json }
      list_attachments: {
        Args: { subject_id?: string; subject_type?: string; tenant: string }
        Returns: Json
      }
      list_audit_events: {
        Args: {
          ascending?: boolean
          cursor_at?: string
          cursor_id?: string
          for_actor_kinds?: string[]
          for_actors?: string[]
          for_categories?: string[]
          for_correlation_ids?: string[]
          for_event_types?: string[]
          for_outcomes?: string[]
          for_records?: string[]
          for_sources?: string[]
          for_target_types?: string[]
          for_tenants?: string[]
          max_items?: number
          search?: string
          since?: string
          skip?: number
          until?: string
        }
        Returns: Json
      }
      list_bank_accounts: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_bank_rules: { Args: { tenant: string }; Returns: Json }
      list_bank_statements: { Args: { account_id: string }; Returns: Json }
      list_bank_transactions: {
        Args: { account_id: string; filter?: Json }
        Returns: Json
      }
      list_bans: {
        Args: { active?: boolean; page_size?: number; tenant: string }
        Returns: Json
      }
      list_bin_slots: { Args: { filters: Json; tenant: string }; Returns: Json }
      list_boms: { Args: { tenant: string; variant?: string }; Returns: Json }
      list_booking_resources: {
        Args: { include_inactive?: boolean; tenant: string }
        Returns: Json
      }
      list_booking_services: {
        Args: { include_inactive?: boolean; tenant: string }
        Returns: Json
      }
      list_bookings: {
        Args: {
          range_end: string
          range_start: string
          resource?: string
          tenant: string
        }
        Returns: Json
      }
      list_calendar_events: {
        Args: { calendar_ids: string[]; range_end: string; range_start: string }
        Returns: Json
      }
      list_calendar_working_hours: {
        Args: { tenant: string; user_ids: string[] }
        Returns: Json
      }
      list_calendars: { Args: { tenant: string }; Returns: Json }
      list_calibrations: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_care_alerts: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_care_plan_measures: {
        Args: { active_only?: boolean; tenant: string }
        Returns: Json
      }
      list_care_plans: {
        Args: {
          include_archived?: boolean
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      list_care_rules: { Args: { tenant: string }; Returns: Json }
      list_case_kinds: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_cases: { Args: { filters?: Json; tenant: string }; Returns: Json }
      list_channels: {
        Args: { browse?: boolean; include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_comments: {
        Args: {
          after?: string
          after_id?: string
          include_deleted?: boolean
          max_rows?: number
          skip?: number
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      list_commission_plans: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_commission_statements: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_commissions: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_companies: {
        Args: {
          after_id: string
          after_name: string
          lifecycle: string
          owner: string
          page_size: number
          role?: string
          search: string
          supplier_status?: string
          tenant: string
        }
        Returns: Json
      }
      list_compliance_policies: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_connector_servers: { Args: { tenant: string }; Returns: Json }
      list_consent_purposes: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_consent_receipts: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      list_consent_signals: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      list_consents: {
        Args: {
          include_history?: boolean
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      list_content_entries: {
        Args: { filter?: Json; tenant: string }
        Returns: Json
      }
      list_contract_obligations: {
        Args: {
          contract_id?: string
          due_before?: string
          open_only?: boolean
          owner_id?: string
          page_size?: number
          tenant: string
        }
        Returns: Json
      }
      list_contracts: {
        Args: {
          before?: string
          counterparty_id?: string
          counterparty_type?: string
          owner_id?: string
          page_size?: number
          renewing_before?: string
          status?: string
          tenant: string
        }
        Returns: Json
      }
      list_control_frameworks: { Args: { tenant: string }; Returns: Json }
      list_controls: {
        Args: {
          framework_id?: string
          owner_id?: string
          page_size?: number
          status?: string
          tenant: string
        }
        Returns: Json
      }
      list_conversation_events: {
        Args: { conversation: string }
        Returns: Json
      }
      list_conversations: {
        Args: { kinds?: string[]; max_rows?: number; tenant: string }
        Returns: Json
      }
      list_count_plans: { Args: { tenant: string }; Returns: Json }
      list_course_learners: {
        Args: {
          before?: string
          course_id: string
          page_size?: number
          status?: string
        }
        Returns: Json
      }
      list_courses: { Args: { status?: string; tenant: string }; Returns: Json }
      list_custom_emoji: { Args: { tenant: string }; Returns: Json }
      list_data_exports: { Args: { tenant?: string }; Returns: Json }
      list_data_subject_requests: {
        Args: { open_only?: boolean; status?: string; tenant: string }
        Returns: Json
      }
      list_document_delivery_preferences: {
        Args: { party: string }
        Returns: Json
      }
      list_document_suggestions: {
        Args: { document_id: string; status?: string }
        Returns: Json
      }
      list_document_templates: {
        Args: {
          active_only?: boolean
          document_type?: string
          legal_entity_id?: string
          tenant: string
        }
        Returns: Json
      }
      list_document_text_blocks: {
        Args: { key?: string; legal_entity_id?: string; tenant: string }
        Returns: Json
      }
      list_document_versions: { Args: { document_id: string }; Returns: Json }
      list_donation_funds: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_donation_receipts: {
        Args: {
          donor_id?: string
          donor_type?: string
          page_size?: number
          tenant: string
          year?: number
        }
        Returns: Json
      }
      list_e_invoice_deliveries: {
        Args: {
          direction?: string
          invoice?: string
          state?: string
          tenant: string
        }
        Returns: Json
      }
      list_emergency_access: {
        Args: {
          before?: string
          page_size?: number
          tenant: string
          unreviewed?: boolean
        }
        Returns: Json
      }
      list_enrollments: {
        Args: {
          before?: string
          page_size?: number
          program?: string
          status?: string
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      list_evidence_tasks: {
        Args: {
          assignee_id?: string
          control_id?: string
          overdue_only?: boolean
          tenant: string
        }
        Returns: Json
      }
      list_expense_categories: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_expense_reports: {
        Args: {
          everyone?: boolean
          page_size?: number
          status?: string
          tenant: string
          user_id?: string
        }
        Returns: Json
      }
      list_field_definitions: {
        Args: { entity: string; tenant: string }
        Returns: Json
      }
      list_file_anchors: {
        Args: { attachment: string; max_rows?: number }
        Returns: Json
      }
      list_file_comments: {
        Args: { attachment: string; max_rows?: number }
        Returns: Json
      }
      list_flag_segments: { Args: Record<PropertyKey, never>; Returns: Json }
      list_flags: { Args: Record<PropertyKey, never>; Returns: Json }
      list_form_submissions: {
        Args: {
          before?: string
          form_id: string
          page_size?: number
          status?: string
        }
        Returns: Json
      }
      list_forms: { Args: { status?: string; tenant: string }; Returns: Json }
      list_funding_awards: {
        Args: {
          include_ended?: boolean
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      list_funding_claims: {
        Args: { funder_id?: string; status?: string; tenant: string }
        Returns: Json
      }
      list_funding_deliveries: {
        Args: { filter?: Json; tenant: string }
        Returns: Json
      }
      list_funding_products: {
        Args: { include_expired?: boolean; tenant: string }
        Returns: Json
      }
      list_gifts: {
        Args: {
          donor_id?: string
          donor_type?: string
          fund_id?: string
          page_size?: number
          pledge_id?: string
          status?: string
          tenant: string
        }
        Returns: Json
      }
      list_guest_grants: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      list_guests: {
        Args: {
          before?: string
          page_size?: number
          status?: string
          tenant: string
        }
        Returns: Json
      }
      list_import_runs: {
        Args: {
          row_limit?: number
          source?: string
          status?: string
          tenant: string
        }
        Returns: Json[]
      }
      list_inbox_conversations: {
        Args: { filter?: Json; tenant?: string }
        Returns: Json
      }
      list_inbox_drafts: { Args: { conversation?: string }; Returns: Json }
      list_inbox_messages: {
        Args: {
          after?: string
          before?: string
          conversation: string
          max?: number
        }
        Returns: Json
      }
      list_incident_filings: {
        Args: { pending?: boolean; tenant: string }
        Returns: Json
      }
      list_incidents: {
        Args: {
          before?: string
          component_id?: string
          page_size?: number
          severity?: string
          status?: string
          tenant: string
        }
        Returns: Json
      }
      list_inspection_programs: { Args: { tenant: string }; Returns: Json }
      list_inspections: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_invite_codes: { Args: { tenant?: string }; Returns: Json }
      list_invoice_allocations: {
        Args: { invoice_id?: string; reference?: string; tenant: string }
        Returns: Json
      }
      list_invoice_approval_levels: { Args: { tenant: string }; Returns: Json }
      list_invoice_dunning_history: { Args: { invoice: string }; Returns: Json }
      list_invoice_dunning_levels: { Args: { tenant: string }; Returns: Json }
      list_invoice_dunning_run_items: { Args: { run: string }; Returns: Json }
      list_invoice_dunning_runs: {
        Args: { max?: number; tenant: string }
        Returns: Json
      }
      list_invoice_payments: { Args: { invoice: string }; Returns: Json }
      list_invoiced_time: {
        Args: { invoice: string; page_size?: number }
        Returns: Json
      }
      list_jobs:
        | { Args: { tenant: string }; Returns: Json }
        | { Args: { status?: string; tenant: string }; Returns: Json }
      list_knowledge_collection_grants: {
        Args: { collection_id: string }
        Returns: Json
      }
      list_knowledge_collections: { Args: { tenant: string }; Returns: Json }
      list_knowledge_documents: {
        Args: {
          collection_id?: string
          max_rows?: number
          scope?: string
          scope_id?: string
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      list_lease_charges: {
        Args: { lease_id: string; page_size?: number }
        Returns: Json
      }
      list_leases: {
        Args: {
          page_size?: number
          party_id?: string
          party_type?: string
          status?: string
          tenant: string
          unit_id?: string
        }
        Returns: Json
      }
      list_legal_entities: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_legal_holds: { Args: { include_released?: boolean }; Returns: Json }
      list_lims_methods: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_mail_threads: {
        Args: {
          account: string
          before: string
          page_size: number
          tenant: string
        }
        Returns: Json
      }
      list_maintenance_meters: { Args: { tenant: string }; Returns: Json }
      list_maintenance_plans: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_maintenance_request_checklist: {
        Args: { work_item: string }
        Returns: Json
      }
      list_maintenance_request_watchers: {
        Args: { work_item: string }
        Returns: Json
      }
      list_maintenance_requests: {
        Args: {
          after: string
          filter: Json
          page_size: number
          search: string
          tenant: string
        }
        Returns: Json
      }
      list_medications: {
        Args: { include_archived?: boolean; search?: string; tenant: string }
        Returns: Json
      }
      list_meetings: { Args: { filters?: Json; tenant: string }; Returns: Json }
      list_members: {
        Args: { organization: string }
        Returns: {
          role: string
          user_id: string
        }[]
      }
      list_message_edits: { Args: { message: string }; Returns: Json }
      list_messages: {
        Args: {
          after?: string
          after_id?: string
          before?: string
          before_id?: string
          conversation: string
          max_rows?: number
        }
        Returns: Json
      }
      list_my_acknowledgements: {
        Args: { pending_only?: boolean; tenant: string }
        Returns: Json
      }
      list_my_organizations: {
        Args: Record<PropertyKey, never>
        Returns: {
          id: string
          name: string
          role: string
          slug: string
        }[]
      }
      list_my_reminders: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: Json
      }
      list_my_sessions: { Args: Record<PropertyKey, never>; Returns: Json }
      list_notices: {
        Args: { page_size?: number; status?: string; tenant: string }
        Returns: Json
      }
      list_notification_preferences: {
        Args: { tenant?: string }
        Returns: Json
      }
      list_notification_subscriptions: {
        Args: { subject_id?: string; subject_type?: string; tenant?: string }
        Returns: Json
      }
      list_notification_suppressions: {
        Args: { max_items?: number }
        Returns: Json
      }
      list_notifications: {
        Args: {
          before?: string
          before_id?: string
          dismissed?: boolean
          max_items?: number
          read?: boolean
          resolved?: boolean
          search?: string
          status?: string
          subject_types?: string[]
          tenant?: string
          types?: string[]
        }
        Returns: Json
      }
      list_observation_definitions: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_observations: {
        Args: {
          definition_key?: string
          include_all?: boolean
          max_rows?: number
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      list_order_variants: { Args: { id: string }; Returns: Json }
      list_organization_domains: { Args: { tenant: string }; Returns: Json }
      list_organization_invitations: {
        Args: { organization: string }
        Returns: {
          email: string
          expires_at: string
          id: string
          role: string
        }[]
      }
      list_party_credits: {
        Args: { party_id: string; tenant: string }
        Returns: Json
      }
      list_pass_check_ins: {
        Args: { before?: string; page_size?: number; pass_id: string }
        Returns: Json
      }
      list_pass_credits: { Args: { pass_id: string }; Returns: Json }
      list_passes: {
        Args: {
          before?: string
          holder_user?: string
          page_size?: number
          status?: string
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      list_payment_batches: {
        Args: { page_size?: number; status?: string; tenant: string }
        Returns: Json
      }
      list_payment_terms: { Args: { tenant: string }; Returns: Json }
      list_payroll_runs: { Args: { tenant: string }; Returns: Json }
      list_pending_ai_tool_approvals: { Args: { size?: number }; Returns: Json }
      list_people: {
        Args: {
          after_id: string
          after_name: string
          lifecycle: string
          owner: string
          page_size: number
          role?: string
          search: string
          supplier_status?: string
          tenant: string
        }
        Returns: Json
      }
      list_periods: { Args: { filters?: Json; tenant: string }; Returns: Json }
      list_person_identities: { Args: { person: string }; Returns: Json }
      list_pick_lists: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_pick_waves: { Args: { tenant: string }; Returns: Json }
      list_pinned_messages: { Args: { conversation: string }; Returns: Json }
      list_pipelines: {
        Args: { subject_type: string; tenant: string }
        Returns: Json
      }
      list_pledges: {
        Args: {
          donor_id?: string
          donor_type?: string
          page_size?: number
          status?: string
          tenant: string
        }
        Returns: Json
      }
      list_post_boards: {
        Args: { archived?: boolean; tenant: string }
        Returns: Json
      }
      list_posts: { Args: { filter?: Json; tenant: string }; Returns: Json }
      list_prescriptions: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_production_orders: {
        Args: { filter?: Json; tenant: string }
        Returns: Json
      }
      list_putaway_rules: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_qualification_requirements: {
        Args: { type_id: string }
        Returns: Json
      }
      list_qualification_types: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_quote_variants: { Args: { quote: string }; Returns: Json }
      list_quotes: {
        Args: { page_size: number; tenant: string }
        Returns: Json
      }
      list_record_access_requests: {
        Args: {
          page_size?: number
          status?: string
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      list_record_mentions: {
        Args: {
          before?: string
          before_id?: string
          max_rows?: number
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      list_referral_codes: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_referrals: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_reminder_schedule: {
        Args: Record<PropertyKey, never>
        Returns: {
          dtstart: string
          offset_minutes: number
          reminder: string
          rrule: string
          subject_id: string
          subject_type: string
          tenant: string
          tzid: string
          user_id: string
        }[]
      }
      list_renditions: {
        Args: { node_id: string; tenant: string }
        Returns: Json
      }
      list_replies: {
        Args: {
          after?: string
          after_id?: string
          max_rows?: number
          message: string
        }
        Returns: Json
      }
      list_representatives: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      list_retention_policies: { Args: { kind?: string }; Returns: Json }
      list_rfqs: { Args: { filters?: Json; tenant: string }; Returns: Json }
      list_risk_matrices: { Args: { tenant: string }; Returns: Json }
      list_risks: { Args: { filters?: Json; tenant: string }; Returns: Json }
      list_roles: { Args: { tenant: string }; Returns: Json }
      list_samples: { Args: { filters?: Json; tenant: string }; Returns: Json }
      list_scheduled_inbox_messages: {
        Args: { conversation?: string }
        Returns: Json
      }
      list_score_models: {
        Args: { subject_type?: string; tenant: string }
        Returns: Json
      }
      list_segment_members: {
        Args: { after?: string; max_count?: number; segment: string }
        Returns: Json
      }
      list_sequence_enrollments: {
        Args: { filter?: Json; tenant: string }
        Returns: Json
      }
      list_sequences: {
        Args: { status?: string; tenant: string }
        Returns: Json
      }
      list_share_links: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      list_shift_availability: {
        Args: {
          from_date: string
          tenant: string
          until_date: string
          user_id?: string
        }
        Returns: Json
      }
      list_shift_templates: {
        Args: { include_archived?: boolean; tenant: string }
        Returns: Json
      }
      list_shipments: {
        Args: {
          before?: string
          carrier?: string
          page_size?: number
          status?: string
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      list_signature_requests: {
        Args: {
          before?: string
          mine?: boolean
          page_size?: number
          status?: string
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      list_sso_providers: { Args: { tenant: string }; Returns: Json }
      list_statements: { Args: { item_id: string }; Returns: Json }
      list_status_components: { Args: { tenant: string }; Returns: Json }
      list_status_history: {
        Args: {
          before?: string
          max_rows?: number
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      list_status_stages: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      list_subject_deliveries: {
        Args: {
          max_items?: number
          subject_id: string
          subject_type: string
          tenant?: string
        }
        Returns: Json
      }
      list_subject_members: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      list_tags: { Args: { kind?: string; tenant: string }; Returns: Json }
      list_teams: { Args: { tenant: string }; Returns: Json }
      list_template_schedule: {
        Args: Record<PropertyKey, never>
        Returns: Json
      }
      list_till_sessions: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_tills: { Args: { filters?: Json; tenant: string }; Returns: Json }
      list_time_entries: {
        Args: {
          ends?: string
          everyone?: boolean
          page_size?: number
          starts?: string
          subject_id?: string
          subject_type?: string
          tenant: string
          user_id?: string
        }
        Returns: Json
      }
      list_time_rates: {
        Args: {
          page_size?: number
          subject_id?: string
          subject_type?: string
          tenant: string
          user_id?: string
        }
        Returns: Json
      }
      list_timesheets: {
        Args: {
          before?: string
          page_size?: number
          status?: string
          tenant: string
          user_id?: string
        }
        Returns: Json
      }
      list_tracking_events: { Args: { shipment_id: string }; Returns: Json }
      list_trash: {
        Args: {
          before?: string
          page_size?: number
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      list_usage_rights: {
        Args: { filters?: Json; tenant: string }
        Returns: Json
      }
      list_versions: {
        Args: {
          before?: number
          page_size?: number
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      list_views: { Args: { list: string; tenant: string }; Returns: Json }
      list_waitlist: {
        Args: { after_position?: number; page_size?: number; status?: string }
        Returns: Json
      }
      list_webhook_endpoints: { Args: { tenant: string }; Returns: Json }
      list_work_centers: { Args: { tenant: string }; Returns: Json }
      list_work_item_checklist: { Args: { work_item: string }; Returns: Json }
      list_work_item_watchers: { Args: { work_item: string }; Returns: Json }
      list_work_items: {
        Args: {
          after: string
          filter: Json
          page_size: number
          search: string
          tenant: string
        }
        Returns: Json
      }
      list_work_order_parts: { Args: { work_order_id: string }; Returns: Json }
      list_work_orders: {
        Args: {
          before?: string
          from_at?: string
          page_size?: number
          status?: string
          subject_id?: string
          subject_type?: string
          technician?: string
          tenant: string
          until_at?: string
        }
        Returns: Json
      }
      load_ai_harness_session: {
        Args: { chat: string; harness: string }
        Returns: Json
      }
      lock_accounting_period: { Args: { period_id: string }; Returns: Json }
      lock_ai_harness_session: {
        Args: {
          chat: string
          harness: string
          holder: string
          ttl_seconds?: number
        }
        Returns: boolean
      }
      lock_period: { Args: { period_id: string }; Returns: Json }
      log_activity: {
        Args: { attrs: Json; subjects: Json; tenant: string }
        Returns: Json
      }
      log_time: {
        Args: {
          billable?: boolean
          ended_at: string
          note?: string
          rate?: number
          rate_currency?: string
          started_at: string
          subject_id?: string
          subject_type?: string
          tenant: string
          user_id?: string
        }
        Returns: Json
      }
      lot_genealogy: {
        Args: { direction?: string; lot_id: string }
        Returns: Json
      }
      lot_recall: { Args: { lot_id: string }; Returns: Json }
      mail_accounts_of: { Args: { tenant: string }; Returns: Json }
      mail_template_stats: {
        Args: { since: string; tenant: string }
        Returns: Json
      }
      mail_thread_visible: { Args: { thread: string }; Returns: boolean }
      mail_threads_of: {
        Args: {
          before: string
          page_size: number
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      maintenance_next_occurrence: {
        Args: { after: string; dtstart: string; rrule: string; tz: string }
        Returns: string
      }
      maintenance_request_tree: { Args: { root: string }; Returns: Json }
      mark_activity_error: {
        Args: { engagement: string; reason: string }
        Returns: Json
      }
      mark_attachment_missing: { Args: { id: string }; Returns: Json }
      mark_conversation_read: {
        Args: { conversation: string }
        Returns: string
      }
      mark_funding_claim_sent: {
        Args: {
          claim_id: string
          external_ref?: string
          payload_sha256?: string
        }
        Returns: Json
      }
      mark_import_running: { Args: { id: string }; Returns: boolean }
      mark_missed_medication_administrations: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      mark_notifications_read: {
        Args: { ids?: string[]; tenant?: string }
        Returns: Json
      }
      mark_notifications_unread: {
        Args: { ids: string[]; tenant?: string }
        Returns: Json
      }
      mark_observation_error: {
        Args: { observation_id: string; reason: string }
        Returns: Json
      }
      mark_payroll_run_exported: {
        Args: { checksum: string; format: string; run_id: string }
        Returns: Json
      }
      mark_read: {
        Args: { conversation: string; read_at?: string; thread?: string }
        Returns: string
      }
      mark_reminder_sent: {
        Args: { occurrence_at: string; reminder: string }
        Returns: boolean
      }
      mark_usage_reported: {
        Args: { day: string; meter: string; tenant: string; value: number }
        Returns: boolean
      }
      mark_used: { Args: { organization: string }; Returns: boolean }
      mark_workflow_start_request: {
        Args: { request: string; run: string }
        Returns: boolean
      }
      match_bank_transaction: {
        Args: { matches: Json; transaction_id: string }
        Returns: Json
      }
      matching_rules: {
        Args: {
          subject: Json
          subject_type: string
          tenant: string
          time_zone?: string
          trigger: string
        }
        Returns: Json
      }
      material_requirements: {
        Args: { horizon_days?: number; tenant: string }
        Returns: Json
      }
      medication_chart: {
        Args: {
          since?: string
          subject_id: string
          subject_type: string
          until?: string
        }
        Returns: Json
      }
      medication_orders_of: {
        Args: {
          include_stopped?: boolean
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      meeting_role: { Args: { meeting_id: string }; Returns: string }
      meeting_set_attendees: {
        Args: { meeting_id: string; team: Json; tenant: string }
        Returns: undefined
      }
      member_can: {
        Args: { member: string; permission: string; tenant: string }
        Returns: boolean
      }
      member_can_while_deleting: {
        Args: { member: string; permission: string; tenant: string }
        Returns: boolean
      }
      member_permissions: {
        Args: { member: string; tenant: string }
        Returns: string[]
      }
      memory_create: {
        Args: {
          content: string
          expected_version?: number
          ns?: Json
          path: string
          tenant: string
        }
        Returns: Json
      }
      memory_delete: {
        Args: { ns?: Json; path: string; tenant: string }
        Returns: number
      }
      memory_document_read: {
        Args: { path: string; scope_key: string }
        Returns: Json
      }
      memory_document_write: {
        Args: {
          content: string
          expected_version?: string
          expires_in?: number
          path: string
          scope_key: string
        }
        Returns: Json
      }
      memory_forget: {
        Args: { memory_id: string; superseded_by?: string }
        Returns: boolean
      }
      memory_insert: {
        Args: {
          insert_line: number
          insert_text: string
          ns?: Json
          path: string
          tenant: string
        }
        Returns: Json
      }
      memory_list: {
        Args: { kind?: string; max_rows?: number; ns?: Json; tenant: string }
        Returns: Json
      }
      memory_rename: {
        Args: { new_path: string; ns?: Json; old_path: string; tenant: string }
        Returns: number
      }
      memory_restore: { Args: { memory_id: string }; Returns: boolean }
      memory_save: {
        Args: {
          category?: string
          confidence?: number
          content: string
          embedding?: string
          expires_at?: string
          model?: string
          ns?: Json
          source_message_id?: string
          tenant: string
        }
        Returns: Json
      }
      memory_search: {
        Args: {
          k?: number
          ns?: Json
          query_embedding?: string
          query_text?: string
          tenant: string
        }
        Returns: Json
      }
      memory_str_replace: {
        Args: {
          new_text: string
          ns?: Json
          old_text: string
          path: string
          tenant: string
        }
        Returns: Json
      }
      memory_view: {
        Args: { ns?: Json; path?: string; tenant: string }
        Returns: Json
      }
      merge_carts: {
        Args: { from_user: string; to_user: string }
        Returns: number
      }
      merge_companies: { Args: { drop: string; keep: string }; Returns: Json }
      merge_people: { Args: { drop: string; keep: string }; Returns: Json }
      merge_posts: {
        Args: { source_id: string; target_id: string }
        Returns: Json
      }
      messaging_file_anchor_valid: { Args: { anchor: Json }; Returns: boolean }
      metric_definitions: { Args: Record<PropertyKey, never>; Returns: Json }
      metric_series: {
        Args: {
          p_dims?: Json
          p_from: string
          p_grain?: string
          p_group_by?: string
          p_metric: string
          p_tenant: string
          p_until: string
        }
        Returns: Json
      }
      metric_value: {
        Args: {
          p_dims?: Json
          p_from: string
          p_metric: string
          p_tenant: string
          p_until: string
        }
        Returns: Json
      }
      metrics_rollup: {
        Args: { p_metric?: string; p_since?: string; p_until?: string }
        Returns: number
      }
      moderate: {
        Args: { action: string; item_id: string; reason?: string }
        Returns: Json
      }
      moderation_hidden: {
        Args: { subject_id: string; subject_type: string }
        Returns: boolean
      }
      moderation_item: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: Json
      }
      moderation_queue: {
        Args: {
          before?: string
          page_size?: number
          status?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      moderation_statuses: {
        Args: { subject_ids: string[]; subject_type: string; tenant: string }
        Returns: Json
      }
      move: {
        Args: {
          next_id: string
          previous_id: string
          subject_id: string
          subject_type: string
          to_group: string
        }
        Returns: string
      }
      move_booking: {
        Args: { booking: string; starts_at: string }
        Returns: Json
      }
      move_category: {
        Args: { category: string; parent: string; rank: string }
        Returns: boolean
      }
      my_guest_access: { Args: Record<PropertyKey, never>; Returns: Json }
      my_invitations: { Args: Record<PropertyKey, never>; Returns: Json }
      my_passes: { Args: Record<PropertyKey, never>; Returns: Json }
      my_permissions: {
        Args: { keys?: string[]; tenant: string }
        Returns: string[]
      }
      my_profile: { Args: Record<PropertyKey, never>; Returns: Json }
      my_reminders_due: {
        Args: { tenant?: string }
        Returns: {
          at: string
          reminder: string
          subject_id: string
          subject_type: string
        }[]
      }
      my_shifts: { Args: { since?: string; until?: string }; Returns: Json }
      my_subjects: {
        Args: {
          cursor?: string
          page_size?: number
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      my_work: { Args: { page_size?: number; tenant?: string }; Returns: Json }
      name_document_version: {
        Args: { document_id: string; label: string; version_id: string }
        Returns: boolean
      }
      next_activity: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      note_signing_key_exp: {
        Args: { exp: string; kid: string }
        Returns: boolean
      }
      notification_actors: { Args: { ids: string[] }; Returns: Json }
      notification_cadence: {
        Args: { channel: string; member: string; tenant: string; type: string }
        Returns: string
      }
      notification_counts: {
        Args: { actionable?: string[]; tenant?: string }
        Returns: Json
      }
      notification_enabled: {
        Args: { channel: string; member: string; tenant: string; type: string }
        Returns: boolean
      }
      notification_page: {
        Args: {
          dismissed?: boolean
          max_items?: number
          read?: boolean
          resolved?: boolean
          search?: string
          skip?: number
          status?: string
          subject_types?: string[]
          tenant?: string
          types?: string[]
        }
        Returns: Json
      }
      notify: { Args: { notification: Json }; Returns: string }
      notify_due_acknowledgements: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      notify_due_case_effectiveness: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      notify_due_drive_reviews: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      notify_due_risk_reviews: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      notify_expiring_qualifications: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      notify_expiring_usage_rights: { Args: { days?: number }; Returns: number }
      notify_overdue_evidence_tasks: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      notify_overdue_inspections: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      object_scan: { Args: { bucket: string; path: string }; Returns: Json }
      observation_series: {
        Args: {
          bucket?: string
          definition_key: string
          since?: string
          subject_id: string
          subject_type: string
          until?: string
        }
        Returns: Json
      }
      observations_from_submission: {
        Args: { submission_id: string }
        Returns: Json
      }
      offboard_employee: {
        Args: { employee: string; end_date: string; reason: string }
        Returns: Json
      }
      onboarding_progress: {
        Args: { checklist: string; tenant?: string }
        Returns: Json
      }
      open_activities: {
        Args: {
          due_before: string
          owner: string
          page_size: number
          tenant: string
        }
        Returns: Json
      }
      open_ai_pending_input: {
        Args: { chat: string; input: Json }
        Returns: Json
      }
      open_appraisal_cycle: {
        Args: { assignments?: Json; cycle_id: string }
        Returns: Json
      }
      open_case: {
        Args: {
          description?: string
          due_on?: string
          fields?: Json
          kind: string
          occurred_at?: string
          owner_id?: string
          severity?: string
          source?: string
          tenant: string
          title: string
        }
        Returns: Json
      }
      open_case_as: {
        Args: { input: Json; kind_id: string; reporter?: string }
        Returns: unknown
        SetofOptions: {
          from: "*"
          to: "cases"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      open_conversation: {
        Args: { attrs?: Json; kind: string; members?: string[]; tenant: string }
        Returns: Json
      }
      open_data_subject_request: {
        Args: {
          details?: string
          kind: string
          requester: string
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      open_document: {
        Args: {
          name?: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      open_emergency_access: {
        Args: { reason: string; subject_id: string; subject_type: string }
        Returns: Json
      }
      open_enrollment_steps: {
        Args: {
          assignee_role?: string
          assignee_user?: string
          due_before?: string
          page_size?: number
          tenant: string
        }
        Returns: Json
      }
      open_fiscal_year: {
        Args: { fiscal_year: number; tenant: string }
        Returns: Json
      }
      open_gift: {
        Args: {
          amount: number
          currency: string
          donor_id: string
          donor_type: string
          fund_id?: string
          note?: string
          period_start?: string
          pledge_id?: string
          provider?: string
          tenant: string
        }
        Returns: Json
      }
      open_incident: { Args: { attrs: Json; tenant: string }; Returns: Json }
      open_item_ageing: {
        Args: { as_of?: string; side?: string; tenant: string }
        Returns: Json
      }
      open_items_for_party: {
        Args: {
          as_of?: string
          party_id?: string
          side?: string
          tenant: string
        }
        Returns: Json
      }
      open_rfq: { Args: { rfq_id: string }; Returns: Json }
      open_stock_count: {
        Args: { attrs?: Json; location: string; tenant: string }
        Returns: Json
      }
      open_till_session: {
        Args: { notes?: string; opening_float?: number; till_id: string }
        Returns: Json
      }
      operation_permission: { Args: { op: string }; Returns: string }
      order_board: {
        Args: { page_size: number; since: string; tenant: string }
        Returns: Json
      }
      order_from_lines: {
        Args: { attrs?: Json; lines: Json; tenant: string }
        Returns: Json
      }
      order_from_quote: { Args: { attrs?: Json; quote: string }; Returns: Json }
      order_status_board: {
        Args: { per_status?: number; tenant: string }
        Returns: Json
      }
      order_updated_at: { Args: { subject_id: string }; Returns: string }
      org_chart: { Args: { root: string; tenant: string }; Returns: Json }
      organization_credential_refs: { Args: { tenant: string }; Returns: Json }
      organization_deletion: { Args: { tenant: string }; Returns: Json }
      organization_domain: { Args: { id: string }; Returns: Json }
      organization_overview: { Args: { organization: string }; Returns: Json }
      organization_setting: {
        Args: { key: string; tenant: string }
        Returns: Json
      }
      organization_slug_problem: {
        Args: { except_organization?: string; value: string }
        Returns: string
      }
      outbox_ack: {
        Args: { consumer: string; owner: string; upto?: number }
        Returns: boolean
      }
      outbox_claim: {
        Args: {
          consumer: string
          lease?: string
          max_events?: number
          owner: string
        }
        Returns: Json
      }
      outbox_dead_letters: {
        Args: { consumer: string; max_rows?: number }
        Returns: Json
      }
      outbox_fail: {
        Args: {
          consumer: string
          error?: string
          failed?: number
          max_attempts?: number
          max_backoff?: string
          owner: string
        }
        Returns: string
      }
      outbox_history: {
        Args: {
          after?: number
          event_type?: string
          max_events?: number
          subject?: string
        }
        Returns: Json
      }
      outbox_register: {
        Args: { consumer: string; from_start?: boolean; types?: string[] }
        Returns: number
      }
      outbox_unregister: { Args: { consumer: string }; Returns: boolean }
      pass_occupancy: { Args: { resource_id: string }; Returns: Json }
      pause_enrollment: { Args: { enrollment_id: string }; Returns: Json }
      pause_invoice_dunning: {
        Args: { invoice: string; reason?: string; until: string }
        Returns: Json
      }
      pause_lifecycle: {
        Args: {
          reason: string
          subject_id: string
          subject_type: string
          until: string
        }
        Returns: boolean
      }
      pause_medication_order: {
        Args: { order_id: string; paused?: boolean }
        Returns: Json
      }
      pause_workflow_schedule: {
        Args: { paused?: boolean; schedule: string }
        Returns: boolean
      }
      pay_commission_statement: {
        Args: { statement_id: string }
        Returns: Json
      }
      payment_term_updated_at: { Args: { subject_id: string }; Returns: string }
      pending_activity_recordings: {
        Args: { batch: number }
        Returns: string[]
      }
      pending_inbound_events: {
        Args: { max?: number; max_attempts?: number }
        Returns: Json
      }
      pending_inbox_files: { Args: { max?: number }; Returns: Json }
      pending_knowledge_chunks: {
        Args: { batch?: number; document_id: string }
        Returns: Json
      }
      pending_knowledge_documents: { Args: { batch?: number }; Returns: Json }
      pending_memory_embeddings: { Args: { batch?: number }; Returns: Json }
      period_close_blockers: { Args: { period_id: string }; Returns: string[] }
      period_for: {
        Args: { kind: string; on_date: string; tenant: string }
        Returns: Json
      }
      period_is_open: {
        Args: { kind: string; on_date: string; tenant: string }
        Returns: boolean
      }
      permission_claims:
        | { Args: { user_id: string }; Returns: Json }
        | { Args: { tenant: string; user_id: string }; Returns: Json }
      permission_matches: {
        Args: { granted: string; wanted: string }
        Returns: boolean
      }
      pin_message: {
        Args: { message: string; pinned?: boolean }
        Returns: Json
      }
      pipeline_board: {
        Args: { owner?: string; pipeline: string; subject_type: string }
        Returns: Json
      }
      pipeline_health: { Args: { pipeline: string }; Returns: Json }
      pipeline_stats: {
        Args: { pipeline: string; since: string; until: string }
        Returns: Json
      }
      place_booking: {
        Args: {
          confirm: boolean
          customer: Json
          customer_user: string
          resource: string
          service: string
          starts_at: string
        }
        Returns: Json
      }
      place_legal_hold: {
        Args: { kind?: string; reason: string; tenant?: string }
        Returns: Json
      }
      place_order: {
        Args: {
          cart: string
          expected_total?: number
          location?: string
          tax?: Json
        }
        Returns: Json
      }
      place_purchase_order: {
        Args: { purchase_order: string }
        Returns: boolean
      }
      plan_dispatch_route: {
        Args: {
          route_date: string
          technician: string
          tenant: string
          work_orders: string[]
        }
        Returns: Json
      }
      plan_medication_administrations: {
        Args: { tenant: string; until: string }
        Returns: number
      }
      platform_can: {
        Args: { member: string; permission: string }
        Returns: boolean
      }
      platform_can_assign: {
        Args: { member: string; role: string }
        Returns: boolean
      }
      portal_parties: {
        Args: Record<PropertyKey, never>
        Returns: {
          party_id: string
          party_type: string
          tenant: string
        }[]
      }
      portal_quote: { Args: { actor?: Json; quote: string }; Returns: Json }
      portal_subjects: {
        Args: { action: string }
        Returns: {
          subject_id: string
          subject_type: string
          tenant: string
        }[]
      }
      post_accounting_entry: { Args: { entry_id: string }; Returns: Json }
      post_accounting_opening_balances: {
        Args: { fiscal_year: number; journal_id?: string; tenant: string }
        Returns: Json
      }
      post_accounting_source: {
        Args: { source_id: string; source_type: string }
        Returns: Json
      }
      post_cycle_count: {
        Args: { approve?: boolean; count_id: string }
        Returns: Json
      }
      post_due_rent: {
        Args: { max_rows?: number; tenant?: string; through?: string }
        Returns: number
      }
      post_incident_update: {
        Args: {
          body: string
          incident_id: string
          is_public?: boolean
          status: string
        }
        Returns: Json
      }
      post_payment_batch: { Args: { batch_id: string }; Returns: Json }
      post_stock_count: { Args: { count: string }; Returns: Json }
      prepare_intrastat: {
        Args: { period: string; tenant: string }
        Returns: Json
      }
      prescribe_medication: {
        Args: {
          attrs: Json
          medication_id: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      price_cart: { Args: { cart: string }; Returns: Json }
      product_identifier_updated_at: {
        Args: { subject_id: string }
        Returns: string
      }
      product_media: {
        Args: { locale?: string; product: string }
        Returns: Json
      }
      product_text: {
        Args: { locale?: string; product: string }
        Returns: Json
      }
      project_costs: { Args: { project_id: string }; Returns: Json }
      promote_supplier_item: {
        Args: { item: string; sku?: string }
        Returns: Json
      }
      prune_push_tokens: { Args: { tokens: string[] }; Returns: number }
      public_available_slots: {
        Args: {
          range_end: string
          range_start: string
          token: string
          tz?: string
        }
        Returns: Json
      }
      public_booking_service: { Args: { token: string }; Returns: Json }
      public_change_booking: {
        Args: { access_token: string; booking: string; to_status: string }
        Returns: Json
      }
      public_content_entries: {
        Args: {
          before?: string
          locale?: string
          page_size?: number
          tenant: string
          type?: string
        }
        Returns: Json
      }
      public_content_entry: {
        Args: { locale?: string; slug: string; tenant: string; type: string }
        Returns: Json
      }
      public_hold_booking: {
        Args: {
          customer: Json
          resource: string
          starts_at: string
          token: string
        }
        Returns: Json
      }
      public_quote: { Args: { token: string }; Returns: Json }
      public_status_page: {
        Args: { days?: number; slug: string }
        Returns: Json
      }
      publish_agent: { Args: { id: string; visibility: string }; Returns: Json }
      publish_care_plan: { Args: { plan_id: string }; Returns: Json }
      publish_compliance_policy: {
        Args: { content: Json; label?: string; policy_id: string }
        Returns: Json
      }
      publish_content_entry: { Args: { entry_id: string }; Returns: Json }
      publish_due_content_entries: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      publish_due_inbox_messages: {
        Args: { max_rows?: number }
        Returns: number
      }
      publish_due_messages: { Args: { max_rows?: number }; Returns: number }
      publish_form_version: {
        Args: { definition: Json; form_id: string }
        Returns: Json
      }
      publish_incident_postmortem: {
        Args: { incident_id: string }
        Returns: Json
      }
      publish_shifts: {
        Args: {
          from_date: string
          team_id?: string
          tenant: string
          until_date: string
        }
        Returns: number
      }
      publish_storefront: {
        Args: { published: boolean; tenant: string }
        Returns: boolean
      }
      publish_template_version: { Args: { template_id: string }; Returns: Json }
      publish_webhook_event: {
        Args: {
          event_id?: string
          event_type: string
          payload: Json
          read_permission?: string
          subject?: string
          tenant?: string
        }
        Returns: number
      }
      publish_webhook_events: { Args: { events: Json }; Returns: Json }
      publish_workflow_version: {
        Args: { compiled?: Json; version: string }
        Returns: Json
      }
      pull_document_updates: {
        Args: { after_seq: number; document_id: string }
        Returns: Json
      }
      purchase_bill_match: { Args: { invoice: string }; Returns: Json }
      purchase_invoice_approval_status: {
        Args: { invoice: string }
        Returns: Json
      }
      purchase_order_from_order: {
        Args: {
          location?: string
          order_id: string
          supplier_id: string
          supplier_type?: string
        }
        Returns: Json
      }
      purchase_order_from_requisitions: {
        Args: {
          currency?: string
          requisitions: string[]
          supplier_id?: string
          supplier_type?: string
        }
        Returns: Json
      }
      purge_ai_cache: { Args: { batch?: number }; Returns: number }
      purge_ai_chats: { Args: { batch?: number }; Returns: number }
      purge_ai_files: {
        Args: { batch?: number; older_than?: string }
        Returns: Json
      }
      purge_audit_log: {
        Args: {
          batch?: number
          for_tenant?: boolean
          older_than?: string
          tenant?: string
        }
        Returns: number
      }
      purge_connector_sessions: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      purge_contact: { Args: { contact: string }; Returns: Json }
      purge_expired_trash: { Args: { max_batches?: number }; Returns: number }
      purge_inbound_events: {
        Args: { batch?: number; older_than?: string }
        Returns: number
      }
      purge_memories: {
        Args: { batch?: number; retention_days?: number; tenant?: string }
        Returns: number
      }
      purge_memory_documents: { Args: { batch?: number }; Returns: number }
      purge_notifications: {
        Args: { batch?: number; older_than?: string }
        Returns: number
      }
      purge_organization: { Args: { tenant: string }; Returns: Json }
      purge_outbox: {
        Args: { batch?: number; ignore_idle?: string; older_than?: string }
        Returns: number
      }
      purge_signing_keys: { Args: { grace?: string }; Returns: number }
      purge_streams: {
        Args: { batch?: number; older_than?: string }
        Returns: number
      }
      purge_trash: { Args: { item_id: string }; Returns: number }
      purge_usage_events: {
        Args: { batch?: number; older_than?: string }
        Returns: number
      }
      purge_usage_history: {
        Args: { batch?: number; older_than?: string }
        Returns: number
      }
      purge_webhook_deliveries: {
        Args: { batch?: number; include_dead?: boolean; older_than?: string }
        Returns: number
      }
      purge_workflow_runs: {
        Args: { batch?: number; older_than?: string }
        Returns: number
      }
      push_document_update: {
        Args: { document_id: string; payload: string }
        Returns: number
      }
      push_tickets_for: { Args: { delivery: string }; Returns: Json }
      push_tokens_for: { Args: { users: string[] }; Returns: Json }
      qualification_gaps: {
        Args: { filters?: Json; holder_type?: string; tenant: string }
        Returns: Json
      }
      qualifications_of: {
        Args: { holder_id: string; holder_type: string }
        Returns: Json
      }
      qualified_holders: {
        Args: {
          holder_type?: string
          on_date?: string
          tenant: string
          type_key: string
        }
        Returns: Json
      }
      qualify_referral: {
        Args: {
          referred_org?: string
          referred_user?: string
          source?: string
          tenant: string
        }
        Returns: Json
      }
      queue_knowledge_file: {
        Args: {
          file_id: string
          metadata?: Json
          owner?: string
          scope?: string
          scope_id?: string
          source?: string
          tenant: string
          title?: string
        }
        Returns: Json
      }
      quote_from_deal: { Args: { deal: string }; Returns: Json }
      quote_totals_by_billing_party: { Args: { quote: string }; Returns: Json }
      quote_updated_at: { Args: { subject_id: string }; Returns: string }
      quote_version: {
        Args: { quote: string; revision: number }
        Returns: Json
      }
      quote_versions: { Args: { quote: string }; Returns: Json }
      raise_actor_readonly: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      raise_inspection_finding_case: {
        Args: { finding_id: string; kind?: string; owner_id?: string }
        Returns: Json
      }
      rank_between: {
        Args: { next: string; previous: string }
        Returns: string
      }
      rank_field_definition: {
        Args: { definition: string; rank: string }
        Returns: boolean
      }
      rank_key: { Args: { nth: number; total: number }; Returns: string }
      rank_pipeline_stage: {
        Args: { rank: string; stage: string }
        Returns: boolean
      }
      rank_rule: { Args: { id: string; rank: string }; Returns: Json }
      rank_tag: { Args: { rank: string; tag_id: string }; Returns: boolean }
      rank_variant: {
        Args: { rank: string; variant: string }
        Returns: boolean
      }
      rank_view: { Args: { rank: string; view_id: string }; Returns: boolean }
      rate_agent: {
        Args: { agent_id: string; comment?: string; rating: number }
        Returns: Json
      }
      rate_ai_message: {
        Args: {
          chat: string
          comment?: string
          message_id: string
          rating: number
          reason?: string
        }
        Returns: Json
      }
      react: {
        Args: {
          actor?: string
          emoji: string
          present?: boolean
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      react_to_inbox_message: {
        Args: {
          actor?: string
          emoji: string
          message: string
          present?: boolean
        }
        Returns: Json
      }
      reaction_list: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: Json
      }
      reaction_summary: {
        Args: { subject_ids: string[]; subject_type: string; tenant: string }
        Returns: Json
      }
      read_field_values: {
        Args: {
          legal_entity?: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      rebalance_ranks: {
        Args: { rank_group: string; subject_type: string; tenant: string }
        Returns: number
      }
      recall_ai_messages: {
        Args: {
          exclude_chat?: string
          k?: number
          owner?: string
          query_embedding: string
          tenant: string
        }
        Returns: Json
      }
      receive_purchase_order: {
        Args: { lines: Json; purchase_order: string }
        Returns: Json
      }
      receive_return: {
        Args: { location?: string; restock?: boolean; return_id: string }
        Returns: boolean
      }
      receive_shipment_return: {
        Args: { lines: Json; shipment_id: string }
        Returns: Json
      }
      receive_transfer: { Args: { transfer: string }; Returns: boolean }
      recompute_invoice_totals: {
        Args: { dry_run?: boolean; invoice_ids?: string[]; tenant: string }
        Returns: Json
      }
      reconcile_till_deposit: {
        Args: { bank_transaction_id: string; deposit_id: string }
        Returns: Json
      }
      record_activity: { Args: { batch: Json }; Returns: number }
      record_ai_batch: {
        Args: {
          fields?: Json
          provider: string
          reference: Json
          tenant: string
        }
        Returns: Json
      }
      record_ai_moderation_event: { Args: { event: Json }; Returns: Json }
      record_ai_run_step: { Args: { run: string; step: Json }; Returns: Json }
      record_ai_tool_approval: {
        Args: { approval: Json; chat: string }
        Returns: Json
      }
      record_approval_created: {
        Args: {
          created_id: string
          created_type: string
          item_key: string
          request_id: string
        }
        Returns: Json
      }
      record_as_needed_administration: {
        Args: {
          checked_by?: string
          dose?: number
          note?: string
          order_id: string
          reason?: string
        }
        Returns: Json
      }
      record_calibration: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      record_care_alerts: {
        Args: {
          alerts: Json
          source: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      record_care_plan_evaluation: {
        Args: {
          goal_id: string
          outcome?: string
          status: string
          submission_id?: string
        }
        Returns: Json
      }
      record_case_effectiveness: {
        Args: {
          case_id: string
          effective: boolean
          note?: string
          submission_id?: string
        }
        Returns: Json
      }
      record_case_root_cause: {
        Args: { case_id: string; root_cause: string; submission_id?: string }
        Returns: Json
      }
      record_connector_grant: {
        Args: {
          credential_ref: Json
          expires_at?: string
          owner: string
          scopes?: string[]
          server_id: string
        }
        Returns: Json
      }
      record_consent: {
        Args: {
          evidence?: Json
          given_by?: string
          given_by_contact_id?: string
          purpose_key: string
          scope?: Json
          status: string
          subject_id: string
          subject_type: string
          valid_until?: string
        }
        Returns: Json
      }
      record_consent_signal: {
        Args: {
          consent_id?: string
          kind: string
          purpose_keys?: string[]
          subject_id: string
          subject_type: string
          value: string
        }
        Returns: Json
      }
      record_count_line: { Args: { attrs: Json; count: string }; Returns: Json }
      record_delivery: {
        Args: {
          channel: string
          error?: string
          external_id?: string
          message: string
          status?: string
        }
        Returns: Json
      }
      record_delivery_event: {
        Args: {
          detail?: Json
          kind: string
          occurred_at?: string
          provider: string
          provider_event_id?: string
          provider_message_id: string
          suppress?: boolean
        }
        Returns: Json
      }
      record_e_invoice_delivery: {
        Args: {
          channel: string
          direction: string
          document_hash?: string
          format?: string
          invoice?: string
          message_id: string
          reason?: string
          state?: string
          tenant: string
        }
        Returns: Json
      }
      record_enrichment: {
        Args: {
          fill?: boolean
          provider: string
          result: Json
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      record_funding_claim_response: {
        Args: { claim_id: string; lines: Json; response?: Json }
        Returns: Json
      }
      record_gift: {
        Args: {
          amount: number
          currency: string
          donor_id: string
          donor_type: string
          fund_id?: string
          method?: string
          note?: string
          period_start?: string
          pledge_id?: string
          received_on?: string
          tenant: string
        }
        Returns: Json
      }
      record_gift_payment: {
        Args: {
          gift_id: string
          payment_id: string
          provider: string
          status: string
        }
        Returns: Json
      }
      record_inbound: { Args: { input: Json }; Returns: Json }
      record_invoice_payment: {
        Args: {
          actor?: Json
          amount: number
          currency: string
          invoice: string
          method: string
          note?: string
          paid_at: string
          reason?: string
          reference: string
        }
        Returns: Json
      }
      record_lims_result: {
        Args: { input: Json; method_id: string; sample_id: string }
        Returns: Json
      }
      record_medication_administration: {
        Args: {
          administration_id: string
          checked_by?: string
          dose?: number
          note?: string
          reason?: string
          signature_id?: string
          status: string
        }
        Returns: Json
      }
      record_meeting_decision: {
        Args: { input: Json; meeting_id: string }
        Returns: Json
      }
      record_meter_reading: {
        Args: { meter_id: string; read_at?: string; value: number }
        Returns: Json
      }
      record_observation: {
        Args: {
          definition_key: string
          details?: Json
          observed_at?: string
          subject_id: string
          subject_type: string
          tenant: string
          value: Json
        }
        Returns: Json
      }
      record_observations: {
        Args: { items: Json; tenant: string }
        Returns: Json
      }
      record_party_payment: {
        Args: {
          actor?: Json
          allocations: Json
          amount: number
          currency: string
          method?: string
          note?: string
          party_id: string
          received_on: string
          reference: string
          tenant: string
        }
        Returns: Json
      }
      record_payment: {
        Args: {
          amount: number
          captured?: number
          currency: string
          order_id: string
          provider: string
          reference: string
          refunded?: number
          status: string
        }
        Returns: Json
      }
      record_pick: { Args: { attrs: Json; line_id: string }; Returns: Json }
      record_prescription_delivery: {
        Args: {
          error?: string
          gateway: string
          prescription_id: string
          reference?: string
        }
        Returns: Json
      }
      record_prescription_dispense: {
        Args: { dispensed_at?: string; prescription_id: string }
        Returns: Json
      }
      record_production_consumption: {
        Args: {
          detail?: Json
          order_id: string
          quantity: number
          variant: string
        }
        Returns: Json
      }
      record_push_tickets: {
        Args: { delivery: string; tickets: Json }
        Returns: number
      }
      record_rendition: {
        Args: { input?: Json; kind: string; node_id: string; tenant: string }
        Returns: Json
      }
      record_rent_payment: {
        Args: {
          amount: number
          lease_id: string
          paid_at?: string
          reference?: string
        }
        Returns: Json
      }
      record_rfq_quote: {
        Args: {
          input: Json
          invitation_id: string
          lines: Json
          rfq_id: string
        }
        Returns: Json
      }
      record_rule_evaluation: {
        Args: {
          matched: boolean
          mode?: string
          results?: Json
          rule: string
          subject_id: string
        }
        Returns: Json
      }
      record_sent_mail: {
        Args: { account: string; message: Json }
        Returns: Json
      }
      record_skill_sync: {
        Args: {
          content_hash: string
          provider: string
          reference: Json
          skill_id: string
        }
        Returns: Json
      }
      record_sla_event: {
        Args: { event: string; subject_id: string; subject_type: string }
        Returns: Json
      }
      record_subject_read: {
        Args: {
          block_name?: string
          function_name?: string
          purpose?: string
          subject_id: string
          subject_type: string
        }
        Returns: undefined
      }
      record_summary: {
        Args: {
          sections: string[]
          seen_at?: string
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      record_template_application: {
        Args: {
          subject_id: string
          subject_type: string
          template_id: string
          tenant: string
          version_id: string
        }
        Returns: Json
      }
      record_till_movement: {
        Args: {
          amount: number
          kind: string
          reason?: string
          reference?: string
          session_id: string
        }
        Returns: Json
      }
      record_tracking_events: {
        Args: { events: Json; shipment_id: string; source?: string }
        Returns: Json
      }
      record_usage: {
        Args: {
          actor?: string
          idempotency_key?: string
          metadata?: Json
          meter: string
          quantity?: number
          source?: string
          tenant: string
        }
        Returns: Json
      }
      record_usage_batch: {
        Args: {
          actor?: string
          check?: boolean
          entries: Json
          idempotency_key?: string
          metadata?: Json
          source?: string
          tenant: string
        }
        Returns: Json
      }
      record_view: {
        Args: {
          subject_id: string
          subject_type: string
          tenant: string
          viewer: string
          viewer_kind: string
        }
        Returns: boolean
      }
      record_work_order_part: {
        Args: {
          asset_id?: string
          location_id?: string
          name: string
          quantity?: number
          unit?: string
          variant_id?: string
          work_order_id: string
        }
        Returns: Json
      }
      record_workflow_node_run: {
        Args: {
          attempt?: number
          error?: string
          node: string
          output?: Json
          run: string
          status: string
        }
        Returns: boolean
      }
      record_workflow_run: {
        Args: {
          actor?: string
          attributes?: Json
          completed_at?: string
          definition: string
          engine: string
          error?: string
          external_id: string
          idempotency_key?: string
          mode?: string
          principal_id?: string
          principal_kind?: string
          started_at?: string
          status: string
          subject_id?: string
          subject_type?: string
          tenant?: string
          trigger_node?: string
        }
        Returns: string
      }
      redeem_for: { Args: { code: string; member: string }; Returns: Json }
      redeem_invite_code: { Args: { code: string }; Returns: Json }
      redeliver_webhook: { Args: { delivery: string }; Returns: string }
      reembed_knowledge: {
        Args: { model?: string; tenant?: string }
        Returns: number
      }
      referral_attribute: {
        Args: {
          code: string
          referred_email?: string
          referred_org?: string
          referred_user?: string
          tenant: string
        }
        Returns: Json
      }
      refresh_due_segments: {
        Args: { max_count?: number; stale_after?: string }
        Returns: Json
      }
      refresh_payroll_run: { Args: { run_id: string }; Returns: Json }
      refresh_segment: { Args: { segment: string }; Returns: Json }
      refuse_data_subject_request: {
        Args: { id: string; reason: string }
        Returns: Json
      }
      register_ai_sandbox: {
        Args: {
          fields?: Json
          provider: string
          sandbox_id: string
          tenant: string
        }
        Returns: Json
      }
      register_funding_deliveries_from_time: {
        Args: { since: string; tenant: string; until: string }
        Returns: Json
      }
      register_funding_delivery: {
        Args: {
          award_id: string
          delivered_on: string
          note?: string
          performer_id?: string
          source_id?: string
          source_type?: string
          units: number
        }
        Returns: Json
      }
      register_push_device: {
        Args: {
          app_version?: string
          device_name?: string
          platform: string
          provider?: string
          token: string
        }
        Returns: string
      }
      register_sample: { Args: { input: Json; tenant: string }; Returns: Json }
      register_service_principal: {
        Args: {
          created_by?: string
          is_default?: boolean
          name: string
          principal: string
          role: string
          tenant: string
        }
        Returns: Json
      }
      register_sso_provider: {
        Args: {
          actor?: string
          domains: string[]
          metadata_url?: string
          provider: string
          tenant: string
        }
        Returns: Json
      }
      reimburse_expense_report: {
        Args: { paid_at?: string; reference?: string; report_id: string }
        Returns: Json
      }
      reject_return: { Args: { return_id: string }; Returns: boolean }
      reject_sample: {
        Args: { reason: string; sample_id: string }
        Returns: Json
      }
      relation_rollup: {
        Args: {
          agg: string
          column_name: string
          kind: string
          of_type: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      relation_walk: {
        Args: {
          kind: string
          max_depth: number
          subject_id: string
          subject_type: string
          tenant: string
          up: boolean
        }
        Returns: {
          depth: number
          id: string
          type: string
        }[]
      }
      relations_by_kind: {
        Args: { kind: string; tenant: string }
        Returns: Json
      }
      relations_of: {
        Args: {
          kind: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      release_ai_chat_stream: {
        Args: {
          chat: string
          cost_micro_usd?: number
          error?: string
          generation_id?: string
          status?: string
          stream: string
          usage?: Json
        }
        Returns: boolean
      }
      release_allocations: {
        Args: { document_id: string; document_type: string; tenant: string }
        Returns: number
      }
      release_asset: { Args: { asset_id: string }; Returns: Json }
      release_legal_hold: { Args: { id: string }; Returns: Json }
      release_pick_wave: { Args: { wave_id: string }; Returns: Json }
      release_production_order: {
        Args: { allow_shortage?: boolean; order_id: string }
        Returns: Json
      }
      release_reservation: { Args: { reservation: string }; Returns: boolean }
      release_sample: { Args: { sample_id: string }; Returns: Json }
      release_workflow_semaphore: {
        Args: { holder: string; key: string }
        Returns: boolean
      }
      remind_approvals: {
        Args: { after?: string; max_requests?: number }
        Returns: number
      }
      remove_ai_chat_participant: {
        Args: { chat: string; participant: string }
        Returns: boolean
      }
      remove_ai_chat_party: {
        Args: { chat: string; party: string; party_kind: string }
        Returns: boolean
      }
      remove_approval_policy: { Args: { policy_id: string }; Returns: boolean }
      remove_assignment_queue: { Args: { queue: string }; Returns: boolean }
      remove_calendar_attendee: {
        Args: { email: string; event_id: string }
        Returns: boolean
      }
      remove_case_action: { Args: { action_id: string }; Returns: Json }
      remove_company_person: {
        Args: { company: string; person: string }
        Returns: boolean
      }
      remove_control_evidence: { Args: { evidence_id: string }; Returns: Json }
      remove_conversation_member: {
        Args: { conversation: string; member: string }
        Returns: boolean
      }
      remove_expense_line: { Args: { line_id: string }; Returns: Json }
      remove_from_collection: {
        Args: { collection: string; product: string }
        Returns: boolean
      }
      remove_incident_postmortem_action: {
        Args: { action_id: string }
        Returns: Json
      }
      remove_invoice_charge: {
        Args: { actor?: Json; charge: string }
        Returns: Json
      }
      remove_meeting_attendee: {
        Args: { meeting_id: string; user_id: string }
        Returns: Json
      }
      remove_member: {
        Args: { member: string; organization: string }
        Returns: boolean
      }
      remove_organization_domain: { Args: { id: string }; Returns: boolean }
      remove_person_identity: { Args: { identity: string }; Returns: boolean }
      remove_product_media: { Args: { media: string }; Returns: boolean }
      remove_promotion_code: {
        Args: { cart: string; code: string }
        Returns: boolean
      }
      remove_qualification_requirement: {
        Args: { requirement_id: string }
        Returns: Json
      }
      remove_retention_policy: {
        Args: { kind: string; plan?: string; tenant?: string }
        Returns: boolean
      }
      remove_rule: { Args: { id: string }; Returns: boolean }
      remove_segment: { Args: { segment: string }; Returns: boolean }
      remove_team_member: {
        Args: { member: string; team: string }
        Returns: boolean
      }
      remove_template: { Args: { template_id: string }; Returns: boolean }
      remove_template_schedule: {
        Args: { schedule_id: string }
        Returns: boolean
      }
      remove_usage_quota: {
        Args: { meter: string; plan: string; tenant: string }
        Returns: boolean
      }
      remove_work_order_part: { Args: { part_id: string }; Returns: boolean }
      remove_workflow_alert: { Args: { alert: string }; Returns: boolean }
      remove_workflow_credential: {
        Args: { credential: string }
        Returns: Json
      }
      remove_workflow_definition: {
        Args: { definition: string }
        Returns: boolean
      }
      remove_workflow_schedule: { Args: { schedule: string }; Returns: boolean }
      remove_workflow_trigger: { Args: { trigger: string }; Returns: boolean }
      render_document: {
        Args: {
          document_id: string
          document_type: string
          fresh?: boolean
          language?: string
          template_name?: string
          tenant: string
        }
        Returns: Json
      }
      renew_connector_grant: {
        Args: { expires_at: string; id: string }
        Returns: boolean
      }
      renew_lease: {
        Args: { ends_on: string; lease_id: string; rent?: number }
        Returns: Json
      }
      reopen_accounting_period: {
        Args: { period_id: string; reason: string }
        Returns: Json
      }
      reopen_case: { Args: { case_id: string; reason?: string }; Returns: Json }
      reopen_deal: { Args: { deal: string; stage: string }; Returns: Json }
      reopen_period: {
        Args: { period_id: string; reason?: string }
        Returns: Json
      }
      reopen_timesheet: { Args: { timesheet_id: string }; Returns: Json }
      reorder_product_media: {
        Args: { media: string[]; product: string }
        Returns: boolean
      }
      reorder_product_options: {
        Args: { options: string[]; product: string }
        Returns: boolean
      }
      repeat_maintenance_request: {
        Args: { due_at: string; work_item: string }
        Returns: Json
      }
      repeat_work_item: {
        Args: { due_at: string; work_item: string }
        Returns: Json
      }
      replace_attachment: {
        Args: {
          height?: number
          id: string
          mime_type: string
          name: string
          pages?: number
          size: number
          width?: number
        }
        Returns: Json
      }
      replacement_variant: { Args: { variant: string }; Returns: string }
      report_content: {
        Args: {
          note?: string
          reason: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      reports_of: {
        Args: { indirect: boolean; manager: string }
        Returns: Json
      }
      represented_by_me: { Args: { tenant: string }; Returns: Json }
      request_access: {
        Args: {
          duration?: string
          reason?: string
          role: string
          tenant: string
        }
        Returns: Json
      }
      request_ai_chat_stop: { Args: { chat: string }; Returns: Json }
      request_approval: {
        Args: {
          action: string
          fingerprint?: string
          payload?: Json
          policy?: Json
          reason?: string
          requested_by?: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      request_approval_items: {
        Args: {
          action: string
          fingerprint?: string
          items: Json
          payload?: Json
          policy?: Json
          reason?: string
          requested_by?: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      request_care_plan_agreement: {
        Args: { message?: string; plan_id: string; signers: string[] }
        Returns: Json
      }
      request_data_export: {
        Args: { subject?: string; tenant?: string }
        Returns: Json
      }
      request_open_shift: { Args: { shift_id: string }; Returns: Json }
      request_organization_deletion: {
        Args: { grace?: string; tenant: string }
        Returns: Json
      }
      request_purchase: {
        Args: {
          currency?: string
          lines: Json
          location: string
          reason?: string
          supplier_id?: string
          supplier_type?: string
          tenant: string
        }
        Returns: Json
      }
      request_record_access: {
        Args: {
          action?: string
          duration?: string
          reason?: string
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      request_return: {
        Args: { lines: Json; order_id: string; reason?: string }
        Returns: Json
      }
      request_shift_swap: {
        Args: { assignment_id: string; note?: string; to_user_id: string }
        Returns: Json
      }
      request_subject_export: {
        Args: { format?: string; subject_id: string; subject_type: string }
        Returns: Json
      }
      request_workflow_cancel: { Args: { run: string }; Returns: Json }
      request_workflow_start: {
        Args: {
          actor?: string
          concurrency?: number
          debounce?: string
          key: string
          payload?: Json
          singleton?: boolean
          subject_id?: string
          subject_type?: string
          tenant?: string
          workflow: string
        }
        Returns: Json
      }
      requires_consent: {
        Args: { purpose_key: string; subject_id: string; subject_type: string }
        Returns: boolean
      }
      reschedule_booking: {
        Args: { booking: string; scope?: string; starts_at: string }
        Returns: Json
      }
      reschedule_inbox_message: {
        Args: { scheduled: string; scheduled_for: string }
        Returns: Json
      }
      resend_invitation: {
        Args: { invitation_id: string; valid_for?: string }
        Returns: Json
      }
      reserve_ai_file: {
        Args: {
          byte_size: number
          chat_id?: string
          filename: string
          media_type: string
          project_id?: string
          tenant: string
        }
        Returns: Json
      }
      reserve_stock: {
        Args: {
          expires_at: string
          location: string
          quantity: number
          reference_id: string
          reference_type: string
          variant: string
        }
        Returns: Json
      }
      reset_default_rule: { Args: { id: string }; Returns: Json }
      reset_enrollment_step: {
        Args: { enrollment_id: string; step: string }
        Returns: Json
      }
      reset_legal_entity_setting: {
        Args: { key: string; legal_entity_id: string }
        Returns: boolean
      }
      reset_onboarding_step: {
        Args: { checklist: string; step: string; tenant?: string }
        Returns: boolean
      }
      reset_organization_setting: {
        Args: { key: string; tenant: string }
        Returns: boolean
      }
      reset_platform_setting: { Args: { key: string }; Returns: boolean }
      reset_user_setting: { Args: { key: string }; Returns: boolean }
      resolve_ai_suggestion: {
        Args: { accepted: boolean; suggestion_id: string }
        Returns: Json
      }
      resolve_document_blocks: {
        Args: {
          keys: string[]
          language?: string
          legal_entity_id?: string
          tenant: string
        }
        Returns: Json
      }
      resolve_document_template: {
        Args: {
          document_type: string
          language?: string
          legal_entity_id?: string
          name?: string
          tenant: string
        }
        Returns: Json
      }
      resolve_line_discount: {
        Args: {
          currency?: string
          on: string
          party: string
          product: string
          quantity: number
          tenant: string
        }
        Returns: Json
      }
      resolve_message: {
        Args: { message: string; resolved?: boolean }
        Returns: Json
      }
      resolve_notifications: {
        Args: {
          resolution?: Json
          subject_id: string
          subject_type: string
          tenant?: string
          type: string
        }
        Returns: Json
      }
      resolve_setting: {
        Args: { key: string; legal_entity?: string; tenant: string }
        Returns: Json
      }
      resolve_share_link: {
        Args: { password?: string; token: string }
        Returns: Json
      }
      resolve_workflow_definition: {
        Args: { purpose?: string; subject_type?: string; tenant: string }
        Returns: Json
      }
      respond_calendar_event: {
        Args: { event_id: string; response: string }
        Returns: boolean
      }
      respond_to_portal_quote: {
        Args: {
          decision: string
          name: string
          note: string
          quote: string
          selected?: Json
        }
        Returns: Json
      }
      respond_to_quote: {
        Args: {
          decision: string
          name: string
          note: string
          selected?: Json
          token: string
        }
        Returns: Json
      }
      restore_allocation: {
        Args: { allocation: string; detail?: Json; quantity: number }
        Returns: Json
      }
      restore_attachment_version: {
        Args: { id: string; version: number }
        Returns: Json
      }
      restore_data_row: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      restore_flag: { Args: { key: string; revision: number }; Returns: Json }
      restore_team: { Args: { team: string }; Returns: boolean }
      restore_trash: { Args: { item_id: string }; Returns: Json }
      restore_version: {
        Args: { fields?: string[]; version_id: string }
        Returns: Json
      }
      resume_enrollment: { Args: { enrollment_id: string }; Returns: Json }
      resume_lifecycle: {
        Args: { subject_id: string; subject_type: string }
        Returns: boolean
      }
      retention_cutoff: {
        Args: { fallback: string; kind: string }
        Returns: string
      }
      retention_floor: { Args: { kind: string }; Returns: string }
      retention_for: {
        Args: { kind: string; tenant?: string }
        Returns: string
      }
      retire_signing_key: { Args: { kid: string }; Returns: boolean }
      reverse_accounting_entry: {
        Args: { entry_date?: string; entry_id: string }
        Returns: Json
      }
      reverse_commission: {
        Args: { commission_id: string; reason?: string }
        Returns: Json
      }
      reverse_invoice_payment: {
        Args: { actor?: Json; payment: string; reason?: string }
        Returns: Json
      }
      revert_audit_entries: { Args: { entries: string[] }; Returns: Json }
      review_care_plan_action: {
        Args: { action_id: string; note?: string }
        Returns: Json
      }
      review_emergency_access: {
        Args: { note?: string; request_id: string; verdict: string }
        Returns: Json
      }
      review_form_submission: {
        Args: { status: string; submission_id: string }
        Returns: Json
      }
      review_risk: { Args: { note?: string; risk_id: string }; Returns: Json }
      revise_quote: { Args: { actor?: Json; quote: string }; Returns: Json }
      revoke_ai_chat_link: { Args: { chat: string }; Returns: boolean }
      revoke_ai_chat_share: { Args: { id: string }; Returns: boolean }
      revoke_api_key: { Args: { key: string }; Returns: boolean }
      revoke_connector_grant: { Args: { id: string }; Returns: Json }
      revoke_course_certificate: {
        Args: { certificate_id: string }
        Returns: boolean
      }
      revoke_guest: { Args: { guest_id: string }; Returns: Json }
      revoke_guest_access: { Args: { grant_id: string }; Returns: boolean }
      revoke_invitation: { Args: { invitation_id: string }; Returns: boolean }
      revoke_invite_code: { Args: { id: string }; Returns: boolean }
      revoke_pass: { Args: { pass_id: string }; Returns: Json }
      revoke_qualification: {
        Args: { qualification_id: string; reason?: string }
        Returns: Json
      }
      revoke_share_link: { Args: { id: string }; Returns: boolean }
      revoke_usage_right: { Args: { right_id: string }; Returns: Json }
      risk_heatmap: {
        Args: { basis?: string; matrix_id?: string; tenant: string }
        Returns: Json
      }
      rollback_ai_document: {
        Args: { document_id: string; version: number }
        Returns: Json
      }
      roster: {
        Args: {
          from_date: string
          team_id?: string
          tenant: string
          until_date: string
        }
        Returns: Json
      }
      rotate_ai_chat_link: { Args: { chat: string }; Returns: Json }
      rotate_api_key: {
        Args: {
          grace?: string
          key: string
          public_id: string
          secret_hash: string
        }
        Returns: Json
      }
      rotate_webhook_secret: {
        Args: { endpoint: string; overlap?: string; secret?: string }
        Returns: string
      }
      rotate_workflow_webhook_token: {
        Args: { trigger: string }
        Returns: string
      }
      rule_boolean: { Args: { value: Json }; Returns: boolean }
      rule_bounds: {
        Args: { kind: string; now: string; time_zone: string; value: Json }
        Returns: string[]
      }
      rule_check: {
        Args: { depth?: number; fields: Json; node: Json }
        Returns: number
      }
      rule_date: {
        Args: {
          kind: string
          now: string
          operand: Json
          operator: string
          time_zone: string
          value: Json
        }
        Returns: boolean
      }
      rule_equal: {
        Args: { operand: Json; type: string; value: Json }
        Returns: boolean
      }
      rule_evaluate: {
        Args: {
          conditions: Json
          fields: Json
          now?: string
          subject: Json
          time_zone?: string
        }
        Returns: Json
      }
      rule_evaluations_list: {
        Args: { before?: string; page_size?: number; rule: string }
        Returns: Json
      }
      rule_field_map: { Args: { subject_type: string }; Returns: Json }
      rule_fields_list: { Args: { subject_type?: string }; Returns: Json }
      rule_get: { Args: { id: string }; Returns: Json }
      rule_list: { Args: { value: Json }; Returns: string[] }
      rule_matches: {
        Args: {
          conditions: Json
          fields: Json
          now?: string
          subject: Json
          time_zone?: string
        }
        Returns: boolean
      }
      rule_moment: { Args: { kind: string; value: Json }; Returns: string }
      rule_node: {
        Args: {
          fields: Json
          node: Json
          now: string
          subject: Json
          time_zone: string
        }
        Returns: Json
      }
      rule_numeric: { Args: { value: Json }; Returns: number }
      rule_positive: {
        Args: {
          kind: string
          now: string
          operand: Json
          operator: string
          time_zone: string
          type: string
          value: Json
        }
        Returns: boolean
      }
      rule_text: { Args: { value: Json }; Returns: string }
      rule_versions_list: { Args: { id: string }; Returns: Json }
      rules_list: {
        Args: {
          enabled?: boolean
          subject_type?: string
          tenant: string
          trigger?: string
        }
        Returns: Json
      }
      run_asset_depreciation: {
        Args: { tenant?: string; until?: string }
        Returns: Json
      }
      run_contract_renewals: { Args: { as_of?: string }; Returns: Json }
      run_count_plan: { Args: { plan_id: string }; Returns: Json }
      run_due_count_plans: { Args: { tenant: string }; Returns: Json }
      run_due_sequences: { Args: { max_count?: number }; Returns: Json }
      run_invoice_dunning: {
        Args: { as_of?: string; tenant?: string }
        Returns: number
      }
      run_notification_digests: {
        Args: { max_digests?: number }
        Returns: Json
      }
      run_rules: {
        Args: {
          subject: Json
          subject_id: string
          subject_type: string
          tenant: string
          time_zone?: string
          trigger: string
        }
        Returns: Json
      }
      running_timer: { Args: { tenant: string }; Returns: Json }
      running_timers: { Args: { tenant: string }; Returns: Json }
      save_accounting_account: {
        Args: {
          account_id?: string
          active?: boolean
          code: string
          currency?: string
          default_tax_code_id?: string
          name: string
          normal_side?: string
          parent_id?: string
          reconcilable?: boolean
          subtype?: string
          tenant: string
          type: string
        }
        Returns: Json
      }
      save_accounting_budget: {
        Args: {
          budget_id?: string
          fiscal_year: number
          lines?: Json
          name: string
          status?: string
          tenant: string
        }
        Returns: Json
      }
      save_accounting_dimension: {
        Args: { key: string; name: string; tenant: string }
        Returns: Json
      }
      save_accounting_dimension_value: {
        Args: {
          archived?: boolean
          code: string
          dimension_id: string
          name: string
        }
        Returns: Json
      }
      save_accounting_entry: {
        Args: {
          entry_date: string
          entry_id?: string
          journal_id: string
          lines: Json
          memo?: string
          reference?: string
          source_id?: string
          source_type?: string
        }
        Returns: Json
      }
      save_accounting_journal: {
        Args: {
          bank_account_id?: string
          code: string
          contra_account_id?: string
          currency?: string
          default_account_id?: string
          journal_id?: string
          name: string
          tenant: string
          type: string
        }
        Returns: Json
      }
      save_accounting_opening_balances: {
        Args: { balances: Json; fiscal_year: number; tenant: string }
        Returns: Json
      }
      save_activity_notes: {
        Args: { engagement: string; notes: Json }
        Returns: Json
      }
      save_activity_transcript: {
        Args: { attrs: Json; recording: string; segments: Json }
        Returns: Json
      }
      save_agent: {
        Args: { fields?: Json; id?: string; tenant: string }
        Returns: Json
      }
      save_ai_assistant_message: {
        Args: {
          chat: string
          format?: string
          message: Json
          model?: string
          native?: Json
          parent_id: string
          run?: string
          status?: string
        }
        Returns: Json
      }
      save_ai_batch_items: {
        Args: { id: string; items: Json }
        Returns: number
      }
      save_ai_harness_session: {
        Args: { chat: string; fields: Json; harness: string; holder?: string }
        Returns: Json
      }
      save_ai_project: {
        Args: { fields: Json; id: string; tenant: string }
        Returns: Json
      }
      save_ai_provider_key: {
        Args: {
          credential_ref: Json
          enabled?: boolean
          name?: string
          provider: string
          settings?: Json
          tenant: string
        }
        Returns: Json
      }
      save_ai_task: {
        Args: {
          fields?: Json
          id?: string
          next_run_at?: string
          tenant: string
        }
        Returns: Json
      }
      save_announcement: { Args: { fields: Json; id: string }; Returns: Json }
      save_approval_policy: {
        Args: { policy: Json; tenant: string }
        Returns: Json
      }
      save_assignment_queue: {
        Args: { queue: Json; tenant: string }
        Returns: Json
      }
      save_bank_account: {
        Args: { account_id?: string; input: Json; tenant: string }
        Returns: Json
      }
      save_bank_rule: {
        Args: { input: Json; rule_id?: string; tenant: string }
        Returns: Json
      }
      save_bin: {
        Args: {
          active: boolean
          bin: string
          code: string
          hold: boolean
          location: string
          name: string
        }
        Returns: Json
      }
      save_bin_slot: { Args: { input: Json; tenant: string }; Returns: Json }
      save_bom: {
        Args: { bom_id?: string; input: Json; tenant: string; variant: string }
        Returns: Json
      }
      save_booking_resource: {
        Args: { item: Json; tenant: string }
        Returns: Json
      }
      save_booking_service: {
        Args: { item: Json; tenant: string }
        Returns: Json
      }
      save_calendar_event: {
        Args: { actor?: string; calendar_id: string; item: Json }
        Returns: Json
      }
      save_care_rule: { Args: { attrs: Json; tenant: string }; Returns: Json }
      save_case_kind: {
        Args: {
          effectiveness_after_days?: number
          effectiveness_form_id?: string
          investigation_form_id?: string
          key: string
          kind_id?: string
          name: string
          prefix: string
          requires_actions?: boolean
          requires_effectiveness?: boolean
          requires_revisions?: boolean
          requires_root_cause?: boolean
          tenant: string
        }
        Returns: Json
      }
      save_catalog_channel: {
        Args: {
          active: boolean
          channel: string
          currency: string
          key: string
          name: string
          price_list: string
          tenant: string
        }
        Returns: Json
      }
      save_category: {
        Args: {
          category: string
          description: string
          name: string
          parent: string
          slug: string
          tenant: string
        }
        Returns: Json
      }
      save_collection: {
        Args: {
          collection: string
          kind: string
          rule: Json
          slug: string
          tenant: string
          title: string
        }
        Returns: Json
      }
      save_commission_plan: {
        Args: {
          archived?: boolean
          kind: string
          name: string
          plan_id?: string
          rate_bps?: number
          tenant: string
          tiers?: Json
        }
        Returns: Json
      }
      save_company: {
        Args: { attrs: Json; company: string; tenant: string }
        Returns: Json
      }
      save_compliance_policy: {
        Args: {
          key: string
          owner_id?: string
          policy_id?: string
          requires_acknowledgement?: boolean
          tenant: string
          title: string
        }
        Returns: Json
      }
      save_connector_server: {
        Args: { fields?: Json; id?: string; tenant: string }
        Returns: Json
      }
      save_connector_session: {
        Args: {
          chat_key?: string
          initialize_result?: Json
          server_id: string
          session_id?: string
        }
        Returns: boolean
      }
      save_consent_purpose: {
        Args: {
          description?: string
          key: string
          legal_basis?: string
          requires_signature?: boolean
          tenant: string
          title: string
          valid_months?: number
          version?: string
        }
        Returns: Json
      }
      save_contract_obligation: {
        Args: {
          contract_id: string
          description?: string
          due_on?: string
          obligation_id?: string
          owner_id?: string
          title: string
        }
        Returns: Json
      }
      save_control: {
        Args: {
          applicable?: boolean
          code: string
          control_id?: string
          description?: string
          framework_id: string
          jurisdiction?: string
          owner_id?: string
          source?: string
          title: string
        }
        Returns: Json
      }
      save_control_framework: {
        Args: {
          description?: string
          key: string
          kind?: string
          name: string
          tenant: string
          version?: string
        }
        Returns: Json
      }
      save_course: { Args: { course: Json; tenant: string }; Returns: Json }
      save_course_lesson: {
        Args: { course_id: string; lesson: Json }
        Returns: Json
      }
      save_course_module: {
        Args: { course_id: string; module: Json }
        Returns: Json
      }
      save_custom_emoji: {
        Args: {
          attachment_id?: string
          shortcode: string
          tenant: string
          url?: string
        }
        Returns: Json
      }
      save_discount_group: {
        Args: {
          code: string
          group: string
          kind: string
          name: string
          tenant: string
        }
        Returns: Json
      }
      save_discount_rule: {
        Args: { attrs: Json; rule: string; tenant: string }
        Returns: Json
      }
      save_document_template: {
        Args: {
          active?: boolean
          body: string
          document_type: string
          language?: string
          legal_entity_id?: string
          name?: string
          tenant: string
        }
        Returns: Json
      }
      save_document_text_block: {
        Args: {
          body: string
          key: string
          language?: string
          legal_entity_id?: string
          tenant: string
        }
        Returns: Json
      }
      save_document_version: {
        Args: { document_id: string; label?: string; state: string }
        Returns: Json
      }
      save_donation_fund: {
        Args: {
          currency?: string
          ends_on?: string
          goal?: number
          key: string
          kind?: string
          name: string
          starts_on?: string
          tenant: string
        }
        Returns: Json
      }
      save_employee_private_details: {
        Args: { attrs: Json; employee: string }
        Returns: Json
      }
      save_enrollment_program: {
        Args: { program: Json; tenant: string }
        Returns: Json
      }
      save_evidence_task: {
        Args: {
          active?: boolean
          assignee_id?: string
          control_id: string
          due_on?: string
          interval_days: number
          task_id?: string
          title: string
        }
        Returns: Json
      }
      save_expense_category: {
        Args: {
          currency?: string
          key: string
          limit_amount?: number
          name: string
          receipt_over?: number
          tenant: string
        }
        Returns: Json
      }
      save_field_definition: {
        Args: {
          entity: string
          key: string
          label: string
          sensitive: boolean
          tenant: string
          type: string
        }
        Returns: Json
      }
      save_flag: {
        Args: { definition: Json; key: string; message?: string }
        Returns: Json
      }
      save_flag_segment: {
        Args: { description: string; name: string; rules: Json }
        Returns: Json
      }
      save_funding_award: {
        Args: {
          attrs: Json
          award_id?: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      save_funding_product: {
        Args: {
          code: string
          currency: string
          product_id?: string
          rate: number
          tenant: string
          title: string
          unit: string
          valid_from?: string
          valid_until?: string
        }
        Returns: Json
      }
      save_goal: {
        Args: { attrs: Json; target: string; tenant: string }
        Returns: Json
      }
      save_inbox_draft: {
        Args: { conversation: string; input: Json; metadata?: Json }
        Returns: Json
      }
      save_incident_postmortem: {
        Args: { attrs: Json; incident_id: string }
        Returns: Json
      }
      save_incident_regulatory_profile: {
        Args: { attrs: Json; incident_id: string }
        Returns: Json
      }
      save_inspection_checklist: {
        Args: { answers: Json; draft?: boolean; inspection_id: string }
        Returns: Json
      }
      save_inspection_program: {
        Args: {
          name: string
          notes?: string
          owner_id?: string
          period_end: string
          period_start: string
          program_id?: string
          tenant: string
        }
        Returns: Json
      }
      save_intrastat_line: {
        Args: { attrs: Json; line: string; tenant: string }
        Returns: Json
      }
      save_iteration: {
        Args: { attrs: Json; iteration: string; tenant: string }
        Returns: Json
      }
      save_job: {
        Args: { attrs: Json; job: string; tenant: string }
        Returns: Json
      }
      save_kitchen_station: {
        Args: { attrs: Json; station: string; tenant: string }
        Returns: Json
      }
      save_lims_method: {
        Args: { input: Json; method_id?: string; tenant: string }
        Returns: Json
      }
      save_location: {
        Args: {
          code: string
          fields?: Json
          kind: string
          location: string
          name: string
          tenant: string
        }
        Returns: Json
      }
      save_lot: {
        Args: { code: string; expires_on: string; variant: string }
        Returns: Json
      }
      save_maintenance_request_checklist_item: {
        Args: { attrs: Json; checklist_item: string; work_item: string }
        Returns: Json
      }
      save_medication: {
        Args: {
          code?: string
          code_system?: string
          form?: string
          high_risk?: boolean
          medication_id?: string
          name: string
          strength?: string
          tenant: string
          unit: string
        }
        Returns: Json
      }
      save_meeting_agenda_item: {
        Args: { item: Json; meeting_id: string }
        Returns: Json
      }
      save_observation_definition: {
        Args: { definition: Json; key: string; tenant: string }
        Returns: Json
      }
      save_payment_term: {
        Args: { attrs: Json; tenant: string }
        Returns: Json
      }
      save_person: {
        Args: { attrs: Json; person: string; tenant: string }
        Returns: Json
      }
      save_pipeline: {
        Args: {
          is_default: boolean
          key: string
          name: string
          pipeline: string
          scope_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      save_pipeline_stage: {
        Args: {
          category: string
          color: string
          key: string
          name: string
          pipeline: string
          probability: number
          rotting_after_days: number
          stage: string
          wip_limit: number
        }
        Returns: Json
      }
      save_post_board: { Args: { board: Json; tenant: string }; Returns: Json }
      save_price_list: {
        Args: {
          customer_group: string
          name: string
          price_list: string
          tenant: string
        }
        Returns: Json
      }
      save_product: {
        Args: {
          clear?: string[]
          description: string
          kind: string
          product: string
          slug: string
          tenant: string
          title: string
        }
        Returns: Json
      }
      save_product_identifier: {
        Args: {
          party?: string
          tenant: string
          type: string
          value: string
          variant: string
        }
        Returns: Json
      }
      save_product_option: {
        Args: {
          name: string
          option: string
          option_values: string[]
          product: string
        }
        Returns: Json
      }
      save_product_relation: {
        Args: {
          from_variant: string
          kind: string
          tenant: string
          to_variant: string
        }
        Returns: Json
      }
      save_project: {
        Args: { attrs: Json; project: string; tenant: string }
        Returns: Json
      }
      save_promotion: {
        Args: { data: Json; promotion: string; tenant: string }
        Returns: Json
      }
      save_purchase_order: {
        Args: {
          currency: string
          expected_at: string
          lines: Json
          location: string
          note: string
          purchase_order: string
          supplier_id: string
          supplier_type: string
          tenant: string
        }
        Returns: Json
      }
      save_putaway_rule: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      save_qualification_type: {
        Args: {
          course_id?: string
          description?: string
          evidence_required?: boolean
          holder_types: string[]
          key: string
          name: string
          tenant: string
          type_id?: string
          valid_for_months?: number
        }
        Returns: Json
      }
      save_reminder: {
        Args: {
          offset_minutes: number
          remind_at?: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      save_risk_matrix: {
        Args: {
          bands: Json
          impact_levels: Json
          is_default?: boolean
          key: string
          likelihood_levels: Json
          matrix_id?: string
          name: string
          scoring?: string
          tenant: string
        }
        Returns: Json
      }
      save_rule: { Args: { rule: Json; tenant: string }; Returns: Json }
      save_score_model: { Args: { model: Json; tenant: string }; Returns: Json }
      save_segment: { Args: { segment: Json; tenant: string }; Returns: Json }
      save_sequence: { Args: { sequence: Json; tenant: string }; Returns: Json }
      save_shift: {
        Args: {
          break_minutes?: number
          ends_at: string
          headcount?: number
          location_id?: string
          note?: string
          required_qualifications?: string[]
          shift_id?: string
          starts_at: string
          team_id?: string
          tenant: string
        }
        Returns: Json
      }
      save_shift_template: {
        Args: {
          break_minutes?: number
          ends_time: string
          headcount?: number
          location_id?: string
          name: string
          required_qualifications?: string[]
          starts_time: string
          team_id?: string
          template_id?: string
          tenant: string
          weekdays?: number[]
        }
        Returns: Json
      }
      save_shipping_rate: {
        Args: { data: Json; rate: string; tenant: string }
        Returns: Json
      }
      save_sla_policy: {
        Args: { attrs: Json; policy: string; tenant: string }
        Returns: Json
      }
      save_status_component: {
        Args: {
          component_id?: string
          description?: string
          group_name?: string
          is_public?: boolean
          name: string
          sort_position?: number
          tenant: string
        }
        Returns: Json
      }
      save_status_page: {
        Args: {
          description?: string
          published?: boolean
          slug: string
          tenant: string
          title: string
        }
        Returns: Json
      }
      save_supplier_item: {
        Args: {
          code: string
          currency: string
          description: string
          item: string
          keywords: string
          price: number
          supplier: string
          tenant: string
          unit: string
        }
        Returns: Json
      }
      save_template: {
        Args: {
          language: string
          name: string
          settings: Json
          template_id: string
          tenant: string
          type: string
        }
        Returns: Json
      }
      save_template_draft: {
        Args: { body: Json; template_id: string }
        Returns: Json
      }
      save_template_schedule: {
        Args: {
          dtstart: string
          enabled: boolean
          input: Json
          rrule: string
          schedule_id: string
          template_id: string
          tenant: string
          tzid: string
        }
        Returns: Json
      }
      save_thread_summary: {
        Args: {
          attrs?: Json
          conversation: string
          summary: string
          thread: string
        }
        Returns: Json
      }
      save_variant: {
        Args: {
          allow_backorder: boolean
          barcode: string
          clear?: string[]
          option_values: string[]
          product: string
          sku: string
          title: string
          track_inventory: boolean
          variant: string
          weight_grams: number
        }
        Returns: Json
      }
      save_variant_size: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      save_view: {
        Args: {
          kind: string
          list: string
          name: string
          scope: string
          state: Json
          team: string
          tenant: string
          view_id: string
        }
        Returns: Json
      }
      save_work_center: {
        Args: { input: Json; tenant: string; work_center_id?: string }
        Returns: Json
      }
      save_work_item_checklist_item: {
        Args: { attrs: Json; checklist_item: string; work_item: string }
        Returns: Json
      }
      save_workflow_alert: {
        Args: {
          alert?: string
          channel?: Json
          definition: string
          on_event: string
          threshold?: string
        }
        Returns: Json
      }
      save_workflow_credential: {
        Args: {
          kind: string
          name: string
          ref: Json
          scopes?: string[]
          tenant: string
        }
        Returns: Json
      }
      save_workflow_definition: {
        Args: {
          description?: string
          name: string
          restricted?: boolean
          scope?: string
          slug: string
          subject_types?: string[]
          tenant: string
        }
        Returns: Json
      }
      save_workflow_draft: {
        Args: { definition: string; graph: Json; input_schema?: Json }
        Returns: Json
      }
      save_workflow_trigger: {
        Args: {
          config?: Json
          definition: string
          enabled?: boolean
          kind: string
          trigger?: string
        }
        Returns: Json
      }
      schedule_ai_tasks: { Args: { items: Json }; Returns: number }
      schedule_case_effectiveness: {
        Args: { case_id: string }
        Returns: undefined
      }
      schedule_content_entry: {
        Args: { at: string; entry_id: string }
        Returns: Json
      }
      schedule_inbox_message: {
        Args: { conversation: string; input: Json; scheduled_for: string }
        Returns: Json
      }
      schedule_inspection: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      schedule_interview: {
        Args: {
          application: string
          ends_at: string
          interviewers: string[]
          kind: string
          location: string
          starts_at: string
        }
        Returns: Json
      }
      schedule_work_order: {
        Args: {
          ends_at?: string
          starts_at: string
          technician: string
          work_order_id: string
        }
        Returns: Json
      }
      scim_delete_group: {
        Args: { id: string; tenant: string }
        Returns: boolean
      }
      scim_delete_user: {
        Args: { id: string; tenant: string }
        Returns: boolean
      }
      scim_get_group: { Args: { id: string; tenant: string }; Returns: Json }
      scim_get_user: { Args: { id: string; tenant: string }; Returns: Json }
      scim_group_role: { Args: { display_name: string }; Returns: string }
      scim_list_groups: { Args: { tenant: string }; Returns: Json }
      scim_list_users: { Args: { tenant: string }; Returns: Json }
      scim_save_group: {
        Args: { data: Json; id: string; tenant: string; version?: number }
        Returns: Json
      }
      scim_save_user: {
        Args: { data: Json; id: string; tenant: string; version?: number }
        Returns: Json
      }
      scim_sync_member: { Args: { scim_user: string }; Returns: undefined }
      scope_permissions: { Args: { scope: string }; Returns: string[] }
      score_history: {
        Args: {
          model_key: string
          page_size?: number
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      score_lead: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: Json
      }
      score_leads_due: { Args: { max_count?: number }; Returns: number }
      search: {
        Args: {
          max_results?: number
          q: string
          tenant?: string
          types?: string[]
        }
        Returns: Json
      }
      search_favorites: {
        Args: { max_results?: number; types?: string[] }
        Returns: Json
      }
      search_recents: {
        Args: { max_results?: number; types?: string[] }
        Returns: Json
      }
      search_refresh: {
        Args: { subject_id: string; subject_type: string }
        Returns: boolean
      }
      search_reindex: { Args: { subject_type?: string }; Returns: number }
      search_remove: {
        Args: { subject_id: string; subject_type: string }
        Returns: boolean
      }
      search_star: {
        Args: { starred: boolean; subject_id: string; subject_type: string }
        Returns: boolean
      }
      search_supplier_items: {
        Args: {
          query: string
          row_limit?: number
          supplier?: string
          tenant: string
        }
        Returns: Json
      }
      search_touch: {
        Args: { subject_id: string; subject_type: string }
        Returns: boolean
      }
      seed_accounting_defaults: {
        Args: { p_locale?: string; p_tenant: string; p_variant?: string }
        Returns: undefined
      }
      seed_attachments_defaults: {
        Args: { p_locale?: string; p_tenant: string; p_variant?: string }
        Returns: undefined
      }
      seed_calendar_defaults: {
        Args: { p_locale?: string; p_tenant: string; p_variant?: string }
        Returns: undefined
      }
      seed_cases_defaults: {
        Args: { p_locale?: string; p_tenant: string; p_variant?: string }
        Returns: undefined
      }
      seed_inbox_defaults: {
        Args: { p_locale?: string; p_tenant: string; p_variant?: string }
        Returns: undefined
      }
      seed_pipelines_defaults: {
        Args: { p_locale?: string; p_tenant: string; p_variant?: string }
        Returns: undefined
      }
      seed_risks_defaults: {
        Args: { p_locale?: string; p_tenant: string; p_variant?: string }
        Returns: undefined
      }
      segment_get: { Args: { segment: string }; Returns: Json }
      segments_list: {
        Args: { subject_type?: string; tenant: string }
        Returns: Json
      }
      segments_of: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      select_order_variant: { Args: { id: string }; Returns: Json }
      select_quote_variant: {
        Args: { options?: Json; quote: string }
        Returns: Json
      }
      send_contract_for_signature: {
        Args: {
          contract_id: string
          message?: string
          sign_order?: string
          signers: string[]
        }
        Returns: Json
      }
      send_inbox_draft: { Args: { draft: string; input?: Json }; Returns: Json }
      send_inbox_message: {
        Args: { conversation: string; input: Json }
        Returns: Json
      }
      send_message: {
        Args: {
          attachments?: string[]
          attrs?: Json
          body: string
          conversation: string
        }
        Returns: Json
      }
      send_notification: { Args: { notification: Json }; Returns: Json }
      send_notifications: { Args: { events: Json }; Returns: Json }
      send_order_to_kitchen: {
        Args: { notes: Json; order_id: string }
        Returns: number
      }
      send_quote: { Args: { actor?: Json; quote: string }; Returns: Json }
      sequence_step_failed: {
        Args: { enrollment_id: string; error: string; step: string }
        Returns: Json
      }
      sequence_step_sent: {
        Args: { enrollment_id: string; message_id: string; step: string }
        Returns: Json
      }
      service_principals_list: { Args: { tenant: string }; Returns: Json }
      sessions_overview: { Args: Record<PropertyKey, never>; Returns: Json }
      set_accounting_account_role: {
        Args: { account_id: string; role: string; tenant: string }
        Returns: Json
      }
      set_accounting_fx_rate: {
        Args: {
          base: string
          on_date: string
          quote: string
          rate: number
          tenant: string
        }
        Returns: Json
      }
      set_accounting_lock_date: {
        Args: { lock_date: string; tenant: string }
        Returns: Json
      }
      set_active_stream: {
        Args: { conversation: string; stream_id?: string }
        Returns: Json
      }
      set_agent_skills: {
        Args: { agent_id: string; skills: Json }
        Returns: number
      }
      set_ai_message_embedding: {
        Args: {
          chat_id: string
          embedding: string
          message_id: string
          model?: string
          tenant: string
          user_id: string
        }
        Returns: boolean
      }
      set_ai_provider_file: {
        Args: {
          expires_at?: string
          file_id: string
          provider: string
          reference: string
        }
        Returns: boolean
      }
      set_ai_run_cost: {
        Args: { cost_micro_usd: number; generation_id: string; usage?: Json }
        Returns: boolean
      }
      set_ai_tool_policy: {
        Args: { policy: string; tenant: string; tool: string }
        Returns: Json
      }
      set_appraisal_competencies: {
        Args: { competencies: Json; cycle_id: string }
        Returns: Json
      }
      set_appraisal_goals: {
        Args: { appraisal_id: string; goal_ids: string[] }
        Returns: Json
      }
      set_asset_link: {
        Args: { asset_id?: string; target_id: string; target_type: string }
        Returns: Json
      }
      set_assignment_members: {
        Args: { members: Json; queue: string }
        Returns: Json
      }
      set_attachment_status: {
        Args: { detail?: string; id: string; status: string }
        Returns: Json
      }
      set_booking_availability: {
        Args: { resource: string; source: Json }
        Returns: number
      }
      set_bot_mode: {
        Args: { conversation: string; mode: string; reason?: string }
        Returns: Json
      }
      set_calendar_attendee: {
        Args: {
          email: string
          event_id: string
          name: string
          role: string
          user_id: string
        }
        Returns: boolean
      }
      set_calendar_working_hours: {
        Args: { hours: Json; tenant: string; tz: string; user_id: string }
        Returns: number
      }
      set_cart_details: {
        Args: {
          billing_address?: Json
          cart: string
          email?: string
          shipping_address?: Json
        }
        Returns: boolean
      }
      set_cart_line: {
        Args: { cart: string; quantity: number; variant: string }
        Returns: Json
      }
      set_cart_shipping_rate: {
        Args: { cart: string; rate: string }
        Returns: boolean
      }
      set_channel_listing: {
        Args: { channel: string; listed: boolean; products: string[] }
        Returns: number
      }
      set_company_person: {
        Args: {
          company: string
          is_primary: boolean
          person: string
          role: string
        }
        Returns: boolean
      }
      set_contract_obligation_status: {
        Args: { obligation_id: string; status: string }
        Returns: Json
      }
      set_conversation_notify: {
        Args: { conversation: string; level: string }
        Returns: boolean
      }
      set_conversation_status: {
        Args: { conversation: string; snoozed_until?: string; status: string }
        Returns: Json
      }
      set_deal_contacts: {
        Args: { contacts: Json; deal: string }
        Returns: number
      }
      set_deal_lines: { Args: { lines: Json; parent: string }; Returns: Json }
      set_deal_members: {
        Args: { deal: string; members: Json }
        Returns: number
      }
      set_default_legal_entity: {
        Args: { legal_entity_id: string }
        Returns: Json
      }
      set_default_template: {
        Args: { on_default: boolean; template_id: string }
        Returns: boolean
      }
      set_default_view: {
        Args: { on_default: boolean; view_id: string }
        Returns: boolean
      }
      set_delivery_status: {
        Args: {
          channel: string
          error?: string
          external_id: string
          status: string
        }
        Returns: number
      }
      set_document_delivery_preferences: {
        Args: { party: string; prefs: Json }
        Returns: Json
      }
      set_document_template_active: {
        Args: { active: boolean; template_id: string }
        Returns: Json
      }
      set_e_invoice_delivery_state: {
        Args: {
          delivery: string
          invoice?: string
          reason?: string
          state: string
        }
        Returns: Json
      }
      set_enrollment_dates: {
        Args: { dates: Json; enrollment_id: string }
        Returns: Json
      }
      set_field_value: {
        Args: {
          definition: string
          legal_entity?: string
          subject_id: string
          subject_type: string
          tenant: string
          value: string
        }
        Returns: Json
      }
      set_flag_override: {
        Args: {
          context?: string
          context_key?: string
          key: string
          member?: string
          tenant?: string
          variant: string
        }
        Returns: boolean
      }
      set_inbound_event_status: {
        Args: {
          error?: string
          event: string
          lease?: string
          retry_in?: string
          status: string
        }
        Returns: boolean
      }
      set_inbox_member: {
        Args: { inbox: string; member: string; role?: string }
        Returns: boolean
      }
      set_inbox_team_member: {
        Args: { member: string; present?: boolean; team: string }
        Returns: boolean
      }
      set_incident_impacts: {
        Args: { impacts: Json; incident_id: string }
        Returns: Json
      }
      set_inspection_members: {
        Args: { inspection_id: string; members: Json }
        Returns: Json
      }
      set_invoice_approval_levels: {
        Args: { legal_entity_id?: string; levels: Json; tenant: string }
        Returns: Json
      }
      set_invoice_dunning_levels: {
        Args: { levels: Json; tenant: string }
        Returns: Json
      }
      set_invoice_e_endpoint: {
        Args: {
          endpoint_id?: string
          party_id: string
          party_kind: string
          scheme?: string
          tenant: string
        }
        Returns: Json
      }
      set_invoice_lines: {
        Args: { lines: Json; parent: string }
        Returns: Json
      }
      set_knowledge_collection_grant: {
        Args: {
          collection_id: string
          granted?: boolean
          team_id?: string
          user_id?: string
        }
        Returns: boolean
      }
      set_knowledge_embeddings: {
        Args: { document_id: string; embeddings: Json; model?: string }
        Returns: number
      }
      set_legal_entity_archived: {
        Args: { archived?: boolean; legal_entity_id: string }
        Returns: Json
      }
      set_legal_entity_setting: {
        Args: { key: string; legal_entity_id: string; value: Json }
        Returns: Json
      }
      set_lifecycle_flag: {
        Args: {
          enabled: boolean
          flag: string
          subject_id: string
          subject_type: string
        }
        Returns: boolean
      }
      set_line_preparation: {
        Args: { line: string; state: string }
        Returns: Json
      }
      set_location_active: {
        Args: { active: boolean; location: string }
        Returns: boolean
      }
      set_location_address: {
        Args: { address: Json; location: string }
        Returns: boolean
      }
      set_mail_account_status: {
        Args: { account: string; error: string; status: string }
        Returns: boolean
      }
      set_maintenance_request_assignees: {
        Args: { users: string[]; work_item: string }
        Returns: number
      }
      set_maintenance_request_recurrence: {
        Args: { rrule: string; tzid?: string; work_item: string }
        Returns: Json
      }
      set_meeting_attendee: {
        Args: {
          attendance?: string
          meeting_id: string
          role?: string
          user_id: string
        }
        Returns: Json
      }
      set_memory_embedding: {
        Args: {
          content_hash?: string
          embedding: string
          memory_id: string
          model?: string
        }
        Returns: boolean
      }
      set_memory_embeddings: {
        Args: { items: Json; model?: string }
        Returns: number
      }
      set_notification_cadence: {
        Args: {
          cadence: string
          channel: string
          tenant?: string
          type: string
        }
        Returns: undefined
      }
      set_notification_preference: {
        Args: {
          channel: string
          enabled: boolean
          tenant?: string
          type: string
        }
        Returns: undefined
      }
      set_notification_subscription: {
        Args: {
          if_absent?: boolean
          level: string
          member?: string
          subject_id: string
          subject_type: string
          tenant?: string
        }
        Returns: undefined
      }
      set_object_scan: {
        Args: { bucket: string; detail?: string; path: string; status: string }
        Returns: Json
      }
      set_order_tax_transaction: {
        Args: { order_id: string; tax_transaction: Json }
        Returns: boolean
      }
      set_order_variant: {
        Args: { id: string; label?: string; variant_of: string }
        Returns: Json
      }
      set_organization_setting: {
        Args: { key: string; tenant: string; value: Json }
        Returns: Json
      }
      set_party_discount_group: {
        Args: { group: string; party: string; tenant: string }
        Returns: boolean
      }
      set_party_roles: {
        Args: { party: string; roles: string[] }
        Returns: Json
      }
      set_permission_override: {
        Args: {
          granted: boolean
          permission: string
          role: string
          tenant: string
        }
        Returns: Json
      }
      set_pick_route: {
        Args: { line_ids: string[]; pick_list_id: string }
        Returns: Json
      }
      set_pipeline_transitions: {
        Args: { pairs: Json; pipeline: string }
        Returns: number
      }
      set_platform_setting: {
        Args: { key: string; value: Json }
        Returns: Json
      }
      set_post_state: { Args: { attrs: Json; post_id: string }; Returns: Json }
      set_price: {
        Args: {
          amount: string
          compare_at: string
          currency: string
          price_list: string
          valid_from: string
          valid_until: string
          variant: string
        }
        Returns: Json
      }
      set_product_categories: {
        Args: { categories: string[]; product: string }
        Returns: boolean
      }
      set_product_options: {
        Args: { options: Json; product: string; title_separator?: string }
        Returns: Json
      }
      set_product_status: {
        Args: { product: string; status: string }
        Returns: Json
      }
      set_product_translation: {
        Args: {
          description: string
          locale: string
          product: string
          title: string
        }
        Returns: boolean
      }
      set_promotion_active: {
        Args: { active: boolean; promotion: string }
        Returns: boolean
      }
      set_quote_lines: { Args: { lines: Json; parent: string }; Returns: Json }
      set_reorder_point: {
        Args: { location: string; reorder_point: number; variant: string }
        Returns: boolean
      }
      set_retention_policy: {
        Args: { keep: string; kind: string; plan?: string; tenant?: string }
        Returns: Json
      }
      set_risk_treatment: {
        Args: { note?: string; risk_id: string; treatment: string }
        Returns: Json
      }
      set_rule_enabled: {
        Args: { enabled: boolean; id: string }
        Returns: Json
      }
      set_service_principal_role: {
        Args: { created_by?: string; principal: string; role: string }
        Returns: boolean
      }
      set_shift_availability: {
        Args: {
          from_time?: string
          kind: string
          note?: string
          on_date: string
          tenant: string
          until_time?: string
          user_id?: string
        }
        Returns: Json
      }
      set_shipment_label: {
        Args: {
          carrier: string
          currency: string
          label_cost: number
          label_format?: string
          label_id: string
          label_url?: string
          service: string
          shipment_id: string
          tracking_number: string
          tracking_url?: string
        }
        Returns: Json
      }
      set_shipment_lines: {
        Args: { lines: Json; shipment_id: string }
        Returns: Json
      }
      set_stock_item: {
        Args: {
          costing: string
          currency: string
          scale: number
          tracking: string
          tracks_expiry: boolean
          unit: string
          variant: string
        }
        Returns: Json
      }
      set_supplier_item_mapping: {
        Args: {
          columns: Json
          defaults?: Json
          supplier: string
          tenant: string
        }
        Returns: Json
      }
      set_supplier_status: {
        Args: { party: string; reason?: string; status: string }
        Returns: Json
      }
      set_time_rate: {
        Args: {
          cost_amount?: number
          currency: string
          effective_from?: string
          rate: number
          subject_id?: string
          subject_type?: string
          tenant: string
          user_id?: string
        }
        Returns: Json
      }
      set_trusted_flagger: {
        Args: {
          active?: boolean
          awarded_by?: string
          name?: string
          tenant: string
          user_id: string
        }
        Returns: Json
      }
      set_typing: {
        Args: { actor?: string; conversation: string; typing?: boolean }
        Returns: boolean
      }
      set_usage_price: {
        Args: {
          currency: string
          included?: number
          label?: string
          meter: string
          unit_amount: number
        }
        Returns: Json
      }
      set_usage_quota: {
        Args: {
          meter: string
          period?: string
          plan: string
          quota_limit: number
          tenant: string
        }
        Returns: undefined
      }
      set_user_setting: { Args: { key: string; value: Json }; Returns: Json }
      set_user_state: {
        Args: { starred: boolean; subject_id: string; subject_type: string }
        Returns: boolean
      }
      set_variant_discount_group: {
        Args: { group: string; variant: string }
        Returns: boolean
      }
      set_variant_status: {
        Args: { status: string; variant: string }
        Returns: Json
      }
      set_variant_trade_code: {
        Args: { trade_code: string; variant: string }
        Returns: boolean
      }
      set_variant_translation: {
        Args: { locale: string; title: string; variant: string }
        Returns: boolean
      }
      set_view_preference: {
        Args: {
          hide: boolean
          make_default: boolean
          pin: boolean
          view_id: string
        }
        Returns: Json
      }
      set_work_item_assignees: {
        Args: { users: string[]; work_item: string }
        Returns: number
      }
      set_work_item_recurrence: {
        Args: { rrule: string; tzid?: string; work_item: string }
        Returns: Json
      }
      set_work_order_status: {
        Args: { note?: string; status: string; work_order_id: string }
        Returns: Json
      }
      set_workflow_definition_grant: {
        Args: {
          action: string
          definition: string
          granted?: boolean
          principal_id: string
          principal_kind: string
        }
        Returns: boolean
      }
      set_workflow_definition_purpose: {
        Args: { definition: string; is_default?: boolean; purpose: string }
        Returns: Json
      }
      set_workflow_opt_out: {
        Args: { definition: string; opted_out?: boolean; tenant: string }
        Returns: boolean
      }
      set_workflow_run_engine: {
        Args: { engine: string; external_id: string; run: string }
        Returns: Json
      }
      settle_approval: {
        Args: { outcome: string; reason?: string; request_id: string }
        Returns: Json
      }
      setup_accounting: {
        Args: {
          fiscal_year_start_month?: number
          functional_currency?: string
          tenant: string
        }
        Returns: Json
      }
      share_ai_chat: { Args: { chat: string; leaf?: string }; Returns: Json }
      shift_hours: {
        Args: { tenant: string; week_start: string }
        Returns: Json
      }
      shifts_to_time_entries: {
        Args: { tenant: string; until?: string }
        Returns: number
      }
      ship_fulfillment: {
        Args: {
          carrier?: string
          fulfillment: string
          tracking_number?: string
          tracking_url?: string
        }
        Returns: boolean
      }
      ship_transfer: { Args: { transfer: string }; Returns: boolean }
      shipping_options: { Args: { cart: string }; Returns: Json }
      shop_orders: { Args: { tenant: string }; Returns: Json }
      shop_products: {
        Args: { currency: string; tenant: string }
        Returns: Json
      }
      shop_stock_levels: { Args: { tenant: string }; Returns: Json }
      sign_off_appraisal: { Args: { appraisal_id: string }; Returns: Json }
      sign_prescription: { Args: { prescription_id: string }; Returns: Json }
      sign_signature: {
        Args: {
          image_attachment_id?: string
          method: string
          request_id: string
          typed_name?: string
        }
        Returns: Json
      }
      signing_jwks: {
        Args: { grace?: string; owner_id: string; owner_type: string }
        Returns: Json
      }
      signing_key: {
        Args: { owner_id: string; owner_type: string }
        Returns: Json
      }
      sla_clocks_of: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      sla_due_at: {
        Args: { business: boolean; minutes: number; start: string }
        Returns: string
      }
      snapshot_version: {
        Args: {
          content?: Json
          label?: string
          storage_path?: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      sources_ready_to_invoice: {
        Args: { party?: Json; tenant: string }
        Returns: Json
      }
      split_calendar_event: {
        Args: {
          before_rrule: string
          event_id: string
          item: Json
          split_at: string
        }
        Returns: Json
      }
      sso_access_token_check: { Args: { event: Json }; Returns: Json }
      sso_domain_for: { Args: { email: string }; Returns: Json }
      sso_provider: {
        Args: { actor?: string; provider: string }
        Returns: Json
      }
      start_ai_task_run: { Args: { id: string }; Returns: Json }
      start_bulk: {
        Args: {
          action: string
          args: Json
          ids: string[]
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      start_care_plan_action: { Args: { action_id: string }; Returns: Json }
      start_conversation: {
        Args: { inbox: string; input?: Json }
        Returns: Json
      }
      start_course_lesson: { Args: { lesson_id: string }; Returns: Json }
      start_import: {
        Args: { mapping: Json; source: string; tenant: string }
        Returns: Json
      }
      start_import_run: {
        Args: { options?: Json; source: string; tenant: string }
        Returns: Json
      }
      start_inspection: { Args: { inspection_id: string }; Returns: Json }
      start_meeting: { Args: { meeting_id: string }; Returns: Json }
      start_production_operation: {
        Args: { operation_id: string }
        Returns: Json
      }
      start_sla_clocks: {
        Args: {
          priority: string
          subject_id: string
          subject_type: string
          trusted?: boolean
        }
        Returns: Json
      }
      start_test_run: {
        Args: {
          definition: string
          input?: Json
          stubs?: Json
          trigger_node?: string
          version?: string
        }
        Returns: Json
      }
      start_timer: {
        Args: {
          billable?: boolean
          note?: string
          rate?: number
          rate_currency?: string
          subject_id?: string
          subject_type?: string
          tenant: string
        }
        Returns: Json
      }
      status_state: {
        Args: { subject_id: string; subject_type: string }
        Returns: Json
      }
      stock_count_updated_at: { Args: { subject_id: string }; Returns: string }
      stock_detail: {
        Args: { location: string; variant: string }
        Returns: Json
      }
      stock_valuation: { Args: { variant: string }; Returns: Json }
      stop_medication_order: {
        Args: { order_id: string; reason: string }
        Returns: Json
      }
      stop_timer: { Args: { entry?: string; tenant: string }; Returns: Json }
      store_ai_file: {
        Args: {
          byte_size: number
          chat_id?: string
          filename: string
          media_type: string
          owner: string
          sha256?: string
          source?: string
          tenant: string
        }
        Returns: Json
      }
      store_inbound_event: {
        Args: {
          adapter: string
          body: string
          external_id?: string
          headers?: Json
          inbox?: string
          tenant?: string
        }
        Returns: Json
      }
      storefront_products: {
        Args: Record<PropertyKey, never>
        Returns: string[]
      }
      storefront_tenants: {
        Args: Record<PropertyKey, never>
        Returns: string[]
      }
      stream_append: {
        Args: { chunks: string[]; from_idx: number; stream_id: string }
        Returns: Json
      }
      stream_cancel: { Args: { stream_id: string }; Returns: boolean }
      stream_close: { Args: { stream_id: string }; Returns: boolean }
      stream_kv_get: { Args: { key: string }; Returns: string }
      stream_kv_incr: { Args: { key: string }; Returns: number }
      stream_kv_publish: {
        Args: { channel: string; message: string }
        Returns: number
      }
      stream_kv_set: {
        Args: { ex?: number; key: string; value: string }
        Returns: string
      }
      stream_open: {
        Args: {
          kind?: string
          owner?: string
          stream_id: string
          tenant?: string
          ttl?: string
          wake?: boolean
        }
        Returns: boolean
      }
      stream_read: {
        Args: { from_idx?: number; max?: number; stream_id: string }
        Returns: Json
      }
      stream_status: { Args: { stream_id: string }; Returns: Json }
      subject_access_log: {
        Args: {
          max_rows?: number
          since?: string
          subject_id: string
          subject_type: string
        }
        Returns: Json
      }
      subject_presence_allowed: { Args: { topic: string }; Returns: boolean }
      subject_scores: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: Json
      }
      subject_tags: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: Json
      }
      subject_title: {
        Args: { subject_id: string; subject_type: string }
        Returns: string
      }
      subject_titles: { Args: { refs: Json }; Returns: Json }
      subject_types: { Args: Record<PropertyKey, never>; Returns: string[] }
      subject_url: {
        Args: { subject_id: string; subject_type: string }
        Returns: string
      }
      subjects_tags: {
        Args: { subject_ids: string[]; subject_type: string; tenant: string }
        Returns: Json
      }
      submit_appraisal_review: {
        Args: { input: Json; review_id: string }
        Returns: Json
      }
      submit_course_quiz: {
        Args: { answers: Json; lesson_id: string }
        Returns: Json
      }
      submit_expense_report: { Args: { report_id: string }; Returns: Json }
      submit_form: {
        Args: {
          answers: Json
          draft?: boolean
          form_id: string
          subject_id?: string
          subject_type?: string
          submission_id?: string
        }
        Returns: Json
      }
      submit_incident_filing: {
        Args: {
          incident_id: string
          notes?: string
          reference?: string
          regime: string
          stage: string
          submitted_at?: string
        }
        Returns: Json
      }
      submit_notice: {
        Args: {
          explanation: string
          notifier_email?: string
          notifier_name?: string
          subject_id: string
          subject_type: string
          tenant: string
          url?: string
        }
        Returns: Json
      }
      submit_public_form: {
        Args: { answers: Json; bot_token?: string; token: string }
        Returns: Json
      }
      submit_scorecard: {
        Args: {
          application: string
          notes: string
          rating: number
          recommendation: string
        }
        Returns: Json
      }
      submit_timesheet: {
        Args: { note?: string; tenant: string; week: string }
        Returns: Json
      }
      suggest_ai_document_edit: {
        Args: {
          description?: string
          document_id: string
          original_text: string
          suggested_text: string
        }
        Returns: Json
      }
      suggest_bank_matches: { Args: { transaction_id: string }; Returns: Json }
      suggest_document_change: {
        Args: { document_id: string; payload: string; summary?: string }
        Returns: Json
      }
      suggest_inbox_draft: {
        Args: { conversation: string; input: Json; metadata?: Json }
        Returns: Json
      }
      suggest_putaway: { Args: { input: Json; tenant: string }; Returns: Json }
      suggest_receipt_putaway: { Args: { receipt_id: string }; Returns: Json }
      suggest_slotting: { Args: { input: Json; tenant: string }; Returns: Json }
      supplier_item_from_row: {
        Args: { source: Json; supplier: string; tenant: string }
        Returns: Json
      }
      supplier_item_mapping: {
        Args: { supplier: string; tenant: string }
        Returns: Json
      }
      supplier_item_updated_at: {
        Args: { subject_id: string }
        Returns: string
      }
      supplier_status_from_qualifications: {
        Args: { party: string }
        Returns: string
      }
      suppress_notification_address: {
        Args: {
          address: string
          channel?: string
          detail?: Json
          provider?: string
          provider_event_id?: string
          reason: string
        }
        Returns: boolean
      }
      switch_ai_branch: {
        Args: { chat: string; message_id: string }
        Returns: Json
      }
      switch_organization: { Args: { organization: string }; Returns: Json }
      sync_profile: { Args: { user_id: string }; Returns: boolean }
      sync_rule_fields: {
        Args: { fields: Json; subject_type: string }
        Returns: number
      }
      sync_templates: { Args: { starters: Json }; Returns: number }
      sync_workflow_node_kinds: { Args: { kinds: Json }; Returns: number }
      sync_workflow_steps: { Args: { steps: Json }; Returns: number }
      tag: {
        Args: {
          subject_id: string
          subject_type: string
          tag_id: string
          tenant: string
        }
        Returns: boolean
      }
      take_forecast_snapshot: {
        Args: {
          currency: string
          pipeline: string
          since: string
          target?: number
          tenant: string
          until: string
        }
        Returns: Json
      }
      team_ids_of: { Args: { member: string }; Returns: string[] }
      technician_day: {
        Args: { day: string; technician?: string; tenant: string }
        Returns: Json
      }
      template_applications_list: {
        Args: {
          subject_id: string
          subject_type: string
          template_id: string
          tenant: string
        }
        Returns: Json
      }
      template_apply_target: {
        Args: { template_id: string; tenant: string }
        Returns: Json
      }
      template_get: { Args: { template_id: string }; Returns: Json }
      template_schedules_list: {
        Args: { template_id: string; tenant: string }
        Returns: Json
      }
      template_versions_list: { Args: { template_id: string }; Returns: Json }
      template_workflow_input_errors: {
        Args: { definition: string; inputs: Json }
        Returns: string[]
      }
      template_workflows_list: { Args: { template_id: string }; Returns: Json }
      templates_list: {
        Args: { language: string; tenant: string; type: string }
        Returns: Json
      }
      tenant_disabled: { Args: { tenant: string }; Returns: boolean }
      tenant_entitlement_value: {
        Args: { key: string; tenant: string }
        Returns: Json
      }
      tenant_entitlements: { Args: { tenant: string }; Returns: string[] }
      tenant_ids_with: { Args: { permission: string }; Returns: string[] }
      tenant_ids_with_entitlement: { Args: { key: string }; Returns: string[] }
      tenant_ids_with_flag: { Args: { key: string }; Returns: string[] }
      tenant_plans: { Args: { tenant: string }; Returns: string[] }
      terminate_lease: {
        Args: {
          deposit_deduction?: number
          lease_id: string
          reason?: string
          terminates_on?: string
        }
        Returns: Json
      }
      thread_summary: {
        Args: { conversation?: string; thread?: string }
        Returns: Json
      }
      time_lines_for_invoice: {
        Args: { group_by: string; scope: Json; tenant: string }
        Returns: Json
      }
      time_rate: {
        Args: {
          on_day?: string
          subject_id?: string
          subject_type?: string
          tenant: string
          user_id?: string
        }
        Returns: Json
      }
      time_week: { Args: { at: string }; Returns: string }
      top_scores: {
        Args: {
          band?: string
          min_score?: number
          model_key: string
          page_size?: number
          tenant: string
        }
        Returns: Json
      }
      touch_ai_sandbox: { Args: { id: string }; Returns: boolean }
      track_mail: {
        Args: { hash: string; kind: string; link: number; user_agent: string }
        Returns: Json
      }
      transfer_ownership: {
        Args: { former_role?: string; new_owner: string; organization: string }
        Returns: boolean
      }
      transition: {
        Args: {
          actor?: Json
          reason?: string
          subject_id: string
          subject_type: string
          to_status: string
        }
        Returns: boolean
      }
      transition_contract: {
        Args: { action: string; contract_id: string; reason?: string }
        Returns: Json
      }
      transparency_report: {
        Args: { period_end: string; period_start: string; tenant: string }
        Returns: string
      }
      trash: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: Json
      }
      unallocate_payment: {
        Args: { actor?: Json; reference: string; tenant: string }
        Returns: Json
      }
      unassign_acknowledgement: {
        Args: { assignment_id: string }
        Returns: Json
      }
      unassign_shift: {
        Args: { assignment_id: string; reason?: string }
        Returns: Json
      }
      unban_user: { Args: { ban_id: string }; Returns: boolean }
      unbilled_time: {
        Args: { group_by?: string; scope?: Json; tenant: string }
        Returns: Json
      }
      unchecked_push_tickets: {
        Args: { max_items?: number; older_than?: string }
        Returns: Json
      }
      unenroll_from_course: {
        Args: { course_id: string; user_id?: string }
        Returns: Json
      }
      unlink: {
        Args: {
          kind: string
          source_id: string
          source_type: string
          target_id: string
          target_type: string
          tenant: string
        }
        Returns: Json
      }
      unlink_mail_thread: {
        Args: { subject_id: string; subject_type: string; thread: string }
        Returns: boolean
      }
      unlock_accounting_period: {
        Args: { period_id: string; reason: string }
        Returns: Json
      }
      unlock_ai_harness_session: {
        Args: { chat: string; harness: string; holder: string }
        Returns: boolean
      }
      unmatch_bank_transaction: {
        Args: { transaction_id: string }
        Returns: Json
      }
      unread_counts: { Args: { tenant: string }; Returns: Json }
      unregister_push_device: { Args: { token: string }; Returns: boolean }
      unregister_sso_provider: {
        Args: { actor?: string; provider: string }
        Returns: Json
      }
      unreported_usage: {
        Args: {
          max_rows?: number
          skip_meters?: string[]
          skip_tenants?: string[]
        }
        Returns: Json
      }
      unschedule_work_order: { Args: { work_order_id: string }; Returns: Json }
      unsuppress_notification_address: {
        Args: { address: string; channel?: string }
        Returns: boolean
      }
      untag: {
        Args: {
          subject_id: string
          subject_type: string
          tag_id: string
          tenant: string
        }
        Returns: boolean
      }
      update_activity: {
        Args: { attrs: Json; engagement: string; subjects: Json }
        Returns: Json
      }
      update_ai_batch: { Args: { fields: Json; id: string }; Returns: Json }
      update_ai_chat: { Args: { chat: string; fields: Json }; Returns: Json }
      update_ai_document: {
        Args: {
          content?: string
          document_id: string
          expected_version?: number
          message_id?: string
          storage_path?: string
          title?: string
        }
        Returns: Json
      }
      update_asset: { Args: { asset_id: string; patch: Json }; Returns: Json }
      update_asset_location: {
        Args: { location_id: string; patch: Json }
        Returns: Json
      }
      update_care_plan: {
        Args: { changes: Json; plan_id: string }
        Returns: Json
      }
      update_care_plan_action: {
        Args: { action_id: string; changes: Json }
        Returns: Json
      }
      update_care_plan_goal: {
        Args: { changes: Json; goal_id: string }
        Returns: Json
      }
      update_care_plan_problem: {
        Args: { changes: Json; problem_id: string }
        Returns: Json
      }
      update_case: { Args: { case_id: string; changes: Json }; Returns: Json }
      update_channel: { Args: { attrs: Json; channel: string }; Returns: Json }
      update_content_entry: {
        Args: { attrs: Json; entry_id: string }
        Returns: Json
      }
      update_contract: {
        Args: { attrs: Json; contract_id: string }
        Returns: Json
      }
      update_deals: { Args: { changes: Json }; Returns: Json }
      update_employees: {
        Args: { atomic?: boolean; changes: Json }
        Returns: Json
      }
      update_expense_line: {
        Args: {
          amount?: number
          category_id?: string
          currency?: string
          description?: string
          dimensions?: Json
          line_id: string
          merchant?: string
          spent_on?: string
        }
        Returns: Json
      }
      update_form: {
        Args: {
          description?: string
          fields?: Json
          form_id: string
          status?: string
          title?: string
        }
        Returns: Json
      }
      update_inbox: { Args: { inbox: string; patch: Json }; Returns: Json }
      update_incident: {
        Args: { attrs: Json; incident_id: string }
        Returns: Json
      }
      update_inspection: {
        Args: { changes: Json; inspection_id: string }
        Returns: Json
      }
      update_inspection_finding: {
        Args: { changes: Json; finding_id: string }
        Returns: Json
      }
      update_invitation: {
        Args: {
          invitation_id: string
          invitee_email?: string
          invitee_role?: string
          prefill?: Json
        }
        Returns: Json
      }
      update_invoice: { Args: { attrs: Json; invoice: string }; Returns: Json }
      update_knowledge_collection: {
        Args: { collection_id: string; patch: Json }
        Returns: Json
      }
      update_legal_entity: {
        Args: { legal_entity_id: string; patch: Json }
        Returns: Json
      }
      update_mail_account: {
        Args: { account: string; paused: boolean; share: string }
        Returns: Json
      }
      update_maintenance_plan: {
        Args: { changes: Json; plan_id: string }
        Returns: Json
      }
      update_maintenance_requests: {
        Args: { atomic?: boolean; changes: Json }
        Returns: Json
      }
      update_medication_order: {
        Args: { attrs: Json; order_id: string }
        Returns: Json
      }
      update_meeting: {
        Args: { changes: Json; meeting_id: string }
        Returns: Json
      }
      update_member_role: {
        Args: { member: string; organization: string; role: string }
        Returns: boolean
      }
      update_my_profile: { Args: { attrs: Json }; Returns: boolean }
      update_organization: {
        Args: { attrs: Json; organization: string }
        Returns: boolean
      }
      update_organization_domain: {
        Args: { auto_join_role?: string; enforce_sso?: boolean; id: string }
        Returns: Json
      }
      update_pledge: {
        Args: {
          amount?: number
          ends_on?: string
          pledge_id: string
          status?: string
        }
        Returns: Json
      }
      update_post: { Args: { attrs: Json; post_id: string }; Returns: Json }
      update_product_media: {
        Args: { alt: Json; media: string; variant: string }
        Returns: boolean
      }
      update_quote: { Args: { attrs: Json; quote: string }; Returns: Json }
      update_rfq: {
        Args: { input: Json; lines?: Json; rfq_id: string }
        Returns: Json
      }
      update_risk: { Args: { changes: Json; risk_id: string }; Returns: Json }
      update_tag: { Args: { name: string; tag_id: string }; Returns: boolean }
      update_team: {
        Args: { description: string; name: string; patch?: Json; team: string }
        Returns: Json
      }
      update_till: { Args: { input: Json; till_id: string }; Returns: Json }
      update_time_entry: {
        Args: { entry_id: string; patch: Json }
        Returns: Json
      }
      update_webhook_endpoint: {
        Args: { endpoint: string; fields: Json }
        Returns: Json
      }
      update_work_items: {
        Args: { atomic?: boolean; changes: Json }
        Returns: Json
      }
      update_work_order: {
        Args: {
          address?: string
          asset_id?: string
          description?: string
          location_id?: string
          priority?: string
          title?: string
          work_order_id: string
        }
        Returns: Json
      }
      upsert_ai_models: {
        Args: { models: Json; prune?: boolean }
        Returns: number
      }
      upsert_message_template: {
        Args: { input: Json; tenant: string }
        Returns: Json
      }
      usage_breakdown: {
        Args: { meter: string; tenant: string }
        Returns: Json
      }
      usage_history: {
        Args: {
          before_id?: number
          max_rows?: number
          meter?: string
          tenant: string
        }
        Returns: Json
      }
      usage_meters: { Args: Record<PropertyKey, never>; Returns: Json }
      usage_overview: { Args: { tenant: string }; Returns: Json }
      usage_quota: {
        Args: { meter: string; tenant: string }
        Returns: {
          period: string
          quota_limit: number
        }[]
      }
      usage_status: { Args: { meter: string; tenant: string }; Returns: Json }
      usage_used: {
        Args: { meter: string; period?: string; tenant: string }
        Returns: number
      }
      usage_window: {
        Args: { period?: string; tenant: string }
        Returns: {
          ends_at: string
          starts_at: string
        }[]
      }
      usage_window_start: {
        Args: { day: string; period: string; tenant: string }
        Returns: string
      }
      user_disabled: { Args: { user_id: string }; Returns: boolean }
      validate_document_template: {
        Args: { body: string; document_type: string; text_block?: boolean }
        Returns: Json
      }
      validate_workflow_graph: { Args: { graph: Json }; Returns: Json }
      variant_identifiers: { Args: { variant: string }; Returns: Json }
      variant_price: {
        Args: {
          as_of?: string
          currency: string
          price_list?: string
          variant: string
        }
        Returns: Json
      }
      variant_relations: {
        Args: { kind?: string; variant: string }
        Returns: Json
      }
      verify_api_key: {
        Args: { public_id: string; secret_hash: string }
        Returns: Json
      }
      verify_course_certificate: { Args: { code: string }; Returns: Json }
      verify_data_subject_request: {
        Args: { id: string; method: string }
        Returns: Json
      }
      verify_organization_domain: {
        Args: { actor?: string; id: string }
        Returns: Json
      }
      version_insert: {
        Args: {
          actor: string
          content: Json
          frozen: boolean
          label: string
          source: string
          storage_path: string
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: Json
      }
      void_donation_receipt: {
        Args: { reason?: string; receipt_id: string }
        Returns: Json
      }
      void_invoice: {
        Args: { actor?: Json; invoice: string; reason: string }
        Returns: Json
      }
      void_referral: {
        Args: { reason?: string; referral_id: string }
        Returns: Json
      }
      vote: {
        Args: {
          actor?: string
          subject_id: string
          subject_type: string
          tenant: string
          value: number
        }
        Returns: Json
      }
      vote_on_post: { Args: { post_id: string; value: number }; Returns: Json }
      vote_summary: {
        Args: { subject_ids: string[]; subject_type: string; tenant: string }
        Returns: Json
      }
      vote_tally: {
        Args: { subject_id: string; subject_type: string; tenant: string }
        Returns: Json
      }
      waitlist_admit: { Args: { code?: string; email: string }; Returns: Json }
      wake_snoozed_conversations: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      watch_maintenance_request: {
        Args: { level: string; work_item: string }
        Returns: boolean
      }
      watch_work_item: {
        Args: { level: string; work_item: string }
        Returns: boolean
      }
      webhook_secrets: { Args: { endpoint: string }; Returns: string[] }
      wip_valuation: { Args: { as_of?: string; tenant: string }; Returns: Json }
      withdraw_consent: {
        Args: { consent_id: string; reason?: string }
        Returns: Json
      }
      withdraw_quote: {
        Args: { actor?: Json; quote: string; reason?: string }
        Returns: Json
      }
      withdraw_rfq_quote: { Args: { quote_id: string }; Returns: Json }
      within_quota: {
        Args: { meter: string; quantity?: number; tenant: string }
        Returns: boolean
      }
      work_item_tree: { Args: { root: string }; Returns: Json }
      workflow_admission_active: { Args: { key: string }; Returns: number }
      workflow_alerts_list: { Args: { definition: string }; Returns: Json }
      workflow_credential_get: { Args: { credential: string }; Returns: Json }
      workflow_credentials_list: { Args: { tenant?: string }; Returns: Json }
      workflow_definition_get: { Args: { definition: string }; Returns: Json }
      workflow_definition_grants_list: {
        Args: { definition: string }
        Returns: Json
      }
      workflow_definitions_list: {
        Args: { subject_type?: string; tenant?: string }
        Returns: Json
      }
      workflow_graph_permissions: { Args: { graph: Json }; Returns: string[] }
      workflow_node_kinds_list: {
        Args: Record<PropertyKey, never>
        Returns: Json
      }
      workflow_node_runs_list: { Args: { run: string }; Returns: Json }
      workflow_run_get: { Args: { run: string }; Returns: Json }
      workflow_run_principal: {
        Args: { tenant?: string; version: string }
        Returns: Json
      }
      workflow_runs_list: {
        Args: {
          before?: string
          definition?: string
          max?: number
          mode?: string
          status?: string
          subject_id?: string
          subject_type?: string
          tenant?: string
        }
        Returns: Json
      }
      workflow_schedules_list: { Args: { tenant?: string }; Returns: Json }
      workflow_start_target: {
        Args: { definition: string; tenant?: string }
        Returns: Json
      }
      workflow_steps_list: { Args: Record<PropertyKey, never>; Returns: Json }
      workflow_subject_start_target: {
        Args: {
          definition: string
          subject_id: string
          subject_type: string
          tenant?: string
        }
        Returns: Json
      }
      workflow_triggers_list: { Args: { definition: string }; Returns: Json }
      workflow_version_get: { Args: { version: string }; Returns: Json }
      workflow_versions_list: { Args: { definition: string }; Returns: Json }
      workflow_webhook_target: { Args: { token: string }; Returns: Json }
      write_knowledge_chunks: {
        Args: { chunks: Json; document_id: string; model?: string }
        Returns: Json
      }
      write_off_invoice: {
        Args: { actor?: Json; invoice: string; reason?: string }
        Returns: Json
      }
      yearly_giving_summary: {
        Args: {
          donor_id: string
          donor_type: string
          tenant: string
          year?: number
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      change_requests: {
        Row: {
          created_at: string
          id: string
          organization_id: string
          status: string | null
          title: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          id?: string
          organization_id: string
          status?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          organization_id?: string
          status?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "change_requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      client_notes: {
        Row: {
          birth_date: string | null
          client_name: string
          created_at: string
          diagnosis: string | null
          id: string
          organization_id: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          birth_date?: string | null
          client_name: string
          created_at?: string
          diagnosis?: string | null
          id?: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          birth_date?: string | null
          client_name?: string
          created_at?: string
          diagnosis?: string | null
          id?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_notes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      contacts: {
        Row: {
          created_at: string
          email: string
          email_domain: string | null
          full_name: string | null
          id: string
          organization_id: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          email: string
          email_domain?: never
          full_name?: string | null
          id?: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string
          email_domain?: never
          full_name?: string | null
          id?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contacts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_tags: {
        Row: {
          created_at: string
          customer_id: string
          organization_id: string
          tag_id: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          customer_id: string
          organization_id: string
          tag_id: string
        }
        Update: {
          created_at?: string
          customer_id?: string
          organization_id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_tags_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "customer_tags_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers_with_owner"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "customer_tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_tags_tag_id_fkey"
            columns: ["tag_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      customers: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          id: string
          kvk: string | null
          logo_path: string | null
          metadata: NonNullable<Json>
          name: string
          organization_id: string
          owner_team_id: string | null
          primary_contact_id: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }
        ComputedFields: never
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          kvk?: string | null
          logo_path?: string | null
          metadata?: NonNullable<Json>
          name: string
          organization_id: string
          owner_team_id?: string | null
          primary_contact_id?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          kvk?: string | null
          logo_path?: string | null
          metadata?: NonNullable<Json>
          name?: string
          organization_id?: string
          owner_team_id?: string | null
          primary_contact_id?: string | null
          status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "customers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_primary_contact_id_fkey"
            columns: ["primary_contact_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      locations: {
        Row: {
          city: string | null
          created_at: string
          customer_id: string
          id: string
          is_primary: boolean
          label: string
          organization_id: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          city?: string | null
          created_at?: string
          customer_id: string
          id?: string
          is_primary?: boolean
          label: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          city?: string | null
          created_at?: string
          customer_id?: string
          id?: string
          is_primary?: boolean
          label?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "locations_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "locations_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers_with_owner"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "locations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      memberships: {
        Row: {
          created_at: string
          last_used_at: string | null
          organization_id: string
          role: string
          updated_at: string
          user_id: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          last_used_at?: string | null
          organization_id: string
          role: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          last_used_at?: string | null
          organization_id?: string
          role?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "memberships_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      notes: {
        Row: {
          attachments: Json | null
          body: string
          created_at: string
          customer_id: string
          embedding: string | null
          id: number
          kind: Database["public"]["Enums"]["note_kind"]
          organization_id: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          attachments?: Json | null
          body: string
          created_at?: string
          customer_id: string
          embedding?: string | null
          id?: never
          kind?: Database["public"]["Enums"]["note_kind"]
          organization_id: string
          updated_at?: string
        }
        Update: {
          attachments?: Json | null
          body?: string
          created_at?: string
          customer_id?: string
          embedding?: string | null
          id?: never
          kind?: Database["public"]["Enums"]["note_kind"]
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notes_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "notes_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers_with_owner"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "notes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          brand: string | null
          created_at: string
          id: string
          name: string
          slug: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          brand?: string | null
          created_at?: string
          id?: string
          name: string
          slug: string
          updated_at?: string
        }
        Update: {
          brand?: string | null
          created_at?: string
          id?: string
          name?: string
          slug?: string
          updated_at?: string
        }
        Relationships: []
      }
      plan_features: {
        Row: {
          feature_key: string
          included: boolean
          plan_key: string
          value: Json | null
        }
        ComputedFields: never
        Insert: {
          feature_key: string
          included?: boolean
          plan_key: string
          value?: Json | null
        }
        Update: {
          feature_key?: string
          included?: boolean
          plan_key?: string
          value?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "plan_features_plan_key_fkey"
            columns: ["plan_key"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["key"]
          },
        ]
      }
      plans: {
        Row: {
          currency: string
          key: string
          name: string
          position: number
          price_cents: number
        }
        ComputedFields: never
        Insert: {
          currency?: string
          key: string
          name: string
          position?: number
          price_cents?: number
        }
        Update: {
          currency?: string
          key?: string
          name?: string
          position?: number
          price_cents?: number
        }
        Relationships: []
      }
      projects: {
        Row: {
          budget_minor: number
          created_at: string
          currency: string
          deleted_at: string | null
          id: string
          internal_notes: string | null
          label_id: string | null
          lead_id: string | null
          name: string
          organization_id: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          budget_minor?: number
          created_at?: string
          currency?: string
          deleted_at?: string | null
          id?: string
          internal_notes?: string | null
          label_id?: string | null
          lead_id?: string | null
          name: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          budget_minor?: number
          created_at?: string
          currency?: string
          deleted_at?: string | null
          id?: string
          internal_notes?: string | null
          label_id?: string | null
          lead_id?: string | null
          name?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "projects_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_views: {
        Row: {
          created_at: string
          filters: NonNullable<Json>
          id: string
          name: string
          updated_at: string
          user_id: string | null
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          filters?: NonNullable<Json>
          id?: string
          name: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          filters?: NonNullable<Json>
          id?: string
          name?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      subscriptions: {
        Row: {
          current_period_end: string | null
          organization_id: string
          plan_key: string
          status: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          current_period_end?: string | null
          organization_id: string
          plan_key: string
          status?: string
          updated_at?: string
        }
        Update: {
          current_period_end?: string | null
          organization_id?: string
          plan_key?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscriptions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_plan_key_fkey"
            columns: ["plan_key"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["key"]
          },
        ]
      }
      tags: {
        Row: {
          color: string
          created_at: string
          id: string
          name: string
          organization_id: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          color?: string
          created_at?: string
          id?: string
          name: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          color?: string
          created_at?: string
          id?: string
          name?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      tasks: {
        Row: {
          assignee_id: string | null
          created_at: string
          due_on: string | null
          id: string
          organization_id: string
          project_id: string
          rank: string
          starts_on: string | null
          status: string
          title: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          assignee_id?: string | null
          created_at?: string
          due_on?: string | null
          id?: string
          organization_id: string
          project_id: string
          rank?: string
          starts_on?: string | null
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          assignee_id?: string | null
          created_at?: string
          due_on?: string | null
          id?: string
          organization_id?: string
          project_id?: string
          rank?: string
          starts_on?: string | null
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tasks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_project_id_fkey"
            columns: ["organization_id", "project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "tasks_project_id_fkey"
            columns: ["organization_id", "project_id"]
            isOneToOne: false
            referencedRelation: "projects_view"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
    }
    Views: {
      customers_with_owner: {
        Row: {
          id: string
          name: string
          organization_id: string
          owner_team_id: string | null
          owner_team_name: string | null
          status: string
        }
        ComputedFields: never
        Relationships: [
          {
            foreignKeyName: "customers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      projects_view: {
        Row: {
          budget_minor: number
          created_at: string
          currency: string
          deleted_at: string | null
          done_tasks: number | null
          id: string
          label_id: string | null
          lead_id: string | null
          name: string
          next_due_on: string | null
          open_tasks: number | null
          organization_id: string
          updated_at: string
        }
        ComputedFields: never
        Relationships: [
          {
            foreignKeyName: "projects_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      tasks_view: {
        Row: {
          assignee_id: string | null
          created_at: string
          due_on: string | null
          id: string
          organization_id: string
          project_id: string
          project_name: string | null
          rank: string
          starts_on: string | null
          status: string
          title: string
          updated_at: string
        }
        ComputedFields: never
        Relationships: [
          {
            foreignKeyName: "tasks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_project_id_fkey"
            columns: ["organization_id", "project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "tasks_project_id_fkey"
            columns: ["organization_id", "project_id"]
            isOneToOne: false
            referencedRelation: "projects_view"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
    }
    Functions: {
      app_table_set: {
        Args: {
          args: Json
          subject_id: string
          subject_type: string
          tenant: string
        }
        Returns: undefined
      }
      client_notes_reveal: {
        Args: { ids: string[] }
        Returns: {
          birth_date: string
          diagnosis: string
          id: string
        }[]
      }
      customer_note_counts: {
        Args: { p_customer_ids?: string[] }
        Returns: {
          customer_id: string
          last_note_at: string
          note_count: number
        }[]
      }
      customers_by_status: {
        Args: { p_limit?: number; p_status: string }
        Returns: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          id: string
          kvk: string | null
          logo_path: string | null
          metadata: NonNullable<Json>
          name: string
          organization_id: string
          owner_team_id: string | null
          primary_contact_id: string | null
          status: string
          updated_at: string
          updated_by: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "customers"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      import_customer: {
        Args: { item: Json; run: string; subject_id: string }
        Returns: Json
      }
      import_customer_updated_at: {
        Args: { subject_id: string }
        Returns: string
      }
      island_counts: { Args: { args: Json }; Returns: Json }
      my_organizations: {
        Args: Record<PropertyKey, never>
        Returns: {
          id: string
          last_used_at: string
          name: string
          plan: string
          role: string
          slug: string
        }[]
      }
      my_profile: {
        Args: Record<PropertyKey, never>
        Returns: {
          avatar_path: string
          avatar_url: string
          email: string
          full_name: string
          username: string
        }[]
      }
      organization_invitations: {
        Args: { organization: string }
        Returns: {
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          role: string
        }[]
      }
      organization_members: {
        Args: { organization: string }
        Returns: {
          avatar_path: string
          avatar_url: string
          email: string
          full_name: string
          joined_at: string
          role: string
          user_id: string
        }[]
      }
      rs_finance_overview: { Args: { p: Json }; Returns: Json }
      rs_pipeline_overview: { Args: { p: Json }; Returns: Json }
      rs_workspace_summary: { Args: { p: Json }; Returns: Json }
      search_notes: {
        Args: { k?: number; query: string }
        Returns: {
          attachments: Json | null
          body: string
          created_at: string
          customer_id: string
          embedding: string | null
          id: number
          kind: Database["public"]["Enums"]["note_kind"]
          organization_id: string
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "notes"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      search_notes_scores: {
        Args: { k?: number; query: string }
        Returns: {
          id: Json
          score: number
        }[]
      }
      set_my_avatar_path: { Args: { avatar_path: string }; Returns: undefined }
      update_my_profile: { Args: { full_name: string }; Returns: undefined }
    }
    Enums: {
      note_kind: "call" | "meeting" | "email"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  api: {
    Enums: {},
  },
  public: {
    Enums: {
      note_kind: ["call", "meeting", "email"],
    },
  },
} as const
