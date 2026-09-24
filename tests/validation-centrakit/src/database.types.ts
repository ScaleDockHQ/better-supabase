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
  public: {
    Tables: {
      agenda_calendar_connection_secrets: {
        Row: {
          connection_id: string
          created_at: string
          credentials: NonNullable<Json>
          id: string
          organization_id: string
          provider: string
          updated_at: string
        }
        Insert: {
          connection_id: string
          created_at?: string
          credentials: NonNullable<Json>
          id?: string
          organization_id: string
          provider: string
          updated_at?: string
        }
        Update: {
          connection_id?: string
          created_at?: string
          credentials?: NonNullable<Json>
          id?: string
          organization_id?: string
          provider?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_calendar_connection_secrets_connection_id_fkey"
            columns: ["connection_id"]
            isOneToOne: true
            referencedRelation: "agenda_calendar_connections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_calendar_connection_secrets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_calendar_connections: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          name: string
          organization_id: string
          provider: string
          provider_account_email: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          organization_id: string
          provider: string
          provider_account_email?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          organization_id?: string
          provider?: string
          provider_account_email?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_calendar_connections_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_calendar_feeds: {
        Row: {
          agenda_collection_id: string
          created_at: string
          created_by: string | null
          id: string
          last_accessed_at: string | null
          organization_id: string
          token: string
          updated_at: string
          user_id: string
        }
        Insert: {
          agenda_collection_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          last_accessed_at?: string | null
          organization_id: string
          token: string
          updated_at?: string
          user_id: string
        }
        Update: {
          agenda_collection_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          last_accessed_at?: string | null
          organization_id?: string
          token?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_calendar_feeds_agenda_collection_id_organization_id_fkey"
            columns: ["agenda_collection_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_collections"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_calendar_feeds_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_calendar_feeds_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      agenda_collection_grants: {
        Row: {
          agenda_collection_id: string
          created_at: string
          created_by: string | null
          id: string
          organization_id: string
          position: number
          role: string
          team_id: number | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          agenda_collection_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          organization_id: string
          position?: number
          role?: string
          team_id?: number | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          agenda_collection_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          organization_id?: string
          position?: number
          role?: string
          team_id?: number | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "agenda_collection_grants_agenda_collection_id_organization_fkey"
            columns: ["agenda_collection_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_collections"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_collection_grants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_collection_grants_team_id_organization_id_fkey"
            columns: ["team_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_collection_grants_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      agenda_collection_notification_preferences: {
        Row: {
          agenda_collection_id: string
          created_at: string
          email_cancelled_events: boolean
          email_changed_events: boolean
          email_event_responses: boolean
          email_new_events: boolean
          organization_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          agenda_collection_id: string
          created_at?: string
          email_cancelled_events?: boolean
          email_changed_events?: boolean
          email_event_responses?: boolean
          email_new_events?: boolean
          organization_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          agenda_collection_id?: string
          created_at?: string
          email_cancelled_events?: boolean
          email_changed_events?: boolean
          email_event_responses?: boolean
          email_new_events?: boolean
          organization_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_collection_notificatio_agenda_collection_id_organiz_fkey"
            columns: ["agenda_collection_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_collections"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_collection_notification_pre_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_collection_notification_preferences_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_collection_notification_reminders: {
        Row: {
          agenda_collection_id: string
          created_at: string
          days_before: number | null
          event_kind: string
          id: string
          local_time: string | null
          method: string
          offset_minutes: number | null
          organization_id: string
          position: number
          updated_at: string
          user_id: string
        }
        Insert: {
          agenda_collection_id: string
          created_at?: string
          days_before?: number | null
          event_kind: string
          id?: string
          local_time?: string | null
          method?: string
          offset_minutes?: number | null
          organization_id: string
          position?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          agenda_collection_id?: string
          created_at?: string
          days_before?: number | null
          event_kind?: string
          id?: string
          local_time?: string | null
          method?: string
          offset_minutes?: number | null
          organization_id?: string
          position?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_collection_notificati_agenda_collection_id_organiz_fkey1"
            columns: ["agenda_collection_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_collections"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_collection_notification_rem_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_collection_notification_reminders_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_collection_preferences: {
        Row: {
          agenda_collection_id: string
          created_at: string
          is_visible: boolean
          organization_id: string
          position: number | null
          updated_at: string
          user_id: string
        }
        Insert: {
          agenda_collection_id: string
          created_at?: string
          is_visible?: boolean
          organization_id: string
          position?: number | null
          updated_at?: string
          user_id: string
        }
        Update: {
          agenda_collection_id?: string
          created_at?: string
          is_visible?: boolean
          organization_id?: string
          position?: number | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_collection_preferences_agenda_collection_id_organiz_fkey"
            columns: ["agenda_collection_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_collections"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_collection_preferences_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_collection_preferences_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      agenda_collections: {
        Row: {
          color: string
          created_at: string
          created_by: string | null
          default_time_zone: string
          description: string | null
          external_calendar_id: string | null
          id: string
          is_default: boolean
          kind: string
          name: string
          organization_id: string
          owner_user_id: string | null
          position: number
          source: string
          updated_at: string
          visibility: string
        }
        Insert: {
          color: string
          created_at?: string
          created_by?: string | null
          default_time_zone?: string
          description?: string | null
          external_calendar_id?: string | null
          id?: string
          is_default?: boolean
          kind?: string
          name: string
          organization_id: string
          owner_user_id?: string | null
          position?: number
          source?: string
          updated_at?: string
          visibility?: string
        }
        Update: {
          color?: string
          created_at?: string
          created_by?: string | null
          default_time_zone?: string
          description?: string | null
          external_calendar_id?: string | null
          id?: string
          is_default?: boolean
          kind?: string
          name?: string
          organization_id?: string
          owner_user_id?: string | null
          position?: number
          source?: string
          updated_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_collections_external_calendar_fk"
            columns: ["external_calendar_id"]
            isOneToOne: false
            referencedRelation: "agenda_external_calendars"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_collections_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_collections_owner_user_id_organization_id_fkey"
            columns: ["owner_user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      agenda_external_calendars: {
        Row: {
          access_role: string | null
          color: string | null
          connection_id: string
          created_at: string
          description: string | null
          enabled: boolean
          id: string
          is_primary: boolean
          last_sync_error: string | null
          last_sync_status: string
          last_synced_at: string | null
          organization_id: string
          provider: string
          provider_calendar_id: string
          summary: string
          sync_token: string | null
          time_zone: string | null
          updated_at: string
          visibility: string
        }
        Insert: {
          access_role?: string | null
          color?: string | null
          connection_id: string
          created_at?: string
          description?: string | null
          enabled?: boolean
          id?: string
          is_primary?: boolean
          last_sync_error?: string | null
          last_sync_status?: string
          last_synced_at?: string | null
          organization_id: string
          provider: string
          provider_calendar_id: string
          summary: string
          sync_token?: string | null
          time_zone?: string | null
          updated_at?: string
          visibility?: string
        }
        Update: {
          access_role?: string | null
          color?: string | null
          connection_id?: string
          created_at?: string
          description?: string | null
          enabled?: boolean
          id?: string
          is_primary?: boolean
          last_sync_error?: string | null
          last_sync_status?: string
          last_synced_at?: string | null
          organization_id?: string
          provider?: string
          provider_calendar_id?: string
          summary?: string
          sync_token?: string | null
          time_zone?: string | null
          updated_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_external_calendars_connection_id_fkey"
            columns: ["connection_id"]
            isOneToOne: false
            referencedRelation: "agenda_calendar_connections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_external_calendars_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_external_event_mappings: {
        Row: {
          agenda_item_id: string
          created_at: string
          etag: string | null
          external_calendar_id: string
          external_event_id: string
          organization_id: string
          status: string | null
          updated_at: string
        }
        Insert: {
          agenda_item_id: string
          created_at?: string
          etag?: string | null
          external_calendar_id: string
          external_event_id: string
          organization_id: string
          status?: string | null
          updated_at?: string
        }
        Update: {
          agenda_item_id?: string
          created_at?: string
          etag?: string | null
          external_calendar_id?: string
          external_event_id?: string
          organization_id?: string
          status?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_external_event_mapping_agenda_item_id_organization__fkey"
            columns: ["agenda_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_external_event_mappings_external_calendar_id_fkey"
            columns: ["external_calendar_id"]
            isOneToOne: false
            referencedRelation: "agenda_external_calendars"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_external_event_mappings_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_item_attendees: {
        Row: {
          agenda_item_id: string
          created_at: string
          customer_contact_id: string | null
          customer_id: number | null
          display_name: string | null
          email: string | null
          id: string
          is_optional: boolean
          is_organizer: boolean
          organization_id: string
          participation_status: string
          role: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          agenda_item_id: string
          created_at?: string
          customer_contact_id?: string | null
          customer_id?: number | null
          display_name?: string | null
          email?: string | null
          id?: string
          is_optional?: boolean
          is_organizer?: boolean
          organization_id: string
          participation_status?: string
          role?: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          agenda_item_id?: string
          created_at?: string
          customer_contact_id?: string | null
          customer_id?: number | null
          display_name?: string | null
          email?: string | null
          id?: string
          is_optional?: boolean
          is_organizer?: boolean
          organization_id?: string
          participation_status?: string
          role?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "agenda_item_attendees_agenda_item_id_organization_id_fkey"
            columns: ["agenda_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_item_attendees_customer_contact_id_fkey"
            columns: ["customer_contact_id"]
            isOneToOne: false
            referencedRelation: "customer_contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_item_attendees_customer_id_organization_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_item_attendees_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_item_attendees_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      agenda_item_recurrence_dates: {
        Row: {
          agenda_item_id: string
          created_at: string
          id: string
          kind: string
          occurs_at: string
          organization_id: string
        }
        Insert: {
          agenda_item_id: string
          created_at?: string
          id?: string
          kind: string
          occurs_at: string
          organization_id: string
        }
        Update: {
          agenda_item_id?: string
          created_at?: string
          id?: string
          kind?: string
          occurs_at?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_item_recurrence_dates_agenda_item_id_organization_i_fkey"
            columns: ["agenda_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_item_recurrence_dates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_item_recurrence_rules: {
        Row: {
          agenda_item_id: string
          count: number | null
          created_at: string
          frequency: string
          interval_count: number
          month_day: number | null
          month_ordinal: number | null
          month_weekday: string | null
          organization_id: string
          until_at: string | null
          updated_at: string
          week_days: string[]
        }
        Insert: {
          agenda_item_id: string
          count?: number | null
          created_at?: string
          frequency: string
          interval_count?: number
          month_day?: number | null
          month_ordinal?: number | null
          month_weekday?: string | null
          organization_id: string
          until_at?: string | null
          updated_at?: string
          week_days?: string[]
        }
        Update: {
          agenda_item_id?: string
          count?: number | null
          created_at?: string
          frequency?: string
          interval_count?: number
          month_day?: number | null
          month_ordinal?: number | null
          month_weekday?: string | null
          organization_id?: string
          until_at?: string | null
          updated_at?: string
          week_days?: string[]
        }
        Relationships: [
          {
            foreignKeyName: "agenda_item_recurrence_rules_agenda_item_id_organization_i_fkey"
            columns: ["agenda_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_item_recurrence_rules_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_item_reminders: {
        Row: {
          agenda_item_id: string
          created_at: string
          id: string
          method: string
          offset_minutes: number
          organization_id: string
          updated_at: string
        }
        Insert: {
          agenda_item_id: string
          created_at?: string
          id?: string
          method?: string
          offset_minutes: number
          organization_id: string
          updated_at?: string
        }
        Update: {
          agenda_item_id?: string
          created_at?: string
          id?: string
          method?: string
          offset_minutes?: number
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_item_reminders_agenda_item_id_organization_id_fkey"
            columns: ["agenda_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_item_reminders_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_item_users: {
        Row: {
          agenda_item_id: string
          created_at: string
          organization_id: string
          user_id: string
        }
        Insert: {
          agenda_item_id: string
          created_at?: string
          organization_id: string
          user_id: string
        }
        Update: {
          agenda_item_id?: string
          created_at?: string
          organization_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_item_users_agenda_item_id_organization_id_fkey"
            columns: ["agenda_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_item_users_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_item_users_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      agenda_items: {
        Row: {
          agenda_collection_id: string
          created_at: string
          created_by: string | null
          description: string | null
          description_html: string | null
          ends_at: string
          external_calendar_id: string | null
          external_etag: string | null
          external_event_id: string | null
          external_html_link: string | null
          ical_uid: string
          id: string
          is_all_day: boolean
          location: string | null
          online_meeting_url: string | null
          organization_id: string
          organizer_display_name: string | null
          organizer_email: string | null
          organizer_user_id: string | null
          owner_user_id: string | null
          provider_time_zone: string | null
          recurrence_id_at: string | null
          recurrence_parent_item_id: string | null
          sequence: number
          source: string
          starts_at: string
          status: string
          task_id: string | null
          time_zone: string | null
          title: string
          transparency: string
          updated_at: string
          visibility: string
        }
        Insert: {
          agenda_collection_id: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          description_html?: string | null
          ends_at: string
          external_calendar_id?: string | null
          external_etag?: string | null
          external_event_id?: string | null
          external_html_link?: string | null
          ical_uid?: string
          id?: string
          is_all_day?: boolean
          location?: string | null
          online_meeting_url?: string | null
          organization_id: string
          organizer_display_name?: string | null
          organizer_email?: string | null
          organizer_user_id?: string | null
          owner_user_id?: string | null
          provider_time_zone?: string | null
          recurrence_id_at?: string | null
          recurrence_parent_item_id?: string | null
          sequence?: number
          source?: string
          starts_at: string
          status?: string
          task_id?: string | null
          time_zone?: string | null
          title: string
          transparency?: string
          updated_at?: string
          visibility?: string
        }
        Update: {
          agenda_collection_id?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          description_html?: string | null
          ends_at?: string
          external_calendar_id?: string | null
          external_etag?: string | null
          external_event_id?: string | null
          external_html_link?: string | null
          ical_uid?: string
          id?: string
          is_all_day?: boolean
          location?: string | null
          online_meeting_url?: string | null
          organization_id?: string
          organizer_display_name?: string | null
          organizer_email?: string | null
          organizer_user_id?: string | null
          owner_user_id?: string | null
          provider_time_zone?: string | null
          recurrence_id_at?: string | null
          recurrence_parent_item_id?: string | null
          sequence?: number
          source?: string
          starts_at?: string
          status?: string
          task_id?: string | null
          time_zone?: string | null
          title?: string
          transparency?: string
          updated_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_items_agenda_collection_id_organization_id_fkey"
            columns: ["agenda_collection_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_collections"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_items_external_calendar_fk"
            columns: ["external_calendar_id"]
            isOneToOne: false
            referencedRelation: "agenda_external_calendars"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_items_recurrence_parent_fk"
            columns: ["recurrence_parent_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_items_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_suggestion_decisions: {
        Row: {
          created_at: string
          decision: string
          id: string
          moved_end_at: string | null
          moved_start_at: string | null
          organization_id: string
          suggested_end_at: string
          suggested_start_at: string
          task_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          decision: string
          id?: string
          moved_end_at?: string | null
          moved_start_at?: string | null
          organization_id: string
          suggested_end_at: string
          suggested_start_at: string
          task_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          decision?: string
          id?: string
          moved_end_at?: string | null
          moved_start_at?: string | null
          organization_id?: string
          suggested_end_at?: string
          suggested_start_at?: string
          task_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_suggestion_decisions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_suggestion_decisions_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
        ]
      }
      agenda_task_projections: {
        Row: {
          agenda_item_id: string
          created_at: string
          organization_id: string
          task_id: string
          updated_at: string
        }
        Insert: {
          agenda_item_id: string
          created_at?: string
          organization_id: string
          task_id: string
          updated_at?: string
        }
        Update: {
          agenda_item_id?: string
          created_at?: string
          organization_id?: string
          task_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_task_projections_agenda_item_id_organization_id_fkey"
            columns: ["agenda_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_task_projections_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_task_projections_task_id_organization_id_fkey"
            columns: ["task_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      agenda_time_off_projections: {
        Row: {
          agenda_item_id: string
          created_at: string
          organization_id: string
          time_off_request_id: string
        }
        Insert: {
          agenda_item_id: string
          created_at?: string
          organization_id: string
          time_off_request_id: string
        }
        Update: {
          agenda_item_id?: string
          created_at?: string
          organization_id?: string
          time_off_request_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "agenda_time_off_projections_agenda_item_id_organization_id_fkey"
            columns: ["agenda_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "agenda_time_off_projections_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agenda_time_off_projections_time_off_request_id_organizati_fkey"
            columns: ["time_off_request_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "time_off_requests"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      ai_agent_delegations: {
        Row: {
          active_stream_id: string
          actor_user_id: string
          created_at: string
          expires_at: string
          id: string
          organization_id: string
          revoked_at: string | null
          status: string
          thread_id: string
        }
        Insert: {
          active_stream_id: string
          actor_user_id: string
          created_at?: string
          expires_at: string
          id?: string
          organization_id: string
          revoked_at?: string | null
          status?: string
          thread_id: string
        }
        Update: {
          active_stream_id?: string
          actor_user_id?: string
          created_at?: string
          expires_at?: string
          id?: string
          organization_id?: string
          revoked_at?: string | null
          status?: string
          thread_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_agent_delegations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_delegations_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_agent_run_events: {
        Row: {
          approval_id: string | null
          created_at: string
          created_by: string | null
          id: string
          kind: string
          metadata: NonNullable<Json>
          organization_id: string | null
          payload: Json | null
          request_id: string | null
          run_id: string
          sequence: number
          status: string | null
          step_id: string | null
          thread_id: string | null
          title: string | null
        }
        Insert: {
          approval_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          kind: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          payload?: Json | null
          request_id?: string | null
          run_id: string
          sequence: number
          status?: string | null
          step_id?: string | null
          thread_id?: string | null
          title?: string | null
        }
        Update: {
          approval_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          kind?: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          payload?: Json | null
          request_id?: string | null
          run_id?: string
          sequence?: number
          status?: string | null
          step_id?: string | null
          thread_id?: string | null
          title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_agent_run_events_approval_id_fkey"
            columns: ["approval_id"]
            isOneToOne: false
            referencedRelation: "approval_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_run_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_run_events_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_run_events_step_id_fkey"
            columns: ["step_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_run_steps"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_run_events_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_agent_run_handoffs: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          assigned_team_id: number | null
          assigned_user_id: string | null
          canceled_at: string | null
          id: string
          metadata: NonNullable<Json>
          organization_id: string | null
          reason: string
          recommended_action: string | null
          requested_at: string
          requested_by: string | null
          resolved_at: string | null
          resolved_by: string | null
          run_id: string
          status: string
          thread_id: string | null
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          assigned_team_id?: number | null
          assigned_user_id?: string | null
          canceled_at?: string | null
          id?: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          reason: string
          recommended_action?: string | null
          requested_at?: string
          requested_by?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          run_id: string
          status?: string
          thread_id?: string | null
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          assigned_team_id?: number | null
          assigned_user_id?: string | null
          canceled_at?: string | null
          id?: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          reason?: string
          recommended_action?: string | null
          requested_at?: string
          requested_by?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          run_id?: string
          status?: string
          thread_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_agent_run_handoffs_assigned_team_id_fkey"
            columns: ["assigned_team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_run_handoffs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_run_handoffs_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_run_handoffs_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_agent_run_steps: {
        Row: {
          attempt: number
          check_result: Json | null
          completed_at: string | null
          created_at: string
          description: string | null
          error: Json | null
          id: string
          input: Json | null
          kind: string
          metadata: NonNullable<Json>
          organization_id: string | null
          output: Json | null
          parent_step_id: string | null
          run_id: string
          sequence: number
          started_at: string | null
          status: string
          terminal: Json | null
          thread_id: string | null
          title: string
          tool_call_id: string | null
          tool_name: string | null
          updated_at: string
        }
        Insert: {
          attempt?: number
          check_result?: Json | null
          completed_at?: string | null
          created_at?: string
          description?: string | null
          error?: Json | null
          id?: string
          input?: Json | null
          kind: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          output?: Json | null
          parent_step_id?: string | null
          run_id: string
          sequence: number
          started_at?: string | null
          status: string
          terminal?: Json | null
          thread_id?: string | null
          title: string
          tool_call_id?: string | null
          tool_name?: string | null
          updated_at?: string
        }
        Update: {
          attempt?: number
          check_result?: Json | null
          completed_at?: string | null
          created_at?: string
          description?: string | null
          error?: Json | null
          id?: string
          input?: Json | null
          kind?: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          output?: Json | null
          parent_step_id?: string | null
          run_id?: string
          sequence?: number
          started_at?: string | null
          status?: string
          terminal?: Json | null
          thread_id?: string | null
          title?: string
          tool_call_id?: string | null
          tool_name?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_agent_run_steps_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_run_steps_parent_step_id_fkey"
            columns: ["parent_step_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_run_steps"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_run_steps_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_run_steps_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_agent_runs: {
        Row: {
          active_stream_id: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          id: string
          input_client_message_id: string | null
          message_id: string | null
          metadata: NonNullable<Json>
          mode: string
          model: string | null
          organization_id: string | null
          request_id: string | null
          started_at: string | null
          status: string
          summary: string | null
          thread_id: string | null
          title: string | null
          updated_at: string
          workflow_run_id: string | null
        }
        Insert: {
          active_stream_id?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          input_client_message_id?: string | null
          message_id?: string | null
          metadata?: NonNullable<Json>
          mode: string
          model?: string | null
          organization_id?: string | null
          request_id?: string | null
          started_at?: string | null
          status?: string
          summary?: string | null
          thread_id?: string | null
          title?: string | null
          updated_at?: string
          workflow_run_id?: string | null
        }
        Update: {
          active_stream_id?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          input_client_message_id?: string | null
          message_id?: string | null
          metadata?: NonNullable<Json>
          mode?: string
          model?: string | null
          organization_id?: string | null
          request_id?: string | null
          started_at?: string | null
          status?: string
          summary?: string | null
          thread_id?: string | null
          title?: string | null
          updated_at?: string
          workflow_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_agent_runs_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "chat_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_runs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_agent_runs_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_agent_tool_checkpoints: {
        Row: {
          call_key: string
          completed_at: string | null
          created_at: string
          error: Json | null
          id: string
          input_hash: string
          output: Json | null
          run_id: string
          status: string
          tool_name: string
        }
        Insert: {
          call_key: string
          completed_at?: string | null
          created_at?: string
          error?: Json | null
          id?: string
          input_hash: string
          output?: Json | null
          run_id: string
          status?: string
          tool_name: string
        }
        Update: {
          call_key?: string
          completed_at?: string | null
          created_at?: string
          error?: Json | null
          id?: string
          input_hash?: string
          output?: Json | null
          run_id?: string
          status?: string
          tool_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_agent_tool_checkpoints_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_contextual_artifact_events: {
        Row: {
          actor_user_id: string | null
          artifact_id: string
          created_at: string
          id: string
          kind: string
          metadata: NonNullable<Json>
          organization_id: string
          payload_summary: string | null
        }
        Insert: {
          actor_user_id?: string | null
          artifact_id: string
          created_at?: string
          id?: string
          kind: string
          metadata?: NonNullable<Json>
          organization_id: string
          payload_summary?: string | null
        }
        Update: {
          actor_user_id?: string | null
          artifact_id?: string
          created_at?: string
          id?: string
          kind?: string
          metadata?: NonNullable<Json>
          organization_id?: string
          payload_summary?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_contextual_artifact_events_artifact_id_organization_id_fkey"
            columns: ["artifact_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "ai_contextual_artifacts"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "ai_contextual_artifact_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_contextual_artifacts: {
        Row: {
          action_id: string
          action_version: string
          applied_at: string | null
          apply_claim_id: string | null
          apply_handler: string | null
          applying_at: string | null
          applying_by: string | null
          context_fingerprint: string
          context_kinds: NonNullable<Json>
          created_at: string
          created_by: string | null
          decided_at: string | null
          decided_by: string | null
          decision_idempotency_key: string | null
          decision_metadata: NonNullable<Json>
          id: string
          idempotency_key: string
          kind: string
          message_id: string | null
          organization_id: string
          origin_execution_policy: string
          origin_permission: string
          origin_risk: string
          origin_route: string
          payload: NonNullable<Json>
          run_id: string | null
          schema_version: number
          source_references: NonNullable<Json>
          status: string
          thread_id: string
          thread_owner_user_id: string
          thread_visibility: string
          updated_at: string
        }
        Insert: {
          action_id: string
          action_version: string
          applied_at?: string | null
          apply_claim_id?: string | null
          apply_handler?: string | null
          applying_at?: string | null
          applying_by?: string | null
          context_fingerprint: string
          context_kinds: NonNullable<Json>
          created_at?: string
          created_by?: string | null
          decided_at?: string | null
          decided_by?: string | null
          decision_idempotency_key?: string | null
          decision_metadata?: NonNullable<Json>
          id?: string
          idempotency_key: string
          kind: string
          message_id?: string | null
          organization_id: string
          origin_execution_policy: string
          origin_permission: string
          origin_risk: string
          origin_route: string
          payload: NonNullable<Json>
          run_id?: string | null
          schema_version: number
          source_references?: NonNullable<Json>
          status?: string
          thread_id: string
          thread_owner_user_id: string
          thread_visibility: string
          updated_at?: string
        }
        Update: {
          action_id?: string
          action_version?: string
          applied_at?: string | null
          apply_claim_id?: string | null
          apply_handler?: string | null
          applying_at?: string | null
          applying_by?: string | null
          context_fingerprint?: string
          context_kinds?: NonNullable<Json>
          created_at?: string
          created_by?: string | null
          decided_at?: string | null
          decided_by?: string | null
          decision_idempotency_key?: string | null
          decision_metadata?: NonNullable<Json>
          id?: string
          idempotency_key?: string
          kind?: string
          message_id?: string | null
          organization_id?: string
          origin_execution_policy?: string
          origin_permission?: string
          origin_risk?: string
          origin_route?: string
          payload?: NonNullable<Json>
          run_id?: string | null
          schema_version?: number
          source_references?: NonNullable<Json>
          status?: string
          thread_id?: string
          thread_owner_user_id?: string
          thread_visibility?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_contextual_artifacts_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "chat_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_contextual_artifacts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_contextual_artifacts_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_contextual_artifacts_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_function_settings: {
        Row: {
          created_at: string
          function_key: string
          input_template: string | null
          instructions: string | null
          max_output_tokens: number | null
          max_steps: number | null
          temperature: number | null
          timeout_ms: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          function_key: string
          input_template?: string | null
          instructions?: string | null
          max_output_tokens?: number | null
          max_steps?: number | null
          temperature?: number | null
          timeout_ms?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          function_key?: string
          input_template?: string | null
          instructions?: string | null
          max_output_tokens?: number | null
          max_steps?: number | null
          temperature?: number | null
          timeout_ms?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      ai_memory_items: {
        Row: {
          confidence: number
          content: string
          content_hash: string | null
          content_tsv: unknown
          created_at: string
          created_by: string | null
          deleted_at: string | null
          embedding: unknown
          expires_at: string | null
          id: string
          kind: string
          last_used_at: string | null
          metadata: NonNullable<Json>
          organization_id: string | null
          scope: string
          source: string
          subject_id: string
          subject_type: string
          thread_id: string | null
          updated_at: string
          use_count: number
          user_id: string | null
          visibility: string
        }
        Insert: {
          confidence?: number
          content: string
          content_hash?: never
          content_tsv?: never
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          embedding?: unknown
          expires_at?: string | null
          id?: string
          kind?: string
          last_used_at?: string | null
          metadata?: NonNullable<Json>
          organization_id?: string | null
          scope: string
          source: string
          subject_id: string
          subject_type: string
          thread_id?: string | null
          updated_at?: string
          use_count?: number
          user_id?: string | null
          visibility: string
        }
        Update: {
          confidence?: number
          content?: string
          content_hash?: never
          content_tsv?: never
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          embedding?: unknown
          expires_at?: string | null
          id?: string
          kind?: string
          last_used_at?: string | null
          metadata?: NonNullable<Json>
          organization_id?: string | null
          scope?: string
          source?: string
          subject_id?: string
          subject_type?: string
          thread_id?: string | null
          updated_at?: string
          use_count?: number
          user_id?: string | null
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_memory_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_memory_items_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_model_settings: {
        Row: {
          created_at: string
          enabled: boolean
          model_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          enabled?: boolean
          model_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          enabled?: boolean
          model_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      ai_model_use_defaults: {
        Row: {
          created_at: string
          model_id: string
          updated_at: string
          use_case: string
        }
        Insert: {
          created_at?: string
          model_id: string
          updated_at?: string
          use_case: string
        }
        Update: {
          created_at?: string
          model_id?: string
          updated_at?: string
          use_case?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_model_use_defaults_model_id_fkey"
            columns: ["model_id"]
            isOneToOne: false
            referencedRelation: "ai_model_settings"
            referencedColumns: ["model_id"]
          },
        ]
      }
      ai_telemetry_events: {
        Row: {
          cost_micros: number | null
          created_at: string
          duration_ms: number | null
          error_code: string | null
          error_message: string | null
          id: string
          idempotency_key: string | null
          input_tokens: number | null
          kind: string
          metadata: NonNullable<Json>
          model: string | null
          name: string
          organization_id: string | null
          output_tokens: number | null
          provider: string | null
          request_id: string | null
          status: string
          thread_id: string | null
          user_id: string | null
          workflow_run_id: string | null
        }
        Insert: {
          cost_micros?: number | null
          created_at?: string
          duration_ms?: number | null
          error_code?: string | null
          error_message?: string | null
          id?: string
          idempotency_key?: string | null
          input_tokens?: number | null
          kind: string
          metadata?: NonNullable<Json>
          model?: string | null
          name: string
          organization_id?: string | null
          output_tokens?: number | null
          provider?: string | null
          request_id?: string | null
          status: string
          thread_id?: string | null
          user_id?: string | null
          workflow_run_id?: string | null
        }
        Update: {
          cost_micros?: number | null
          created_at?: string
          duration_ms?: number | null
          error_code?: string | null
          error_message?: string | null
          id?: string
          idempotency_key?: string | null
          input_tokens?: number | null
          kind?: string
          metadata?: NonNullable<Json>
          model?: string | null
          name?: string
          organization_id?: string | null
          output_tokens?: number | null
          provider?: string | null
          request_id?: string | null
          status?: string
          thread_id?: string | null
          user_id?: string | null
          workflow_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_telemetry_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_telemetry_events_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_decisions: {
        Row: {
          comment: string | null
          created_at: string
          decided_by: string
          decision: string
          delegated_from_user_id: string | null
          id: string
          organization_id: string | null
          request_id: string
          step: number
        }
        Insert: {
          comment?: string | null
          created_at?: string
          decided_by: string
          decision: string
          delegated_from_user_id?: string | null
          id?: string
          organization_id?: string | null
          request_id: string
          step?: number
        }
        Update: {
          comment?: string | null
          created_at?: string
          decided_by?: string
          decision?: string
          delegated_from_user_id?: string | null
          id?: string
          organization_id?: string | null
          request_id?: string
          step?: number
        }
        Relationships: [
          {
            foreignKeyName: "approval_decisions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_decisions_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "approval_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_delegations: {
        Row: {
          created_at: string
          created_by: string | null
          delegate_employee_id: string
          employee_id: string
          ends_on: string
          id: string
          organization_id: string
          starts_on: string
          subject_type:
            | Database["public"]["Enums"]["hr_approval_subject"]
            | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          delegate_employee_id: string
          employee_id: string
          ends_on: string
          id?: string
          organization_id: string
          starts_on: string
          subject_type?:
            | Database["public"]["Enums"]["hr_approval_subject"]
            | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          delegate_employee_id?: string
          employee_id?: string
          ends_on?: string
          id?: string
          organization_id?: string
          starts_on?: string
          subject_type?:
            | Database["public"]["Enums"]["hr_approval_subject"]
            | null
        }
        Relationships: [
          {
            foreignKeyName: "approval_delegations_delegate_employee_id_organization_id_fkey"
            columns: ["delegate_employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "approval_delegations_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "approval_delegations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_events: {
        Row: {
          actor_user_id: string | null
          created_at: string
          id: string
          kind: string
          metadata: NonNullable<Json>
          organization_id: string | null
          request_id: string
        }
        Insert: {
          actor_user_id?: string | null
          created_at?: string
          id?: string
          kind: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          request_id: string
        }
        Update: {
          actor_user_id?: string | null
          created_at?: string
          id?: string
          kind?: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          request_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "approval_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_events_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "approval_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_policies: {
        Row: {
          action_key: string | null
          actor_kinds: Database["public"]["Enums"]["approval_actor_kind"][]
          allow_self: boolean
          approver_manager: boolean
          approver_mode: Database["public"]["Enums"]["approval_approver_mode"]
          approver_permission: string | null
          approver_user_ids: string[]
          conditions: NonNullable<Json>
          created_at: string
          created_by: string | null
          description: string | null
          effect: string | null
          enabled: boolean
          escalate_after_seconds: number | null
          escalate_to_permission: string | null
          expires_after_seconds: number | null
          id: string
          name: string
          organization_id: string | null
          quorum: number
          requirement: Database["public"]["Enums"]["approval_requirement"]
          updated_at: string
        }
        Insert: {
          action_key?: string | null
          actor_kinds?: Database["public"]["Enums"]["approval_actor_kind"][]
          allow_self?: boolean
          approver_manager?: boolean
          approver_mode?: Database["public"]["Enums"]["approval_approver_mode"]
          approver_permission?: string | null
          approver_user_ids?: string[]
          conditions?: NonNullable<Json>
          created_at?: string
          created_by?: string | null
          description?: string | null
          effect?: string | null
          enabled?: boolean
          escalate_after_seconds?: number | null
          escalate_to_permission?: string | null
          expires_after_seconds?: number | null
          id?: string
          name: string
          organization_id?: string | null
          quorum?: number
          requirement: Database["public"]["Enums"]["approval_requirement"]
          updated_at?: string
        }
        Update: {
          action_key?: string | null
          actor_kinds?: Database["public"]["Enums"]["approval_actor_kind"][]
          allow_self?: boolean
          approver_manager?: boolean
          approver_mode?: Database["public"]["Enums"]["approval_approver_mode"]
          approver_permission?: string | null
          approver_user_ids?: string[]
          conditions?: NonNullable<Json>
          created_at?: string
          created_by?: string | null
          description?: string | null
          effect?: string | null
          enabled?: boolean
          escalate_after_seconds?: number | null
          escalate_to_permission?: string | null
          expires_after_seconds?: number | null
          id?: string
          name?: string
          organization_id?: string | null
          quorum?: number
          requirement?: Database["public"]["Enums"]["approval_requirement"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "approval_policies_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_requests: {
        Row: {
          action_key: string
          agent_run_id: string | null
          agent_step_id: string | null
          allow_self: boolean
          approver_employee_id: string | null
          approver_mode: Database["public"]["Enums"]["approval_approver_mode"]
          approver_permission: string | null
          approver_user_id: string | null
          approver_user_ids: string[]
          consumed_at: string | null
          decided_at: string | null
          decision_reason: string | null
          employee_id: string | null
          escalate_at: string | null
          escalate_to_permission: string | null
          escalated_at: string | null
          expires_at: string | null
          explanation: Json | null
          id: string
          input: NonNullable<Json>
          input_fingerprint: string | null
          metadata: NonNullable<Json>
          on_behalf_of_user_id: string | null
          organization_id: string | null
          policy: NonNullable<Json>
          quorum: number
          requested_at: string
          requested_by: string | null
          requester_kind: Database["public"]["Enums"]["approval_actor_kind"]
          requirement: Database["public"]["Enums"]["approval_requirement"]
          response_active_stream_id: string | null
          response_approved: boolean | null
          response_idempotency_key: string | null
          response_message_id: string | null
          response_reason: string | null
          response_recorded_at: string | null
          response_run_id: string | null
          response_tool_call_id: string | null
          response_workflow_run_id: string | null
          risk: string
          source: Database["public"]["Enums"]["approval_source"]
          status: string
          step: number
          subject_id: string | null
          subject_type: string | null
          thread_id: string | null
          title: string | null
          tool_call_id: string | null
          tool_name: string | null
          updated_at: string
          workflow_node_id: string | null
          workflow_run_id: string | null
          can_decide_approval_request: boolean | null
          is_approval_approver: boolean | null
          is_approval_requester: boolean | null
        }
        Insert: {
          action_key: string
          agent_run_id?: string | null
          agent_step_id?: string | null
          allow_self?: boolean
          approver_employee_id?: string | null
          approver_mode?: Database["public"]["Enums"]["approval_approver_mode"]
          approver_permission?: string | null
          approver_user_id?: string | null
          approver_user_ids?: string[]
          consumed_at?: string | null
          decided_at?: string | null
          decision_reason?: string | null
          employee_id?: string | null
          escalate_at?: string | null
          escalate_to_permission?: string | null
          escalated_at?: string | null
          expires_at?: string | null
          explanation?: Json | null
          id?: string
          input?: NonNullable<Json>
          input_fingerprint?: string | null
          metadata?: NonNullable<Json>
          on_behalf_of_user_id?: string | null
          organization_id?: string | null
          policy?: NonNullable<Json>
          quorum?: number
          requested_at?: string
          requested_by?: string | null
          requester_kind?: Database["public"]["Enums"]["approval_actor_kind"]
          requirement?: Database["public"]["Enums"]["approval_requirement"]
          response_active_stream_id?: string | null
          response_approved?: boolean | null
          response_idempotency_key?: string | null
          response_message_id?: string | null
          response_reason?: string | null
          response_recorded_at?: string | null
          response_run_id?: string | null
          response_tool_call_id?: string | null
          response_workflow_run_id?: string | null
          risk?: string
          source: Database["public"]["Enums"]["approval_source"]
          status?: string
          step?: number
          subject_id?: string | null
          subject_type?: string | null
          thread_id?: string | null
          title?: string | null
          tool_call_id?: string | null
          tool_name?: string | null
          updated_at?: string
          workflow_node_id?: string | null
          workflow_run_id?: string | null
        }
        Update: {
          action_key?: string
          agent_run_id?: string | null
          agent_step_id?: string | null
          allow_self?: boolean
          approver_employee_id?: string | null
          approver_mode?: Database["public"]["Enums"]["approval_approver_mode"]
          approver_permission?: string | null
          approver_user_id?: string | null
          approver_user_ids?: string[]
          consumed_at?: string | null
          decided_at?: string | null
          decision_reason?: string | null
          employee_id?: string | null
          escalate_at?: string | null
          escalate_to_permission?: string | null
          escalated_at?: string | null
          expires_at?: string | null
          explanation?: Json | null
          id?: string
          input?: NonNullable<Json>
          input_fingerprint?: string | null
          metadata?: NonNullable<Json>
          on_behalf_of_user_id?: string | null
          organization_id?: string | null
          policy?: NonNullable<Json>
          quorum?: number
          requested_at?: string
          requested_by?: string | null
          requester_kind?: Database["public"]["Enums"]["approval_actor_kind"]
          requirement?: Database["public"]["Enums"]["approval_requirement"]
          response_active_stream_id?: string | null
          response_approved?: boolean | null
          response_idempotency_key?: string | null
          response_message_id?: string | null
          response_reason?: string | null
          response_recorded_at?: string | null
          response_run_id?: string | null
          response_tool_call_id?: string | null
          response_workflow_run_id?: string | null
          risk?: string
          source?: Database["public"]["Enums"]["approval_source"]
          status?: string
          step?: number
          subject_id?: string | null
          subject_type?: string | null
          thread_id?: string | null
          title?: string | null
          tool_call_id?: string | null
          tool_name?: string | null
          updated_at?: string
          workflow_node_id?: string | null
          workflow_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "approval_requests_agent_run_id_fkey"
            columns: ["agent_run_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_requests_agent_step_id_fkey"
            columns: ["agent_step_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_run_steps"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_requests_approver_employee_id_organization_id_fkey"
            columns: ["approver_employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "approval_requests_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "approval_requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_requests_response_run_id_fkey"
            columns: ["response_run_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_requests_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_requests_workflow_run_id_fkey"
            columns: ["workflow_run_id"]
            isOneToOne: false
            referencedRelation: "workflow_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_custom_attributes: {
        Row: {
          boolean_value: boolean | null
          created_at: string
          customer_asset_id: number | null
          date_value: string | null
          id: string
          key: string
          label: string
          number_value: number | null
          organization_id: string
          position: number
          product_id: string | null
          text_value: string | null
          updated_at: string
          url_value: string | null
          value_type: Database["public"]["Enums"]["asset_attribute_value_type"]
        }
        Insert: {
          boolean_value?: boolean | null
          created_at?: string
          customer_asset_id?: number | null
          date_value?: string | null
          id?: string
          key: string
          label: string
          number_value?: number | null
          organization_id: string
          position?: number
          product_id?: string | null
          text_value?: string | null
          updated_at?: string
          url_value?: string | null
          value_type: Database["public"]["Enums"]["asset_attribute_value_type"]
        }
        Update: {
          boolean_value?: boolean | null
          created_at?: string
          customer_asset_id?: number | null
          date_value?: string | null
          id?: string
          key?: string
          label?: string
          number_value?: number | null
          organization_id?: string
          position?: number
          product_id?: string | null
          text_value?: string | null
          updated_at?: string
          url_value?: string | null
          value_type?: Database["public"]["Enums"]["asset_attribute_value_type"]
        }
        Relationships: [
          {
            foreignKeyName: "asset_custom_attributes_customer_asset_id_fkey"
            columns: ["customer_asset_id"]
            isOneToOne: false
            referencedRelation: "customer_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_custom_attributes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_custom_attributes_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_images: {
        Row: {
          alt_text: string | null
          created_at: string
          id: string
          organization_id: string
          position: number
          product_id: string
          storage_path: string
          updated_at: string
        }
        Insert: {
          alt_text?: string | null
          created_at?: string
          id?: string
          organization_id: string
          position?: number
          product_id: string
          storage_path: string
          updated_at?: string
        }
        Update: {
          alt_text?: string | null
          created_at?: string
          id?: string
          organization_id?: string
          position?: number
          product_id?: string
          storage_path?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "asset_images_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_images_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_tags: {
        Row: {
          created_at: string
          customer_asset_id: number | null
          id: string
          organization_id: string
          product_id: string | null
          tag_id: string
        }
        Insert: {
          created_at?: string
          customer_asset_id?: number | null
          id?: string
          organization_id: string
          product_id?: string | null
          tag_id: string
        }
        Update: {
          created_at?: string
          customer_asset_id?: number | null
          id?: string
          organization_id?: string
          product_id?: string | null
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "asset_tags_customer_asset_id_fkey"
            columns: ["customer_asset_id"]
            isOneToOne: false
            referencedRelation: "customer_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_tags_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_tags_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "organization_tags"
            referencedColumns: ["id"]
          },
        ]
      }
      attendance_records: {
        Row: {
          auto_closed_at: string | null
          break_minutes: number
          clock_in_at: string
          clock_in_latitude: number | null
          clock_in_longitude: number | null
          clock_out_at: string | null
          created_at: string
          employee_id: string
          id: string
          note: string | null
          organization_id: string
          updated_at: string
        }
        Insert: {
          auto_closed_at?: string | null
          break_minutes?: number
          clock_in_at?: string
          clock_in_latitude?: number | null
          clock_in_longitude?: number | null
          clock_out_at?: string | null
          created_at?: string
          employee_id: string
          id?: string
          note?: string | null
          organization_id: string
          updated_at?: string
        }
        Update: {
          auto_closed_at?: string | null
          break_minutes?: number
          clock_in_at?: string
          clock_in_latitude?: number | null
          clock_in_longitude?: number | null
          clock_out_at?: string | null
          created_at?: string
          employee_id?: string
          id?: string
          note?: string | null
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "attendance_records_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "attendance_records_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_log_export_jobs: {
        Row: {
          completed_at: string | null
          downloaded_at: string | null
          error_message: string | null
          expires_at: string | null
          id: string
          include_restricted: boolean
          normalized_filters: NonNullable<Json>
          organization_id: string | null
          requested_at: string
          requested_by: string
          row_count: number | null
          scope: string
          status: string
          storage_path: string | null
          updated_at: string
          workflow_run_id: string | null
        }
        Insert: {
          completed_at?: string | null
          downloaded_at?: string | null
          error_message?: string | null
          expires_at?: string | null
          id?: string
          include_restricted?: boolean
          normalized_filters?: NonNullable<Json>
          organization_id?: string | null
          requested_at?: string
          requested_by: string
          row_count?: number | null
          scope: string
          status?: string
          storage_path?: string | null
          updated_at?: string
          workflow_run_id?: string | null
        }
        Update: {
          completed_at?: string | null
          downloaded_at?: string | null
          error_message?: string | null
          expires_at?: string | null
          id?: string
          include_restricted?: boolean
          normalized_filters?: NonNullable<Json>
          organization_id?: string | null
          requested_at?: string
          requested_by?: string
          row_count?: number | null
          scope?: string
          status?: string
          storage_path?: string | null
          updated_at?: string
          workflow_run_id?: string | null
        }
        Relationships: []
      }
      audit_log_restricted_details: {
        Row: {
          created_at: string
          event_id: string
          ip_address: unknown
          restricted_metadata: NonNullable<Json>
          session_id: string | null
          user_agent: string | null
        }
        Insert: {
          created_at?: string
          event_id: string
          ip_address?: unknown
          restricted_metadata?: NonNullable<Json>
          session_id?: string | null
          user_agent?: string | null
        }
        Update: {
          created_at?: string
          event_id?: string
          ip_address?: unknown
          restricted_metadata?: NonNullable<Json>
          session_id?: string | null
          user_agent?: string | null
        }
        Relationships: []
      }
      audit_log_table_registry: {
        Row: {
          capture_enabled: boolean
          category: string
          event_prefix: string
          organization_column: string
          registered_at: string
          table_name: string
          target_id_column: string
          target_type: string
        }
        Insert: {
          capture_enabled?: boolean
          category?: string
          event_prefix: string
          organization_column?: string
          registered_at?: string
          table_name: string
          target_id_column?: string
          target_type: string
        }
        Update: {
          capture_enabled?: boolean
          category?: string
          event_prefix?: string
          organization_column?: string
          registered_at?: string
          table_name?: string
          target_id_column?: string
          target_type?: string
        }
        Relationships: []
      }
      audit_logs: {
        Row: {
          actor_display_name: string | null
          actor_id: string | null
          actor_is_platform_admin: boolean
          actor_kind: string
          category: string
          correlation_id: string | null
          created_at: string
          event_type: string
          id: string
          idempotency_key: string | null
          occurred_at: string
          organization_id: string | null
          organization_name_snapshot: string | null
          outcome: string
          request_id: string | null
          safe_metadata: NonNullable<Json>
          scope: string
          source: string
          summary: string | null
          target_display_name: string | null
          target_id: string | null
          target_type: string | null
        }
        Insert: {
          actor_display_name?: string | null
          actor_id?: string | null
          actor_is_platform_admin?: boolean
          actor_kind: string
          category: string
          correlation_id?: string | null
          created_at?: string
          event_type: string
          id?: string
          idempotency_key?: string | null
          occurred_at?: string
          organization_id?: string | null
          organization_name_snapshot?: string | null
          outcome: string
          request_id?: string | null
          safe_metadata?: NonNullable<Json>
          scope: string
          source: string
          summary?: string | null
          target_display_name?: string | null
          target_id?: string | null
          target_type?: string | null
        }
        Update: {
          actor_display_name?: string | null
          actor_id?: string | null
          actor_is_platform_admin?: boolean
          actor_kind?: string
          category?: string
          correlation_id?: string | null
          created_at?: string
          event_type?: string
          id?: string
          idempotency_key?: string | null
          occurred_at?: string
          organization_id?: string | null
          organization_name_snapshot?: string | null
          outcome?: string
          request_id?: string | null
          safe_metadata?: NonNullable<Json>
          scope?: string
          source?: string
          summary?: string | null
          target_display_name?: string | null
          target_id?: string | null
          target_type?: string | null
        }
        Relationships: []
      }
      billing_credit_rollover_periods: {
        Row: {
          created_at: string
          credit_package_key: string
          credits_granted: number
          credits_remaining: number
          expires_at: string
          id: string
          organization_id: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          source_period_end: string
          source_period_start: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          credit_package_key: string
          credits_granted?: number
          credits_remaining?: number
          expires_at: string
          id?: string
          organization_id: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          source_period_end: string
          source_period_start: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          credit_package_key?: string
          credits_granted?: number
          credits_remaining?: number
          expires_at?: string
          id?: string
          organization_id?: string
          plan_key?: Database["public"]["Enums"]["billing_plan_key"]
          source_period_end?: string
          source_period_start?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_credit_rollover_periods_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_plan_credit_packages: {
        Row: {
          created_at: string
          display_order: number
          included_credits: number
          is_default: boolean
          label: string
          package_key: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          selectable: boolean
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          included_credits?: number
          is_default?: boolean
          label: string
          package_key: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          selectable?: boolean
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          included_credits?: number
          is_default?: boolean
          label?: string
          package_key?: string
          plan_key?: Database["public"]["Enums"]["billing_plan_key"]
          selectable?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_plan_credit_packages_plan_key_fkey"
            columns: ["plan_key"]
            isOneToOne: false
            referencedRelation: "billing_plans"
            referencedColumns: ["plan_key"]
          },
        ]
      }
      billing_plan_features: {
        Row: {
          category: string
          created_at: string
          description: string | null
          display_order: number
          feature_key: string
          id: string
          included: boolean
          label: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          updated_at: string
        }
        Insert: {
          category?: string
          created_at?: string
          description?: string | null
          display_order?: number
          feature_key: string
          id?: string
          included?: boolean
          label: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          updated_at?: string
        }
        Update: {
          category?: string
          created_at?: string
          description?: string | null
          display_order?: number
          feature_key?: string
          id?: string
          included?: boolean
          label?: string
          plan_key?: Database["public"]["Enums"]["billing_plan_key"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_plan_features_plan_key_fkey"
            columns: ["plan_key"]
            isOneToOne: false
            referencedRelation: "billing_plans"
            referencedColumns: ["plan_key"]
          },
        ]
      }
      billing_plan_prices: {
        Row: {
          amount: number
          annual_discount_bps: number
          created_at: string
          currency: string
          id: string
          interval: Database["public"]["Enums"]["billing_plan_interval"]
          lookup_key: string
          package_key: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          published_version: number
          stripe_price_id: string | null
          stripe_product_id: string | null
          updated_at: string
        }
        Insert: {
          amount?: number
          annual_discount_bps?: number
          created_at?: string
          currency?: string
          id?: string
          interval: Database["public"]["Enums"]["billing_plan_interval"]
          lookup_key: string
          package_key: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          published_version?: number
          stripe_price_id?: string | null
          stripe_product_id?: string | null
          updated_at?: string
        }
        Update: {
          amount?: number
          annual_discount_bps?: number
          created_at?: string
          currency?: string
          id?: string
          interval?: Database["public"]["Enums"]["billing_plan_interval"]
          lookup_key?: string
          package_key?: string
          plan_key?: Database["public"]["Enums"]["billing_plan_key"]
          published_version?: number
          stripe_price_id?: string | null
          stripe_product_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_plan_prices_plan_key_package_key_fkey"
            columns: ["plan_key", "package_key"]
            isOneToOne: false
            referencedRelation: "billing_plan_credit_packages"
            referencedColumns: ["plan_key", "package_key"]
          },
        ]
      }
      billing_plan_usage_limits: {
        Row: {
          base_cost_unit_price_micros: number | null
          created_at: string
          credit_weight: number
          enforcement_mode: string
          id: string
          included_quantity: number
          is_unlimited: boolean
          markup_bps: number
          meter_key: string
          overage_unit_price_micros: number
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          pricing_model: string
          reset_interval: string
          updated_at: string
        }
        Insert: {
          base_cost_unit_price_micros?: number | null
          created_at?: string
          credit_weight?: number
          enforcement_mode?: string
          id?: string
          included_quantity?: number
          is_unlimited?: boolean
          markup_bps?: number
          meter_key: string
          overage_unit_price_micros?: number
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          pricing_model?: string
          reset_interval?: string
          updated_at?: string
        }
        Update: {
          base_cost_unit_price_micros?: number | null
          created_at?: string
          credit_weight?: number
          enforcement_mode?: string
          id?: string
          included_quantity?: number
          is_unlimited?: boolean
          markup_bps?: number
          meter_key?: string
          overage_unit_price_micros?: number
          plan_key?: Database["public"]["Enums"]["billing_plan_key"]
          pricing_model?: string
          reset_interval?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_plan_usage_limits_meter_key_fkey"
            columns: ["meter_key"]
            isOneToOne: false
            referencedRelation: "billing_usage_meters"
            referencedColumns: ["key"]
          },
        ]
      }
      billing_plans: {
        Row: {
          created_at: string
          currency: string
          description: string | null
          display_order: number
          name: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          quote_only: boolean
          selectable: boolean
          status: string
          updated_at: string
          visible: boolean
        }
        Insert: {
          created_at?: string
          currency?: string
          description?: string | null
          display_order?: number
          name: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          quote_only?: boolean
          selectable?: boolean
          status?: string
          updated_at?: string
          visible?: boolean
        }
        Update: {
          created_at?: string
          currency?: string
          description?: string | null
          display_order?: number
          name?: string
          plan_key?: Database["public"]["Enums"]["billing_plan_key"]
          quote_only?: boolean
          selectable?: boolean
          status?: string
          updated_at?: string
          visible?: boolean
        }
        Relationships: []
      }
      billing_usage_meters: {
        Row: {
          billable: boolean
          category: string
          created_at: string
          description: string | null
          display_order: number
          key: string
          metadata: NonNullable<Json>
          name: string
          stripe_event_name: string | null
          unit: string
          updated_at: string
        }
        Insert: {
          billable?: boolean
          category: string
          created_at?: string
          description?: string | null
          display_order?: number
          key: string
          metadata?: NonNullable<Json>
          name: string
          stripe_event_name?: string | null
          unit: string
          updated_at?: string
        }
        Update: {
          billable?: boolean
          category?: string
          created_at?: string
          description?: string | null
          display_order?: number
          key?: string
          metadata?: NonNullable<Json>
          name?: string
          stripe_event_name?: string | null
          unit?: string
          updated_at?: string
        }
        Relationships: []
      }
      brand_images: {
        Row: {
          alt_text: string | null
          brand_id: string
          created_at: string
          id: string
          organization_id: string
          position: number
          storage_path: string
          updated_at: string
        }
        Insert: {
          alt_text?: string | null
          brand_id: string
          created_at?: string
          id?: string
          organization_id: string
          position?: number
          storage_path: string
          updated_at?: string
        }
        Update: {
          alt_text?: string | null
          brand_id?: string
          created_at?: string
          id?: string
          organization_id?: string
          position?: number
          storage_path?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "brand_images_brand_id_fkey"
            columns: ["brand_id"]
            isOneToOne: false
            referencedRelation: "brands"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "brand_images_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      brand_tags: {
        Row: {
          brand_id: string
          created_at: string
          id: string
          organization_id: string
          tag_id: string
        }
        Insert: {
          brand_id: string
          created_at?: string
          id?: string
          organization_id: string
          tag_id: string
        }
        Update: {
          brand_id?: string
          created_at?: string
          id?: string
          organization_id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "brand_tags_brand_id_fkey"
            columns: ["brand_id"]
            isOneToOne: false
            referencedRelation: "brands"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "brand_tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "brand_tags_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "organization_tags"
            referencedColumns: ["id"]
          },
        ]
      }
      brands: {
        Row: {
          created_at: string
          description: string | null
          id: string
          logo_path: string | null
          name: string
          organization_id: string
          slug: string
          updated_at: string
          website: string | null
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          logo_path?: string | null
          name: string
          organization_id: string
          slug: string
          updated_at?: string
          website?: string | null
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          logo_path?: string | null
          name?: string
          organization_id?: string
          slug?: string
          updated_at?: string
          website?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "brands_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_attachments: {
        Row: {
          bucket: string
          byte_size: number
          created_at: string
          created_by: string | null
          file_name: string
          id: string
          media_type: string
          message_id: string | null
          metadata: NonNullable<Json>
          organization_id: string | null
          path: string
          status: string
          thread_id: string
        }
        Insert: {
          bucket: string
          byte_size?: number
          created_at?: string
          created_by?: string | null
          file_name: string
          id?: string
          media_type: string
          message_id?: string | null
          metadata?: NonNullable<Json>
          organization_id?: string | null
          path: string
          status?: string
          thread_id: string
        }
        Update: {
          bucket?: string
          byte_size?: number
          created_at?: string
          created_by?: string | null
          file_name?: string
          id?: string
          media_type?: string
          message_id?: string | null
          metadata?: NonNullable<Json>
          organization_id?: string | null
          path?: string
          status?: string
          thread_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_attachments_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "chat_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_attachments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_attachments_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_message_feedback: {
        Row: {
          created_at: string
          message_id: string
          model_id: string | null
          organization_id: string
          rating: string
          run_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          message_id: string
          model_id?: string | null
          organization_id: string
          rating: string
          run_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          message_id?: string
          model_id?: string | null
          organization_id?: string
          rating?: string
          run_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_message_feedback_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "chat_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_message_feedback_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_message_feedback_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "ai_agent_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_messages: {
        Row: {
          client_message_id: string | null
          created_at: string
          created_by: string | null
          dispatch_claimed_at: string | null
          dispatch_id: string | null
          dispatch_linked_at: string | null
          id: string
          metadata: NonNullable<Json>
          organization_id: string | null
          parts: NonNullable<Json>
          role: string
          status: string
          thread_id: string
        }
        Insert: {
          client_message_id?: string | null
          created_at?: string
          created_by?: string | null
          dispatch_claimed_at?: string | null
          dispatch_id?: string | null
          dispatch_linked_at?: string | null
          id?: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          parts?: NonNullable<Json>
          role: string
          status?: string
          thread_id: string
        }
        Update: {
          client_message_id?: string | null
          created_at?: string
          created_by?: string | null
          dispatch_claimed_at?: string | null
          dispatch_id?: string | null
          dispatch_linked_at?: string | null
          id?: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          parts?: NonNullable<Json>
          role?: string
          status?: string
          thread_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_messages_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_messages_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_suggestion_snapshots: {
        Row: {
          created_at: string
          organization_id: string
          refreshed_at: string
          snapshot: NonNullable<Json>
          updated_at: string
        }
        Insert: {
          created_at?: string
          organization_id: string
          refreshed_at?: string
          snapshot?: NonNullable<Json>
          updated_at?: string
        }
        Update: {
          created_at?: string
          organization_id?: string
          refreshed_at?: string
          snapshot?: NonNullable<Json>
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_suggestion_snapshots_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_thread_participants: {
        Row: {
          channel_connection_id: string | null
          created_at: string
          customer_id: number | null
          external_actor_id: string | null
          id: string
          kind: string
          organization_id: string | null
          thread_id: string
          user_id: string | null
        }
        Insert: {
          channel_connection_id?: string | null
          created_at?: string
          customer_id?: number | null
          external_actor_id?: string | null
          id?: string
          kind: string
          organization_id?: string | null
          thread_id: string
          user_id?: string | null
        }
        Update: {
          channel_connection_id?: string | null
          created_at?: string
          customer_id?: number | null
          external_actor_id?: string | null
          id?: string
          kind?: string
          organization_id?: string | null
          thread_id?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "chat_thread_participants_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_thread_participants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_thread_participants_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_thread_share_links: {
        Row: {
          created_at: string
          created_by: string
          expires_at: string | null
          id: string
          organization_id: string
          revoked_at: string | null
          thread_id: string
          token_hash: string
        }
        Insert: {
          created_at?: string
          created_by: string
          expires_at?: string | null
          id?: string
          organization_id: string
          revoked_at?: string | null
          thread_id: string
          token_hash: string
        }
        Update: {
          created_at?: string
          created_by?: string
          expires_at?: string | null
          id?: string
          organization_id?: string
          revoked_at?: string | null
          thread_id?: string
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_thread_share_links_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_thread_share_links_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_threads: {
        Row: {
          active_stream_id: string | null
          active_workflow_run_id: string | null
          archived_at: string | null
          created_at: string
          id: string
          metadata: NonNullable<Json>
          mode: string
          organization_id: string | null
          owner_user_id: string
          pinned_at: string | null
          stream_status: string
          title: string | null
          updated_at: string
          visibility: string
        }
        Insert: {
          active_stream_id?: string | null
          active_workflow_run_id?: string | null
          archived_at?: string | null
          created_at?: string
          id?: string
          metadata?: NonNullable<Json>
          mode?: string
          organization_id?: string | null
          owner_user_id: string
          pinned_at?: string | null
          stream_status?: string
          title?: string | null
          updated_at?: string
          visibility?: string
        }
        Update: {
          active_stream_id?: string | null
          active_workflow_run_id?: string | null
          archived_at?: string | null
          created_at?: string
          id?: string
          metadata?: NonNullable<Json>
          mode?: string
          organization_id?: string | null
          owner_user_id?: string
          pinned_at?: string | null
          stream_status?: string
          title?: string | null
          updated_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_threads_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      comment_threads: {
        Row: {
          created_at: string
          customer_asset_id: number | null
          customer_id: number | null
          id: string
          invoice_id: string | null
          organization_id: string
          quote_id: string | null
          subject_id: string
          subject_type: string
          task_id: string | null
        }
        Insert: {
          created_at?: string
          customer_asset_id?: number | null
          customer_id?: number | null
          id?: string
          invoice_id?: string | null
          organization_id: string
          quote_id?: string | null
          subject_id: string
          subject_type: string
          task_id?: string | null
        }
        Update: {
          created_at?: string
          customer_asset_id?: number | null
          customer_id?: number | null
          id?: string
          invoice_id?: string | null
          organization_id?: string
          quote_id?: string | null
          subject_id?: string
          subject_type?: string
          task_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "comment_threads_customer_asset_id_fkey"
            columns: ["customer_asset_id"]
            isOneToOne: false
            referencedRelation: "customer_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comment_threads_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "comment_threads_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comment_threads_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comment_threads_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comment_threads_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
        ]
      }
      comments: {
        Row: {
          author_id: string | null
          content_doc: NonNullable<Json>
          content_text: string
          created_at: string
          id: string
          organization_id: string
          parent_id: string | null
          thread_id: string
          updated_at: string
        }
        Insert: {
          author_id?: string | null
          content_doc: NonNullable<Json>
          content_text: string
          created_at?: string
          id?: string
          organization_id: string
          parent_id?: string | null
          thread_id: string
          updated_at?: string
        }
        Update: {
          author_id?: string | null
          content_doc?: NonNullable<Json>
          content_text?: string
          created_at?: string
          id?: string
          organization_id?: string
          parent_id?: string | null
          thread_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "comments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "comment_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      contact_methods: {
        Row: {
          contact_profile_id: string
          created_at: string
          id: string
          is_primary: boolean
          label: string | null
          position: number
          type: Database["public"]["Enums"]["contact_method_type"]
          updated_at: string
          value: string
          verified_at: string | null
        }
        Insert: {
          contact_profile_id: string
          created_at?: string
          id?: string
          is_primary?: boolean
          label?: string | null
          position?: number
          type: Database["public"]["Enums"]["contact_method_type"]
          updated_at?: string
          value: string
          verified_at?: string | null
        }
        Update: {
          contact_profile_id?: string
          created_at?: string
          id?: string
          is_primary?: boolean
          label?: string | null
          position?: number
          type?: Database["public"]["Enums"]["contact_method_type"]
          updated_at?: string
          value?: string
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contact_methods_contact_profile_id_fkey"
            columns: ["contact_profile_id"]
            isOneToOne: false
            referencedRelation: "contact_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      contact_profiles: {
        Row: {
          avatar_path: string | null
          created_at: string
          display_name: string | null
          first_name: string | null
          id: string
          last_name: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          avatar_path?: string | null
          created_at?: string
          display_name?: string | null
          first_name?: string | null
          id?: string
          last_name?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          avatar_path?: string | null
          created_at?: string
          display_name?: string | null
          first_name?: string | null
          id?: string
          last_name?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      currencies: {
        Row: {
          code: string
          created_at: string
          name: string
          symbol: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          name: string
          symbol: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          name?: string
          symbol?: string
          updated_at?: string
        }
        Relationships: []
      }
      customer_asset_files: {
        Row: {
          alt_text: string | null
          byte_size: number
          content_type: string
          created_at: string
          created_by: string | null
          customer_asset_id: number
          file_name: string
          id: string
          organization_id: string
          position: number
          storage_path: string
          updated_at: string
        }
        Insert: {
          alt_text?: string | null
          byte_size: number
          content_type: string
          created_at?: string
          created_by?: string | null
          customer_asset_id: number
          file_name: string
          id?: string
          organization_id: string
          position?: number
          storage_path: string
          updated_at?: string
        }
        Update: {
          alt_text?: string | null
          byte_size?: number
          content_type?: string
          created_at?: string
          created_by?: string | null
          customer_asset_id?: number
          file_name?: string
          id?: string
          organization_id?: string
          position?: number
          storage_path?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_asset_files_customer_asset_id_fkey"
            columns: ["customer_asset_id"]
            isOneToOne: false
            referencedRelation: "customer_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_asset_files_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_assets: {
        Row: {
          asset_tag: string | null
          barcode: string | null
          condition: Database["public"]["Enums"]["customer_asset_condition"]
          created_at: string
          created_by: string | null
          currency: string
          customer_id: number
          customer_location_id: string | null
          description: string | null
          id: number
          installed_on: string | null
          invoice_id: string | null
          organization_id: string
          product_id: string
          purchase_price: number | null
          purchased_on: string | null
          quote_id: string | null
          serial_number: string | null
          service_interval_days: number | null
          status: Database["public"]["Enums"]["customer_asset_status"]
          updated_at: string
          updated_by: string | null
          variant_id: string | null
          warranty_expires_on: string | null
          warranty_provider: string | null
          warranty_reference: string | null
        }
        Insert: {
          asset_tag?: string | null
          barcode?: string | null
          condition?: Database["public"]["Enums"]["customer_asset_condition"]
          created_at?: string
          created_by?: string | null
          currency?: string
          customer_id: number
          customer_location_id?: string | null
          description?: string | null
          id?: number
          installed_on?: string | null
          invoice_id?: string | null
          organization_id: string
          product_id: string
          purchase_price?: number | null
          purchased_on?: string | null
          quote_id?: string | null
          serial_number?: string | null
          service_interval_days?: number | null
          status?: Database["public"]["Enums"]["customer_asset_status"]
          updated_at?: string
          updated_by?: string | null
          variant_id?: string | null
          warranty_expires_on?: string | null
          warranty_provider?: string | null
          warranty_reference?: string | null
        }
        Update: {
          asset_tag?: string | null
          barcode?: string | null
          condition?: Database["public"]["Enums"]["customer_asset_condition"]
          created_at?: string
          created_by?: string | null
          currency?: string
          customer_id?: number
          customer_location_id?: string | null
          description?: string | null
          id?: number
          installed_on?: string | null
          invoice_id?: string | null
          organization_id?: string
          product_id?: string
          purchase_price?: number | null
          purchased_on?: string | null
          quote_id?: string | null
          serial_number?: string | null
          service_interval_days?: number | null
          status?: Database["public"]["Enums"]["customer_asset_status"]
          updated_at?: string
          updated_by?: string | null
          variant_id?: string | null
          warranty_expires_on?: string | null
          warranty_provider?: string | null
          warranty_reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "customer_assets_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "customer_assets_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_assets_customer_id_organization_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "customer_assets_customer_location_id_fkey"
            columns: ["customer_location_id"]
            isOneToOne: false
            referencedRelation: "customer_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_assets_invoice_organization_fkey"
            columns: ["invoice_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "customer_assets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_assets_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_assets_quote_organization_fkey"
            columns: ["quote_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "customer_assets_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      customer_assignees: {
        Row: {
          created_at: string
          customer_id: number
          organization_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          customer_id: number
          organization_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          customer_id?: number
          organization_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_assignees_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_assignees_customer_id_organization_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "customer_assignees_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_assignees_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      customer_contacts: {
        Row: {
          contact_profile_id: string
          created_at: string
          customer_id: number
          id: string
          is_primary: boolean
          job_title: string | null
          notes: string | null
          organization_id: string
          updated_at: string
        }
        Insert: {
          contact_profile_id: string
          created_at?: string
          customer_id: number
          id?: string
          is_primary?: boolean
          job_title?: string | null
          notes?: string | null
          organization_id: string
          updated_at?: string
        }
        Update: {
          contact_profile_id?: string
          created_at?: string
          customer_id?: number
          id?: string
          is_primary?: boolean
          job_title?: string | null
          notes?: string | null
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_contacts_contact_profile_id_fkey"
            columns: ["contact_profile_id"]
            isOneToOne: false
            referencedRelation: "contact_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_contacts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_contacts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_locations: {
        Row: {
          address_city: string | null
          address_country: string | null
          address_line1: string | null
          address_line2: string | null
          address_postal_code: string | null
          address_state: string | null
          created_at: string
          customer_id: number
          id: string
          is_primary: boolean
          name: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          address_city?: string | null
          address_country?: string | null
          address_line1?: string | null
          address_line2?: string | null
          address_postal_code?: string | null
          address_state?: string | null
          created_at?: string
          customer_id: number
          id?: string
          is_primary?: boolean
          name: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          address_city?: string | null
          address_country?: string | null
          address_line1?: string | null
          address_line2?: string | null
          address_postal_code?: string | null
          address_state?: string | null
          created_at?: string
          customer_id?: number
          id?: string
          is_primary?: boolean
          name?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_locations_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_locations_customer_id_organization_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "customer_locations_organization_id_fkey"
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
          customer_id: number
          organization_id: string
          tag_id: string
        }
        Insert: {
          created_at?: string
          customer_id: number
          organization_id: string
          tag_id: string
        }
        Update: {
          created_at?: string
          customer_id?: number
          organization_id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_tags_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
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
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "organization_tags"
            referencedColumns: ["id"]
          },
        ]
      }
      customers: {
        Row: {
          archived_at: string | null
          archived_reason: string | null
          billing_email: string | null
          billing_name: string | null
          btw: string | null
          budget_warned_month: string | null
          company_name: string | null
          created_at: string
          created_by: string | null
          description: string | null
          id: number
          is_business: boolean
          kvk: string | null
          logo_path: string | null
          monthly_budget_hours: number | null
          organization_id: string
          sort_name: string | null
          status: Database["public"]["Enums"]["customer_status"]
          updated_at: string
          updated_by: string | null
          website: string | null
        }
        Insert: {
          archived_at?: string | null
          archived_reason?: string | null
          billing_email?: string | null
          billing_name?: string | null
          btw?: string | null
          budget_warned_month?: string | null
          company_name?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: number
          is_business?: boolean
          kvk?: string | null
          logo_path?: string | null
          monthly_budget_hours?: number | null
          organization_id: string
          sort_name?: string | null
          status?: Database["public"]["Enums"]["customer_status"]
          updated_at?: string
          updated_by?: string | null
          website?: string | null
        }
        Update: {
          archived_at?: string | null
          archived_reason?: string | null
          billing_email?: string | null
          billing_name?: string | null
          btw?: string | null
          budget_warned_month?: string | null
          company_name?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: number
          is_business?: boolean
          kvk?: string | null
          logo_path?: string | null
          monthly_budget_hours?: number | null
          organization_id?: string
          sort_name?: string | null
          status?: Database["public"]["Enums"]["customer_status"]
          updated_at?: string
          updated_by?: string | null
          website?: string | null
        }
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
      document_views: {
        Row: {
          first_viewed_at: string
          id: string
          last_viewed_at: string
          organization_id: string
          subject_id: string
          subject_type: Database["public"]["Enums"]["document_view_subject_type"]
          version: number
          view_count: number
          viewer_kind: Database["public"]["Enums"]["document_viewer_kind"]
        }
        Insert: {
          first_viewed_at?: string
          id?: string
          last_viewed_at?: string
          organization_id: string
          subject_id: string
          subject_type: Database["public"]["Enums"]["document_view_subject_type"]
          version?: number
          view_count?: number
          viewer_kind: Database["public"]["Enums"]["document_viewer_kind"]
        }
        Update: {
          first_viewed_at?: string
          id?: string
          last_viewed_at?: string
          organization_id?: string
          subject_id?: string
          subject_type?: Database["public"]["Enums"]["document_view_subject_type"]
          version?: number
          view_count?: number
          viewer_kind?: Database["public"]["Enums"]["document_viewer_kind"]
        }
        Relationships: [
          {
            foreignKeyName: "document_views_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      email_deliveries: {
        Row: {
          created_at: string
          entity_id: string | null
          entity_type: string | null
          error_code: string | null
          error_message: string | null
          id: string
          last_event_at: string | null
          last_event_id: string | null
          last_event_type: string | null
          organization_id: string | null
          provider: string
          provider_message_id: string | null
          recipient_email: string
          sent_at: string | null
          status: Database["public"]["Enums"]["email_delivery_status"]
          template_key: string
          transport: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          error_code?: string | null
          error_message?: string | null
          id?: string
          last_event_at?: string | null
          last_event_id?: string | null
          last_event_type?: string | null
          organization_id?: string | null
          provider: string
          provider_message_id?: string | null
          recipient_email: string
          sent_at?: string | null
          status: Database["public"]["Enums"]["email_delivery_status"]
          template_key: string
          transport: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          error_code?: string | null
          error_message?: string | null
          id?: string
          last_event_at?: string | null
          last_event_id?: string | null
          last_event_type?: string | null
          organization_id?: string | null
          provider?: string
          provider_message_id?: string | null
          recipient_email?: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["email_delivery_status"]
          template_key?: string
          transport?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "email_deliveries_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_contract_bonuses: {
        Row: {
          amount: number | null
          contract_id: string
          created_at: string
          description: string | null
          frequency: Database["public"]["Enums"]["employee_bonus_frequency"]
          id: string
          kind: Database["public"]["Enums"]["employee_bonus_kind"]
          organization_id: string
          position: number
          updated_at: string
        }
        Insert: {
          amount?: number | null
          contract_id: string
          created_at?: string
          description?: string | null
          frequency?: Database["public"]["Enums"]["employee_bonus_frequency"]
          id?: string
          kind?: Database["public"]["Enums"]["employee_bonus_kind"]
          organization_id: string
          position?: number
          updated_at?: string
        }
        Update: {
          amount?: number | null
          contract_id?: string
          created_at?: string
          description?: string | null
          frequency?: Database["public"]["Enums"]["employee_bonus_frequency"]
          id?: string
          kind?: Database["public"]["Enums"]["employee_bonus_kind"]
          organization_id?: string
          position?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_contract_bonuses_contract_id_organization_id_fkey"
            columns: ["contract_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employee_contracts"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_contract_bonuses_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_contracts: {
        Row: {
          created_at: string
          created_by: string | null
          currency: string
          document_storage_path: string | null
          employee_id: string
          ending_notified_at: string | null
          ends_on: string | null
          holiday_allowance_pct: number
          hours_per_week: number | null
          id: string
          is_flexible: boolean
          leave_entitlement_hours_override: number | null
          notes: string | null
          notice_period_days: number | null
          organization_id: string
          pay_amount: number | null
          pay_basis: Database["public"]["Enums"]["employee_pay_basis"]
          pay_frequency: Database["public"]["Enums"]["employee_pay_frequency"]
          probation_ends_on: string | null
          signature_provider: string | null
          signature_request_id: string | null
          signed_at: string | null
          starts_on: string
          type: Database["public"]["Enums"]["employee_contract_type"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          currency?: string
          document_storage_path?: string | null
          employee_id: string
          ending_notified_at?: string | null
          ends_on?: string | null
          holiday_allowance_pct?: number
          hours_per_week?: number | null
          id?: string
          is_flexible?: boolean
          leave_entitlement_hours_override?: number | null
          notes?: string | null
          notice_period_days?: number | null
          organization_id: string
          pay_amount?: number | null
          pay_basis?: Database["public"]["Enums"]["employee_pay_basis"]
          pay_frequency?: Database["public"]["Enums"]["employee_pay_frequency"]
          probation_ends_on?: string | null
          signature_provider?: string | null
          signature_request_id?: string | null
          signed_at?: string | null
          starts_on: string
          type?: Database["public"]["Enums"]["employee_contract_type"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          currency?: string
          document_storage_path?: string | null
          employee_id?: string
          ending_notified_at?: string | null
          ends_on?: string | null
          holiday_allowance_pct?: number
          hours_per_week?: number | null
          id?: string
          is_flexible?: boolean
          leave_entitlement_hours_override?: number | null
          notes?: string | null
          notice_period_days?: number | null
          organization_id?: string
          pay_amount?: number | null
          pay_basis?: Database["public"]["Enums"]["employee_pay_basis"]
          pay_frequency?: Database["public"]["Enums"]["employee_pay_frequency"]
          probation_ends_on?: string | null
          signature_provider?: string | null
          signature_request_id?: string | null
          signed_at?: string | null
          starts_on?: string
          type?: Database["public"]["Enums"]["employee_contract_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_contracts_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_contracts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_documents: {
        Row: {
          created_at: string
          created_by: string | null
          employee_id: string
          expires_on: string | null
          file_name: string | null
          id: string
          issued_on: string | null
          last_reminded_at: string | null
          mime_type: string | null
          name: string
          organization_id: string
          reminder_days_before: number
          size_bytes: number | null
          storage_path: string | null
          type: Database["public"]["Enums"]["employee_document_type"]
          updated_at: string
          uploaded_via_preboarding: boolean
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          employee_id: string
          expires_on?: string | null
          file_name?: string | null
          id?: string
          issued_on?: string | null
          last_reminded_at?: string | null
          mime_type?: string | null
          name: string
          organization_id: string
          reminder_days_before?: number
          size_bytes?: number | null
          storage_path?: string | null
          type?: Database["public"]["Enums"]["employee_document_type"]
          updated_at?: string
          uploaded_via_preboarding?: boolean
        }
        Update: {
          created_at?: string
          created_by?: string | null
          employee_id?: string
          expires_on?: string | null
          file_name?: string | null
          id?: string
          issued_on?: string | null
          last_reminded_at?: string | null
          mime_type?: string | null
          name?: string
          organization_id?: string
          reminder_days_before?: number
          size_bytes?: number | null
          storage_path?: string | null
          type?: Database["public"]["Enums"]["employee_document_type"]
          updated_at?: string
          uploaded_via_preboarding?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "employee_documents_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_documents_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_field_definitions: {
        Row: {
          created_at: string
          id: string
          key: string
          label: string
          organization_id: string
          position: number
          sensitive: boolean
          type: Database["public"]["Enums"]["employee_field_type"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          key: string
          label: string
          organization_id: string
          position?: number
          sensitive?: boolean
          type?: Database["public"]["Enums"]["employee_field_type"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          key?: string
          label?: string
          organization_id?: string
          position?: number
          sensitive?: boolean
          type?: Database["public"]["Enums"]["employee_field_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_field_definitions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_field_options: {
        Row: {
          definition_id: string
          id: string
          label: string
          organization_id: string
          position: number
        }
        Insert: {
          definition_id: string
          id?: string
          label: string
          organization_id: string
          position?: number
        }
        Update: {
          definition_id?: string
          id?: string
          label?: string
          organization_id?: string
          position?: number
        }
        Relationships: [
          {
            foreignKeyName: "employee_field_options_definition_id_organization_id_fkey"
            columns: ["definition_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employee_field_definitions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_field_options_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_field_values: {
        Row: {
          definition_id: string
          employee_id: string
          id: string
          option_id: string | null
          organization_id: string
          updated_at: string
          value_bool: boolean | null
          value_date: string | null
          value_number: number | null
          value_text: string | null
        }
        Insert: {
          definition_id: string
          employee_id: string
          id?: string
          option_id?: string | null
          organization_id: string
          updated_at?: string
          value_bool?: boolean | null
          value_date?: string | null
          value_number?: number | null
          value_text?: string | null
        }
        Update: {
          definition_id?: string
          employee_id?: string
          id?: string
          option_id?: string | null
          organization_id?: string
          updated_at?: string
          value_bool?: boolean | null
          value_date?: string | null
          value_number?: number | null
          value_text?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employee_field_values_definition_id_organization_id_fkey"
            columns: ["definition_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employee_field_definitions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_field_values_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_field_values_option_id_organization_id_fkey"
            columns: ["option_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employee_field_options"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_field_values_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_journey_items: {
        Row: {
          assignee_role: Database["public"]["Enums"]["journey_assignee_role"]
          assignee_user_id: string | null
          completed_at: string | null
          completed_by: string | null
          created_at: string
          description: string | null
          due_on: string | null
          equipment_assignment_id: string | null
          id: string
          journey_id: string
          kind: Database["public"]["Enums"]["journey_item_kind"]
          organization_id: string
          position: number
          task_id: string | null
          title: string
          updated_at: string
        }
        Insert: {
          assignee_role?: Database["public"]["Enums"]["journey_assignee_role"]
          assignee_user_id?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          description?: string | null
          due_on?: string | null
          equipment_assignment_id?: string | null
          id?: string
          journey_id: string
          kind?: Database["public"]["Enums"]["journey_item_kind"]
          organization_id: string
          position?: number
          task_id?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          assignee_role?: Database["public"]["Enums"]["journey_assignee_role"]
          assignee_user_id?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          description?: string | null
          due_on?: string | null
          equipment_assignment_id?: string | null
          id?: string
          journey_id?: string
          kind?: Database["public"]["Enums"]["journey_item_kind"]
          organization_id?: string
          position?: number
          task_id?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_journey_items_equipment_assignment_id_fkey"
            columns: ["equipment_assignment_id"]
            isOneToOne: false
            referencedRelation: "equipment_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_journey_items_journey_id_organization_id_fkey"
            columns: ["journey_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employee_journeys"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_journey_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_journey_items_task_id_organization_id_fkey"
            columns: ["task_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      employee_journeys: {
        Row: {
          anchor_date: string
          buddy_employee_id: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          employee_id: string
          id: string
          kind: Database["public"]["Enums"]["employee_journey_kind"]
          organization_id: string
          preboarding_expires_at: string | null
          preboarding_token: string | null
          status: Database["public"]["Enums"]["employee_journey_status"]
          template_id: string | null
          updated_at: string
        }
        Insert: {
          anchor_date: string
          buddy_employee_id?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          employee_id: string
          id?: string
          kind?: Database["public"]["Enums"]["employee_journey_kind"]
          organization_id: string
          preboarding_expires_at?: string | null
          preboarding_token?: string | null
          status?: Database["public"]["Enums"]["employee_journey_status"]
          template_id?: string | null
          updated_at?: string
        }
        Update: {
          anchor_date?: string
          buddy_employee_id?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          employee_id?: string
          id?: string
          kind?: Database["public"]["Enums"]["employee_journey_kind"]
          organization_id?: string
          preboarding_expires_at?: string | null
          preboarding_token?: string | null
          status?: Database["public"]["Enums"]["employee_journey_status"]
          template_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_journeys_buddy_employee_id_organization_id_fkey"
            columns: ["buddy_employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_journeys_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_journeys_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_journeys_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_private_details: {
        Row: {
          anonymized_at: string | null
          birth_date: string | null
          created_at: string
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          emergency_contact_relation: string | null
          employee_id: string
          home_address_line1: string | null
          home_city: string | null
          home_country: string | null
          home_postal_code: string | null
          iban: string | null
          organization_id: string
          personal_email: string | null
          phone: string | null
          updated_at: string
        }
        Insert: {
          anonymized_at?: string | null
          birth_date?: string | null
          created_at?: string
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          emergency_contact_relation?: string | null
          employee_id: string
          home_address_line1?: string | null
          home_city?: string | null
          home_country?: string | null
          home_postal_code?: string | null
          iban?: string | null
          organization_id: string
          personal_email?: string | null
          phone?: string | null
          updated_at?: string
        }
        Update: {
          anonymized_at?: string | null
          birth_date?: string | null
          created_at?: string
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          emergency_contact_relation?: string | null
          employee_id?: string
          home_address_line1?: string | null
          home_city?: string | null
          home_country?: string | null
          home_postal_code?: string | null
          iban?: string | null
          organization_id?: string
          personal_email?: string | null
          phone?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_private_details_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_private_details_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_skills: {
        Row: {
          certified_on: string | null
          created_at: string
          employee_document_id: string | null
          employee_id: string
          expires_on: string | null
          id: string
          level: number | null
          organization_id: string
          skill_id: string
          updated_at: string
        }
        Insert: {
          certified_on?: string | null
          created_at?: string
          employee_document_id?: string | null
          employee_id: string
          expires_on?: string | null
          id?: string
          level?: number | null
          organization_id: string
          skill_id: string
          updated_at?: string
        }
        Update: {
          certified_on?: string | null
          created_at?: string
          employee_document_id?: string | null
          employee_id?: string
          expires_on?: string | null
          id?: string
          level?: number | null
          organization_id?: string
          skill_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_skills_employee_document_id_organization_id_fkey"
            columns: ["employee_document_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employee_documents"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_skills_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_skills_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_skills_skill_id_organization_id_fkey"
            columns: ["skill_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      employee_time_off_policies: {
        Row: {
          created_at: string
          employee_id: string
          ends_on: string | null
          id: string
          organization_id: string
          policy_id: string
          starts_on: string
        }
        Insert: {
          created_at?: string
          employee_id: string
          ends_on?: string | null
          id?: string
          organization_id: string
          policy_id: string
          starts_on: string
        }
        Update: {
          created_at?: string
          employee_id?: string
          ends_on?: string | null
          id?: string
          organization_id?: string
          policy_id?: string
          starts_on?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_time_off_policies_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_time_off_policies_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_time_off_policies_policy_id_organization_id_fkey"
            columns: ["policy_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "time_off_policies"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      employee_work_schedules: {
        Row: {
          created_at: string
          cycle_week: number
          employee_id: string
          ends_at: string
          id: string
          organization_id: string
          starts_at: string
          weekday: number
        }
        Insert: {
          created_at?: string
          cycle_week?: number
          employee_id: string
          ends_at: string
          id?: string
          organization_id: string
          starts_at: string
          weekday: number
        }
        Update: {
          created_at?: string
          cycle_week?: number
          employee_id?: string
          ends_at?: string
          id?: string
          organization_id?: string
          starts_at?: string
          weekday?: number
        }
        Relationships: [
          {
            foreignKeyName: "employee_work_schedules_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employee_work_schedules_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      employees: {
        Row: {
          archived_at: string | null
          company_name: string | null
          created_at: string
          created_by: string | null
          department_team_id: number | null
          end_date: string | null
          first_name: string
          id: string
          job_title: string | null
          kind: Database["public"]["Enums"]["employee_kind"]
          kvk: string | null
          last_name: string | null
          organization_id: string
          reports_to_employee_id: string | null
          schedule_cycle_anchor: string | null
          show_birthday: boolean
          show_work_anniversary: boolean
          start_date: string | null
          status: Database["public"]["Enums"]["employee_status"]
          timezone: string | null
          updated_at: string
          updated_by: string | null
          user_id: string | null
          vat_id: string | null
          work_email: string | null
        }
        Insert: {
          archived_at?: string | null
          company_name?: string | null
          created_at?: string
          created_by?: string | null
          department_team_id?: number | null
          end_date?: string | null
          first_name: string
          id?: string
          job_title?: string | null
          kind?: Database["public"]["Enums"]["employee_kind"]
          kvk?: string | null
          last_name?: string | null
          organization_id: string
          reports_to_employee_id?: string | null
          schedule_cycle_anchor?: string | null
          show_birthday?: boolean
          show_work_anniversary?: boolean
          start_date?: string | null
          status?: Database["public"]["Enums"]["employee_status"]
          timezone?: string | null
          updated_at?: string
          updated_by?: string | null
          user_id?: string | null
          vat_id?: string | null
          work_email?: string | null
        }
        Update: {
          archived_at?: string | null
          company_name?: string | null
          created_at?: string
          created_by?: string | null
          department_team_id?: number | null
          end_date?: string | null
          first_name?: string
          id?: string
          job_title?: string | null
          kind?: Database["public"]["Enums"]["employee_kind"]
          kvk?: string | null
          last_name?: string | null
          organization_id?: string
          reports_to_employee_id?: string | null
          schedule_cycle_anchor?: string | null
          show_birthday?: boolean
          show_work_anniversary?: boolean
          start_date?: string | null
          status?: Database["public"]["Enums"]["employee_status"]
          timezone?: string | null
          updated_at?: string
          updated_by?: string | null
          user_id?: string | null
          vat_id?: string | null
          work_email?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employees_department_team_id_organization_id_fkey"
            columns: ["department_team_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "employees_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_reports_to_employee_id_organization_id_fkey"
            columns: ["reports_to_employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      equipment_assignments: {
        Row: {
          acknowledged_at: string | null
          assigned_by: string | null
          assigned_on: string
          condition_in: string | null
          condition_out: string | null
          created_at: string
          employee_id: string
          equipment_item_id: string
          expected_return_on: string | null
          id: string
          organization_id: string
          returned_on: string | null
          updated_at: string
        }
        Insert: {
          acknowledged_at?: string | null
          assigned_by?: string | null
          assigned_on?: string
          condition_in?: string | null
          condition_out?: string | null
          created_at?: string
          employee_id: string
          equipment_item_id: string
          expected_return_on?: string | null
          id?: string
          organization_id: string
          returned_on?: string | null
          updated_at?: string
        }
        Update: {
          acknowledged_at?: string | null
          assigned_by?: string | null
          assigned_on?: string
          condition_in?: string | null
          condition_out?: string | null
          created_at?: string
          employee_id?: string
          equipment_item_id?: string
          expected_return_on?: string | null
          id?: string
          organization_id?: string
          returned_on?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "equipment_assignments_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "equipment_assignments_equipment_item_id_organization_id_fkey"
            columns: ["equipment_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "equipment_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "equipment_assignments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      equipment_items: {
        Row: {
          asset_tag: string | null
          category: string | null
          created_at: string
          created_by: string | null
          currency: string
          id: string
          name: string
          notes: string | null
          organization_id: string
          product_id: string | null
          purchase_date: string | null
          purchase_price: number | null
          serial_number: string | null
          status: Database["public"]["Enums"]["equipment_status"]
          updated_at: string
          warranty_ends_on: string | null
        }
        Insert: {
          asset_tag?: string | null
          category?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          id?: string
          name: string
          notes?: string | null
          organization_id: string
          product_id?: string | null
          purchase_date?: string | null
          purchase_price?: number | null
          serial_number?: string | null
          status?: Database["public"]["Enums"]["equipment_status"]
          updated_at?: string
          warranty_ends_on?: string | null
        }
        Update: {
          asset_tag?: string | null
          category?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          id?: string
          name?: string
          notes?: string | null
          organization_id?: string
          product_id?: string | null
          purchase_date?: string | null
          purchase_price?: number | null
          serial_number?: string | null
          status?: Database["public"]["Enums"]["equipment_status"]
          updated_at?: string
          warranty_ends_on?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "equipment_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "equipment_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      equipment_requests: {
        Row: {
          created_at: string
          created_by: string | null
          description: string
          employee_id: string
          equipment_item_id: string | null
          fulfilled_at: string | null
          id: string
          journey_item_id: string | null
          needed_by: string | null
          organization_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description: string
          employee_id: string
          equipment_item_id?: string | null
          fulfilled_at?: string | null
          id?: string
          journey_item_id?: string | null
          needed_by?: string | null
          organization_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string
          employee_id?: string
          equipment_item_id?: string | null
          fulfilled_at?: string | null
          id?: string
          journey_item_id?: string | null
          needed_by?: string | null
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "equipment_requests_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "equipment_requests_equipment_item_id_organization_id_fkey"
            columns: ["equipment_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "equipment_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "equipment_requests_journey_item_id_fkey"
            columns: ["journey_item_id"]
            isOneToOne: false
            referencedRelation: "employee_journey_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "equipment_requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_capture_addresses: {
        Row: {
          created_at: string
          employee_id: string
          id: string
          organization_id: string
          rotated_at: string | null
          token: string
        }
        Insert: {
          created_at?: string
          employee_id: string
          id?: string
          organization_id: string
          rotated_at?: string | null
          token?: string
        }
        Update: {
          created_at?: string
          employee_id?: string
          id?: string
          organization_id?: string
          rotated_at?: string | null
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "expense_capture_addresses_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "expense_capture_addresses_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_categories: {
        Row: {
          archived_at: string | null
          created_at: string
          default_vat_rate: number | null
          gl_code: string | null
          icon_name: string | null
          id: string
          name: string
          organization_id: string
          position: number
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          default_vat_rate?: number | null
          gl_code?: string | null
          icon_name?: string | null
          id?: string
          name: string
          organization_id: string
          position?: number
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          default_vat_rate?: number | null
          gl_code?: string | null
          icon_name?: string | null
          id?: string
          name?: string
          organization_id?: string
          position?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "expense_categories_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_flags: {
        Row: {
          created_at: string
          expense_id: string
          id: string
          kind: Database["public"]["Enums"]["expense_flag_kind"]
          message: string | null
          organization_id: string
          related_expense_id: string | null
          resolved_at: string | null
          resolved_by: string | null
        }
        Insert: {
          created_at?: string
          expense_id: string
          id?: string
          kind: Database["public"]["Enums"]["expense_flag_kind"]
          message?: string | null
          organization_id: string
          related_expense_id?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
        }
        Update: {
          created_at?: string
          expense_id?: string
          id?: string
          kind?: Database["public"]["Enums"]["expense_flag_kind"]
          message?: string | null
          organization_id?: string
          related_expense_id?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "expense_flags_expense_id_organization_id_fkey"
            columns: ["expense_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "expenses"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "expense_flags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expense_flags_related_expense_id_organization_id_fkey"
            columns: ["related_expense_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "expenses"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      expense_policies: {
        Row: {
          active: boolean
          category_id: string | null
          created_at: string
          id: string
          max_amount: number | null
          mode: Database["public"]["Enums"]["hr_enforcement_mode"]
          name: string
          organization_id: string
          period: Database["public"]["Enums"]["expense_policy_period"]
          receipt_required_above: number | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          category_id?: string | null
          created_at?: string
          id?: string
          max_amount?: number | null
          mode?: Database["public"]["Enums"]["hr_enforcement_mode"]
          name: string
          organization_id: string
          period?: Database["public"]["Enums"]["expense_policy_period"]
          receipt_required_above?: number | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          category_id?: string | null
          created_at?: string
          id?: string
          max_amount?: number | null
          mode?: Database["public"]["Enums"]["hr_enforcement_mode"]
          name?: string
          organization_id?: string
          period?: Database["public"]["Enums"]["expense_policy_period"]
          receipt_required_above?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "expense_policies_category_id_organization_id_fkey"
            columns: ["category_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "expense_categories"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "expense_policies_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_trips: {
        Row: {
          created_at: string
          customer_id: number | null
          destination: string | null
          employee_id: string
          ends_on: string
          id: string
          name: string
          organization_id: string
          starts_on: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          customer_id?: number | null
          destination?: string | null
          employee_id: string
          ends_on: string
          id?: string
          name: string
          organization_id: string
          starts_on: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          customer_id?: number | null
          destination?: string | null
          employee_id?: string
          ends_on?: string
          id?: string
          name?: string
          organization_id?: string
          starts_on?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "expense_trips_customer_id_organization_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "expense_trips_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "expense_trips_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      expenses: {
        Row: {
          amount: number
          amount_base: number
          billable: boolean
          category_id: string | null
          created_at: string
          created_by: string | null
          currency: string
          customer_id: number | null
          decided_at: string | null
          decided_by: string | null
          decision_note: string | null
          description: string | null
          distance_km: number | null
          employee_id: string | null
          exchange_rate: number
          extraction_confidence: number | null
          id: string
          invoice_id: string | null
          kind: Database["public"]["Enums"]["expense_kind"]
          merchant: string | null
          mileage_rate: number | null
          organization_id: string
          payment_method: Database["public"]["Enums"]["expense_payment_method"]
          per_diem_days: number | null
          receipt_file_name: string | null
          receipt_mime_type: string | null
          receipt_sha256: string | null
          receipt_status: Database["public"]["Enums"]["expense_receipt_status"]
          receipt_storage_path: string | null
          reimbursed_at: string | null
          reimbursed_by: string | null
          reimbursement_reference: string | null
          round_trip: boolean
          route_from: string | null
          route_to: string | null
          source: Database["public"]["Enums"]["expense_source"]
          spent_on: string
          status: Database["public"]["Enums"]["expense_status"]
          submitted_at: string | null
          task_id: string | null
          trip_id: string | null
          updated_at: string
          updated_by: string | null
          vat_amount: number | null
          vat_rate: number | null
        }
        Insert: {
          amount: number
          amount_base?: number
          billable?: boolean
          category_id?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          customer_id?: number | null
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          description?: string | null
          distance_km?: number | null
          employee_id?: string | null
          exchange_rate?: number
          extraction_confidence?: number | null
          id?: string
          invoice_id?: string | null
          kind?: Database["public"]["Enums"]["expense_kind"]
          merchant?: string | null
          mileage_rate?: number | null
          organization_id: string
          payment_method?: Database["public"]["Enums"]["expense_payment_method"]
          per_diem_days?: number | null
          receipt_file_name?: string | null
          receipt_mime_type?: string | null
          receipt_sha256?: string | null
          receipt_status?: Database["public"]["Enums"]["expense_receipt_status"]
          receipt_storage_path?: string | null
          reimbursed_at?: string | null
          reimbursed_by?: string | null
          reimbursement_reference?: string | null
          round_trip?: boolean
          route_from?: string | null
          route_to?: string | null
          source?: Database["public"]["Enums"]["expense_source"]
          spent_on: string
          status?: Database["public"]["Enums"]["expense_status"]
          submitted_at?: string | null
          task_id?: string | null
          trip_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number | null
          vat_rate?: number | null
        }
        Update: {
          amount?: number
          amount_base?: number
          billable?: boolean
          category_id?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          customer_id?: number | null
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          description?: string | null
          distance_km?: number | null
          employee_id?: string | null
          exchange_rate?: number
          extraction_confidence?: number | null
          id?: string
          invoice_id?: string | null
          kind?: Database["public"]["Enums"]["expense_kind"]
          merchant?: string | null
          mileage_rate?: number | null
          organization_id?: string
          payment_method?: Database["public"]["Enums"]["expense_payment_method"]
          per_diem_days?: number | null
          receipt_file_name?: string | null
          receipt_mime_type?: string | null
          receipt_sha256?: string | null
          receipt_status?: Database["public"]["Enums"]["expense_receipt_status"]
          receipt_storage_path?: string | null
          reimbursed_at?: string | null
          reimbursed_by?: string | null
          reimbursement_reference?: string | null
          round_trip?: boolean
          route_from?: string | null
          route_to?: string | null
          source?: Database["public"]["Enums"]["expense_source"]
          spent_on?: string
          status?: Database["public"]["Enums"]["expense_status"]
          submitted_at?: string | null
          task_id?: string | null
          trip_id?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_amount?: number | null
          vat_rate?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "expenses_category_id_organization_id_fkey"
            columns: ["category_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "expense_categories"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "expenses_customer_id_organization_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "expenses_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "expenses_invoice_id_organization_id_fkey"
            columns: ["invoice_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "expenses_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_task_id_organization_id_fkey"
            columns: ["task_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "expenses_trip_id_organization_id_fkey"
            columns: ["trip_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "expense_trips"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      file_comments: {
        Row: {
          body: string
          created_at: string
          created_by: string | null
          deleted_at: string | null
          id: string
          node_id: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          body: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          id?: string
          node_id: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          body?: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          id?: string
          node_id?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "file_comments_node_id_fkey"
            columns: ["node_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_comments_node_id_organization_id_fkey"
            columns: ["node_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_comments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      file_copy_operation_items: {
        Row: {
          created_at: string
          error_message: string | null
          id: string
          operation_id: string
          organization_id: string
          source_node_id: string
          source_version_id: string | null
          status: string
          target_node_id: string
          target_storage_path: string | null
          target_version_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          error_message?: string | null
          id?: string
          operation_id: string
          organization_id: string
          source_node_id: string
          source_version_id?: string | null
          status?: string
          target_node_id: string
          target_storage_path?: string | null
          target_version_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          error_message?: string | null
          id?: string
          operation_id?: string
          organization_id?: string
          source_node_id?: string
          source_version_id?: string | null
          status?: string
          target_node_id?: string
          target_storage_path?: string | null
          target_version_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "file_copy_operation_items_operation_id_fkey"
            columns: ["operation_id"]
            isOneToOne: false
            referencedRelation: "file_copy_operations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_copy_operation_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_copy_operation_items_target_node_id_fkey"
            columns: ["target_node_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_copy_operation_items_target_version_id_fkey"
            columns: ["target_version_id"]
            isOneToOne: false
            referencedRelation: "file_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      file_copy_operations: {
        Row: {
          completed_at: string | null
          completed_items: number
          conflict_strategy: string
          created_at: string
          created_by: string
          destination_drive_id: string
          destination_parent_id: string | null
          error_message: string | null
          id: string
          idempotency_key: string
          organization_id: string
          source_node_ids: string[]
          started_at: string | null
          status: string
          total_items: number
          updated_at: string
        }
        Insert: {
          completed_at?: string | null
          completed_items?: number
          conflict_strategy?: string
          created_at?: string
          created_by: string
          destination_drive_id: string
          destination_parent_id?: string | null
          error_message?: string | null
          id?: string
          idempotency_key: string
          organization_id: string
          source_node_ids: string[]
          started_at?: string | null
          status?: string
          total_items?: number
          updated_at?: string
        }
        Update: {
          completed_at?: string | null
          completed_items?: number
          conflict_strategy?: string
          created_at?: string
          created_by?: string
          destination_drive_id?: string
          destination_parent_id?: string | null
          error_message?: string | null
          id?: string
          idempotency_key?: string
          organization_id?: string
          source_node_ids?: string[]
          started_at?: string | null
          status?: string
          total_items?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "file_copy_operations_created_by_organization_id_fkey"
            columns: ["created_by", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
          {
            foreignKeyName: "file_copy_operations_destination_drive_id_fkey"
            columns: ["destination_drive_id"]
            isOneToOne: false
            referencedRelation: "file_drives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_copy_operations_destination_drive_id_organization_id_fkey"
            columns: ["destination_drive_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "file_drives"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_copy_operations_destination_parent_id_destination_dri_fkey"
            columns: ["destination_parent_id", "destination_drive_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id", "drive_id"]
          },
          {
            foreignKeyName: "file_copy_operations_destination_parent_id_fkey"
            columns: ["destination_parent_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_copy_operations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      file_drive_grants: {
        Row: {
          created_at: string
          created_by: string | null
          drive_id: string
          id: string
          organization_id: string
          role: string
          team_id: number | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          drive_id: string
          id?: string
          organization_id: string
          role?: string
          team_id?: number | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          drive_id?: string
          id?: string
          organization_id?: string
          role?: string
          team_id?: number | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "file_drive_grants_drive_id_fkey"
            columns: ["drive_id"]
            isOneToOne: false
            referencedRelation: "file_drives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_drive_grants_drive_id_organization_id_fkey"
            columns: ["drive_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "file_drives"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_drive_grants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_drive_grants_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_drive_grants_team_id_organization_id_fkey"
            columns: ["team_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_drive_grants_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      file_drives: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          drive_type: string
          id: string
          lifecycle_state: string
          name: string
          organization_id: string
          owner_released_at: string | null
          owner_user_id: string | null
          purge_after: string | null
          trashed_at: string | null
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          drive_type: string
          id?: string
          lifecycle_state?: string
          name: string
          organization_id: string
          owner_released_at?: string | null
          owner_user_id?: string | null
          purge_after?: string | null
          trashed_at?: string | null
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          drive_type?: string
          id?: string
          lifecycle_state?: string
          name?: string
          organization_id?: string
          owner_released_at?: string | null
          owner_user_id?: string | null
          purge_after?: string | null
          trashed_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "file_drives_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_drives_owner_user_id_organization_id_fkey"
            columns: ["owner_user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      file_node_grants: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          node_id: string
          organization_id: string
          role: string
          team_id: number | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          node_id: string
          organization_id: string
          role?: string
          team_id?: number | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          node_id?: string
          organization_id?: string
          role?: string
          team_id?: number | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "file_node_grants_node_id_fkey"
            columns: ["node_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_node_grants_node_id_organization_id_fkey"
            columns: ["node_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_node_grants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_node_grants_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_node_grants_team_id_organization_id_fkey"
            columns: ["team_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_node_grants_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      file_node_user_state: {
        Row: {
          last_opened_at: string | null
          node_id: string
          organization_id: string
          starred_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          last_opened_at?: string | null
          node_id: string
          organization_id: string
          starred_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          last_opened_at?: string | null
          node_id?: string
          organization_id?: string
          starred_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "file_node_user_state_node_id_fkey"
            columns: ["node_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_node_user_state_node_id_organization_id_fkey"
            columns: ["node_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_node_user_state_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_node_user_state_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      file_nodes: {
        Row: {
          created_at: string
          created_by: string | null
          current_version_id: string | null
          customer_id: number | null
          deleted_at: string | null
          deleted_by: string | null
          deletion_batch_id: string | null
          drive_id: string
          external_id: string | null
          external_metadata: NonNullable<Json>
          id: string
          kind: string
          legal_hold_until: string | null
          name: string
          organization_id: string
          parent_id: string | null
          purge_after: string | null
          source: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          current_version_id?: string | null
          customer_id?: number | null
          deleted_at?: string | null
          deleted_by?: string | null
          deletion_batch_id?: string | null
          drive_id: string
          external_id?: string | null
          external_metadata?: NonNullable<Json>
          id?: string
          kind: string
          legal_hold_until?: string | null
          name: string
          organization_id: string
          parent_id?: string | null
          purge_after?: string | null
          source?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          current_version_id?: string | null
          customer_id?: number | null
          deleted_at?: string | null
          deleted_by?: string | null
          deletion_batch_id?: string | null
          drive_id?: string
          external_id?: string | null
          external_metadata?: NonNullable<Json>
          id?: string
          kind?: string
          legal_hold_until?: string | null
          name?: string
          organization_id?: string
          parent_id?: string | null
          purge_after?: string | null
          source?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "file_nodes_current_version_id_fkey"
            columns: ["current_version_id"]
            isOneToOne: false
            referencedRelation: "file_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_nodes_customer_id_organization_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_nodes_drive_id_fkey"
            columns: ["drive_id"]
            isOneToOne: false
            referencedRelation: "file_drives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_nodes_drive_id_organization_id_fkey"
            columns: ["drive_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "file_drives"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_nodes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_nodes_parent_id_drive_id_fkey"
            columns: ["parent_id", "drive_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id", "drive_id"]
          },
          {
            foreignKeyName: "file_nodes_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
        ]
      }
      file_share_links: {
        Row: {
          created_at: string
          created_by: string | null
          expires_at: string | null
          id: string
          node_id: string
          organization_id: string
          revoked_at: string | null
          role: string
          token: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          expires_at?: string | null
          id?: string
          node_id: string
          organization_id: string
          revoked_at?: string | null
          role?: string
          token: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          expires_at?: string | null
          id?: string
          node_id?: string
          organization_id?: string
          revoked_at?: string | null
          role?: string
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "file_share_links_node_id_fkey"
            columns: ["node_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_share_links_node_id_organization_id_fkey"
            columns: ["node_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_share_links_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      file_storage_settings: {
        Row: {
          created_at: string
          enterprise_retention_days: number | null
          organization_id: string
          quota_bytes: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          enterprise_retention_days?: number | null
          organization_id: string
          quota_bytes?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          enterprise_retention_days?: number | null
          organization_id?: string
          quota_bytes?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "file_storage_settings_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      file_upload_reservations: {
        Row: {
          actual_bytes: number | null
          checksum: string | null
          created_at: string
          created_by: string
          drive_id: string
          etag: string | null
          expected_bytes: number
          expires_at: string
          file_name: string
          finalized_at: string | null
          finalized_version_id: string | null
          id: string
          idempotency_key: string
          media_type: string
          node_id: string | null
          organization_id: string
          parent_id: string | null
          status: string
          storage_bucket: string
          storage_path: string
          updated_at: string
        }
        Insert: {
          actual_bytes?: number | null
          checksum?: string | null
          created_at?: string
          created_by: string
          drive_id: string
          etag?: string | null
          expected_bytes: number
          expires_at: string
          file_name: string
          finalized_at?: string | null
          finalized_version_id?: string | null
          id?: string
          idempotency_key: string
          media_type: string
          node_id?: string | null
          organization_id: string
          parent_id?: string | null
          status?: string
          storage_bucket: string
          storage_path: string
          updated_at?: string
        }
        Update: {
          actual_bytes?: number | null
          checksum?: string | null
          created_at?: string
          created_by?: string
          drive_id?: string
          etag?: string | null
          expected_bytes?: number
          expires_at?: string
          file_name?: string
          finalized_at?: string | null
          finalized_version_id?: string | null
          id?: string
          idempotency_key?: string
          media_type?: string
          node_id?: string | null
          organization_id?: string
          parent_id?: string | null
          status?: string
          storage_bucket?: string
          storage_path?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "file_upload_reservations_created_by_organization_id_fkey"
            columns: ["created_by", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
          {
            foreignKeyName: "file_upload_reservations_drive_id_fkey"
            columns: ["drive_id"]
            isOneToOne: false
            referencedRelation: "file_drives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_upload_reservations_drive_id_organization_id_fkey"
            columns: ["drive_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "file_drives"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_upload_reservations_finalized_version_id_fkey"
            columns: ["finalized_version_id"]
            isOneToOne: false
            referencedRelation: "file_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_upload_reservations_node_id_drive_id_fkey"
            columns: ["node_id", "drive_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id", "drive_id"]
          },
          {
            foreignKeyName: "file_upload_reservations_node_id_fkey"
            columns: ["node_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_upload_reservations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_upload_reservations_parent_id_drive_id_fkey"
            columns: ["parent_id", "drive_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id", "drive_id"]
          },
          {
            foreignKeyName: "file_upload_reservations_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
        ]
      }
      file_versions: {
        Row: {
          byte_size: number
          checksum: string | null
          created_at: string
          created_by: string | null
          drive_id: string
          etag: string | null
          id: string
          legal_hold_until: string | null
          media_type: string
          node_id: string
          organization_id: string
          retention_until: string
          source_modified_at: string | null
          storage_bucket: string
          storage_path: string
          version_number: number
        }
        Insert: {
          byte_size: number
          checksum?: string | null
          created_at?: string
          created_by?: string | null
          drive_id: string
          etag?: string | null
          id?: string
          legal_hold_until?: string | null
          media_type: string
          node_id: string
          organization_id: string
          retention_until: string
          source_modified_at?: string | null
          storage_bucket: string
          storage_path: string
          version_number: number
        }
        Update: {
          byte_size?: number
          checksum?: string | null
          created_at?: string
          created_by?: string | null
          drive_id?: string
          etag?: string | null
          id?: string
          legal_hold_until?: string | null
          media_type?: string
          node_id?: string
          organization_id?: string
          retention_until?: string
          source_modified_at?: string | null
          storage_bucket?: string
          storage_path?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "file_versions_drive_id_fkey"
            columns: ["drive_id"]
            isOneToOne: false
            referencedRelation: "file_drives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_versions_drive_id_organization_id_fkey"
            columns: ["drive_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "file_drives"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "file_versions_node_id_drive_id_fkey"
            columns: ["node_id", "drive_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id", "drive_id"]
          },
          {
            foreignKeyName: "file_versions_node_id_fkey"
            columns: ["node_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_versions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      file_zip_export_items: {
        Row: {
          archive_path: string
          byte_size: number
          created_at: string
          export_id: string
          id: string
          media_type: string | null
          node_id: string
          organization_id: string
          storage_bucket: string | null
          storage_path: string | null
          version_id: string | null
        }
        Insert: {
          archive_path: string
          byte_size?: number
          created_at?: string
          export_id: string
          id?: string
          media_type?: string | null
          node_id: string
          organization_id: string
          storage_bucket?: string | null
          storage_path?: string | null
          version_id?: string | null
        }
        Update: {
          archive_path?: string
          byte_size?: number
          created_at?: string
          export_id?: string
          id?: string
          media_type?: string | null
          node_id?: string
          organization_id?: string
          storage_bucket?: string | null
          storage_path?: string | null
          version_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "file_zip_export_items_export_id_fkey"
            columns: ["export_id"]
            isOneToOne: false
            referencedRelation: "file_zip_exports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "file_zip_export_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      file_zip_exports: {
        Row: {
          artifact_expires_at: string | null
          artifact_storage_bucket: string | null
          artifact_storage_path: string | null
          completed_at: string | null
          completed_items: number
          created_at: string
          created_by: string
          delivery_mode: string
          error_message: string | null
          file_name: string
          id: string
          idempotency_key: string
          organization_id: string
          source_node_ids: string[]
          started_at: string | null
          status: string
          total_bytes: number
          total_items: number
          updated_at: string
        }
        Insert: {
          artifact_expires_at?: string | null
          artifact_storage_bucket?: string | null
          artifact_storage_path?: string | null
          completed_at?: string | null
          completed_items?: number
          created_at?: string
          created_by: string
          delivery_mode: string
          error_message?: string | null
          file_name: string
          id?: string
          idempotency_key: string
          organization_id: string
          source_node_ids: string[]
          started_at?: string | null
          status?: string
          total_bytes?: number
          total_items?: number
          updated_at?: string
        }
        Update: {
          artifact_expires_at?: string | null
          artifact_storage_bucket?: string | null
          artifact_storage_path?: string | null
          completed_at?: string | null
          completed_items?: number
          created_at?: string
          created_by?: string
          delivery_mode?: string
          error_message?: string | null
          file_name?: string
          id?: string
          idempotency_key?: string
          organization_id?: string
          source_node_ids?: string[]
          started_at?: string | null
          status?: string
          total_bytes?: number
          total_items?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "file_zip_exports_created_by_organization_id_fkey"
            columns: ["created_by", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
          {
            foreignKeyName: "file_zip_exports_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      hiring_applications: {
        Row: {
          candidate_id: string
          cover_letter: string | null
          created_at: string
          hired_at: string | null
          id: string
          job_id: string
          organization_id: string
          position: number
          rejection_reason: string | null
          source: Database["public"]["Enums"]["hiring_application_source"]
          stage_entered_at: string
          stage_id: string
          status: Database["public"]["Enums"]["hiring_application_status"]
          updated_at: string
        }
        Insert: {
          candidate_id: string
          cover_letter?: string | null
          created_at?: string
          hired_at?: string | null
          id?: string
          job_id: string
          organization_id: string
          position?: number
          rejection_reason?: string | null
          source?: Database["public"]["Enums"]["hiring_application_source"]
          stage_entered_at?: string
          stage_id: string
          status?: Database["public"]["Enums"]["hiring_application_status"]
          updated_at?: string
        }
        Update: {
          candidate_id?: string
          cover_letter?: string | null
          created_at?: string
          hired_at?: string | null
          id?: string
          job_id?: string
          organization_id?: string
          position?: number
          rejection_reason?: string | null
          source?: Database["public"]["Enums"]["hiring_application_source"]
          stage_entered_at?: string
          stage_id?: string
          status?: Database["public"]["Enums"]["hiring_application_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "hiring_applications_candidate_id_organization_id_fkey"
            columns: ["candidate_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "hiring_candidates"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "hiring_applications_job_id_organization_id_fkey"
            columns: ["job_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "hiring_jobs"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "hiring_applications_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hiring_applications_stage_id_organization_id_fkey"
            columns: ["stage_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "hiring_stages"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      hiring_candidates: {
        Row: {
          anonymized_at: string | null
          consent_given_at: string | null
          created_at: string
          cv_experience_years: number | null
          cv_file_name: string | null
          cv_skills: string[]
          cv_storage_path: string | null
          cv_summary: string | null
          email: string | null
          employee_id: string | null
          first_name: string
          id: string
          last_name: string | null
          linkedin_url: string | null
          organization_id: string
          phone: string | null
          retention_until: string | null
          talent_pool_consent_until: string | null
          updated_at: string
        }
        Insert: {
          anonymized_at?: string | null
          consent_given_at?: string | null
          created_at?: string
          cv_experience_years?: number | null
          cv_file_name?: string | null
          cv_skills?: string[]
          cv_storage_path?: string | null
          cv_summary?: string | null
          email?: string | null
          employee_id?: string | null
          first_name: string
          id?: string
          last_name?: string | null
          linkedin_url?: string | null
          organization_id: string
          phone?: string | null
          retention_until?: string | null
          talent_pool_consent_until?: string | null
          updated_at?: string
        }
        Update: {
          anonymized_at?: string | null
          consent_given_at?: string | null
          created_at?: string
          cv_experience_years?: number | null
          cv_file_name?: string | null
          cv_skills?: string[]
          cv_storage_path?: string | null
          cv_summary?: string | null
          email?: string | null
          employee_id?: string | null
          first_name?: string
          id?: string
          last_name?: string | null
          linkedin_url?: string | null
          organization_id?: string
          phone?: string | null
          retention_until?: string | null
          talent_pool_consent_until?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "hiring_candidates_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "hiring_candidates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      hiring_email_templates: {
        Row: {
          body: string
          created_at: string
          id: string
          kind: string
          organization_id: string
          stage_id: string | null
          subject: string
          updated_at: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          kind: string
          organization_id: string
          stage_id?: string | null
          subject: string
          updated_at?: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          kind?: string
          organization_id?: string
          stage_id?: string | null
          subject?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "hiring_email_templates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hiring_email_templates_stage_id_organization_id_fkey"
            columns: ["stage_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "hiring_stages"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      hiring_interview_interviewers: {
        Row: {
          interview_id: string
          organization_id: string
          user_id: string
        }
        Insert: {
          interview_id: string
          organization_id: string
          user_id: string
        }
        Update: {
          interview_id?: string
          organization_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "hiring_interview_interviewers_interview_id_fkey"
            columns: ["interview_id"]
            isOneToOne: false
            referencedRelation: "hiring_interviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hiring_interview_interviewers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      hiring_interviews: {
        Row: {
          agenda_item_id: string | null
          application_id: string
          created_at: string
          created_by: string | null
          ends_at: string
          id: string
          location: string | null
          organization_id: string
          starts_at: string
          updated_at: string
        }
        Insert: {
          agenda_item_id?: string | null
          application_id: string
          created_at?: string
          created_by?: string | null
          ends_at: string
          id?: string
          location?: string | null
          organization_id: string
          starts_at: string
          updated_at?: string
        }
        Update: {
          agenda_item_id?: string | null
          application_id?: string
          created_at?: string
          created_by?: string | null
          ends_at?: string
          id?: string
          location?: string | null
          organization_id?: string
          starts_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "hiring_interviews_agenda_item_id_organization_id_fkey"
            columns: ["agenda_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "hiring_interviews_application_id_organization_id_fkey"
            columns: ["application_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "hiring_applications"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "hiring_interviews_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      hiring_jobs: {
        Row: {
          closed_at: string | null
          contract_type:
            | Database["public"]["Enums"]["employee_contract_type"]
            | null
          created_at: string
          created_by: string | null
          currency: string
          description: string | null
          employment_kind: Database["public"]["Enums"]["employee_kind"]
          hiring_manager_employee_id: string | null
          hours_per_week: number | null
          id: string
          location: string | null
          opened_at: string | null
          organization_id: string
          published_on_careers_page: boolean
          salary_max: number | null
          salary_min: number | null
          slug: string
          status: Database["public"]["Enums"]["hiring_job_status"]
          team_id: number | null
          title: string
          updated_at: string
        }
        Insert: {
          closed_at?: string | null
          contract_type?:
            | Database["public"]["Enums"]["employee_contract_type"]
            | null
          created_at?: string
          created_by?: string | null
          currency?: string
          description?: string | null
          employment_kind?: Database["public"]["Enums"]["employee_kind"]
          hiring_manager_employee_id?: string | null
          hours_per_week?: number | null
          id?: string
          location?: string | null
          opened_at?: string | null
          organization_id: string
          published_on_careers_page?: boolean
          salary_max?: number | null
          salary_min?: number | null
          slug: string
          status?: Database["public"]["Enums"]["hiring_job_status"]
          team_id?: number | null
          title: string
          updated_at?: string
        }
        Update: {
          closed_at?: string | null
          contract_type?:
            | Database["public"]["Enums"]["employee_contract_type"]
            | null
          created_at?: string
          created_by?: string | null
          currency?: string
          description?: string | null
          employment_kind?: Database["public"]["Enums"]["employee_kind"]
          hiring_manager_employee_id?: string | null
          hours_per_week?: number | null
          id?: string
          location?: string | null
          opened_at?: string | null
          organization_id?: string
          published_on_careers_page?: boolean
          salary_max?: number | null
          salary_min?: number | null
          slug?: string
          status?: Database["public"]["Enums"]["hiring_job_status"]
          team_id?: number | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "hiring_jobs_hiring_manager_employee_id_organization_id_fkey"
            columns: ["hiring_manager_employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "hiring_jobs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hiring_jobs_team_id_organization_id_fkey"
            columns: ["team_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      hiring_scorecard_scores: {
        Row: {
          criterion_id: string
          organization_id: string
          score: number
          scorecard_id: string
        }
        Insert: {
          criterion_id: string
          organization_id: string
          score: number
          scorecard_id: string
        }
        Update: {
          criterion_id?: string
          organization_id?: string
          score?: number
          scorecard_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "hiring_scorecard_scores_criterion_id_organization_id_fkey"
            columns: ["criterion_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "hiring_stage_criteria"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "hiring_scorecard_scores_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hiring_scorecard_scores_scorecard_id_organization_id_fkey"
            columns: ["scorecard_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "hiring_scorecards"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      hiring_scorecards: {
        Row: {
          application_id: string
          created_at: string
          id: string
          notes: string | null
          organization_id: string
          rating: number
          reviewer_user_id: string | null
          stage_id: string | null
          updated_at: string
        }
        Insert: {
          application_id: string
          created_at?: string
          id?: string
          notes?: string | null
          organization_id: string
          rating: number
          reviewer_user_id?: string | null
          stage_id?: string | null
          updated_at?: string
        }
        Update: {
          application_id?: string
          created_at?: string
          id?: string
          notes?: string | null
          organization_id?: string
          rating?: number
          reviewer_user_id?: string | null
          stage_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "hiring_scorecards_application_id_organization_id_fkey"
            columns: ["application_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "hiring_applications"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "hiring_scorecards_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hiring_scorecards_stage_id_organization_id_fkey"
            columns: ["stage_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "hiring_stages"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      hiring_stage_criteria: {
        Row: {
          created_at: string
          id: string
          label: string
          organization_id: string
          position: number
          required: boolean
          stage_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          label: string
          organization_id: string
          position?: number
          required?: boolean
          stage_id: string
        }
        Update: {
          created_at?: string
          id?: string
          label?: string
          organization_id?: string
          position?: number
          required?: boolean
          stage_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "hiring_stage_criteria_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hiring_stage_criteria_stage_id_organization_id_fkey"
            columns: ["stage_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "hiring_stages"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      hiring_stages: {
        Row: {
          created_at: string
          id: string
          is_hired: boolean
          job_id: string
          name: string
          organization_id: string
          position: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_hired?: boolean
          job_id: string
          name: string
          organization_id: string
          position?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          is_hired?: boolean
          job_id?: string
          name?: string
          organization_id?: string
          position?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "hiring_stages_job_id_organization_id_fkey"
            columns: ["job_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "hiring_jobs"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "hiring_stages_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_default_schedule: {
        Row: {
          created_at: string
          cycle_week: number
          ends_at: string
          id: string
          organization_id: string
          starts_at: string
          weekday: number
        }
        Insert: {
          created_at?: string
          cycle_week?: number
          ends_at: string
          id?: string
          organization_id: string
          starts_at: string
          weekday: number
        }
        Update: {
          created_at?: string
          cycle_week?: number
          ends_at?: string
          id?: string
          organization_id?: string
          starts_at?: string
          weekday?: number
        }
        Relationships: [
          {
            foreignKeyName: "hr_default_schedule_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_settings: {
        Row: {
          allow_negative_balance_hours: number
          attendance_enabled: boolean
          attendance_location_enabled: boolean
          auto_create_employee_for_members: boolean
          billing_rounding_minutes: number
          billing_rounding_mode: Database["public"]["Enums"]["hr_rounding_mode"]
          budget_warning_pct: number
          candidate_retention_weeks: number
          created_at: string
          employee_data_retention_months: number
          expense_auto_approve_below: number | null
          expense_capture_enabled: boolean
          expired_certificate_mode: Database["public"]["Enums"]["hr_enforcement_mode"]
          full_time_hours_per_week: number
          hiring_stalled_after_days: number
          hr_handbook_collection_id: string | null
          leave_year_start_month: number
          mileage_rate: number
          organization_id: string
          pay_day: number | null
          pay_frequency: Database["public"]["Enums"]["employee_pay_frequency"]
          per_diem_rate: number | null
          public_holiday_country: string
          team_capacity_warning_threshold: number
          time_off_requires_approval: boolean
          timer_grace_minutes: number
          timesheet_approval_required: boolean
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          allow_negative_balance_hours?: number
          attendance_enabled?: boolean
          attendance_location_enabled?: boolean
          auto_create_employee_for_members?: boolean
          billing_rounding_minutes?: number
          billing_rounding_mode?: Database["public"]["Enums"]["hr_rounding_mode"]
          budget_warning_pct?: number
          candidate_retention_weeks?: number
          created_at?: string
          employee_data_retention_months?: number
          expense_auto_approve_below?: number | null
          expense_capture_enabled?: boolean
          expired_certificate_mode?: Database["public"]["Enums"]["hr_enforcement_mode"]
          full_time_hours_per_week?: number
          hiring_stalled_after_days?: number
          hr_handbook_collection_id?: string | null
          leave_year_start_month?: number
          mileage_rate?: number
          organization_id: string
          pay_day?: number | null
          pay_frequency?: Database["public"]["Enums"]["employee_pay_frequency"]
          per_diem_rate?: number | null
          public_holiday_country?: string
          team_capacity_warning_threshold?: number
          time_off_requires_approval?: boolean
          timer_grace_minutes?: number
          timesheet_approval_required?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          allow_negative_balance_hours?: number
          attendance_enabled?: boolean
          attendance_location_enabled?: boolean
          auto_create_employee_for_members?: boolean
          billing_rounding_minutes?: number
          billing_rounding_mode?: Database["public"]["Enums"]["hr_rounding_mode"]
          budget_warning_pct?: number
          candidate_retention_weeks?: number
          created_at?: string
          employee_data_retention_months?: number
          expense_auto_approve_below?: number | null
          expense_capture_enabled?: boolean
          expired_certificate_mode?: Database["public"]["Enums"]["hr_enforcement_mode"]
          full_time_hours_per_week?: number
          hiring_stalled_after_days?: number
          hr_handbook_collection_id?: string | null
          leave_year_start_month?: number
          mileage_rate?: number
          organization_id?: string
          pay_day?: number | null
          pay_frequency?: Database["public"]["Enums"]["employee_pay_frequency"]
          per_diem_rate?: number | null
          public_holiday_country?: string
          team_capacity_warning_threshold?: number
          time_off_requires_approval?: boolean
          timer_grace_minutes?: number
          timesheet_approval_required?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hr_settings_hr_handbook_collection_id_fkey"
            columns: ["hr_handbook_collection_id"]
            isOneToOne: false
            referencedRelation: "knowledge_collections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_settings_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      inbox_automation_runs: {
        Row: {
          channel_thread_id: string
          completed_at: string | null
          created_at: string
          error: Json | null
          id: string
          lease_token: string
          leased_until: string
          organization_id: string
          output: Json | null
          source_message_id: string
          status: string
          updated_at: string
        }
        Insert: {
          channel_thread_id: string
          completed_at?: string | null
          created_at?: string
          error?: Json | null
          id?: string
          lease_token: string
          leased_until: string
          organization_id: string
          output?: Json | null
          source_message_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          channel_thread_id?: string
          completed_at?: string | null
          created_at?: string
          error?: Json | null
          id?: string
          lease_token?: string
          leased_until?: string
          organization_id?: string
          output?: Json | null
          source_message_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inbox_automation_runs_channel_thread_id_fkey"
            columns: ["channel_thread_id"]
            isOneToOne: false
            referencedRelation: "inbox_threads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_automation_runs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_automation_runs_source_message_id_fkey"
            columns: ["source_message_id"]
            isOneToOne: false
            referencedRelation: "chat_messages"
            referencedColumns: ["id"]
          },
        ]
      }
      inbox_connection_secrets: {
        Row: {
          connection_id: string
          created_at: string
          credentials: NonNullable<Json>
          id: string
          kind: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          connection_id: string
          created_at?: string
          credentials: NonNullable<Json>
          id?: string
          kind: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          connection_id?: string
          created_at?: string
          credentials?: NonNullable<Json>
          id?: string
          kind?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inbox_connection_secrets_connection_id_fkey"
            columns: ["connection_id"]
            isOneToOne: true
            referencedRelation: "inbox_connections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_connection_secrets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      inbox_connections: {
        Row: {
          config: NonNullable<Json>
          consecutive_failures: number
          created_at: string
          created_by: string | null
          credentials_ref: string | null
          health_status: string
          id: string
          kind: string
          last_delivery_at: string | null
          last_failure_at: string | null
          last_webhook_at: string | null
          name: string
          organization_id: string
          status: string
          updated_at: string
        }
        Insert: {
          config?: NonNullable<Json>
          consecutive_failures?: number
          created_at?: string
          created_by?: string | null
          credentials_ref?: string | null
          health_status?: string
          id?: string
          kind: string
          last_delivery_at?: string | null
          last_failure_at?: string | null
          last_webhook_at?: string | null
          name: string
          organization_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          config?: NonNullable<Json>
          consecutive_failures?: number
          created_at?: string
          created_by?: string | null
          credentials_ref?: string | null
          health_status?: string
          id?: string
          kind?: string
          last_delivery_at?: string | null
          last_failure_at?: string | null
          last_webhook_at?: string | null
          name?: string
          organization_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inbox_connections_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      inbox_deliveries: {
        Row: {
          canceled_at: string | null
          chat_message_id: string | null
          connection_id: string
          created_at: string
          direction: string
          error_message: string | null
          external_message_id: string | null
          id: string
          idempotency_key: string | null
          metadata: NonNullable<Json>
          next_attempt_at: string | null
          organization_id: string
          retry_count: number
          status: string
          updated_at: string
        }
        Insert: {
          canceled_at?: string | null
          chat_message_id?: string | null
          connection_id: string
          created_at?: string
          direction: string
          error_message?: string | null
          external_message_id?: string | null
          id?: string
          idempotency_key?: string | null
          metadata?: NonNullable<Json>
          next_attempt_at?: string | null
          organization_id: string
          retry_count?: number
          status?: string
          updated_at?: string
        }
        Update: {
          canceled_at?: string | null
          chat_message_id?: string | null
          connection_id?: string
          created_at?: string
          direction?: string
          error_message?: string | null
          external_message_id?: string | null
          id?: string
          idempotency_key?: string | null
          metadata?: NonNullable<Json>
          next_attempt_at?: string | null
          organization_id?: string
          retry_count?: number
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inbox_deliveries_chat_message_id_fkey"
            columns: ["chat_message_id"]
            isOneToOne: false
            referencedRelation: "chat_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_deliveries_connection_id_fkey"
            columns: ["connection_id"]
            isOneToOne: false
            referencedRelation: "inbox_connections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_deliveries_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      inbox_delivery_attempts: {
        Row: {
          attempt: number
          completed_at: string | null
          created_at: string
          delivery_id: string
          error_code: string | null
          error_message: string | null
          id: string
          organization_id: string
          provider_status: string | null
          response_metadata: NonNullable<Json>
          started_at: string
          status: string
        }
        Insert: {
          attempt: number
          completed_at?: string | null
          created_at?: string
          delivery_id: string
          error_code?: string | null
          error_message?: string | null
          id?: string
          organization_id: string
          provider_status?: string | null
          response_metadata?: NonNullable<Json>
          started_at?: string
          status: string
        }
        Update: {
          attempt?: number
          completed_at?: string | null
          created_at?: string
          delivery_id?: string
          error_code?: string | null
          error_message?: string | null
          id?: string
          organization_id?: string
          provider_status?: string | null
          response_metadata?: NonNullable<Json>
          started_at?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "inbox_delivery_attempts_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "inbox_deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_delivery_attempts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      inbox_draft_suggestions: {
        Row: {
          channel_thread_id: string
          confidence: number | null
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision: string | null
          edited_by: string | null
          escalation_reason: string | null
          id: string
          model: string | null
          organization_id: string
          source_message_id: string | null
          status: string
          text: string
          updated_at: string
        }
        Insert: {
          channel_thread_id: string
          confidence?: number | null
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision?: string | null
          edited_by?: string | null
          escalation_reason?: string | null
          id?: string
          model?: string | null
          organization_id: string
          source_message_id?: string | null
          status?: string
          text: string
          updated_at?: string
        }
        Update: {
          channel_thread_id?: string
          confidence?: number | null
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision?: string | null
          edited_by?: string | null
          escalation_reason?: string | null
          id?: string
          model?: string | null
          organization_id?: string
          source_message_id?: string | null
          status?: string
          text?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inbox_draft_suggestions_channel_thread_id_fkey"
            columns: ["channel_thread_id"]
            isOneToOne: false
            referencedRelation: "inbox_threads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_draft_suggestions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_draft_suggestions_source_message_id_fkey"
            columns: ["source_message_id"]
            isOneToOne: false
            referencedRelation: "chat_messages"
            referencedColumns: ["id"]
          },
        ]
      }
      inbox_endpoints: {
        Row: {
          connection_id: string
          contact_profile_id: string | null
          created_at: string
          external_actor_id: string
          id: string
          metadata: NonNullable<Json>
          normalized_address: string | null
          organization_id: string
          principal_type: string
          provider: string
          service_name: string | null
          updated_at: string
          user_id: string | null
          verified_at: string | null
        }
        Insert: {
          connection_id: string
          contact_profile_id?: string | null
          created_at?: string
          external_actor_id: string
          id?: string
          metadata?: NonNullable<Json>
          normalized_address?: string | null
          organization_id: string
          principal_type?: string
          provider: string
          service_name?: string | null
          updated_at?: string
          user_id?: string | null
          verified_at?: string | null
        }
        Update: {
          connection_id?: string
          contact_profile_id?: string | null
          created_at?: string
          external_actor_id?: string
          id?: string
          metadata?: NonNullable<Json>
          normalized_address?: string | null
          organization_id?: string
          principal_type?: string
          provider?: string
          service_name?: string | null
          updated_at?: string
          user_id?: string | null
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inbox_endpoints_connection_id_fkey"
            columns: ["connection_id"]
            isOneToOne: false
            referencedRelation: "inbox_connections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_endpoints_contact_profile_id_fkey"
            columns: ["contact_profile_id"]
            isOneToOne: false
            referencedRelation: "contact_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_endpoints_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      inbox_threads: {
        Row: {
          assigned_team_id: number | null
          assigned_user_id: string | null
          chat_thread_id: string | null
          connection_id: string
          continuation_cursor: string | null
          created_at: string
          customer_id: number | null
          external_actor_id: string | null
          external_channel_id: string | null
          external_thread_id: string
          id: string
          metadata: NonNullable<Json>
          organization_id: string
          takeover_at: string | null
          takeover_reason: string | null
          takeover_status: string
          updated_at: string
        }
        Insert: {
          assigned_team_id?: number | null
          assigned_user_id?: string | null
          chat_thread_id?: string | null
          connection_id: string
          continuation_cursor?: string | null
          created_at?: string
          customer_id?: number | null
          external_actor_id?: string | null
          external_channel_id?: string | null
          external_thread_id: string
          id?: string
          metadata?: NonNullable<Json>
          organization_id: string
          takeover_at?: string | null
          takeover_reason?: string | null
          takeover_status?: string
          updated_at?: string
        }
        Update: {
          assigned_team_id?: number | null
          assigned_user_id?: string | null
          chat_thread_id?: string | null
          connection_id?: string
          continuation_cursor?: string | null
          created_at?: string
          customer_id?: number | null
          external_actor_id?: string | null
          external_channel_id?: string | null
          external_thread_id?: string
          id?: string
          metadata?: NonNullable<Json>
          organization_id?: string
          takeover_at?: string | null
          takeover_reason?: string | null
          takeover_status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inbox_threads_assigned_team_id_fkey"
            columns: ["assigned_team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_threads_chat_thread_id_fkey"
            columns: ["chat_thread_id"]
            isOneToOne: false
            referencedRelation: "chat_threads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_threads_connection_id_fkey"
            columns: ["connection_id"]
            isOneToOne: false
            referencedRelation: "inbox_connections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_threads_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inbox_threads_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      inbox_webhook_jobs: {
        Row: {
          available_at: string
          connection_id: string
          continuation_cursor: string | null
          created_at: string
          id: string
          last_error: string | null
          leased_until: string | null
          organization_id: string
          payload: NonNullable<Json>
          processed_at: string | null
          provider: string
          provider_cursor: string | null
          provider_delivery_id: string
          retry_count: number
          status: string
          updated_at: string
        }
        Insert: {
          available_at?: string
          connection_id: string
          continuation_cursor?: string | null
          created_at?: string
          id?: string
          last_error?: string | null
          leased_until?: string | null
          organization_id: string
          payload: NonNullable<Json>
          processed_at?: string | null
          provider: string
          provider_cursor?: string | null
          provider_delivery_id: string
          retry_count?: number
          status?: string
          updated_at?: string
        }
        Update: {
          available_at?: string
          connection_id?: string
          continuation_cursor?: string | null
          created_at?: string
          id?: string
          last_error?: string | null
          leased_until?: string | null
          organization_id?: string
          payload?: NonNullable<Json>
          processed_at?: string | null
          provider?: string
          provider_cursor?: string | null
          provider_delivery_id?: string
          retry_count?: number
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inbox_webhook_jobs_connection_id_fkey"
            columns: ["connection_id"]
            isOneToOne: false
            referencedRelation: "inbox_connections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inbox_webhook_jobs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      integration_categories: {
        Row: {
          created_at: string
          description: string | null
          id: string
          name: string
          position: number
          slug: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          name: string
          position?: number
          slug: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          name?: string
          position?: number
          slug?: string
          updated_at?: string
        }
        Relationships: []
      }
      integration_definition_categories: {
        Row: {
          category_id: string
          created_at: string
          definition_id: string
        }
        Insert: {
          category_id: string
          created_at?: string
          definition_id: string
        }
        Update: {
          category_id?: string
          created_at?: string
          definition_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "integration_definition_categories_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "integration_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "integration_definition_categories_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "integration_definitions"
            referencedColumns: ["id"]
          },
        ]
      }
      integration_definitions: {
        Row: {
          allow_multiple: boolean
          created_at: string
          description: string
          documentation_url: string | null
          enabled: boolean
          featured: boolean
          id: string
          keywords: string[]
          logo_path: string | null
          long_description: string | null
          name: string
          privacy_policy_url: string | null
          provider: string
          recently_added_at: string | null
          requestable: boolean
          slug: string
          status: string
          support_url: string | null
          supports_organization_install: boolean
          supports_user_install: boolean
          terms_url: string | null
          updated_at: string
          usage_count: number
          website_url: string | null
        }
        Insert: {
          allow_multiple?: boolean
          created_at?: string
          description: string
          documentation_url?: string | null
          enabled?: boolean
          featured?: boolean
          id?: string
          keywords?: string[]
          logo_path?: string | null
          long_description?: string | null
          name: string
          privacy_policy_url?: string | null
          provider: string
          recently_added_at?: string | null
          requestable?: boolean
          slug: string
          status?: string
          support_url?: string | null
          supports_organization_install?: boolean
          supports_user_install?: boolean
          terms_url?: string | null
          updated_at?: string
          usage_count?: number
          website_url?: string | null
        }
        Update: {
          allow_multiple?: boolean
          created_at?: string
          description?: string
          documentation_url?: string | null
          enabled?: boolean
          featured?: boolean
          id?: string
          keywords?: string[]
          logo_path?: string | null
          long_description?: string | null
          name?: string
          privacy_policy_url?: string | null
          provider?: string
          recently_added_at?: string | null
          requestable?: boolean
          slug?: string
          status?: string
          support_url?: string | null
          supports_organization_install?: boolean
          supports_user_install?: boolean
          terms_url?: string | null
          updated_at?: string
          usage_count?: number
          website_url?: string | null
        }
        Relationships: []
      }
      integration_installation_secrets: {
        Row: {
          auth_header_name: string | null
          auth_header_value: string | null
          base_url: string | null
          created_at: string
          installation_id: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          auth_header_name?: string | null
          auth_header_value?: string | null
          base_url?: string | null
          created_at?: string
          installation_id: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          auth_header_name?: string | null
          auth_header_value?: string | null
          base_url?: string | null
          created_at?: string
          installation_id?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "integration_installation_secr_installation_id_organization_fkey"
            columns: ["installation_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "integration_installations"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "integration_installation_secrets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      integration_installations: {
        Row: {
          created_at: string
          created_by: string | null
          definition_id: string
          display_name: string
          domain_kind: string
          domain_record_id: string | null
          id: string
          metadata: NonNullable<Json>
          organization_id: string
          scope: string
          status: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          definition_id: string
          display_name: string
          domain_kind: string
          domain_record_id?: string | null
          id?: string
          metadata?: NonNullable<Json>
          organization_id: string
          scope: string
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          definition_id?: string
          display_name?: string
          domain_kind?: string
          domain_record_id?: string | null
          id?: string
          metadata?: NonNullable<Json>
          organization_id?: string
          scope?: string
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "integration_installations_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "integration_definitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "integration_installations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "integration_installations_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      integration_requests: {
        Row: {
          created_at: string
          definition_id: string | null
          id: string
          metadata: NonNullable<Json>
          notes: string | null
          organization_id: string
          requested_name: string | null
          scope: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          definition_id?: string | null
          id?: string
          metadata?: NonNullable<Json>
          notes?: string | null
          organization_id: string
          requested_name?: string | null
          scope?: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          definition_id?: string | null
          id?: string
          metadata?: NonNullable<Json>
          notes?: string | null
          organization_id?: string
          requested_name?: string | null
          scope?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "integration_requests_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "integration_definitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "integration_requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "integration_requests_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      integration_user_authorizations: {
        Row: {
          authorized_at: string
          created_at: string
          expires_at: string | null
          id: string
          installation_id: string
          metadata: NonNullable<Json>
          organization_id: string
          revoked_at: string | null
          scopes: string[]
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          authorized_at?: string
          created_at?: string
          expires_at?: string | null
          id?: string
          installation_id: string
          metadata?: NonNullable<Json>
          organization_id: string
          revoked_at?: string | null
          scopes?: string[]
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          authorized_at?: string
          created_at?: string
          expires_at?: string | null
          id?: string
          installation_id?: string
          metadata?: NonNullable<Json>
          organization_id?: string
          revoked_at?: string | null
          scopes?: string[]
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "integration_user_authorizatio_installation_id_organization_fkey"
            columns: ["installation_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "integration_installations"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "integration_user_authorizations_installation_id_fkey"
            columns: ["installation_id"]
            isOneToOne: false
            referencedRelation: "integration_installations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "integration_user_authorizations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "integration_user_authorizations_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      inventory_allocations: {
        Row: {
          consumed_at: string | null
          created_at: string
          id: string
          invoice_line_id: string | null
          order_line_id: string | null
          organization_id: string
          product_id: string
          quantity: number
          quote_version_line_id: string | null
          state: Database["public"]["Enums"]["inventory_allocation_state"]
          stock_record_id: string | null
          task_material_id: string | null
          updated_at: string
          variant_id: string | null
        }
        Insert: {
          consumed_at?: string | null
          created_at?: string
          id?: string
          invoice_line_id?: string | null
          order_line_id?: string | null
          organization_id: string
          product_id: string
          quantity: number
          quote_version_line_id?: string | null
          state?: Database["public"]["Enums"]["inventory_allocation_state"]
          stock_record_id?: string | null
          task_material_id?: string | null
          updated_at?: string
          variant_id?: string | null
        }
        Update: {
          consumed_at?: string | null
          created_at?: string
          id?: string
          invoice_line_id?: string | null
          order_line_id?: string | null
          organization_id?: string
          product_id?: string
          quantity?: number
          quote_version_line_id?: string | null
          state?: Database["public"]["Enums"]["inventory_allocation_state"]
          stock_record_id?: string | null
          task_material_id?: string | null
          updated_at?: string
          variant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_allocations_invoice_line_id_organization_id_fkey"
            columns: ["invoice_line_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "invoice_lines"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_allocations_order_line_organization_fkey"
            columns: ["order_line_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "order_lines"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_allocations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_allocations_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_allocations_quote_version_line_id_organization_i_fkey"
            columns: ["quote_version_line_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "quote_version_lines"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_allocations_stock_record_id_organization_id_fkey"
            columns: ["stock_record_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "inventory_stock_records"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_allocations_task_material_id_organization_id_fkey"
            columns: ["task_material_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "task_materials"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_allocations_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      inventory_locations: {
        Row: {
          created_at: string
          description: string | null
          id: string
          name: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          name: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          name?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_locations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_movements: {
        Row: {
          allocated_after: number
          allocated_delta: number
          created_at: string
          created_by: string | null
          id: string
          invoice_id: string | null
          location_id: string | null
          movement_type: Database["public"]["Enums"]["inventory_movement_type"]
          occurred_at: string
          on_hand_delta: number
          order_id: string | null
          organization_id: string
          product_id: string
          purchase_order_id: string | null
          quantity_after: number
          quote_id: string | null
          reason: string | null
          reference_number: string | null
          shipment_id: string | null
          stock_record_id: string
          supplier_id: string | null
          task_material_id: string | null
          variant_id: string | null
        }
        Insert: {
          allocated_after: number
          allocated_delta?: number
          created_at?: string
          created_by?: string | null
          id?: string
          invoice_id?: string | null
          location_id?: string | null
          movement_type: Database["public"]["Enums"]["inventory_movement_type"]
          occurred_at?: string
          on_hand_delta: number
          order_id?: string | null
          organization_id: string
          product_id: string
          purchase_order_id?: string | null
          quantity_after: number
          quote_id?: string | null
          reason?: string | null
          reference_number?: string | null
          shipment_id?: string | null
          stock_record_id: string
          supplier_id?: string | null
          task_material_id?: string | null
          variant_id?: string | null
        }
        Update: {
          allocated_after?: number
          allocated_delta?: number
          created_at?: string
          created_by?: string | null
          id?: string
          invoice_id?: string | null
          location_id?: string | null
          movement_type?: Database["public"]["Enums"]["inventory_movement_type"]
          occurred_at?: string
          on_hand_delta?: number
          order_id?: string | null
          organization_id?: string
          product_id?: string
          purchase_order_id?: string | null
          quantity_after?: number
          quote_id?: string | null
          reason?: string | null
          reference_number?: string | null
          shipment_id?: string | null
          stock_record_id?: string
          supplier_id?: string | null
          task_material_id?: string | null
          variant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_movements_invoice_organization_fkey"
            columns: ["invoice_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_movements_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "inventory_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_location_id_organization_id_fkey"
            columns: ["location_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "inventory_locations"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_movements_order_organization_fkey"
            columns: ["order_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_movements_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_movements_purchase_order_organization_fkey"
            columns: ["purchase_order_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_movements_quote_organization_fkey"
            columns: ["quote_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_movements_shipment_organization_fkey"
            columns: ["shipment_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "shipments"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_movements_stock_record_id_fkey"
            columns: ["stock_record_id"]
            isOneToOne: false
            referencedRelation: "inventory_stock_records"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_stock_record_id_organization_id_fkey"
            columns: ["stock_record_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "inventory_stock_records"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_movements_supplier_id_organization_id_fkey"
            columns: ["supplier_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_movements_task_material_organization_fkey"
            columns: ["task_material_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "task_materials"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_movements_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      inventory_reorder_rules: {
        Row: {
          created_at: string
          id: string
          location_id: string | null
          max_level: number | null
          organization_id: string
          product_id: string
          reorder_point: number
          reorder_quantity: number | null
          supplier_id: string | null
          updated_at: string
          variant_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          location_id?: string | null
          max_level?: number | null
          organization_id: string
          product_id: string
          reorder_point: number
          reorder_quantity?: number | null
          supplier_id?: string | null
          updated_at?: string
          variant_id: string
        }
        Update: {
          created_at?: string
          id?: string
          location_id?: string | null
          max_level?: number | null
          organization_id?: string
          product_id?: string
          reorder_point?: number
          reorder_quantity?: number | null
          supplier_id?: string | null
          updated_at?: string
          variant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_reorder_rules_location_id_organization_id_fkey"
            columns: ["location_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "inventory_locations"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_reorder_rules_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_reorder_rules_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_reorder_rules_supplier_id_organization_id_fkey"
            columns: ["supplier_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_reorder_rules_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      inventory_stock_records: {
        Row: {
          allocated_quantity: number
          bin_location: string | null
          created_at: string
          created_by: string | null
          currency: string | null
          expires_on: string | null
          id: string
          last_counted_on: string | null
          location_id: string | null
          lot_number: string | null
          notes: string | null
          on_hand_quantity: number
          organization_id: string
          product_id: string
          serial_number: string | null
          status: Database["public"]["Enums"]["inventory_status"]
          unit_cost: number | null
          updated_at: string
          updated_by: string | null
          variant_id: string | null
        }
        Insert: {
          allocated_quantity?: number
          bin_location?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          expires_on?: string | null
          id?: string
          last_counted_on?: string | null
          location_id?: string | null
          lot_number?: string | null
          notes?: string | null
          on_hand_quantity?: number
          organization_id: string
          product_id: string
          serial_number?: string | null
          status?: Database["public"]["Enums"]["inventory_status"]
          unit_cost?: number | null
          updated_at?: string
          updated_by?: string | null
          variant_id?: string | null
        }
        Update: {
          allocated_quantity?: number
          bin_location?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          expires_on?: string | null
          id?: string
          last_counted_on?: string | null
          location_id?: string | null
          lot_number?: string | null
          notes?: string | null
          on_hand_quantity?: number
          organization_id?: string
          product_id?: string
          serial_number?: string | null
          status?: Database["public"]["Enums"]["inventory_status"]
          unit_cost?: number | null
          updated_at?: string
          updated_by?: string | null
          variant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_stock_records_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "inventory_stock_records_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "inventory_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_stock_records_location_id_organization_id_fkey"
            columns: ["location_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "inventory_locations"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_stock_records_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_stock_records_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_stock_records_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "inventory_stock_records_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      invoice_charges: {
        Row: {
          amount_cents: number
          created_at: string
          created_by: string | null
          created_by_run_step_id: string | null
          currency: string
          id: string
          invoice_id: string
          kind: Database["public"]["Enums"]["invoice_charge_kind"]
          organization_id: string
          reason: string | null
          updated_at: string
        }
        Insert: {
          amount_cents: number
          created_at?: string
          created_by?: string | null
          created_by_run_step_id?: string | null
          currency: string
          id?: string
          invoice_id: string
          kind: Database["public"]["Enums"]["invoice_charge_kind"]
          organization_id: string
          reason?: string | null
          updated_at?: string
        }
        Update: {
          amount_cents?: number
          created_at?: string
          created_by?: string | null
          created_by_run_step_id?: string | null
          currency?: string
          id?: string
          invoice_id?: string
          kind?: Database["public"]["Enums"]["invoice_charge_kind"]
          organization_id?: string
          reason?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoice_charges_created_by_run_step_id_fkey"
            columns: ["created_by_run_step_id"]
            isOneToOne: false
            referencedRelation: "workflow_run_steps"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_charges_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_charges_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_lines: {
        Row: {
          created_at: string
          description: string | null
          direct_cost_confidence:
            | Database["public"]["Enums"]["invoice_direct_cost_confidence"]
            | null
          direct_cost_currency: string | null
          direct_cost_snapshotted_at: string | null
          direct_cost_source:
            | Database["public"]["Enums"]["invoice_direct_cost_source"]
            | null
          direct_cost_unit_amount: number | null
          discount_kind: Database["public"]["Enums"]["discount_kind"]
          discount_value: number
          id: string
          invoice_id: string
          kind: Database["public"]["Enums"]["invoice_line_kind"]
          line_type: Database["public"]["Enums"]["invoice_line_type"] | null
          order_line_id: string | null
          organization_id: string
          position: number
          pricing_mode: Database["public"]["Enums"]["invoice_line_pricing_mode"]
          product_id: string | null
          promotion_id: string | null
          quantity: number
          shipment_id: string | null
          stock_mode: Database["public"]["Enums"]["document_line_stock_mode"]
          task_id: string | null
          title: string
          unit: string | null
          unit_price: number
          updated_at: string
          variant_id: string | null
          vat_rate: number
        }
        Insert: {
          created_at?: string
          description?: string | null
          direct_cost_confidence?:
            | Database["public"]["Enums"]["invoice_direct_cost_confidence"]
            | null
          direct_cost_currency?: string | null
          direct_cost_snapshotted_at?: string | null
          direct_cost_source?:
            | Database["public"]["Enums"]["invoice_direct_cost_source"]
            | null
          direct_cost_unit_amount?: number | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          invoice_id: string
          kind?: Database["public"]["Enums"]["invoice_line_kind"]
          line_type?: Database["public"]["Enums"]["invoice_line_type"] | null
          order_line_id?: string | null
          organization_id: string
          position?: number
          pricing_mode?: Database["public"]["Enums"]["invoice_line_pricing_mode"]
          product_id?: string | null
          promotion_id?: string | null
          quantity?: number
          shipment_id?: string | null
          stock_mode?: Database["public"]["Enums"]["document_line_stock_mode"]
          task_id?: string | null
          title: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          variant_id?: string | null
          vat_rate?: number
        }
        Update: {
          created_at?: string
          description?: string | null
          direct_cost_confidence?:
            | Database["public"]["Enums"]["invoice_direct_cost_confidence"]
            | null
          direct_cost_currency?: string | null
          direct_cost_snapshotted_at?: string | null
          direct_cost_source?:
            | Database["public"]["Enums"]["invoice_direct_cost_source"]
            | null
          direct_cost_unit_amount?: number | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          invoice_id?: string
          kind?: Database["public"]["Enums"]["invoice_line_kind"]
          line_type?: Database["public"]["Enums"]["invoice_line_type"] | null
          order_line_id?: string | null
          organization_id?: string
          position?: number
          pricing_mode?: Database["public"]["Enums"]["invoice_line_pricing_mode"]
          product_id?: string | null
          promotion_id?: string | null
          quantity?: number
          shipment_id?: string | null
          stock_mode?: Database["public"]["Enums"]["document_line_stock_mode"]
          task_id?: string | null
          title?: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          variant_id?: string | null
          vat_rate?: number
        }
        Relationships: [
          {
            foreignKeyName: "invoice_lines_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_lines_order_line_organization_fkey"
            columns: ["order_line_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "order_lines"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "invoice_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_lines_promotion_organization_fkey"
            columns: ["promotion_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "promotions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "invoice_lines_shipment_organization_fkey"
            columns: ["shipment_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "shipments"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "invoice_lines_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_lines_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      invoice_payments: {
        Row: {
          amount_cents: number
          amount_total: number
          application_fee_amount: number
          application_fee_bps: number
          application_fee_mode: string
          canceled_at: string | null
          created_at: string
          currency: string
          disputed_at: string | null
          failure_code: string | null
          failure_message: string | null
          id: string
          invoice_id: string
          method: Database["public"]["Enums"]["invoice_payment_method"]
          note: string | null
          organization_id: string
          paid_at: string | null
          provider: string
          received_on: string | null
          recorded_by: string | null
          reference: string | null
          refunded_at: string | null
          status: Database["public"]["Enums"]["invoice_payment_status"]
          stripe_charge_id: string | null
          stripe_destination_account_id: string | null
          stripe_payment_intent_id: string | null
          updated_at: string
        }
        Insert: {
          amount_cents?: number
          amount_total: number
          application_fee_amount?: number
          application_fee_bps?: number
          application_fee_mode?: string
          canceled_at?: string | null
          created_at?: string
          currency: string
          disputed_at?: string | null
          failure_code?: string | null
          failure_message?: string | null
          id?: string
          invoice_id: string
          method?: Database["public"]["Enums"]["invoice_payment_method"]
          note?: string | null
          organization_id: string
          paid_at?: string | null
          provider?: string
          received_on?: string | null
          recorded_by?: string | null
          reference?: string | null
          refunded_at?: string | null
          status?: Database["public"]["Enums"]["invoice_payment_status"]
          stripe_charge_id?: string | null
          stripe_destination_account_id?: string | null
          stripe_payment_intent_id?: string | null
          updated_at?: string
        }
        Update: {
          amount_cents?: number
          amount_total?: number
          application_fee_amount?: number
          application_fee_bps?: number
          application_fee_mode?: string
          canceled_at?: string | null
          created_at?: string
          currency?: string
          disputed_at?: string | null
          failure_code?: string | null
          failure_message?: string | null
          id?: string
          invoice_id?: string
          method?: Database["public"]["Enums"]["invoice_payment_method"]
          note?: string | null
          organization_id?: string
          paid_at?: string | null
          provider?: string
          received_on?: string | null
          recorded_by?: string | null
          reference?: string | null
          refunded_at?: string | null
          status?: Database["public"]["Enums"]["invoice_payment_status"]
          stripe_charge_id?: string | null
          stripe_destination_account_id?: string | null
          stripe_payment_intent_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoice_payments_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_payments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_status_history: {
        Row: {
          actor_user_id: string | null
          created_at: string
          from_status: Database["public"]["Enums"]["invoice_status"] | null
          id: string
          invoice_id: string
          organization_id: string
          reason: string | null
          to_status: Database["public"]["Enums"]["invoice_status"]
        }
        Insert: {
          actor_user_id?: string | null
          created_at?: string
          from_status?: Database["public"]["Enums"]["invoice_status"] | null
          id?: string
          invoice_id: string
          organization_id: string
          reason?: string | null
          to_status: Database["public"]["Enums"]["invoice_status"]
        }
        Update: {
          actor_user_id?: string | null
          created_at?: string
          from_status?: Database["public"]["Enums"]["invoice_status"] | null
          id?: string
          invoice_id?: string
          organization_id?: string
          reason?: string | null
          to_status?: Database["public"]["Enums"]["invoice_status"]
        }
        Relationships: [
          {
            foreignKeyName: "invoice_status_history_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_status_history_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_tasks: {
        Row: {
          created_at: string
          invoice_id: string
          organization_id: string
          position: number
          task_id: string
        }
        Insert: {
          created_at?: string
          invoice_id: string
          organization_id: string
          position?: number
          task_id: string
        }
        Update: {
          created_at?: string
          invoice_id?: string
          organization_id?: string
          position?: number
          task_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoice_tasks_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_tasks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_tasks_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
        ]
      }
      invoices: {
        Row: {
          amount_due_cents: number
          amount_paid_cents: number
          archived_at: string | null
          buyer_address_city: string | null
          buyer_address_country: string | null
          buyer_address_line1: string | null
          buyer_address_line2: string | null
          buyer_address_postal_code: string | null
          buyer_btw: string | null
          buyer_email: string | null
          buyer_kvk: string | null
          buyer_name: string | null
          cancelled_at: string | null
          created_at: string
          created_by: string | null
          currency: string
          customer_contact_id: string | null
          customer_id: number
          customer_reference: string | null
          delivery_date: string | null
          discount_description: string | null
          discount_kind: Database["public"]["Enums"]["discount_kind"]
          discount_value: number
          due_date: string | null
          due_days: number | null
          footer_text: string | null
          formatted_number: string | null
          id: string
          intro: string | null
          invoice_template_id: string | null
          issue_date: string | null
          kind: Database["public"]["Enums"]["invoice_kind"]
          number: number | null
          number_prefix: string
          number_year: number | null
          online_payment_enabled: boolean
          order_id: string | null
          organization_id: string
          original_invoice_id: string | null
          paid_at: string | null
          promotion_id: string | null
          public_message: string | null
          seller_address_city: string | null
          seller_address_country: string | null
          seller_address_line1: string | null
          seller_address_line2: string | null
          seller_address_postal_code: string | null
          seller_btw: string | null
          seller_email: string | null
          seller_iban: string | null
          seller_kvk: string | null
          seller_name: string | null
          seller_phone: string | null
          sent_at: string | null
          source_quote_id: string | null
          status: Database["public"]["Enums"]["invoice_status"]
          subtotal_excl: number
          terms: string | null
          terms_pdf_file_id: string | null
          terms_pdf_version_id: string | null
          terms_rich_text: string | null
          terms_url: string | null
          title: string
          total_incl: number
          uncollectible_at: string | null
          uncollectible_reason: string | null
          updated_at: string
          updated_by: string | null
          vat_inclusive: boolean
          vat_regime: Database["public"]["Enums"]["document_vat_regime"]
          vat_total: number
        }
        Insert: {
          amount_due_cents?: number
          amount_paid_cents?: number
          archived_at?: string | null
          buyer_address_city?: string | null
          buyer_address_country?: string | null
          buyer_address_line1?: string | null
          buyer_address_line2?: string | null
          buyer_address_postal_code?: string | null
          buyer_btw?: string | null
          buyer_email?: string | null
          buyer_kvk?: string | null
          buyer_name?: string | null
          cancelled_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          customer_contact_id?: string | null
          customer_id: number
          customer_reference?: string | null
          delivery_date?: string | null
          discount_description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          due_date?: string | null
          due_days?: number | null
          footer_text?: string | null
          formatted_number?: string | null
          id?: string
          intro?: string | null
          invoice_template_id?: string | null
          issue_date?: string | null
          kind?: Database["public"]["Enums"]["invoice_kind"]
          number?: number | null
          number_prefix?: string
          number_year?: number | null
          online_payment_enabled?: boolean
          order_id?: string | null
          organization_id: string
          original_invoice_id?: string | null
          paid_at?: string | null
          promotion_id?: string | null
          public_message?: string | null
          seller_address_city?: string | null
          seller_address_country?: string | null
          seller_address_line1?: string | null
          seller_address_line2?: string | null
          seller_address_postal_code?: string | null
          seller_btw?: string | null
          seller_email?: string | null
          seller_iban?: string | null
          seller_kvk?: string | null
          seller_name?: string | null
          seller_phone?: string | null
          sent_at?: string | null
          source_quote_id?: string | null
          status?: Database["public"]["Enums"]["invoice_status"]
          subtotal_excl?: number
          terms?: string | null
          terms_pdf_file_id?: string | null
          terms_pdf_version_id?: string | null
          terms_rich_text?: string | null
          terms_url?: string | null
          title: string
          total_incl?: number
          uncollectible_at?: string | null
          uncollectible_reason?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_inclusive?: boolean
          vat_regime?: Database["public"]["Enums"]["document_vat_regime"]
          vat_total?: number
        }
        Update: {
          amount_due_cents?: number
          amount_paid_cents?: number
          archived_at?: string | null
          buyer_address_city?: string | null
          buyer_address_country?: string | null
          buyer_address_line1?: string | null
          buyer_address_line2?: string | null
          buyer_address_postal_code?: string | null
          buyer_btw?: string | null
          buyer_email?: string | null
          buyer_kvk?: string | null
          buyer_name?: string | null
          cancelled_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          customer_contact_id?: string | null
          customer_id?: number
          customer_reference?: string | null
          delivery_date?: string | null
          discount_description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          due_date?: string | null
          due_days?: number | null
          footer_text?: string | null
          formatted_number?: string | null
          id?: string
          intro?: string | null
          invoice_template_id?: string | null
          issue_date?: string | null
          kind?: Database["public"]["Enums"]["invoice_kind"]
          number?: number | null
          number_prefix?: string
          number_year?: number | null
          online_payment_enabled?: boolean
          order_id?: string | null
          organization_id?: string
          original_invoice_id?: string | null
          paid_at?: string | null
          promotion_id?: string | null
          public_message?: string | null
          seller_address_city?: string | null
          seller_address_country?: string | null
          seller_address_line1?: string | null
          seller_address_line2?: string | null
          seller_address_postal_code?: string | null
          seller_btw?: string | null
          seller_email?: string | null
          seller_iban?: string | null
          seller_kvk?: string | null
          seller_name?: string | null
          seller_phone?: string | null
          sent_at?: string | null
          source_quote_id?: string | null
          status?: Database["public"]["Enums"]["invoice_status"]
          subtotal_excl?: number
          terms?: string | null
          terms_pdf_file_id?: string | null
          terms_pdf_version_id?: string | null
          terms_rich_text?: string | null
          terms_url?: string | null
          title?: string
          total_incl?: number
          uncollectible_at?: string | null
          uncollectible_reason?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_inclusive?: boolean
          vat_regime?: Database["public"]["Enums"]["document_vat_regime"]
          vat_total?: number
        }
        Relationships: [
          {
            foreignKeyName: "invoices_customer_contact_id_fkey"
            columns: ["customer_contact_id"]
            isOneToOne: false
            referencedRelation: "customer_contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "invoices_invoice_template_id_fkey"
            columns: ["invoice_template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_order_organization_fkey"
            columns: ["order_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "invoices_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_original_invoice_id_fkey"
            columns: ["original_invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_promotion_organization_fkey"
            columns: ["promotion_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "promotions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "invoices_source_quote_id_fkey"
            columns: ["source_quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_terms_pdf_file_id_fkey"
            columns: ["terms_pdf_file_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_terms_pdf_version_id_fkey"
            columns: ["terms_pdf_version_id"]
            isOneToOne: false
            referencedRelation: "file_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_chunks: {
        Row: {
          collection_id: string
          content: string
          content_hash: string
          content_tsv: unknown
          created_at: string
          embedding: unknown
          file_id: string
          id: string
          metadata: NonNullable<Json>
          organization_id: string | null
          position: number
          token_count: number | null
        }
        Insert: {
          collection_id: string
          content: string
          content_hash: string
          content_tsv?: never
          created_at?: string
          embedding?: unknown
          file_id: string
          id?: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          position: number
          token_count?: number | null
        }
        Update: {
          collection_id?: string
          content?: string
          content_hash?: string
          content_tsv?: never
          created_at?: string
          embedding?: unknown
          file_id?: string
          id?: string
          metadata?: NonNullable<Json>
          organization_id?: string | null
          position?: number
          token_count?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_chunks_collection_id_fkey"
            columns: ["collection_id"]
            isOneToOne: false
            referencedRelation: "knowledge_collections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_chunks_file_id_fkey"
            columns: ["file_id"]
            isOneToOne: false
            referencedRelation: "knowledge_files"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_chunks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_collection_grants: {
        Row: {
          collection_id: string
          created_at: string
          created_by: string | null
          id: string
          organization_id: string
          team_id: number | null
          user_id: string | null
        }
        Insert: {
          collection_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          organization_id: string
          team_id?: number | null
          user_id?: string | null
        }
        Update: {
          collection_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          organization_id?: string
          team_id?: number | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_collection_grants_collection_id_fkey"
            columns: ["collection_id"]
            isOneToOne: false
            referencedRelation: "knowledge_collections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_collection_grants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_collection_grants_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_collections: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          metadata: NonNullable<Json>
          name: string
          organization_id: string | null
          retrieval_priority: number
          scope: string
          updated_at: string
          visibility: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          metadata?: NonNullable<Json>
          name: string
          organization_id?: string | null
          retrieval_priority?: number
          scope: string
          updated_at?: string
          visibility?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          metadata?: NonNullable<Json>
          name?: string
          organization_id?: string | null
          retrieval_priority?: number
          scope?: string
          updated_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_collections_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_files: {
        Row: {
          byte_size: number | null
          checksum: string | null
          collection_id: string
          created_at: string
          created_by: string | null
          error_message: string | null
          file_node_id: string | null
          id: string
          media_type: string | null
          metadata: NonNullable<Json>
          organization_id: string | null
          source_kind: string
          source_uri: string | null
          status: string
          storage_bucket: string | null
          storage_path: string | null
          title: string
          updated_at: string
        }
        Insert: {
          byte_size?: number | null
          checksum?: string | null
          collection_id: string
          created_at?: string
          created_by?: string | null
          error_message?: string | null
          file_node_id?: string | null
          id?: string
          media_type?: string | null
          metadata?: NonNullable<Json>
          organization_id?: string | null
          source_kind: string
          source_uri?: string | null
          status?: string
          storage_bucket?: string | null
          storage_path?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          byte_size?: number | null
          checksum?: string | null
          collection_id?: string
          created_at?: string
          created_by?: string | null
          error_message?: string | null
          file_node_id?: string | null
          id?: string
          media_type?: string | null
          metadata?: NonNullable<Json>
          organization_id?: string | null
          source_kind?: string
          source_uri?: string | null
          status?: string
          storage_bucket?: string | null
          storage_path?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_files_collection_id_fkey"
            columns: ["collection_id"]
            isOneToOne: false
            referencedRelation: "knowledge_collections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_files_file_node_id_fkey"
            columns: ["file_node_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_files_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_deliveries: {
        Row: {
          attempted_at: string | null
          channel: string
          created_at: string
          delivered_at: string | null
          error: string | null
          id: string
          organization_id: string
          provider: string | null
          provider_message_id: string | null
          recipient_id: string
          status: string
        }
        Insert: {
          attempted_at?: string | null
          channel: string
          created_at?: string
          delivered_at?: string | null
          error?: string | null
          id?: string
          organization_id: string
          provider?: string | null
          provider_message_id?: string | null
          recipient_id: string
          status: string
        }
        Update: {
          attempted_at?: string | null
          channel?: string
          created_at?: string
          delivered_at?: string | null
          error?: string | null
          id?: string
          organization_id?: string
          provider?: string | null
          provider_message_id?: string | null
          recipient_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_deliveries_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_deliveries_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "notification_recipients"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_events: {
        Row: {
          action_path: string | null
          actor_user_id: string | null
          created_at: string
          created_by: string | null
          id: string
          metadata: NonNullable<Json>
          organization_id: string
          priority: string
          subject_id: string
          subject_label: string
          subject_type: string
          summary: string | null
          type: string
        }
        Insert: {
          action_path?: string | null
          actor_user_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          metadata?: NonNullable<Json>
          organization_id: string
          priority?: string
          subject_id: string
          subject_label: string
          subject_type: string
          summary?: string | null
          type: string
        }
        Update: {
          action_path?: string | null
          actor_user_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          metadata?: NonNullable<Json>
          organization_id?: string
          priority?: string
          subject_id?: string
          subject_label?: string
          subject_type?: string
          summary?: string | null
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          channel: string
          created_at: string
          enabled: boolean
          id: string
          organization_id: string | null
          type: string
          user_id: string
        }
        Insert: {
          channel: string
          created_at?: string
          enabled?: boolean
          id?: string
          organization_id?: string | null
          type: string
          user_id: string
        }
        Update: {
          channel?: string
          created_at?: string
          enabled?: boolean
          id?: string
          organization_id?: string | null
          type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_recipients: {
        Row: {
          created_at: string
          delivered_at: string
          dismissed_at: string | null
          event_id: string
          id: string
          organization_id: string
          read_at: string | null
          recipient_user_id: string
          resolved_at: string | null
        }
        Insert: {
          created_at?: string
          delivered_at?: string
          dismissed_at?: string | null
          event_id: string
          id?: string
          organization_id: string
          read_at?: string | null
          recipient_user_id: string
          resolved_at?: string | null
        }
        Update: {
          created_at?: string
          delivered_at?: string
          dismissed_at?: string | null
          event_id?: string
          id?: string
          organization_id?: string
          read_at?: string | null
          recipient_user_id?: string
          resolved_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notification_recipients_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "notification_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_recipients_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_recipients_recipient_user_id_organization_id_fkey"
            columns: ["recipient_user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      notification_subscriptions: {
        Row: {
          created_at: string
          id: string
          level: string
          organization_id: string
          subject_id: string
          subject_type: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          level?: string
          organization_id: string
          subject_id: string
          subject_type: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          level?: string
          organization_id?: string
          subject_id?: string
          subject_type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_subscriptions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_subscriptions_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      order_digital_grants: {
        Row: {
          created_at: string
          digital_file_id: string | null
          download_count: number
          expires_at: string | null
          id: string
          license_key_id: string | null
          order_line_id: string
          organization_id: string
          revoked_at: string | null
        }
        Insert: {
          created_at?: string
          digital_file_id?: string | null
          download_count?: number
          expires_at?: string | null
          id?: string
          license_key_id?: string | null
          order_line_id: string
          organization_id: string
          revoked_at?: string | null
        }
        Update: {
          created_at?: string
          digital_file_id?: string | null
          download_count?: number
          expires_at?: string | null
          id?: string
          license_key_id?: string | null
          order_line_id?: string
          organization_id?: string
          revoked_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "order_digital_grants_digital_file_id_fkey"
            columns: ["digital_file_id"]
            isOneToOne: false
            referencedRelation: "product_digital_files"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_digital_grants_license_key_id_fkey"
            columns: ["license_key_id"]
            isOneToOne: false
            referencedRelation: "product_license_keys"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_digital_grants_order_line_id_organization_id_fkey"
            columns: ["order_line_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "order_lines"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "order_digital_grants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      order_lines: {
        Row: {
          created_at: string
          description: string | null
          discount_kind: Database["public"]["Enums"]["discount_kind"]
          discount_value: number
          id: string
          line_type: Database["public"]["Enums"]["order_line_type"]
          order_id: string
          organization_id: string
          position: number
          product_id: string | null
          promotion_id: string | null
          quantity: number
          quantity_cancelled: number
          quote_line_id: string | null
          title: string
          unit: string | null
          unit_price: number
          updated_at: string
          variant_id: string | null
          vat_rate: number
        }
        Insert: {
          created_at?: string
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          line_type?: Database["public"]["Enums"]["order_line_type"]
          order_id: string
          organization_id: string
          position?: number
          product_id?: string | null
          promotion_id?: string | null
          quantity: number
          quantity_cancelled?: number
          quote_line_id?: string | null
          title: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          variant_id?: string | null
          vat_rate?: number
        }
        Update: {
          created_at?: string
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          line_type?: Database["public"]["Enums"]["order_line_type"]
          order_id?: string
          organization_id?: string
          position?: number
          product_id?: string | null
          promotion_id?: string | null
          quantity?: number
          quantity_cancelled?: number
          quote_line_id?: string | null
          title?: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          variant_id?: string | null
          vat_rate?: number
        }
        Relationships: [
          {
            foreignKeyName: "order_lines_order_id_organization_id_fkey"
            columns: ["order_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "order_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_lines_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "order_lines_promotion_organization_fkey"
            columns: ["promotion_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "promotions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "order_lines_quote_line_id_fkey"
            columns: ["quote_line_id"]
            isOneToOne: false
            referencedRelation: "quote_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_lines_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      orders: {
        Row: {
          buyer_address_city: string | null
          buyer_address_country: string | null
          buyer_address_line1: string | null
          buyer_address_line2: string | null
          buyer_address_postal_code: string | null
          buyer_btw: string | null
          buyer_email: string | null
          buyer_kvk: string | null
          buyer_name: string | null
          buyer_phone: string | null
          cancel_reason: string | null
          cancelled_at: string | null
          channel: Database["public"]["Enums"]["order_channel"]
          completed_at: string | null
          confirmed_at: string | null
          created_at: string
          created_by: string | null
          currency: string
          customer_contact_id: string | null
          customer_id: number
          customer_note: string | null
          delivery_method: Database["public"]["Enums"]["order_delivery_method"]
          discount_description: string | null
          discount_kind: Database["public"]["Enums"]["discount_kind"]
          discount_value: number
          external_id: string | null
          id: string
          inbox_thread_id: string | null
          invoicing_policy: Database["public"]["Enums"]["order_invoicing_policy"]
          notes: string | null
          number: number
          number_prefix: string
          organization_id: string
          promotion_id: string | null
          quote_id: string | null
          requested_delivery_date: string | null
          shipping_address_city: string | null
          shipping_address_country: string | null
          shipping_address_line1: string | null
          shipping_address_line2: string | null
          shipping_address_postal_code: string | null
          shipping_name: string | null
          shipping_phone: string | null
          source: string | null
          status: Database["public"]["Enums"]["order_status"]
          subtotal_excl: number
          template_id: string | null
          total_incl: number
          updated_at: string
          updated_by: string | null
          vat_inclusive: boolean
          vat_regime: Database["public"]["Enums"]["document_vat_regime"]
          vat_total: number
        }
        Insert: {
          buyer_address_city?: string | null
          buyer_address_country?: string | null
          buyer_address_line1?: string | null
          buyer_address_line2?: string | null
          buyer_address_postal_code?: string | null
          buyer_btw?: string | null
          buyer_email?: string | null
          buyer_kvk?: string | null
          buyer_name?: string | null
          buyer_phone?: string | null
          cancel_reason?: string | null
          cancelled_at?: string | null
          channel?: Database["public"]["Enums"]["order_channel"]
          completed_at?: string | null
          confirmed_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          customer_contact_id?: string | null
          customer_id: number
          customer_note?: string | null
          delivery_method?: Database["public"]["Enums"]["order_delivery_method"]
          discount_description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          external_id?: string | null
          id?: string
          inbox_thread_id?: string | null
          invoicing_policy?: Database["public"]["Enums"]["order_invoicing_policy"]
          notes?: string | null
          number: number
          number_prefix?: string
          organization_id: string
          promotion_id?: string | null
          quote_id?: string | null
          requested_delivery_date?: string | null
          shipping_address_city?: string | null
          shipping_address_country?: string | null
          shipping_address_line1?: string | null
          shipping_address_line2?: string | null
          shipping_address_postal_code?: string | null
          shipping_name?: string | null
          shipping_phone?: string | null
          source?: string | null
          status?: Database["public"]["Enums"]["order_status"]
          subtotal_excl?: number
          template_id?: string | null
          total_incl?: number
          updated_at?: string
          updated_by?: string | null
          vat_inclusive?: boolean
          vat_regime?: Database["public"]["Enums"]["document_vat_regime"]
          vat_total?: number
        }
        Update: {
          buyer_address_city?: string | null
          buyer_address_country?: string | null
          buyer_address_line1?: string | null
          buyer_address_line2?: string | null
          buyer_address_postal_code?: string | null
          buyer_btw?: string | null
          buyer_email?: string | null
          buyer_kvk?: string | null
          buyer_name?: string | null
          buyer_phone?: string | null
          cancel_reason?: string | null
          cancelled_at?: string | null
          channel?: Database["public"]["Enums"]["order_channel"]
          completed_at?: string | null
          confirmed_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          customer_contact_id?: string | null
          customer_id?: number
          customer_note?: string | null
          delivery_method?: Database["public"]["Enums"]["order_delivery_method"]
          discount_description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          external_id?: string | null
          id?: string
          inbox_thread_id?: string | null
          invoicing_policy?: Database["public"]["Enums"]["order_invoicing_policy"]
          notes?: string | null
          number?: number
          number_prefix?: string
          organization_id?: string
          promotion_id?: string | null
          quote_id?: string | null
          requested_delivery_date?: string | null
          shipping_address_city?: string | null
          shipping_address_country?: string | null
          shipping_address_line1?: string | null
          shipping_address_line2?: string | null
          shipping_address_postal_code?: string | null
          shipping_name?: string | null
          shipping_phone?: string | null
          source?: string | null
          status?: Database["public"]["Enums"]["order_status"]
          subtotal_excl?: number
          template_id?: string | null
          total_incl?: number
          updated_at?: string
          updated_by?: string | null
          vat_inclusive?: boolean
          vat_regime?: Database["public"]["Enums"]["document_vat_regime"]
          vat_total?: number
        }
        Relationships: [
          {
            foreignKeyName: "orders_customer_contact_id_fkey"
            columns: ["customer_contact_id"]
            isOneToOne: false
            referencedRelation: "customer_contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_customer_id_organization_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "orders_inbox_thread_id_fkey"
            columns: ["inbox_thread_id"]
            isOneToOne: false
            referencedRelation: "inbox_threads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_promotion_organization_fkey"
            columns: ["promotion_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "promotions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "orders_quote_id_organization_id_fkey"
            columns: ["quote_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "orders_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_ai_action_policies: {
        Row: {
          action_id: string
          created_at: string
          created_by: string | null
          enabled: boolean
          execution_ceiling: string | null
          force_approval: boolean
          organization_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          action_id: string
          created_at?: string
          created_by?: string | null
          enabled?: boolean
          execution_ceiling?: string | null
          force_approval?: boolean
          organization_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          action_id?: string
          created_at?: string
          created_by?: string | null
          enabled?: boolean
          execution_ceiling?: string | null
          force_approval?: boolean
          organization_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_ai_action_policies_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_ai_policies: {
        Row: {
          approval_risk_threshold: string
          background_actions_enabled: boolean
          chat_instructions: string | null
          created_at: string
          created_by: string | null
          daily_credit_budget: number | null
          execution_ceiling: string
          external_integrations_enabled: boolean
          organization_id: string
          private_memory_enabled: boolean
          private_memory_retention_days: number | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          approval_risk_threshold?: string
          background_actions_enabled?: boolean
          chat_instructions?: string | null
          created_at?: string
          created_by?: string | null
          daily_credit_budget?: number | null
          execution_ceiling?: string
          external_integrations_enabled?: boolean
          organization_id: string
          private_memory_enabled?: boolean
          private_memory_retention_days?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          approval_risk_threshold?: string
          background_actions_enabled?: boolean
          chat_instructions?: string | null
          created_at?: string
          created_by?: string | null
          daily_credit_budget?: number | null
          execution_ceiling?: string
          external_integrations_enabled?: boolean
          organization_id?: string
          private_memory_enabled?: boolean
          private_memory_retention_days?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_ai_policies_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_billing_customers: {
        Row: {
          address_city: string | null
          address_country: string | null
          address_line1: string | null
          address_line2: string | null
          address_postal_code: string | null
          address_state: string | null
          billing_email: string | null
          company_name: string
          created_at: string
          id: string
          livemode: boolean
          organization_id: string
          provider: Database["public"]["Enums"]["billing_provider"]
          stripe_customer_id: string
          updated_at: string
        }
        Insert: {
          address_city?: string | null
          address_country?: string | null
          address_line1?: string | null
          address_line2?: string | null
          address_postal_code?: string | null
          address_state?: string | null
          billing_email?: string | null
          company_name: string
          created_at?: string
          id?: string
          livemode?: boolean
          organization_id: string
          provider?: Database["public"]["Enums"]["billing_provider"]
          stripe_customer_id: string
          updated_at?: string
        }
        Update: {
          address_city?: string | null
          address_country?: string | null
          address_line1?: string | null
          address_line2?: string | null
          address_postal_code?: string | null
          address_state?: string | null
          billing_email?: string | null
          company_name?: string
          created_at?: string
          id?: string
          livemode?: boolean
          organization_id?: string
          provider?: Database["public"]["Enums"]["billing_provider"]
          stripe_customer_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_billing_customers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_billing_top_ups: {
        Row: {
          auto_top_up_enabled: boolean
          created_at: string
          current_period_amount_micros: number
          monthly_limit_micros: number | null
          organization_id: string
          updated_at: string
        }
        Insert: {
          auto_top_up_enabled?: boolean
          created_at?: string
          current_period_amount_micros?: number
          monthly_limit_micros?: number | null
          organization_id: string
          updated_at?: string
        }
        Update: {
          auto_top_up_enabled?: boolean
          created_at?: string
          current_period_amount_micros?: number
          monthly_limit_micros?: number | null
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_billing_top_ups_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_brand_images: {
        Row: {
          byte_size: number
          created_at: string
          height: number
          id: string
          organization_id: string
          path: string
          position: number
          width: number
        }
        Insert: {
          byte_size: number
          created_at?: string
          height: number
          id?: string
          organization_id: string
          path: string
          position?: number
          width: number
        }
        Update: {
          byte_size?: number
          created_at?: string
          height?: number
          id?: string
          organization_id?: string
          path?: string
          position?: number
          width?: number
        }
        Relationships: [
          {
            foreignKeyName: "organization_brand_images_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_invitations: {
        Row: {
          accepted_at: string | null
          created_at: string
          declined_at: string | null
          email: string
          expires_at: string
          id: string
          invited_by: string | null
          organization_id: string | null
          prefill: NonNullable<Json>
          role_id: string
          token: string
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          declined_at?: string | null
          email: string
          expires_at: string
          id?: string
          invited_by?: string | null
          organization_id?: string | null
          prefill?: NonNullable<Json>
          role_id: string
          token: string
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          declined_at?: string | null
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string | null
          organization_id?: string | null
          prefill?: NonNullable<Json>
          role_id?: string
          token?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_invitations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_invitations_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_invoice_recipients: {
        Row: {
          created_at: string
          email: string
          id: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          email: string
          id?: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_invoice_recipients_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_invoices: {
        Row: {
          amount_due: number
          amount_paid: number
          amount_remaining: number
          billing_customer_id: string
          created_at: string
          credit_package_key: string | null
          currency: string
          due_at: string | null
          hosted_invoice_url: string | null
          id: string
          invoice_number: string
          invoice_pdf_url: string | null
          issued_at: string | null
          organization_id: string
          paid_at: string | null
          plan_key: Database["public"]["Enums"]["billing_plan_key"] | null
          plan_name: string | null
          status: Database["public"]["Enums"]["billing_invoice_status"]
          stripe_invoice_id: string
          stripe_subscription_id: string | null
          updated_at: string
        }
        Insert: {
          amount_due?: number
          amount_paid?: number
          amount_remaining?: number
          billing_customer_id: string
          created_at?: string
          credit_package_key?: string | null
          currency: string
          due_at?: string | null
          hosted_invoice_url?: string | null
          id?: string
          invoice_number: string
          invoice_pdf_url?: string | null
          issued_at?: string | null
          organization_id: string
          paid_at?: string | null
          plan_key?: Database["public"]["Enums"]["billing_plan_key"] | null
          plan_name?: string | null
          status: Database["public"]["Enums"]["billing_invoice_status"]
          stripe_invoice_id: string
          stripe_subscription_id?: string | null
          updated_at?: string
        }
        Update: {
          amount_due?: number
          amount_paid?: number
          amount_remaining?: number
          billing_customer_id?: string
          created_at?: string
          credit_package_key?: string | null
          currency?: string
          due_at?: string | null
          hosted_invoice_url?: string | null
          id?: string
          invoice_number?: string
          invoice_pdf_url?: string | null
          issued_at?: string | null
          organization_id?: string
          paid_at?: string | null
          plan_key?: Database["public"]["Enums"]["billing_plan_key"] | null
          plan_name?: string | null
          status?: Database["public"]["Enums"]["billing_invoice_status"]
          stripe_invoice_id?: string
          stripe_subscription_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_invoices_billing_customer_id_fkey"
            columns: ["billing_customer_id"]
            isOneToOne: false
            referencedRelation: "organization_billing_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_invoices_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_number_sequences: {
        Row: {
          entity: string
          last_number: number
          organization_id: string
          period: string
        }
        Insert: {
          entity: string
          last_number?: number
          organization_id: string
          period?: string
        }
        Update: {
          entity?: string
          last_number?: number
          organization_id?: string
          period?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_number_sequences_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_payment_accounts: {
        Row: {
          charges_enabled: boolean
          country: string | null
          created_at: string
          default_currency: string | null
          details_submitted: boolean
          disabled_reason: string | null
          id: string
          livemode: boolean
          onboarding_completed_at: string | null
          organization_id: string
          payouts_enabled: boolean
          provider: string
          status: Database["public"]["Enums"]["organization_payment_account_status"]
          stripe_account_id: string
          updated_at: string
        }
        Insert: {
          charges_enabled?: boolean
          country?: string | null
          created_at?: string
          default_currency?: string | null
          details_submitted?: boolean
          disabled_reason?: string | null
          id?: string
          livemode?: boolean
          onboarding_completed_at?: string | null
          organization_id: string
          payouts_enabled?: boolean
          provider?: string
          status?: Database["public"]["Enums"]["organization_payment_account_status"]
          stripe_account_id: string
          updated_at?: string
        }
        Update: {
          charges_enabled?: boolean
          country?: string | null
          created_at?: string
          default_currency?: string | null
          details_submitted?: boolean
          disabled_reason?: string | null
          id?: string
          livemode?: boolean
          onboarding_completed_at?: string | null
          organization_id?: string
          payouts_enabled?: boolean
          provider?: string
          status?: Database["public"]["Enums"]["organization_payment_account_status"]
          stripe_account_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_payment_accounts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_payment_methods: {
        Row: {
          billing_customer_id: string
          billing_name: string | null
          brand: string | null
          created_at: string
          exp_month: number | null
          exp_year: number | null
          id: string
          is_default: boolean
          last4: string | null
          organization_id: string
          status: Database["public"]["Enums"]["billing_payment_method_status"]
          stripe_payment_method_id: string
          type: Database["public"]["Enums"]["billing_payment_method_type"]
          updated_at: string
        }
        Insert: {
          billing_customer_id: string
          billing_name?: string | null
          brand?: string | null
          created_at?: string
          exp_month?: number | null
          exp_year?: number | null
          id?: string
          is_default?: boolean
          last4?: string | null
          organization_id: string
          status?: Database["public"]["Enums"]["billing_payment_method_status"]
          stripe_payment_method_id: string
          type: Database["public"]["Enums"]["billing_payment_method_type"]
          updated_at?: string
        }
        Update: {
          billing_customer_id?: string
          billing_name?: string | null
          brand?: string | null
          created_at?: string
          exp_month?: number | null
          exp_year?: number | null
          id?: string
          is_default?: boolean
          last4?: string | null
          organization_id?: string
          status?: Database["public"]["Enums"]["billing_payment_method_status"]
          stripe_payment_method_id?: string
          type?: Database["public"]["Enums"]["billing_payment_method_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_payment_methods_billing_customer_id_fkey"
            columns: ["billing_customer_id"]
            isOneToOne: false
            referencedRelation: "organization_billing_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_payment_methods_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_permission_overrides: {
        Row: {
          created_at: string
          granted: boolean
          organization_id: string
          permission_id: string
          role_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          granted: boolean
          organization_id: string
          permission_id: string
          role_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          granted?: boolean
          organization_id?: string
          permission_id?: string
          role_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_permission_overrides_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_permission_overrides_permission_id_fkey"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_permission_overrides_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_subscription_history: {
        Row: {
          cancel_at: string | null
          cancel_at_period_end: boolean
          catalog_currency: string | null
          catalog_monthly_amount: number | null
          change_kind: Database["public"]["Enums"]["subscription_history_change_kind"]
          created_at: string
          credit_package_key: string | null
          current_period_end: string | null
          current_period_start: string | null
          effective_at: string
          id: string
          included_credits: number | null
          interval: Database["public"]["Enums"]["billing_plan_interval"] | null
          organization_id: string
          organization_subscription_id: string | null
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          plan_name: string
          quantity: number
          status: Database["public"]["Enums"]["billing_subscription_status"]
          stripe_subscription_id: string | null
          trial_end: string | null
        }
        Insert: {
          cancel_at?: string | null
          cancel_at_period_end: boolean
          catalog_currency?: string | null
          catalog_monthly_amount?: number | null
          change_kind: Database["public"]["Enums"]["subscription_history_change_kind"]
          created_at?: string
          credit_package_key?: string | null
          current_period_end?: string | null
          current_period_start?: string | null
          effective_at: string
          id?: string
          included_credits?: number | null
          interval?: Database["public"]["Enums"]["billing_plan_interval"] | null
          organization_id: string
          organization_subscription_id?: string | null
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          plan_name: string
          quantity: number
          status: Database["public"]["Enums"]["billing_subscription_status"]
          stripe_subscription_id?: string | null
          trial_end?: string | null
        }
        Update: {
          cancel_at?: string | null
          cancel_at_period_end?: boolean
          catalog_currency?: string | null
          catalog_monthly_amount?: number | null
          change_kind?: Database["public"]["Enums"]["subscription_history_change_kind"]
          created_at?: string
          credit_package_key?: string | null
          current_period_end?: string | null
          current_period_start?: string | null
          effective_at?: string
          id?: string
          included_credits?: number | null
          interval?: Database["public"]["Enums"]["billing_plan_interval"] | null
          organization_id?: string
          organization_subscription_id?: string | null
          plan_key?: Database["public"]["Enums"]["billing_plan_key"]
          plan_name?: string
          quantity?: number
          status?: Database["public"]["Enums"]["billing_subscription_status"]
          stripe_subscription_id?: string | null
          trial_end?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_subscription_his_organization_subscription_id_fkey"
            columns: ["organization_subscription_id"]
            isOneToOne: false
            referencedRelation: "organization_subscriptions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_subscription_history_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_subscriptions: {
        Row: {
          audit_log_retention_days: number | null
          billing_customer_id: string
          cancel_at: string | null
          cancel_at_period_end: boolean
          created_at: string
          credit_package_key: string | null
          current_period_end: string | null
          current_period_start: string | null
          id: string
          included_credits: number | null
          interval: Database["public"]["Enums"]["billing_plan_interval"] | null
          organization_id: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          plan_name: string
          quantity: number
          status: Database["public"]["Enums"]["billing_subscription_status"]
          stripe_customer_id: string
          stripe_latest_invoice_id: string | null
          stripe_price_id: string | null
          stripe_subscription_id: string | null
          trial_end: string | null
          updated_at: string
        }
        Insert: {
          audit_log_retention_days?: number | null
          billing_customer_id: string
          cancel_at?: string | null
          cancel_at_period_end?: boolean
          created_at?: string
          credit_package_key?: string | null
          current_period_end?: string | null
          current_period_start?: string | null
          id?: string
          included_credits?: number | null
          interval?: Database["public"]["Enums"]["billing_plan_interval"] | null
          organization_id: string
          plan_key: Database["public"]["Enums"]["billing_plan_key"]
          plan_name: string
          quantity?: number
          status: Database["public"]["Enums"]["billing_subscription_status"]
          stripe_customer_id: string
          stripe_latest_invoice_id?: string | null
          stripe_price_id?: string | null
          stripe_subscription_id?: string | null
          trial_end?: string | null
          updated_at?: string
        }
        Update: {
          audit_log_retention_days?: number | null
          billing_customer_id?: string
          cancel_at?: string | null
          cancel_at_period_end?: boolean
          created_at?: string
          credit_package_key?: string | null
          current_period_end?: string | null
          current_period_start?: string | null
          id?: string
          included_credits?: number | null
          interval?: Database["public"]["Enums"]["billing_plan_interval"] | null
          organization_id?: string
          plan_key?: Database["public"]["Enums"]["billing_plan_key"]
          plan_name?: string
          quantity?: number
          status?: Database["public"]["Enums"]["billing_subscription_status"]
          stripe_customer_id?: string
          stripe_latest_invoice_id?: string | null
          stripe_price_id?: string | null
          stripe_subscription_id?: string | null
          trial_end?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_subscriptions_billing_customer_id_fkey"
            columns: ["billing_customer_id"]
            isOneToOne: false
            referencedRelation: "organization_billing_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_subscriptions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_tags: {
        Row: {
          color: string | null
          created_at: string
          description: string | null
          id: string
          kind: Database["public"]["Enums"]["organization_tag_kind"]
          name: string
          organization_id: string
          position: number
          slug: string
          updated_at: string
        }
        Insert: {
          color?: string | null
          created_at?: string
          description?: string | null
          id?: string
          kind: Database["public"]["Enums"]["organization_tag_kind"]
          name: string
          organization_id: string
          position?: number
          slug: string
          updated_at?: string
        }
        Update: {
          color?: string | null
          created_at?: string
          description?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["organization_tag_kind"]
          name?: string
          organization_id?: string
          position?: number
          slug?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_tax_ids: {
        Row: {
          billing_customer_id: string | null
          created_at: string
          id: string
          organization_id: string
          stripe_tax_id_id: string | null
          type: string
          updated_at: string
          value: string
          verification_status: string | null
        }
        Insert: {
          billing_customer_id?: string | null
          created_at?: string
          id?: string
          organization_id: string
          stripe_tax_id_id?: string | null
          type: string
          updated_at?: string
          value: string
          verification_status?: string | null
        }
        Update: {
          billing_customer_id?: string | null
          created_at?: string
          id?: string
          organization_id?: string
          stripe_tax_id_id?: string | null
          type?: string
          updated_at?: string
          value?: string
          verification_status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_tax_ids_billing_customer_id_fkey"
            columns: ["billing_customer_id"]
            isOneToOne: false
            referencedRelation: "organization_billing_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_tax_ids_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_usage_events: {
        Row: {
          billable: boolean
          created_at: string
          id: string
          idempotency_key: string | null
          metadata: NonNullable<Json>
          meter_key: string
          organization_id: string
          period_end: string
          period_start: string
          quantity: number
          source: string
          source_id: string | null
          user_id: string | null
        }
        Insert: {
          billable?: boolean
          created_at?: string
          id?: string
          idempotency_key?: string | null
          metadata?: NonNullable<Json>
          meter_key: string
          organization_id: string
          period_end: string
          period_start: string
          quantity: number
          source: string
          source_id?: string | null
          user_id?: string | null
        }
        Update: {
          billable?: boolean
          created_at?: string
          id?: string
          idempotency_key?: string | null
          metadata?: NonNullable<Json>
          meter_key?: string
          organization_id?: string
          period_end?: string
          period_start?: string
          quantity?: number
          source?: string
          source_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_usage_events_meter_key_fkey"
            columns: ["meter_key"]
            isOneToOne: false
            referencedRelation: "billing_usage_meters"
            referencedColumns: ["key"]
          },
          {
            foreignKeyName: "organization_usage_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_usage_periods: {
        Row: {
          created_at: string
          id: string
          included_quantity: number
          meter_key: string
          organization_id: string
          overage_amount_micros: number
          overage_quantity: number
          period_end: string
          period_start: string
          quantity: number
          stripe_event_id: string | null
          stripe_event_name: string | null
          stripe_sync_error: string | null
          stripe_sync_status: string
          stripe_synced_at: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          included_quantity?: number
          meter_key: string
          organization_id: string
          overage_amount_micros?: number
          overage_quantity?: number
          period_end: string
          period_start: string
          quantity?: number
          stripe_event_id?: string | null
          stripe_event_name?: string | null
          stripe_sync_error?: string | null
          stripe_sync_status?: string
          stripe_synced_at?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          included_quantity?: number
          meter_key?: string
          organization_id?: string
          overage_amount_micros?: number
          overage_quantity?: number
          period_end?: string
          period_start?: string
          quantity?: number
          stripe_event_id?: string | null
          stripe_event_name?: string | null
          stripe_sync_error?: string | null
          stripe_sync_status?: string
          stripe_synced_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_usage_periods_meter_key_fkey"
            columns: ["meter_key"]
            isOneToOne: false
            referencedRelation: "billing_usage_meters"
            referencedColumns: ["key"]
          },
          {
            foreignKeyName: "organization_usage_periods_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_users: {
        Row: {
          created_at: string
          last_used_at: string
          organization_id: string
          role_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          last_used_at?: string
          organization_id: string
          role_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          last_used_at?: string
          organization_id?: string
          role_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_users_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_users_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_vat_rates: {
        Row: {
          created_at: string
          id: string
          is_default: boolean
          organization_id: string
          position: number
          rate: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_default?: boolean
          organization_id: string
          position?: number
          rate: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          is_default?: boolean
          organization_id?: string
          position?: number
          rate?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_vat_rates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          address_city: string | null
          address_country: string | null
          address_line1: string | null
          address_line2: string | null
          address_postal_code: string | null
          address_state: string | null
          ai_inference_region: string
          brand_primary_color: string | null
          brand_secondary_color: string | null
          btw: string | null
          created_at: string
          default_currency: string
          default_hourly_rate: number
          default_invoice_lifecycle_key: string | null
          default_order_lifecycle_key: string | null
          default_purchase_order_lifecycle_key: string | null
          default_quote_lifecycle_key: string | null
          default_quote_validity_days: number
          default_shipment_lifecycle_key: string | null
          default_task_lifecycle_key: string | null
          default_vat_rate: number
          disabled_at: string | null
          email_reply_to: string | null
          export_date_format: string
          export_default_format: string
          fiscal_year_start_day: number
          fiscal_year_start_month: number
          forwarding_email: string | null
          iban: string | null
          id: string
          inbox_email: string | null
          invoice_number_format: string
          invoice_number_prefix: string
          kvk: string | null
          logo_path: string | null
          name: string
          operating_country: string | null
          phone: string | null
          quote_number_prefix: string
          slug: string
          socials: NonNullable<Json>
          task_number_prefix: string
          updated_at: string
          website: string | null
        }
        Insert: {
          address_city?: string | null
          address_country?: string | null
          address_line1?: string | null
          address_line2?: string | null
          address_postal_code?: string | null
          address_state?: string | null
          ai_inference_region?: string
          brand_primary_color?: string | null
          brand_secondary_color?: string | null
          btw?: string | null
          created_at?: string
          default_currency?: string
          default_hourly_rate?: number
          default_invoice_lifecycle_key?: string | null
          default_order_lifecycle_key?: string | null
          default_purchase_order_lifecycle_key?: string | null
          default_quote_lifecycle_key?: string | null
          default_quote_validity_days?: number
          default_shipment_lifecycle_key?: string | null
          default_task_lifecycle_key?: string | null
          default_vat_rate?: number
          disabled_at?: string | null
          email_reply_to?: string | null
          export_date_format?: string
          export_default_format?: string
          fiscal_year_start_day?: number
          fiscal_year_start_month?: number
          forwarding_email?: string | null
          iban?: string | null
          id?: string
          inbox_email?: string | null
          invoice_number_format?: string
          invoice_number_prefix?: string
          kvk?: string | null
          logo_path?: string | null
          name: string
          operating_country?: string | null
          phone?: string | null
          quote_number_prefix?: string
          slug: string
          socials?: NonNullable<Json>
          task_number_prefix?: string
          updated_at?: string
          website?: string | null
        }
        Update: {
          address_city?: string | null
          address_country?: string | null
          address_line1?: string | null
          address_line2?: string | null
          address_postal_code?: string | null
          address_state?: string | null
          ai_inference_region?: string
          brand_primary_color?: string | null
          brand_secondary_color?: string | null
          btw?: string | null
          created_at?: string
          default_currency?: string
          default_hourly_rate?: number
          default_invoice_lifecycle_key?: string | null
          default_order_lifecycle_key?: string | null
          default_purchase_order_lifecycle_key?: string | null
          default_quote_lifecycle_key?: string | null
          default_quote_validity_days?: number
          default_shipment_lifecycle_key?: string | null
          default_task_lifecycle_key?: string | null
          default_vat_rate?: number
          disabled_at?: string | null
          email_reply_to?: string | null
          export_date_format?: string
          export_default_format?: string
          fiscal_year_start_day?: number
          fiscal_year_start_month?: number
          forwarding_email?: string | null
          iban?: string | null
          id?: string
          inbox_email?: string | null
          invoice_number_format?: string
          invoice_number_prefix?: string
          kvk?: string | null
          logo_path?: string | null
          name?: string
          operating_country?: string | null
          phone?: string | null
          quote_number_prefix?: string
          slug?: string
          socials?: NonNullable<Json>
          task_number_prefix?: string
          updated_at?: string
          website?: string | null
        }
        Relationships: []
      }
      payroll_periods: {
        Row: {
          created_at: string
          exported_at: string | null
          exported_by: string | null
          id: string
          organization_id: string
          period_end: string
          period_start: string
          provider: string | null
          status: Database["public"]["Enums"]["payroll_period_status"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          exported_at?: string | null
          exported_by?: string | null
          id?: string
          organization_id: string
          period_end: string
          period_start: string
          provider?: string | null
          status?: Database["public"]["Enums"]["payroll_period_status"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          exported_at?: string | null
          exported_by?: string | null
          id?: string
          organization_id?: string
          period_end?: string
          period_start?: string
          provider?: string | null
          status?: Database["public"]["Enums"]["payroll_period_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_periods_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      permissions: {
        Row: {
          created_at: string
          description: string | null
          id: string
          key: string
          name: string
          scope: Database["public"]["Enums"]["scope_type"]
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          key: string
          name: string
          scope: Database["public"]["Enums"]["scope_type"]
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          key?: string
          name?: string
          scope?: Database["public"]["Enums"]["scope_type"]
        }
        Relationships: []
      }
      platform_settings: {
        Row: {
          key: string
          updated_at: string
          updated_by: string | null
          value: NonNullable<Json>
        }
        Insert: {
          key: string
          updated_at?: string
          updated_by?: string | null
          value?: NonNullable<Json>
        }
        Update: {
          key?: string
          updated_at?: string
          updated_by?: string | null
          value?: NonNullable<Json>
        }
        Relationships: []
      }
      product_categories: {
        Row: {
          created_at: string
          description: string | null
          icon: string
          id: string
          name: string
          organization_id: string
          parent_id: string | null
          position: number
          slug: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          icon?: string
          id?: string
          name: string
          organization_id: string
          parent_id?: string | null
          position?: number
          slug: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          icon?: string
          id?: string
          name?: string
          organization_id?: string
          parent_id?: string | null
          position?: number
          slug?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_categories_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_categories_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "product_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      product_category_assignments: {
        Row: {
          category_id: string
          created_at: string
          id: string
          organization_id: string
          product_id: string
        }
        Insert: {
          category_id: string
          created_at?: string
          id?: string
          organization_id: string
          product_id: string
        }
        Update: {
          category_id?: string
          created_at?: string
          id?: string
          organization_id?: string
          product_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_category_assignments_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "product_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_category_assignments_category_id_organization_id_fkey"
            columns: ["category_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "product_categories"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "product_category_assignments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_category_assignments_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_category_assignments_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      product_digital_files: {
        Row: {
          byte_size: number | null
          content_type: string | null
          created_at: string
          created_by: string | null
          file_name: string
          id: string
          organization_id: string
          position: number
          product_id: string
          storage_path: string
          variant_id: string | null
        }
        Insert: {
          byte_size?: number | null
          content_type?: string | null
          created_at?: string
          created_by?: string | null
          file_name: string
          id?: string
          organization_id: string
          position?: number
          product_id: string
          storage_path: string
          variant_id?: string | null
        }
        Update: {
          byte_size?: number | null
          content_type?: string | null
          created_at?: string
          created_by?: string | null
          file_name?: string
          id?: string
          organization_id?: string
          position?: number
          product_id?: string
          storage_path?: string
          variant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "product_digital_files_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_digital_files_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "product_digital_files_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      product_license_keys: {
        Row: {
          assigned_at: string | null
          created_at: string
          id: string
          license_key: string
          order_line_id: string | null
          organization_id: string
          product_id: string
          revoked_at: string | null
          variant_id: string | null
        }
        Insert: {
          assigned_at?: string | null
          created_at?: string
          id?: string
          license_key: string
          order_line_id?: string | null
          organization_id: string
          product_id: string
          revoked_at?: string | null
          variant_id?: string | null
        }
        Update: {
          assigned_at?: string | null
          created_at?: string
          id?: string
          license_key?: string
          order_line_id?: string | null
          organization_id?: string
          product_id?: string
          revoked_at?: string | null
          variant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "product_license_keys_order_line_id_organization_id_fkey"
            columns: ["order_line_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "order_lines"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "product_license_keys_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_license_keys_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "product_license_keys_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      product_option_values: {
        Row: {
          created_at: string
          id: string
          option_id: string
          organization_id: string
          position: number
          value: string
        }
        Insert: {
          created_at?: string
          id?: string
          option_id: string
          organization_id: string
          position?: number
          value: string
        }
        Update: {
          created_at?: string
          id?: string
          option_id?: string
          organization_id?: string
          position?: number
          value?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_option_values_option_id_fkey"
            columns: ["option_id"]
            isOneToOne: false
            referencedRelation: "product_options"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_option_values_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      product_options: {
        Row: {
          created_at: string
          id: string
          name: string
          organization_id: string
          position: number
          product_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          organization_id: string
          position?: number
          product_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          organization_id?: string
          position?: number
          product_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_options_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_options_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      product_scan_requests: {
        Row: {
          completed_at: string | null
          context: NonNullable<Json>
          created_at: string
          created_by: string | null
          expires_at: string
          failure: Json | null
          id: string
          identifiers: NonNullable<Json>
          organization_id: string
          outcome: Json | null
          purpose: Database["public"]["Enums"]["product_scan_purpose"]
          status: Database["public"]["Enums"]["product_scan_status"]
          storage_path: string | null
          updated_at: string
          workflow_run_id: string | null
        }
        Insert: {
          completed_at?: string | null
          context?: NonNullable<Json>
          created_at?: string
          created_by?: string | null
          expires_at?: string
          failure?: Json | null
          id?: string
          identifiers?: NonNullable<Json>
          organization_id: string
          outcome?: Json | null
          purpose: Database["public"]["Enums"]["product_scan_purpose"]
          status?: Database["public"]["Enums"]["product_scan_status"]
          storage_path?: string | null
          updated_at?: string
          workflow_run_id?: string | null
        }
        Update: {
          completed_at?: string | null
          context?: NonNullable<Json>
          created_at?: string
          created_by?: string | null
          expires_at?: string
          failure?: Json | null
          id?: string
          identifiers?: NonNullable<Json>
          organization_id?: string
          outcome?: Json | null
          purpose?: Database["public"]["Enums"]["product_scan_purpose"]
          status?: Database["public"]["Enums"]["product_scan_status"]
          storage_path?: string | null
          updated_at?: string
          workflow_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "product_scan_requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      product_supplier_links: {
        Row: {
          created_at: string
          currency: string | null
          external_id: string | null
          id: string
          is_active: boolean
          is_preferred: boolean
          lead_time_days: number | null
          min_order_quantity: number | null
          order_code: string | null
          order_multiple: number | null
          organization_id: string
          product_id: string
          supplier_id: string
          supplier_sku: string | null
          unit_cost: number | null
          updated_at: string
          variant_id: string | null
        }
        Insert: {
          created_at?: string
          currency?: string | null
          external_id?: string | null
          id?: string
          is_active?: boolean
          is_preferred?: boolean
          lead_time_days?: number | null
          min_order_quantity?: number | null
          order_code?: string | null
          order_multiple?: number | null
          organization_id: string
          product_id: string
          supplier_id: string
          supplier_sku?: string | null
          unit_cost?: number | null
          updated_at?: string
          variant_id?: string | null
        }
        Update: {
          created_at?: string
          currency?: string | null
          external_id?: string | null
          id?: string
          is_active?: boolean
          is_preferred?: boolean
          lead_time_days?: number | null
          min_order_quantity?: number | null
          order_code?: string | null
          order_multiple?: number | null
          organization_id?: string
          product_id?: string
          supplier_id?: string
          supplier_sku?: string | null
          unit_cost?: number | null
          updated_at?: string
          variant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "product_supplier_links_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "product_supplier_links_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_supplier_links_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_supplier_links_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_supplier_links_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      product_variant_option_values: {
        Row: {
          option_value_id: string
          organization_id: string
          variant_id: string
        }
        Insert: {
          option_value_id: string
          organization_id: string
          variant_id: string
        }
        Update: {
          option_value_id?: string
          organization_id?: string
          variant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_variant_option_values_option_value_id_fkey"
            columns: ["option_value_id"]
            isOneToOne: false
            referencedRelation: "product_option_values"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_variant_option_values_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_variant_option_values_variant_id_fkey"
            columns: ["variant_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id"]
          },
        ]
      }
      product_variants: {
        Row: {
          allow_backorder: boolean
          average_cost: number | null
          created_at: string
          ean: string | null
          id: string
          image_id: string | null
          is_default: boolean
          manufacturer_part_number: string | null
          organization_id: string
          position: number
          product_id: string
          purchase_price: number | null
          selling_price: number | null
          sku: string | null
          status: Database["public"]["Enums"]["product_status"]
          title: string
          updated_at: string
          weight_grams: number | null
        }
        Insert: {
          allow_backorder?: boolean
          average_cost?: number | null
          created_at?: string
          ean?: string | null
          id?: string
          image_id?: string | null
          is_default?: boolean
          manufacturer_part_number?: string | null
          organization_id: string
          position?: number
          product_id: string
          purchase_price?: number | null
          selling_price?: number | null
          sku?: string | null
          status?: Database["public"]["Enums"]["product_status"]
          title?: string
          updated_at?: string
          weight_grams?: number | null
        }
        Update: {
          allow_backorder?: boolean
          average_cost?: number | null
          created_at?: string
          ean?: string | null
          id?: string
          image_id?: string | null
          is_default?: boolean
          manufacturer_part_number?: string | null
          organization_id?: string
          position?: number
          product_id?: string
          purchase_price?: number | null
          selling_price?: number | null
          sku?: string | null
          status?: Database["public"]["Enums"]["product_status"]
          title?: string
          updated_at?: string
          weight_grams?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "product_variants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_variants_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      products: {
        Row: {
          brand_id: string | null
          country_of_origin: string | null
          created_at: string
          created_by: string | null
          currency: string | null
          default_purchase_price: number | null
          default_selling_price: number | null
          description: string | null
          digital_delivery:
            | Database["public"]["Enums"]["digital_delivery_kind"]
            | null
          ean: string | null
          hs_code: string | null
          id: string
          manufacturer: string | null
          manufacturer_part_number: string | null
          model: string | null
          name: string
          organization_id: string
          product_type: Database["public"]["Enums"]["product_type"]
          sku: string | null
          slug: string
          status: Database["public"]["Enums"]["product_status"]
          track_inventory: boolean
          unit_of_measure: string | null
          updated_at: string
          updated_by: string | null
          vat_percentage: number | null
          weight_grams: number | null
        }
        Insert: {
          brand_id?: string | null
          country_of_origin?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          default_purchase_price?: number | null
          default_selling_price?: number | null
          description?: string | null
          digital_delivery?:
            | Database["public"]["Enums"]["digital_delivery_kind"]
            | null
          ean?: string | null
          hs_code?: string | null
          id?: string
          manufacturer?: string | null
          manufacturer_part_number?: string | null
          model?: string | null
          name: string
          organization_id: string
          product_type?: Database["public"]["Enums"]["product_type"]
          sku?: string | null
          slug: string
          status?: Database["public"]["Enums"]["product_status"]
          track_inventory?: boolean
          unit_of_measure?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_percentage?: number | null
          weight_grams?: number | null
        }
        Update: {
          brand_id?: string | null
          country_of_origin?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          default_purchase_price?: number | null
          default_selling_price?: number | null
          description?: string | null
          digital_delivery?:
            | Database["public"]["Enums"]["digital_delivery_kind"]
            | null
          ean?: string | null
          hs_code?: string | null
          id?: string
          manufacturer?: string | null
          manufacturer_part_number?: string | null
          model?: string | null
          name?: string
          organization_id?: string
          product_type?: Database["public"]["Enums"]["product_type"]
          sku?: string | null
          slug?: string
          status?: Database["public"]["Enums"]["product_status"]
          track_inventory?: boolean
          unit_of_measure?: string | null
          updated_at?: string
          updated_by?: string | null
          vat_percentage?: number | null
          weight_grams?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "products_brand_id_fkey"
            columns: ["brand_id"]
            isOneToOne: false
            referencedRelation: "brands"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "products_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "products_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          active_organization_id: string | null
          active_team_id: number | null
          avatar_path: string | null
          created_at: string
          date_format: string
          disabled_at: string | null
          email: string | null
          first_name: string | null
          last_name: string | null
          locale: Database["public"]["Enums"]["app_locale"]
          time_format: string
          timezone: string
          updated_at: string
          user_id: string
          username: string
          week_start: string
        }
        Insert: {
          active_organization_id?: string | null
          active_team_id?: number | null
          avatar_path?: string | null
          created_at?: string
          date_format?: string
          disabled_at?: string | null
          email?: string | null
          first_name?: string | null
          last_name?: string | null
          locale?: Database["public"]["Enums"]["app_locale"]
          time_format?: string
          timezone?: string
          updated_at?: string
          user_id: string
          username: string
          week_start?: string
        }
        Update: {
          active_organization_id?: string | null
          active_team_id?: number | null
          avatar_path?: string | null
          created_at?: string
          date_format?: string
          disabled_at?: string | null
          email?: string | null
          first_name?: string | null
          last_name?: string | null
          locale?: Database["public"]["Enums"]["app_locale"]
          time_format?: string
          timezone?: string
          updated_at?: string
          user_id?: string
          username?: string
          week_start?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_active_organization_id_fkey"
            columns: ["active_organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profiles_active_team_id_fkey"
            columns: ["active_team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
        ]
      }
      promotion_eligibility: {
        Row: {
          customer_id: number | null
          id: string
          kind: Database["public"]["Enums"]["promotion_eligibility_kind"]
          organization_id: string
          promotion_id: string
          tag_id: string | null
        }
        Insert: {
          customer_id?: number | null
          id?: string
          kind: Database["public"]["Enums"]["promotion_eligibility_kind"]
          organization_id: string
          promotion_id: string
          tag_id?: string | null
        }
        Update: {
          customer_id?: number | null
          id?: string
          kind?: Database["public"]["Enums"]["promotion_eligibility_kind"]
          organization_id?: string
          promotion_id?: string
          tag_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "promotion_eligibility_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "promotion_eligibility_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "promotion_eligibility_promotion_id_organization_id_fkey"
            columns: ["promotion_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "promotions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "promotion_eligibility_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "organization_tags"
            referencedColumns: ["id"]
          },
        ]
      }
      promotion_redemptions: {
        Row: {
          amount: number
          committed_at: string | null
          created_at: string
          customer_id: number | null
          id: string
          organization_id: string
          promotion_id: string
          released_at: string | null
          state: Database["public"]["Enums"]["promotion_redemption_state"]
          subject_id: string
          subject_type: Database["public"]["Enums"]["promotion_subject_type"]
          updated_at: string
        }
        Insert: {
          amount?: number
          committed_at?: string | null
          created_at?: string
          customer_id?: number | null
          id?: string
          organization_id: string
          promotion_id: string
          released_at?: string | null
          state?: Database["public"]["Enums"]["promotion_redemption_state"]
          subject_id: string
          subject_type: Database["public"]["Enums"]["promotion_subject_type"]
          updated_at?: string
        }
        Update: {
          amount?: number
          committed_at?: string | null
          created_at?: string
          customer_id?: number | null
          id?: string
          organization_id?: string
          promotion_id?: string
          released_at?: string | null
          state?: Database["public"]["Enums"]["promotion_redemption_state"]
          subject_id?: string
          subject_type?: Database["public"]["Enums"]["promotion_subject_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "promotion_redemptions_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "promotion_redemptions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "promotion_redemptions_promotion_id_organization_id_fkey"
            columns: ["promotion_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "promotions"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      promotion_targets: {
        Row: {
          category_id: string | null
          id: string
          kind: Database["public"]["Enums"]["promotion_target_kind"]
          organization_id: string
          product_id: string | null
          promotion_id: string
          variant_id: string | null
        }
        Insert: {
          category_id?: string | null
          id?: string
          kind: Database["public"]["Enums"]["promotion_target_kind"]
          organization_id: string
          product_id?: string | null
          promotion_id: string
          variant_id?: string | null
        }
        Update: {
          category_id?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["promotion_target_kind"]
          organization_id?: string
          product_id?: string | null
          promotion_id?: string
          variant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "promotion_targets_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "product_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "promotion_targets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "promotion_targets_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "promotion_targets_promotion_id_organization_id_fkey"
            columns: ["promotion_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "promotions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "promotion_targets_variant_id_fkey"
            columns: ["variant_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id"]
          },
        ]
      }
      promotions: {
        Row: {
          applies_to: Database["public"]["Enums"]["promotion_applies_to"]
          code: string | null
          combinable: boolean
          created_at: string
          created_by: string | null
          currency: string
          description: string | null
          ends_at: string | null
          id: string
          kind: Database["public"]["Enums"]["promotion_kind"]
          min_quantity: number | null
          min_subtotal: number | null
          name: string
          organization_id: string
          starts_at: string | null
          status: Database["public"]["Enums"]["promotion_status"]
          surfaces: Database["public"]["Enums"]["promotion_subject_type"][]
          updated_at: string
          usage_limit_per_customer: number | null
          usage_limit_total: number | null
          value: number
        }
        Insert: {
          applies_to?: Database["public"]["Enums"]["promotion_applies_to"]
          code?: string | null
          combinable?: boolean
          created_at?: string
          created_by?: string | null
          currency?: string
          description?: string | null
          ends_at?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["promotion_kind"]
          min_quantity?: number | null
          min_subtotal?: number | null
          name: string
          organization_id: string
          starts_at?: string | null
          status?: Database["public"]["Enums"]["promotion_status"]
          surfaces?: Database["public"]["Enums"]["promotion_subject_type"][]
          updated_at?: string
          usage_limit_per_customer?: number | null
          usage_limit_total?: number | null
          value?: number
        }
        Update: {
          applies_to?: Database["public"]["Enums"]["promotion_applies_to"]
          code?: string | null
          combinable?: boolean
          created_at?: string
          created_by?: string | null
          currency?: string
          description?: string | null
          ends_at?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["promotion_kind"]
          min_quantity?: number | null
          min_subtotal?: number | null
          name?: string
          organization_id?: string
          starts_at?: string | null
          status?: Database["public"]["Enums"]["promotion_status"]
          surfaces?: Database["public"]["Enums"]["promotion_subject_type"][]
          updated_at?: string
          usage_limit_per_customer?: number | null
          usage_limit_total?: number | null
          value?: number
        }
        Relationships: [
          {
            foreignKeyName: "promotions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      public_holidays: {
        Row: {
          created_at: string
          holiday_date: string
          id: string
          name: string
          organization_id: string
        }
        Insert: {
          created_at?: string
          holiday_date: string
          id?: string
          name: string
          organization_id: string
        }
        Update: {
          created_at?: string
          holiday_date?: string
          id?: string
          name?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "public_holidays_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_order_lines: {
        Row: {
          created_at: string
          expected_at: string | null
          id: string
          organization_id: string
          position: number
          product_id: string
          product_supplier_link_id: string | null
          purchase_order_id: string
          quantity_cancelled: number
          quantity_ordered: number
          quantity_received: number
          supplier_sku: string | null
          title: string
          unit_cost: number
          updated_at: string
          variant_id: string
          vat_rate: number
        }
        Insert: {
          created_at?: string
          expected_at?: string | null
          id?: string
          organization_id: string
          position?: number
          product_id: string
          product_supplier_link_id?: string | null
          purchase_order_id: string
          quantity_cancelled?: number
          quantity_ordered: number
          quantity_received?: number
          supplier_sku?: string | null
          title: string
          unit_cost?: number
          updated_at?: string
          variant_id: string
          vat_rate?: number
        }
        Update: {
          created_at?: string
          expected_at?: string | null
          id?: string
          organization_id?: string
          position?: number
          product_id?: string
          product_supplier_link_id?: string | null
          purchase_order_id?: string
          quantity_cancelled?: number
          quantity_ordered?: number
          quantity_received?: number
          supplier_sku?: string | null
          title?: string
          unit_cost?: number
          updated_at?: string
          variant_id?: string
          vat_rate?: number
        }
        Relationships: [
          {
            foreignKeyName: "purchase_order_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_lines_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "purchase_order_lines_product_supplier_link_id_fkey"
            columns: ["product_supplier_link_id"]
            isOneToOne: false
            referencedRelation: "product_supplier_links"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_lines_purchase_order_id_organization_id_fkey"
            columns: ["purchase_order_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "purchase_order_lines_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      purchase_orders: {
        Row: {
          cancelled_at: string | null
          closed_at: string | null
          created_at: string
          created_by: string | null
          currency: string
          exchange_rate: number
          expected_at: string | null
          id: string
          notes: string | null
          number: number
          number_prefix: string
          organization_id: string
          received_at: string | null
          sent_at: string | null
          ship_to_location_id: string | null
          status: Database["public"]["Enums"]["purchase_order_status"]
          subtotal_excl: number
          supplier_id: string
          supplier_notes: string | null
          supplier_reference: string | null
          template_id: string | null
          total_incl: number
          updated_at: string
          updated_by: string | null
          vat_total: number
        }
        Insert: {
          cancelled_at?: string | null
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          exchange_rate?: number
          expected_at?: string | null
          id?: string
          notes?: string | null
          number: number
          number_prefix?: string
          organization_id: string
          received_at?: string | null
          sent_at?: string | null
          ship_to_location_id?: string | null
          status?: Database["public"]["Enums"]["purchase_order_status"]
          subtotal_excl?: number
          supplier_id: string
          supplier_notes?: string | null
          supplier_reference?: string | null
          template_id?: string | null
          total_incl?: number
          updated_at?: string
          updated_by?: string | null
          vat_total?: number
        }
        Update: {
          cancelled_at?: string | null
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          exchange_rate?: number
          expected_at?: string | null
          id?: string
          notes?: string | null
          number?: number
          number_prefix?: string
          organization_id?: string
          received_at?: string | null
          sent_at?: string | null
          ship_to_location_id?: string | null
          status?: Database["public"]["Enums"]["purchase_order_status"]
          subtotal_excl?: number
          supplier_id?: string
          supplier_notes?: string | null
          supplier_reference?: string | null
          template_id?: string | null
          total_incl?: number
          updated_at?: string
          updated_by?: string | null
          vat_total?: number
        }
        Relationships: [
          {
            foreignKeyName: "purchase_orders_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_ship_to_location_id_organization_id_fkey"
            columns: ["ship_to_location_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "inventory_locations"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "purchase_orders_supplier_id_organization_id_fkey"
            columns: ["supplier_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "purchase_orders_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_assets: {
        Row: {
          created_at: string
          customer_asset_id: number
          organization_id: string
          position: number
          quote_id: string
        }
        Insert: {
          created_at?: string
          customer_asset_id: number
          organization_id: string
          position?: number
          quote_id: string
        }
        Update: {
          created_at?: string
          customer_asset_id?: number
          organization_id?: string
          position?: number
          quote_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "quote_assets_customer_asset_id_fkey"
            columns: ["customer_asset_id"]
            isOneToOne: false
            referencedRelation: "customer_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_assets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_assets_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_change_requests: {
        Row: {
          comment: string
          created_at: string
          id: string
          ip: string | null
          organization_id: string
          quote_id: string
          requested_by_email: string
          requested_by_name: string
          user_agent: string | null
          version: number
        }
        Insert: {
          comment: string
          created_at?: string
          id?: string
          ip?: string | null
          organization_id: string
          quote_id: string
          requested_by_email: string
          requested_by_name: string
          user_agent?: string | null
          version: number
        }
        Update: {
          comment?: string
          created_at?: string
          id?: string
          ip?: string | null
          organization_id?: string
          quote_id?: string
          requested_by_email?: string
          requested_by_name?: string
          user_agent?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "quote_change_requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_change_requests_quote_id_fkey"
            columns: ["quote_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      quote_lines: {
        Row: {
          created_at: string
          description: string | null
          discount_kind: Database["public"]["Enums"]["discount_kind"]
          discount_value: number
          id: string
          is_optional: boolean
          kind: Database["public"]["Enums"]["quote_line_kind"]
          line_type: Database["public"]["Enums"]["quote_line_type"] | null
          organization_id: string
          position: number
          pricing_mode: Database["public"]["Enums"]["quote_line_pricing_mode"]
          product_id: string | null
          promotion_id: string | null
          quantity: number
          quote_id: string
          stock_mode: Database["public"]["Enums"]["document_line_stock_mode"]
          subscription_interval:
            | Database["public"]["Enums"]["quote_subscription_interval"]
            | null
          subscription_periods: number | null
          task_id: string | null
          title: string
          unit: string | null
          unit_price: number
          updated_at: string
          variant_id: string | null
          vat_rate: number
        }
        Insert: {
          created_at?: string
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          is_optional?: boolean
          kind?: Database["public"]["Enums"]["quote_line_kind"]
          line_type?: Database["public"]["Enums"]["quote_line_type"] | null
          organization_id: string
          position?: number
          pricing_mode?: Database["public"]["Enums"]["quote_line_pricing_mode"]
          product_id?: string | null
          promotion_id?: string | null
          quantity?: number
          quote_id: string
          stock_mode?: Database["public"]["Enums"]["document_line_stock_mode"]
          subscription_interval?:
            | Database["public"]["Enums"]["quote_subscription_interval"]
            | null
          subscription_periods?: number | null
          task_id?: string | null
          title: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          variant_id?: string | null
          vat_rate?: number
        }
        Update: {
          created_at?: string
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          is_optional?: boolean
          kind?: Database["public"]["Enums"]["quote_line_kind"]
          line_type?: Database["public"]["Enums"]["quote_line_type"] | null
          organization_id?: string
          position?: number
          pricing_mode?: Database["public"]["Enums"]["quote_line_pricing_mode"]
          product_id?: string | null
          promotion_id?: string | null
          quantity?: number
          quote_id?: string
          stock_mode?: Database["public"]["Enums"]["document_line_stock_mode"]
          subscription_interval?:
            | Database["public"]["Enums"]["quote_subscription_interval"]
            | null
          subscription_periods?: number | null
          task_id?: string | null
          title?: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          variant_id?: string | null
          vat_rate?: number
        }
        Relationships: [
          {
            foreignKeyName: "quote_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_lines_promotion_organization_fkey"
            columns: ["promotion_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "promotions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "quote_lines_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_lines_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_lines_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      quote_status_history: {
        Row: {
          actor_customer_email: string | null
          actor_customer_name: string | null
          actor_user_id: string | null
          created_at: string
          from_status: Database["public"]["Enums"]["quote_status"] | null
          id: string
          ip: string | null
          organization_id: string
          quote_id: string
          reason: string | null
          to_status: Database["public"]["Enums"]["quote_status"]
          user_agent: string | null
        }
        Insert: {
          actor_customer_email?: string | null
          actor_customer_name?: string | null
          actor_user_id?: string | null
          created_at?: string
          from_status?: Database["public"]["Enums"]["quote_status"] | null
          id?: string
          ip?: string | null
          organization_id: string
          quote_id: string
          reason?: string | null
          to_status: Database["public"]["Enums"]["quote_status"]
          user_agent?: string | null
        }
        Update: {
          actor_customer_email?: string | null
          actor_customer_name?: string | null
          actor_user_id?: string | null
          created_at?: string
          from_status?: Database["public"]["Enums"]["quote_status"] | null
          id?: string
          ip?: string | null
          organization_id?: string
          quote_id?: string
          reason?: string | null
          to_status?: Database["public"]["Enums"]["quote_status"]
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "quote_status_history_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_status_history_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_tasks: {
        Row: {
          created_at: string
          organization_id: string
          position: number
          quote_id: string
          task_id: string
        }
        Insert: {
          created_at?: string
          organization_id: string
          position?: number
          quote_id: string
          task_id: string
        }
        Update: {
          created_at?: string
          organization_id?: string
          position?: number
          quote_id?: string
          task_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "quote_tasks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_tasks_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_tasks_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_version_lines: {
        Row: {
          created_at: string
          description: string | null
          discount_kind: Database["public"]["Enums"]["discount_kind"]
          discount_value: number
          id: string
          is_optional: boolean
          kind: Database["public"]["Enums"]["quote_line_kind"]
          line_type: Database["public"]["Enums"]["quote_line_type"] | null
          organization_id: string
          position: number
          pricing_mode: Database["public"]["Enums"]["quote_line_pricing_mode"]
          product_id: string | null
          quantity: number
          quote_version_id: string
          source_line_id: string | null
          stock_mode: Database["public"]["Enums"]["document_line_stock_mode"]
          subscription_interval:
            | Database["public"]["Enums"]["quote_subscription_interval"]
            | null
          subscription_periods: number | null
          task_id: string | null
          title: string
          unit: string | null
          unit_price: number
          variant_id: string | null
          vat_rate: number
        }
        Insert: {
          created_at?: string
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          is_optional?: boolean
          kind?: Database["public"]["Enums"]["quote_line_kind"]
          line_type?: Database["public"]["Enums"]["quote_line_type"] | null
          organization_id: string
          position?: number
          pricing_mode?: Database["public"]["Enums"]["quote_line_pricing_mode"]
          product_id?: string | null
          quantity?: number
          quote_version_id: string
          source_line_id?: string | null
          stock_mode?: Database["public"]["Enums"]["document_line_stock_mode"]
          subscription_interval?:
            | Database["public"]["Enums"]["quote_subscription_interval"]
            | null
          subscription_periods?: number | null
          task_id?: string | null
          title: string
          unit?: string | null
          unit_price?: number
          variant_id?: string | null
          vat_rate?: number
        }
        Update: {
          created_at?: string
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          is_optional?: boolean
          kind?: Database["public"]["Enums"]["quote_line_kind"]
          line_type?: Database["public"]["Enums"]["quote_line_type"] | null
          organization_id?: string
          position?: number
          pricing_mode?: Database["public"]["Enums"]["quote_line_pricing_mode"]
          product_id?: string | null
          quantity?: number
          quote_version_id?: string
          source_line_id?: string | null
          stock_mode?: Database["public"]["Enums"]["document_line_stock_mode"]
          subscription_interval?:
            | Database["public"]["Enums"]["quote_subscription_interval"]
            | null
          subscription_periods?: number | null
          task_id?: string | null
          title?: string
          unit?: string | null
          unit_price?: number
          variant_id?: string | null
          vat_rate?: number
        }
        Relationships: [
          {
            foreignKeyName: "quote_version_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_version_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_version_lines_quote_version_id_fkey"
            columns: ["quote_version_id"]
            isOneToOne: false
            referencedRelation: "quote_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_version_lines_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_version_lines_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      quote_versions: {
        Row: {
          buyer_address_city: string | null
          buyer_address_country: string | null
          buyer_address_line1: string | null
          buyer_address_line2: string | null
          buyer_address_postal_code: string | null
          buyer_btw: string | null
          buyer_email: string | null
          buyer_kvk: string | null
          buyer_name: string | null
          currency: string
          deposit_kind: Database["public"]["Enums"]["quote_deposit_kind"]
          deposit_required_to_accept: boolean
          deposit_value: number
          discount_description: string | null
          discount_kind: Database["public"]["Enums"]["discount_kind"]
          discount_value: number
          id: string
          intro: string | null
          issue_date: string | null
          organization_id: string
          public_message: string | null
          published_at: string
          published_by: string | null
          quote_id: string
          reason: string | null
          seller_address_city: string | null
          seller_address_country: string | null
          seller_address_line1: string | null
          seller_address_line2: string | null
          seller_address_postal_code: string | null
          seller_btw: string | null
          seller_email: string | null
          seller_iban: string | null
          seller_kvk: string | null
          seller_name: string | null
          seller_phone: string | null
          status: Database["public"]["Enums"]["quote_status"]
          subtotal_excl: number
          terms: string | null
          terms_pdf_file_id: string | null
          terms_pdf_version_id: string | null
          terms_rich_text: string | null
          terms_url: string | null
          title: string
          total_incl: number
          valid_until: string | null
          vat_inclusive: boolean
          vat_regime: Database["public"]["Enums"]["document_vat_regime"]
          vat_total: number
          version: number
        }
        Insert: {
          buyer_address_city?: string | null
          buyer_address_country?: string | null
          buyer_address_line1?: string | null
          buyer_address_line2?: string | null
          buyer_address_postal_code?: string | null
          buyer_btw?: string | null
          buyer_email?: string | null
          buyer_kvk?: string | null
          buyer_name?: string | null
          currency: string
          deposit_kind?: Database["public"]["Enums"]["quote_deposit_kind"]
          deposit_required_to_accept?: boolean
          deposit_value?: number
          discount_description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          intro?: string | null
          issue_date?: string | null
          organization_id: string
          public_message?: string | null
          published_at?: string
          published_by?: string | null
          quote_id: string
          reason?: string | null
          seller_address_city?: string | null
          seller_address_country?: string | null
          seller_address_line1?: string | null
          seller_address_line2?: string | null
          seller_address_postal_code?: string | null
          seller_btw?: string | null
          seller_email?: string | null
          seller_iban?: string | null
          seller_kvk?: string | null
          seller_name?: string | null
          seller_phone?: string | null
          status: Database["public"]["Enums"]["quote_status"]
          subtotal_excl?: number
          terms?: string | null
          terms_pdf_file_id?: string | null
          terms_pdf_version_id?: string | null
          terms_rich_text?: string | null
          terms_url?: string | null
          title: string
          total_incl?: number
          valid_until?: string | null
          vat_inclusive?: boolean
          vat_regime?: Database["public"]["Enums"]["document_vat_regime"]
          vat_total?: number
          version: number
        }
        Update: {
          buyer_address_city?: string | null
          buyer_address_country?: string | null
          buyer_address_line1?: string | null
          buyer_address_line2?: string | null
          buyer_address_postal_code?: string | null
          buyer_btw?: string | null
          buyer_email?: string | null
          buyer_kvk?: string | null
          buyer_name?: string | null
          currency?: string
          deposit_kind?: Database["public"]["Enums"]["quote_deposit_kind"]
          deposit_required_to_accept?: boolean
          deposit_value?: number
          discount_description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          intro?: string | null
          issue_date?: string | null
          organization_id?: string
          public_message?: string | null
          published_at?: string
          published_by?: string | null
          quote_id?: string
          reason?: string | null
          seller_address_city?: string | null
          seller_address_country?: string | null
          seller_address_line1?: string | null
          seller_address_line2?: string | null
          seller_address_postal_code?: string | null
          seller_btw?: string | null
          seller_email?: string | null
          seller_iban?: string | null
          seller_kvk?: string | null
          seller_name?: string | null
          seller_phone?: string | null
          status?: Database["public"]["Enums"]["quote_status"]
          subtotal_excl?: number
          terms?: string | null
          terms_pdf_file_id?: string | null
          terms_pdf_version_id?: string | null
          terms_rich_text?: string | null
          terms_url?: string | null
          title?: string
          total_incl?: number
          valid_until?: string | null
          vat_inclusive?: boolean
          vat_regime?: Database["public"]["Enums"]["document_vat_regime"]
          vat_total?: number
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "quote_versions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_versions_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_versions_terms_pdf_file_id_fkey"
            columns: ["terms_pdf_file_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_versions_terms_pdf_version_id_fkey"
            columns: ["terms_pdf_version_id"]
            isOneToOne: false
            referencedRelation: "file_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      quotes: {
        Row: {
          accepted_at: string | null
          accepted_by_email: string | null
          accepted_by_name: string | null
          accepted_ip: string | null
          accepted_optional_line_ids: NonNullable<Json>
          accepted_user_agent: string | null
          archived_at: string | null
          buyer_address_city: string | null
          buyer_address_country: string | null
          buyer_address_line1: string | null
          buyer_address_line2: string | null
          buyer_address_postal_code: string | null
          buyer_btw: string | null
          buyer_email: string | null
          buyer_kvk: string | null
          buyer_name: string | null
          changes_requested_at: string | null
          create_order_on_accept: boolean
          created_at: string
          created_by: string | null
          currency: string
          customer_id: number
          deposit_kind: Database["public"]["Enums"]["quote_deposit_kind"]
          deposit_required_to_accept: boolean
          deposit_value: number
          discount_description: string | null
          discount_kind: Database["public"]["Enums"]["discount_kind"]
          discount_value: number
          expired_at: string | null
          has_unpublished_changes: boolean
          id: string
          intro: string | null
          invoice_id: string | null
          issue_date: string | null
          number: number
          number_prefix: string
          organization_id: string
          promotion_id: string | null
          public_message: string | null
          quote_template_id: string | null
          rejected_at: string | null
          seller_address_city: string | null
          seller_address_country: string | null
          seller_address_line1: string | null
          seller_address_line2: string | null
          seller_address_postal_code: string | null
          seller_btw: string | null
          seller_email: string | null
          seller_iban: string | null
          seller_kvk: string | null
          seller_name: string | null
          seller_phone: string | null
          sent_at: string | null
          signature_envelope_id: string | null
          signature_provider: string | null
          signed_pdf_url: string | null
          status: Database["public"]["Enums"]["quote_status"]
          subtotal_excl: number
          supersedes_quote_id: string | null
          terms: string | null
          terms_pdf_file_id: string | null
          terms_pdf_version_id: string | null
          terms_rich_text: string | null
          terms_url: string | null
          title: string
          total_incl: number
          updated_at: string
          updated_by: string | null
          valid_until: string | null
          vat_inclusive: boolean
          vat_regime: Database["public"]["Enums"]["document_vat_regime"]
          vat_total: number
          version: number
          withdrawn_at: string | null
        }
        Insert: {
          accepted_at?: string | null
          accepted_by_email?: string | null
          accepted_by_name?: string | null
          accepted_ip?: string | null
          accepted_optional_line_ids?: NonNullable<Json>
          accepted_user_agent?: string | null
          archived_at?: string | null
          buyer_address_city?: string | null
          buyer_address_country?: string | null
          buyer_address_line1?: string | null
          buyer_address_line2?: string | null
          buyer_address_postal_code?: string | null
          buyer_btw?: string | null
          buyer_email?: string | null
          buyer_kvk?: string | null
          buyer_name?: string | null
          changes_requested_at?: string | null
          create_order_on_accept?: boolean
          created_at?: string
          created_by?: string | null
          currency?: string
          customer_id: number
          deposit_kind?: Database["public"]["Enums"]["quote_deposit_kind"]
          deposit_required_to_accept?: boolean
          deposit_value?: number
          discount_description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          expired_at?: string | null
          has_unpublished_changes?: boolean
          id?: string
          intro?: string | null
          invoice_id?: string | null
          issue_date?: string | null
          number: number
          number_prefix?: string
          organization_id: string
          promotion_id?: string | null
          public_message?: string | null
          quote_template_id?: string | null
          rejected_at?: string | null
          seller_address_city?: string | null
          seller_address_country?: string | null
          seller_address_line1?: string | null
          seller_address_line2?: string | null
          seller_address_postal_code?: string | null
          seller_btw?: string | null
          seller_email?: string | null
          seller_iban?: string | null
          seller_kvk?: string | null
          seller_name?: string | null
          seller_phone?: string | null
          sent_at?: string | null
          signature_envelope_id?: string | null
          signature_provider?: string | null
          signed_pdf_url?: string | null
          status?: Database["public"]["Enums"]["quote_status"]
          subtotal_excl?: number
          supersedes_quote_id?: string | null
          terms?: string | null
          terms_pdf_file_id?: string | null
          terms_pdf_version_id?: string | null
          terms_rich_text?: string | null
          terms_url?: string | null
          title: string
          total_incl?: number
          updated_at?: string
          updated_by?: string | null
          valid_until?: string | null
          vat_inclusive?: boolean
          vat_regime?: Database["public"]["Enums"]["document_vat_regime"]
          vat_total?: number
          version?: number
          withdrawn_at?: string | null
        }
        Update: {
          accepted_at?: string | null
          accepted_by_email?: string | null
          accepted_by_name?: string | null
          accepted_ip?: string | null
          accepted_optional_line_ids?: NonNullable<Json>
          accepted_user_agent?: string | null
          archived_at?: string | null
          buyer_address_city?: string | null
          buyer_address_country?: string | null
          buyer_address_line1?: string | null
          buyer_address_line2?: string | null
          buyer_address_postal_code?: string | null
          buyer_btw?: string | null
          buyer_email?: string | null
          buyer_kvk?: string | null
          buyer_name?: string | null
          changes_requested_at?: string | null
          create_order_on_accept?: boolean
          created_at?: string
          created_by?: string | null
          currency?: string
          customer_id?: number
          deposit_kind?: Database["public"]["Enums"]["quote_deposit_kind"]
          deposit_required_to_accept?: boolean
          deposit_value?: number
          discount_description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          expired_at?: string | null
          has_unpublished_changes?: boolean
          id?: string
          intro?: string | null
          invoice_id?: string | null
          issue_date?: string | null
          number?: number
          number_prefix?: string
          organization_id?: string
          promotion_id?: string | null
          public_message?: string | null
          quote_template_id?: string | null
          rejected_at?: string | null
          seller_address_city?: string | null
          seller_address_country?: string | null
          seller_address_line1?: string | null
          seller_address_line2?: string | null
          seller_address_postal_code?: string | null
          seller_btw?: string | null
          seller_email?: string | null
          seller_iban?: string | null
          seller_kvk?: string | null
          seller_name?: string | null
          seller_phone?: string | null
          sent_at?: string | null
          signature_envelope_id?: string | null
          signature_provider?: string | null
          signed_pdf_url?: string | null
          status?: Database["public"]["Enums"]["quote_status"]
          subtotal_excl?: number
          supersedes_quote_id?: string | null
          terms?: string | null
          terms_pdf_file_id?: string | null
          terms_pdf_version_id?: string | null
          terms_rich_text?: string | null
          terms_url?: string | null
          title?: string
          total_incl?: number
          updated_at?: string
          updated_by?: string | null
          valid_until?: string | null
          vat_inclusive?: boolean
          vat_regime?: Database["public"]["Enums"]["document_vat_regime"]
          vat_total?: number
          version?: number
          withdrawn_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "quotes_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "quotes_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_promotion_organization_fkey"
            columns: ["promotion_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "promotions"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "quotes_quote_template_id_fkey"
            columns: ["quote_template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_supersedes_quote_id_fkey"
            columns: ["supersedes_quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_terms_pdf_file_id_fkey"
            columns: ["terms_pdf_file_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_terms_pdf_version_id_fkey"
            columns: ["terms_pdf_version_id"]
            isOneToOne: false
            referencedRelation: "file_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      role_permissions: {
        Row: {
          permission_id: string
          role_id: string
        }
        Insert: {
          permission_id: string
          role_id: string
        }
        Update: {
          permission_id?: string
          role_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_permission_id_fkey"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      roles: {
        Row: {
          created_at: string
          description: string | null
          id: string
          key: string
          name: string
          organization_id: string | null
          scope: Database["public"]["Enums"]["scope_type"]
          system: boolean
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          key: string
          name: string
          organization_id?: string | null
          scope: Database["public"]["Enums"]["scope_type"]
          system?: boolean
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          key?: string
          name?: string
          organization_id?: string | null
          scope?: Database["public"]["Enums"]["scope_type"]
          system?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "roles_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      shipment_lines: {
        Row: {
          created_at: string
          expires_on: string | null
          id: string
          lot_number: string | null
          order_line_id: string | null
          organization_id: string
          position: number
          product_id: string | null
          purchase_order_line_id: string | null
          quantity: number
          return_disposition:
            | Database["public"]["Enums"]["shipment_return_disposition"]
            | null
          serial_number: string | null
          shipment_id: string
          variant_id: string | null
        }
        Insert: {
          created_at?: string
          expires_on?: string | null
          id?: string
          lot_number?: string | null
          order_line_id?: string | null
          organization_id: string
          position?: number
          product_id?: string | null
          purchase_order_line_id?: string | null
          quantity: number
          return_disposition?:
            | Database["public"]["Enums"]["shipment_return_disposition"]
            | null
          serial_number?: string | null
          shipment_id: string
          variant_id?: string | null
        }
        Update: {
          created_at?: string
          expires_on?: string | null
          id?: string
          lot_number?: string | null
          order_line_id?: string | null
          organization_id?: string
          position?: number
          product_id?: string | null
          purchase_order_line_id?: string | null
          quantity?: number
          return_disposition?:
            | Database["public"]["Enums"]["shipment_return_disposition"]
            | null
          serial_number?: string | null
          shipment_id?: string
          variant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "shipment_lines_order_line_id_organization_id_fkey"
            columns: ["order_line_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "order_lines"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "shipment_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shipment_lines_purchase_order_line_id_organization_id_fkey"
            columns: ["purchase_order_line_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "purchase_order_lines"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "shipment_lines_shipment_id_organization_id_fkey"
            columns: ["shipment_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "shipments"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      shipments: {
        Row: {
          address_city: string | null
          address_country: string | null
          address_line1: string | null
          address_line2: string | null
          address_postal_code: string | null
          agenda_item_id: string | null
          carrier: string | null
          created_at: string
          created_by: string | null
          delivered_at: string | null
          delivery_method: Database["public"]["Enums"]["order_delivery_method"]
          direction: Database["public"]["Enums"]["shipment_direction"]
          id: string
          label_path: string | null
          location_id: string | null
          notes: string | null
          number: number
          number_prefix: string
          order_id: string | null
          organization_id: string
          package_count: number
          purchase_order_id: string | null
          service: string | null
          ship_to_name: string | null
          shipped_at: string | null
          status: Database["public"]["Enums"]["shipment_status"]
          status_occurred_at: string | null
          tracking_number: string | null
          tracking_url: string | null
          updated_at: string
          weight_grams: number | null
        }
        Insert: {
          address_city?: string | null
          address_country?: string | null
          address_line1?: string | null
          address_line2?: string | null
          address_postal_code?: string | null
          agenda_item_id?: string | null
          carrier?: string | null
          created_at?: string
          created_by?: string | null
          delivered_at?: string | null
          delivery_method?: Database["public"]["Enums"]["order_delivery_method"]
          direction?: Database["public"]["Enums"]["shipment_direction"]
          id?: string
          label_path?: string | null
          location_id?: string | null
          notes?: string | null
          number: number
          number_prefix?: string
          order_id?: string | null
          organization_id: string
          package_count?: number
          purchase_order_id?: string | null
          service?: string | null
          ship_to_name?: string | null
          shipped_at?: string | null
          status?: Database["public"]["Enums"]["shipment_status"]
          status_occurred_at?: string | null
          tracking_number?: string | null
          tracking_url?: string | null
          updated_at?: string
          weight_grams?: number | null
        }
        Update: {
          address_city?: string | null
          address_country?: string | null
          address_line1?: string | null
          address_line2?: string | null
          address_postal_code?: string | null
          agenda_item_id?: string | null
          carrier?: string | null
          created_at?: string
          created_by?: string | null
          delivered_at?: string | null
          delivery_method?: Database["public"]["Enums"]["order_delivery_method"]
          direction?: Database["public"]["Enums"]["shipment_direction"]
          id?: string
          label_path?: string | null
          location_id?: string | null
          notes?: string | null
          number?: number
          number_prefix?: string
          order_id?: string | null
          organization_id?: string
          package_count?: number
          purchase_order_id?: string | null
          service?: string | null
          ship_to_name?: string | null
          shipped_at?: string | null
          status?: Database["public"]["Enums"]["shipment_status"]
          status_occurred_at?: string | null
          tracking_number?: string | null
          tracking_url?: string | null
          updated_at?: string
          weight_grams?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "shipments_agenda_item_id_fkey"
            columns: ["agenda_item_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shipments_location_id_organization_id_fkey"
            columns: ["location_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "inventory_locations"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "shipments_order_id_organization_id_fkey"
            columns: ["order_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "shipments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shipments_purchase_order_id_organization_id_fkey"
            columns: ["purchase_order_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      sick_leave_cases: {
        Row: {
          actual_return_on: string | null
          created_at: string
          employee_id: string
          expected_return_on: string | null
          id: string
          note: string | null
          organization_id: string
          partial_return_pct: number | null
          reported_by: string | null
          reported_on: string
          status: Database["public"]["Enums"]["sick_leave_status"]
          time_off_request_id: string | null
          updated_at: string
        }
        Insert: {
          actual_return_on?: string | null
          created_at?: string
          employee_id: string
          expected_return_on?: string | null
          id?: string
          note?: string | null
          organization_id: string
          partial_return_pct?: number | null
          reported_by?: string | null
          reported_on: string
          status?: Database["public"]["Enums"]["sick_leave_status"]
          time_off_request_id?: string | null
          updated_at?: string
        }
        Update: {
          actual_return_on?: string | null
          created_at?: string
          employee_id?: string
          expected_return_on?: string | null
          id?: string
          note?: string | null
          organization_id?: string
          partial_return_pct?: number | null
          reported_by?: string | null
          reported_on?: string
          status?: Database["public"]["Enums"]["sick_leave_status"]
          time_off_request_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sick_leave_cases_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "sick_leave_cases_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sick_leave_cases_time_off_request_id_organization_id_fkey"
            columns: ["time_off_request_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "time_off_requests"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      skills: {
        Row: {
          color: string | null
          created_at: string
          default_validity_months: number | null
          description: string | null
          icon_name: string | null
          id: string
          kind: Database["public"]["Enums"]["employee_skill_kind"]
          name: string
          organization_id: string
          requires_document: boolean
          updated_at: string
        }
        Insert: {
          color?: string | null
          created_at?: string
          default_validity_months?: number | null
          description?: string | null
          icon_name?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["employee_skill_kind"]
          name: string
          organization_id: string
          requires_document?: boolean
          updated_at?: string
        }
        Update: {
          color?: string | null
          created_at?: string
          default_validity_months?: number | null
          description?: string | null
          icon_name?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["employee_skill_kind"]
          name?: string
          organization_id?: string
          requires_document?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "skills_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      stripe_webhook_events: {
        Row: {
          created_at: string
          error_message: string | null
          id: string
          livemode: boolean
          processed_at: string | null
          processing_claim_id: string | null
          processing_started_at: string | null
          processing_status: Database["public"]["Enums"]["stripe_webhook_processing_status"]
          retry_count: number
          stripe_created_at: string
          stripe_event_id: string
          type: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          error_message?: string | null
          id?: string
          livemode: boolean
          processed_at?: string | null
          processing_claim_id?: string | null
          processing_started_at?: string | null
          processing_status?: Database["public"]["Enums"]["stripe_webhook_processing_status"]
          retry_count?: number
          stripe_created_at: string
          stripe_event_id: string
          type: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          error_message?: string | null
          id?: string
          livemode?: boolean
          processed_at?: string | null
          processing_claim_id?: string | null
          processing_started_at?: string | null
          processing_status?: Database["public"]["Enums"]["stripe_webhook_processing_status"]
          retry_count?: number
          stripe_created_at?: string
          stripe_event_id?: string
          type?: string
          updated_at?: string
        }
        Relationships: []
      }
      suppliers: {
        Row: {
          account_number: string | null
          address_city: string | null
          address_country: string | null
          address_line1: string | null
          address_line2: string | null
          address_postal_code: string | null
          address_state: string | null
          billing_email: string | null
          btw: string | null
          code: string | null
          created_at: string
          currency: string | null
          default_inventory_location_id: string | null
          default_lead_time_days: number | null
          email: string | null
          external_id: string | null
          id: string
          kvk: string | null
          name: string
          notes: string | null
          ordering_email: string | null
          organization_id: string
          payment_terms_days: number | null
          phone: string | null
          source: string | null
          status: Database["public"]["Enums"]["supplier_status"]
          updated_at: string
          website: string | null
        }
        Insert: {
          account_number?: string | null
          address_city?: string | null
          address_country?: string | null
          address_line1?: string | null
          address_line2?: string | null
          address_postal_code?: string | null
          address_state?: string | null
          billing_email?: string | null
          btw?: string | null
          code?: string | null
          created_at?: string
          currency?: string | null
          default_inventory_location_id?: string | null
          default_lead_time_days?: number | null
          email?: string | null
          external_id?: string | null
          id?: string
          kvk?: string | null
          name: string
          notes?: string | null
          ordering_email?: string | null
          organization_id: string
          payment_terms_days?: number | null
          phone?: string | null
          source?: string | null
          status?: Database["public"]["Enums"]["supplier_status"]
          updated_at?: string
          website?: string | null
        }
        Update: {
          account_number?: string | null
          address_city?: string | null
          address_country?: string | null
          address_line1?: string | null
          address_line2?: string | null
          address_postal_code?: string | null
          address_state?: string | null
          billing_email?: string | null
          btw?: string | null
          code?: string | null
          created_at?: string
          currency?: string | null
          default_inventory_location_id?: string | null
          default_lead_time_days?: number | null
          email?: string | null
          external_id?: string | null
          id?: string
          kvk?: string | null
          name?: string
          notes?: string | null
          ordering_email?: string | null
          organization_id?: string
          payment_terms_days?: number | null
          phone?: string | null
          source?: string | null
          status?: Database["public"]["Enums"]["supplier_status"]
          updated_at?: string
          website?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "suppliers_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "suppliers_default_inventory_location_organization_fkey"
            columns: ["default_inventory_location_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "inventory_locations"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "suppliers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      task_assignees: {
        Row: {
          created_at: string
          organization_id: string
          task_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          organization_id: string
          task_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          organization_id?: string
          task_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_assignees_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_assignees_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_assignees_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      task_hold_reasons: {
        Row: {
          created_at: string
          id: string
          label: string
          organization_id: string
          position: number
          system_key: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          label: string
          organization_id: string
          position?: number
          system_key?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          label?: string
          organization_id?: string
          position?: number
          system_key?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_hold_reasons_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      task_materials: {
        Row: {
          billable: boolean
          consumed_at: string | null
          created_at: string
          created_by: string | null
          currency: string | null
          id: string
          notes: string | null
          organization_id: string
          position: number
          product_id: string
          quantity: number
          quote_id: string | null
          stock_state: Database["public"]["Enums"]["task_material_stock_state"]
          task_id: string
          unit: string | null
          unit_price: number
          updated_at: string
          updated_by: string | null
          variant_id: string | null
          vat_rate: number
        }
        Insert: {
          billable?: boolean
          consumed_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          id?: string
          notes?: string | null
          organization_id: string
          position?: number
          product_id: string
          quantity: number
          quote_id?: string | null
          stock_state?: Database["public"]["Enums"]["task_material_stock_state"]
          task_id: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          updated_by?: string | null
          variant_id?: string | null
          vat_rate?: number
        }
        Update: {
          billable?: boolean
          consumed_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string | null
          id?: string
          notes?: string | null
          organization_id?: string
          position?: number
          product_id?: string
          quantity?: number
          quote_id?: string | null
          stock_state?: Database["public"]["Enums"]["task_material_stock_state"]
          task_id?: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          updated_by?: string | null
          variant_id?: string | null
          vat_rate?: number
        }
        Relationships: [
          {
            foreignKeyName: "task_materials_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "task_materials_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_materials_product_id_organization_id_fkey"
            columns: ["product_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "task_materials_quote_organization_fkey"
            columns: ["quote_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "task_materials_task_id_organization_id_fkey"
            columns: ["task_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "task_materials_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      task_required_skills: {
        Row: {
          created_at: string
          organization_id: string
          skill_id: string
          task_id: string
        }
        Insert: {
          created_at?: string
          organization_id: string
          skill_id: string
          task_id: string
        }
        Update: {
          created_at?: string
          organization_id?: string
          skill_id?: string
          task_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_required_skills_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_required_skills_skill_id_organization_id_fkey"
            columns: ["skill_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "skills"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "task_required_skills_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
        ]
      }
      task_tags: {
        Row: {
          created_at: string
          organization_id: string
          tag_id: string
          task_id: string
        }
        Insert: {
          created_at?: string
          organization_id: string
          tag_id: string
          task_id: string
        }
        Update: {
          created_at?: string
          organization_id?: string
          tag_id?: string
          task_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_tags_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "organization_tags"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_tags_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
        ]
      }
      tasks: {
        Row: {
          archived_at: string | null
          budget_hours: number | null
          budget_warned_at: string | null
          created_at: string
          created_by: string | null
          customer_asset_id: number | null
          customer_id: number | null
          description: string | null
          due_at: string | null
          end_at: string | null
          hold_reason_id: string | null
          id: string
          invoice_timing: string
          number: number
          organization_id: string
          parent_task_id: string | null
          position: number
          priority: Database["public"]["Enums"]["task_priority"]
          start_at: string | null
          status: Database["public"]["Enums"]["task_status"]
          task_template_id: string | null
          title: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          archived_at?: string | null
          budget_hours?: number | null
          budget_warned_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_asset_id?: number | null
          customer_id?: number | null
          description?: string | null
          due_at?: string | null
          end_at?: string | null
          hold_reason_id?: string | null
          id?: string
          invoice_timing?: string
          number: number
          organization_id: string
          parent_task_id?: string | null
          position?: number
          priority?: Database["public"]["Enums"]["task_priority"]
          start_at?: string | null
          status?: Database["public"]["Enums"]["task_status"]
          task_template_id?: string | null
          title: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          archived_at?: string | null
          budget_hours?: number | null
          budget_warned_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_asset_id?: number | null
          customer_id?: number | null
          description?: string | null
          due_at?: string | null
          end_at?: string | null
          hold_reason_id?: string | null
          id?: string
          invoice_timing?: string
          number?: number
          organization_id?: string
          parent_task_id?: string | null
          position?: number
          priority?: Database["public"]["Enums"]["task_priority"]
          start_at?: string | null
          status?: Database["public"]["Enums"]["task_status"]
          task_template_id?: string | null
          title?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tasks_customer_asset_id_fkey"
            columns: ["customer_asset_id"]
            isOneToOne: false
            referencedRelation: "customer_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "tasks_hold_reason_id_fkey"
            columns: ["hold_reason_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "task_hold_reasons"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "tasks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_parent_task_id_organization_id_fkey"
            columns: ["parent_task_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "tasks_task_template_id_fkey"
            columns: ["task_template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
        ]
      }
      team_members: {
        Row: {
          created_at: string
          organization_id: string
          team_id: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          organization_id: string
          team_id: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          organization_id?: string
          team_id?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "team_members_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "team_members_team_id_organization_id_fkey"
            columns: ["team_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "team_members_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      teams: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          icon_name: string
          id: number
          name: string
          organization_id: string
          slug: string
          status: Database["public"]["Enums"]["team_status"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          icon_name: string
          id?: number
          name: string
          organization_id: string
          slug: string
          status?: Database["public"]["Enums"]["team_status"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          icon_name?: string
          id?: number
          name?: string
          organization_id?: string
          slug?: string
          status?: Database["public"]["Enums"]["team_status"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "teams_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      template_invoice_lines: {
        Row: {
          created_at: string
          description: string | null
          discount_kind: Database["public"]["Enums"]["discount_kind"]
          discount_value: number
          id: string
          kind: Database["public"]["Enums"]["invoice_line_kind"]
          line_type: Database["public"]["Enums"]["invoice_line_type"] | null
          organization_id: string
          position: number
          pricing_mode: Database["public"]["Enums"]["invoice_line_pricing_mode"]
          product_id: string | null
          quantity: number
          template_id: string
          title: string
          unit: string | null
          unit_price: number
          updated_at: string
          variant_id: string | null
          vat_rate: number
        }
        Insert: {
          created_at?: string
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          kind?: Database["public"]["Enums"]["invoice_line_kind"]
          line_type?: Database["public"]["Enums"]["invoice_line_type"] | null
          organization_id: string
          position?: number
          pricing_mode?: Database["public"]["Enums"]["invoice_line_pricing_mode"]
          product_id?: string | null
          quantity?: number
          template_id: string
          title: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          variant_id?: string | null
          vat_rate?: number
        }
        Update: {
          created_at?: string
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          kind?: Database["public"]["Enums"]["invoice_line_kind"]
          line_type?: Database["public"]["Enums"]["invoice_line_type"] | null
          organization_id?: string
          position?: number
          pricing_mode?: Database["public"]["Enums"]["invoice_line_pricing_mode"]
          product_id?: string | null
          quantity?: number
          template_id?: string
          title?: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          variant_id?: string | null
          vat_rate?: number
        }
        Relationships: [
          {
            foreignKeyName: "template_invoice_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_invoice_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_invoice_lines_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_invoice_lines_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      template_onboarding_items: {
        Row: {
          assignee_role: Database["public"]["Enums"]["journey_assignee_role"]
          assignee_user_id: string | null
          created_at: string
          description: string | null
          id: string
          journey_kind: Database["public"]["Enums"]["employee_journey_kind"]
          kind: Database["public"]["Enums"]["journey_item_kind"]
          offset_days: number
          organization_id: string
          position: number
          relative_to: Database["public"]["Enums"]["journey_relative_to"]
          template_id: string
          title: string
          updated_at: string
        }
        Insert: {
          assignee_role?: Database["public"]["Enums"]["journey_assignee_role"]
          assignee_user_id?: string | null
          created_at?: string
          description?: string | null
          id?: string
          journey_kind?: Database["public"]["Enums"]["employee_journey_kind"]
          kind?: Database["public"]["Enums"]["journey_item_kind"]
          offset_days?: number
          organization_id: string
          position?: number
          relative_to?: Database["public"]["Enums"]["journey_relative_to"]
          template_id: string
          title: string
          updated_at?: string
        }
        Update: {
          assignee_role?: Database["public"]["Enums"]["journey_assignee_role"]
          assignee_user_id?: string | null
          created_at?: string
          description?: string | null
          id?: string
          journey_kind?: Database["public"]["Enums"]["employee_journey_kind"]
          kind?: Database["public"]["Enums"]["journey_item_kind"]
          offset_days?: number
          organization_id?: string
          position?: number
          relative_to?: Database["public"]["Enums"]["journey_relative_to"]
          template_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "template_onboarding_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_onboarding_items_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
        ]
      }
      template_quote_lines: {
        Row: {
          created_at: string
          description: string | null
          discount_kind: Database["public"]["Enums"]["discount_kind"]
          discount_value: number
          id: string
          is_optional: boolean
          kind: Database["public"]["Enums"]["quote_line_kind"]
          line_type: Database["public"]["Enums"]["quote_line_type"] | null
          organization_id: string
          position: number
          pricing_mode: Database["public"]["Enums"]["quote_line_pricing_mode"]
          product_id: string | null
          quantity: number
          subscription_interval:
            | Database["public"]["Enums"]["quote_subscription_interval"]
            | null
          subscription_periods: number | null
          template_id: string
          title: string
          unit: string | null
          unit_price: number
          updated_at: string
          variant_id: string | null
          vat_rate: number
        }
        Insert: {
          created_at?: string
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          is_optional?: boolean
          kind?: Database["public"]["Enums"]["quote_line_kind"]
          line_type?: Database["public"]["Enums"]["quote_line_type"] | null
          organization_id: string
          position?: number
          pricing_mode?: Database["public"]["Enums"]["quote_line_pricing_mode"]
          product_id?: string | null
          quantity?: number
          subscription_interval?:
            | Database["public"]["Enums"]["quote_subscription_interval"]
            | null
          subscription_periods?: number | null
          template_id: string
          title: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          variant_id?: string | null
          vat_rate?: number
        }
        Update: {
          created_at?: string
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          id?: string
          is_optional?: boolean
          kind?: Database["public"]["Enums"]["quote_line_kind"]
          line_type?: Database["public"]["Enums"]["quote_line_type"] | null
          organization_id?: string
          position?: number
          pricing_mode?: Database["public"]["Enums"]["quote_line_pricing_mode"]
          product_id?: string | null
          quantity?: number
          subscription_interval?:
            | Database["public"]["Enums"]["quote_subscription_interval"]
            | null
          subscription_periods?: number | null
          template_id?: string
          title?: string
          unit?: string | null
          unit_price?: number
          updated_at?: string
          variant_id?: string | null
          vat_rate?: number
        }
        Relationships: [
          {
            foreignKeyName: "template_quote_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_quote_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_quote_lines_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_quote_lines_variant_id_product_id_fkey"
            columns: ["variant_id", "product_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id", "product_id"]
          },
        ]
      }
      template_task_assignees: {
        Row: {
          created_at: string
          organization_id: string
          template_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          organization_id: string
          template_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          organization_id?: string
          template_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "template_task_assignees_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_task_assignees_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_task_assignees_user_id_organization_id_fkey"
            columns: ["user_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "organization_users"
            referencedColumns: ["user_id", "organization_id"]
          },
        ]
      }
      template_task_settings: {
        Row: {
          created_at: string
          customer_asset_id: number | null
          customer_id: number | null
          description: string | null
          organization_id: string
          priority: Database["public"]["Enums"]["task_priority"]
          status: Database["public"]["Enums"]["task_status"]
          template_id: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          customer_asset_id?: number | null
          customer_id?: number | null
          description?: string | null
          organization_id: string
          priority?: Database["public"]["Enums"]["task_priority"]
          status?: Database["public"]["Enums"]["task_status"]
          template_id: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          customer_asset_id?: number | null
          customer_id?: number | null
          description?: string | null
          organization_id?: string
          priority?: Database["public"]["Enums"]["task_priority"]
          status?: Database["public"]["Enums"]["task_status"]
          template_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "template_task_settings_customer_asset_id_fkey"
            columns: ["customer_asset_id"]
            isOneToOne: false
            referencedRelation: "customer_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_task_settings_customer_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "template_task_settings_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_task_settings_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: true
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
        ]
      }
      template_task_subtasks: {
        Row: {
          created_at: string
          id: string
          organization_id: string
          position: number
          priority: Database["public"]["Enums"]["task_priority"]
          status: Database["public"]["Enums"]["task_status"]
          template_id: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          organization_id: string
          position?: number
          priority?: Database["public"]["Enums"]["task_priority"]
          status?: Database["public"]["Enums"]["task_status"]
          template_id: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          organization_id?: string
          position?: number
          priority?: Database["public"]["Enums"]["task_priority"]
          status?: Database["public"]["Enums"]["task_status"]
          template_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "template_task_subtasks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_task_subtasks_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
        ]
      }
      template_task_tags: {
        Row: {
          created_at: string
          organization_id: string
          tag_id: string
          template_id: string
        }
        Insert: {
          created_at?: string
          organization_id: string
          tag_id: string
          template_id: string
        }
        Update: {
          created_at?: string
          organization_id?: string
          tag_id?: string
          template_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "template_task_tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_task_tags_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "organization_tags"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_task_tags_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
        ]
      }
      template_workflows: {
        Row: {
          created_at: string
          created_by: string | null
          definition_key: string
          enabled: boolean
          id: string
          mode: string
          organization_id: string
          position: number
          template_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          definition_key: string
          enabled?: boolean
          id?: string
          mode?: string
          organization_id: string
          position?: number
          template_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          definition_key?: string
          enabled?: boolean
          id?: string
          mode?: string
          organization_id?: string
          position?: number
          template_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "template_workflows_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "template_workflows_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "templates"
            referencedColumns: ["id"]
          },
        ]
      }
      templates: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          currency: string
          default_due_days: number | null
          default_validity_days: number | null
          deposit_kind: Database["public"]["Enums"]["quote_deposit_kind"]
          deposit_required_to_accept: boolean
          deposit_value: number
          description: string | null
          discount_kind: Database["public"]["Enums"]["discount_kind"]
          discount_value: number
          footer_text: string | null
          id: string
          internal_notes: string | null
          intro: string | null
          is_default: boolean
          language: Database["public"]["Enums"]["app_locale"]
          lifecycle_workflow_key: string | null
          name: string
          organization_id: string
          public_message: string | null
          terms: string | null
          terms_pdf_file_id: string | null
          terms_pdf_version_id: string | null
          terms_rich_text: string | null
          terms_url: string | null
          title: string
          type: Database["public"]["Enums"]["template_type"]
          updated_at: string
          updated_by: string | null
          vat_inclusive: boolean
          vat_regime: Database["public"]["Enums"]["document_vat_regime"]
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          default_due_days?: number | null
          default_validity_days?: number | null
          deposit_kind?: Database["public"]["Enums"]["quote_deposit_kind"]
          deposit_required_to_accept?: boolean
          deposit_value?: number
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          footer_text?: string | null
          id?: string
          internal_notes?: string | null
          intro?: string | null
          is_default?: boolean
          language?: Database["public"]["Enums"]["app_locale"]
          lifecycle_workflow_key?: string | null
          name: string
          organization_id: string
          public_message?: string | null
          terms?: string | null
          terms_pdf_file_id?: string | null
          terms_pdf_version_id?: string | null
          terms_rich_text?: string | null
          terms_url?: string | null
          title: string
          type: Database["public"]["Enums"]["template_type"]
          updated_at?: string
          updated_by?: string | null
          vat_inclusive?: boolean
          vat_regime?: Database["public"]["Enums"]["document_vat_regime"]
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          default_due_days?: number | null
          default_validity_days?: number | null
          deposit_kind?: Database["public"]["Enums"]["quote_deposit_kind"]
          deposit_required_to_accept?: boolean
          deposit_value?: number
          description?: string | null
          discount_kind?: Database["public"]["Enums"]["discount_kind"]
          discount_value?: number
          footer_text?: string | null
          id?: string
          internal_notes?: string | null
          intro?: string | null
          is_default?: boolean
          language?: Database["public"]["Enums"]["app_locale"]
          lifecycle_workflow_key?: string | null
          name?: string
          organization_id?: string
          public_message?: string | null
          terms?: string | null
          terms_pdf_file_id?: string | null
          terms_pdf_version_id?: string | null
          terms_rich_text?: string | null
          terms_url?: string | null
          title?: string
          type?: Database["public"]["Enums"]["template_type"]
          updated_at?: string
          updated_by?: string | null
          vat_inclusive?: boolean
          vat_regime?: Database["public"]["Enums"]["document_vat_regime"]
        }
        Relationships: [
          {
            foreignKeyName: "templates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "templates_terms_pdf_file_id_fkey"
            columns: ["terms_pdf_file_id"]
            isOneToOne: false
            referencedRelation: "file_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "templates_terms_pdf_version_id_fkey"
            columns: ["terms_pdf_version_id"]
            isOneToOne: false
            referencedRelation: "file_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      time_entries: {
        Row: {
          agenda_item_id: string | null
          bill_rate: number | null
          billable: boolean
          cost_rate: number | null
          created_at: string
          customer_id: number | null
          duration_seconds: number | null
          employee_id: string | null
          id: string
          invoice_line_id: string | null
          note: string | null
          organization_id: string
          source: Database["public"]["Enums"]["time_entry_source"]
          started_at: string
          task_id: string | null
          timesheet_id: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          agenda_item_id?: string | null
          bill_rate?: number | null
          billable?: boolean
          cost_rate?: number | null
          created_at?: string
          customer_id?: number | null
          duration_seconds?: number | null
          employee_id?: string | null
          id?: string
          invoice_line_id?: string | null
          note?: string | null
          organization_id: string
          source?: Database["public"]["Enums"]["time_entry_source"]
          started_at?: string
          task_id?: string | null
          timesheet_id?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          agenda_item_id?: string | null
          bill_rate?: number | null
          billable?: boolean
          cost_rate?: number | null
          created_at?: string
          customer_id?: number | null
          duration_seconds?: number | null
          employee_id?: string | null
          id?: string
          invoice_line_id?: string | null
          note?: string | null
          organization_id?: string
          source?: Database["public"]["Enums"]["time_entry_source"]
          started_at?: string
          task_id?: string | null
          timesheet_id?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "time_entries_agenda_item_id_organization_id_fkey"
            columns: ["agenda_item_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "agenda_items"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "time_entries_customer_id_organization_id_fkey"
            columns: ["customer_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "time_entries_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "time_entries_invoice_line_id_fkey"
            columns: ["invoice_line_id"]
            isOneToOne: false
            referencedRelation: "invoice_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_entries_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_entries_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_entries_timesheet_id_organization_id_fkey"
            columns: ["timesheet_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "timesheets"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      time_entry_dismissals: {
        Row: {
          created_at: string
          employee_id: string
          organization_id: string
          signal_key: string
        }
        Insert: {
          created_at?: string
          employee_id: string
          organization_id: string
          signal_key: string
        }
        Update: {
          created_at?: string
          employee_id?: string
          organization_id?: string
          signal_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "time_entry_dismissals_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "time_entry_dismissals_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      time_off_blackout_periods: {
        Row: {
          created_at: string
          created_by: string | null
          ends_on: string
          id: string
          mode: Database["public"]["Enums"]["hr_enforcement_mode"]
          name: string
          organization_id: string
          starts_on: string
          team_id: number | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          ends_on: string
          id?: string
          mode?: Database["public"]["Enums"]["hr_enforcement_mode"]
          name: string
          organization_id: string
          starts_on: string
          team_id?: number | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          ends_on?: string
          id?: string
          mode?: Database["public"]["Enums"]["hr_enforcement_mode"]
          name?: string
          organization_id?: string
          starts_on?: string
          team_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "time_off_blackout_periods_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_off_blackout_periods_team_id_organization_id_fkey"
            columns: ["team_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      time_off_feeds: {
        Row: {
          created_at: string
          id: string
          organization_id: string
          rotated_at: string | null
          team_id: number | null
          token: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          organization_id: string
          rotated_at?: string | null
          team_id?: number | null
          token?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          organization_id?: string
          rotated_at?: string | null
          team_id?: number | null
          token?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "time_off_feeds_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_off_feeds_team_id_organization_id_fkey"
            columns: ["team_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      time_off_ledger: {
        Row: {
          created_at: string
          created_by: string | null
          effective_on: string
          employee_id: string
          expires_on: string | null
          hours: number
          id: string
          kind: Database["public"]["Enums"]["time_off_ledger_kind"]
          note: string | null
          organization_id: string
          time_off_request_id: string | null
          time_off_type_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          effective_on: string
          employee_id: string
          expires_on?: string | null
          hours: number
          id?: string
          kind: Database["public"]["Enums"]["time_off_ledger_kind"]
          note?: string | null
          organization_id: string
          time_off_request_id?: string | null
          time_off_type_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          effective_on?: string
          employee_id?: string
          expires_on?: string | null
          hours?: number
          id?: string
          kind?: Database["public"]["Enums"]["time_off_ledger_kind"]
          note?: string | null
          organization_id?: string
          time_off_request_id?: string | null
          time_off_type_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "time_off_ledger_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "time_off_ledger_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_off_ledger_time_off_request_id_organization_id_fkey"
            columns: ["time_off_request_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "time_off_requests"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "time_off_ledger_time_off_type_id_organization_id_fkey"
            columns: ["time_off_type_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "time_off_types"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      time_off_policies: {
        Row: {
          accrual_method: Database["public"]["Enums"]["time_off_accrual_method"]
          annual_hours: number
          carryover_expires_after_months: number | null
          carryover_max_hours: number | null
          created_at: string
          id: string
          is_default: boolean
          name: string
          organization_id: string
          prorate_by_contract_hours: boolean
          time_off_type_id: string
          updated_at: string
        }
        Insert: {
          accrual_method?: Database["public"]["Enums"]["time_off_accrual_method"]
          annual_hours?: number
          carryover_expires_after_months?: number | null
          carryover_max_hours?: number | null
          created_at?: string
          id?: string
          is_default?: boolean
          name: string
          organization_id: string
          prorate_by_contract_hours?: boolean
          time_off_type_id: string
          updated_at?: string
        }
        Update: {
          accrual_method?: Database["public"]["Enums"]["time_off_accrual_method"]
          annual_hours?: number
          carryover_expires_after_months?: number | null
          carryover_max_hours?: number | null
          created_at?: string
          id?: string
          is_default?: boolean
          name?: string
          organization_id?: string
          prorate_by_contract_hours?: boolean
          time_off_type_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "time_off_policies_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_off_policies_time_off_type_id_organization_id_fkey"
            columns: ["time_off_type_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "time_off_types"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      time_off_requests: {
        Row: {
          attachment_storage_path: string | null
          cancelled_at: string | null
          created_at: string
          created_by: string | null
          decided_at: string | null
          decided_by: string | null
          decision_note: string | null
          employee_id: string
          end_part: Database["public"]["Enums"]["time_off_partial_day"]
          end_time: string | null
          ends_on: string
          hours: number
          id: string
          note: string | null
          organization_id: string
          start_part: Database["public"]["Enums"]["time_off_partial_day"]
          start_time: string | null
          starts_on: string
          status: Database["public"]["Enums"]["time_off_request_status"]
          time_off_type_id: string
          updated_at: string
        }
        Insert: {
          attachment_storage_path?: string | null
          cancelled_at?: string | null
          created_at?: string
          created_by?: string | null
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          employee_id: string
          end_part?: Database["public"]["Enums"]["time_off_partial_day"]
          end_time?: string | null
          ends_on: string
          hours?: number
          id?: string
          note?: string | null
          organization_id: string
          start_part?: Database["public"]["Enums"]["time_off_partial_day"]
          start_time?: string | null
          starts_on: string
          status?: Database["public"]["Enums"]["time_off_request_status"]
          time_off_type_id: string
          updated_at?: string
        }
        Update: {
          attachment_storage_path?: string | null
          cancelled_at?: string | null
          created_at?: string
          created_by?: string | null
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          employee_id?: string
          end_part?: Database["public"]["Enums"]["time_off_partial_day"]
          end_time?: string | null
          ends_on?: string
          hours?: number
          id?: string
          note?: string | null
          organization_id?: string
          start_part?: Database["public"]["Enums"]["time_off_partial_day"]
          start_time?: string | null
          starts_on?: string
          status?: Database["public"]["Enums"]["time_off_request_status"]
          time_off_type_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "time_off_requests_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "time_off_requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "time_off_requests_time_off_type_id_organization_id_fkey"
            columns: ["time_off_type_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "time_off_types"
            referencedColumns: ["id", "organization_id"]
          },
        ]
      }
      time_off_types: {
        Row: {
          allow_half_days: boolean
          allow_hours: boolean
          archived_at: string | null
          category: Database["public"]["Enums"]["time_off_category"]
          color: string | null
          created_at: string
          deducts_balance: boolean
          icon_name: string | null
          id: string
          name: string
          organization_id: string
          paid: boolean
          position: number
          requires_approval: boolean | null
          requires_attachment: boolean
          updated_at: string
        }
        Insert: {
          allow_half_days?: boolean
          allow_hours?: boolean
          archived_at?: string | null
          category?: Database["public"]["Enums"]["time_off_category"]
          color?: string | null
          created_at?: string
          deducts_balance?: boolean
          icon_name?: string | null
          id?: string
          name: string
          organization_id: string
          paid?: boolean
          position?: number
          requires_approval?: boolean | null
          requires_attachment?: boolean
          updated_at?: string
        }
        Update: {
          allow_half_days?: boolean
          allow_hours?: boolean
          archived_at?: string | null
          category?: Database["public"]["Enums"]["time_off_category"]
          color?: string | null
          created_at?: string
          deducts_balance?: boolean
          icon_name?: string | null
          id?: string
          name?: string
          organization_id?: string
          paid?: boolean
          position?: number
          requires_approval?: boolean | null
          requires_attachment?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "time_off_types_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      timesheets: {
        Row: {
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision_note: string | null
          employee_id: string
          id: string
          organization_id: string
          status: Database["public"]["Enums"]["timesheet_status"]
          submitted_at: string | null
          updated_at: string
          week_start: string
        }
        Insert: {
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          employee_id: string
          id?: string
          organization_id: string
          status?: Database["public"]["Enums"]["timesheet_status"]
          submitted_at?: string | null
          updated_at?: string
          week_start: string
        }
        Update: {
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          employee_id?: string
          id?: string
          organization_id?: string
          status?: Database["public"]["Enums"]["timesheet_status"]
          submitted_at?: string | null
          updated_at?: string
          week_start?: string
        }
        Relationships: [
          {
            foreignKeyName: "timesheets_employee_id_organization_id_fkey"
            columns: ["employee_id", "organization_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id", "organization_id"]
          },
          {
            foreignKeyName: "timesheets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          created_at: string
          role_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          role_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          role_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_roles_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      webhook_deliveries: {
        Row: {
          attempt: number
          available_at: string
          created_at: string
          destination_id: string
          duration_ms: number | null
          event_id: string | null
          event_kind: string
          id: string
          last_error: string | null
          leased_until: string | null
          organization_id: string
          payload: NonNullable<Json>
          processed_at: string | null
          response_body: string | null
          response_status: number | null
          status: string
          updated_at: string
          workflow_run_id: string | null
        }
        Insert: {
          attempt?: number
          available_at?: string
          created_at?: string
          destination_id: string
          duration_ms?: number | null
          event_id?: string | null
          event_kind: string
          id?: string
          last_error?: string | null
          leased_until?: string | null
          organization_id: string
          payload?: NonNullable<Json>
          processed_at?: string | null
          response_body?: string | null
          response_status?: number | null
          status?: string
          updated_at?: string
          workflow_run_id?: string | null
        }
        Update: {
          attempt?: number
          available_at?: string
          created_at?: string
          destination_id?: string
          duration_ms?: number | null
          event_id?: string | null
          event_kind?: string
          id?: string
          last_error?: string | null
          leased_until?: string | null
          organization_id?: string
          payload?: NonNullable<Json>
          processed_at?: string | null
          response_body?: string | null
          response_status?: number | null
          status?: string
          updated_at?: string
          workflow_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "webhook_deliveries_destination_id_fkey"
            columns: ["destination_id"]
            isOneToOne: false
            referencedRelation: "webhook_destinations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webhook_deliveries_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "workflow_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webhook_deliveries_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webhook_deliveries_workflow_run_id_fkey"
            columns: ["workflow_run_id"]
            isOneToOne: false
            referencedRelation: "workflow_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      webhook_destination_secrets: {
        Row: {
          created_at: string
          destination_id: string
          id: string
          organization_id: string
          secret: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          destination_id: string
          id?: string
          organization_id: string
          secret: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          destination_id?: string
          id?: string
          organization_id?: string
          secret?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "webhook_destination_secrets_destination_id_fkey"
            columns: ["destination_id"]
            isOneToOne: true
            referencedRelation: "webhook_destinations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webhook_destination_secrets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      webhook_destinations: {
        Row: {
          created_at: string
          created_by: string | null
          enabled: boolean
          event_kinds: string[]
          id: string
          name: string
          organization_id: string
          updated_at: string
          url: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          enabled?: boolean
          event_kinds?: string[]
          id?: string
          name: string
          organization_id: string
          updated_at?: string
          url: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          enabled?: boolean
          event_kinds?: string[]
          id?: string
          name?: string
          organization_id?: string
          updated_at?: string
          url?: string
        }
        Relationships: [
          {
            foreignKeyName: "webhook_destinations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      webhook_endpoint_secrets: {
        Row: {
          created_at: string
          endpoint_id: string
          id: string
          organization_id: string
          secret: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          endpoint_id: string
          id?: string
          organization_id: string
          secret: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          endpoint_id?: string
          id?: string
          organization_id?: string
          secret?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "webhook_endpoint_secrets_endpoint_id_fkey"
            columns: ["endpoint_id"]
            isOneToOne: true
            referencedRelation: "webhook_endpoints"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webhook_endpoint_secrets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      webhook_endpoints: {
        Row: {
          created_at: string
          created_by: string | null
          enabled: boolean
          id: string
          last_received_at: string | null
          last_status: string | null
          name: string
          organization_id: string
          receive_count: number
          token: string
          updated_at: string
          workflow_definition_id: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          enabled?: boolean
          id?: string
          last_received_at?: string | null
          last_status?: string | null
          name: string
          organization_id: string
          receive_count?: number
          token: string
          updated_at?: string
          workflow_definition_id?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          enabled?: boolean
          id?: string
          last_received_at?: string | null
          last_status?: string | null
          name?: string
          organization_id?: string
          receive_count?: number
          token?: string
          updated_at?: string
          workflow_definition_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "webhook_endpoints_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webhook_endpoints_workflow_definition_id_fkey"
            columns: ["workflow_definition_id"]
            isOneToOne: false
            referencedRelation: "workflow_definitions"
            referencedColumns: ["id"]
          },
        ]
      }
      workflow_definitions: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          description: string | null
          forked_from_definition_id: string | null
          forked_from_version: number | null
          graph: NonNullable<Json>
          id: string
          is_default: boolean
          key: string
          metadata: NonNullable<Json>
          name: string
          organization_id: string | null
          owner_scope: string
          published_at: string | null
          purpose: string
          status: string
          subject_type: string | null
          updated_at: string
          version: number
          visibility: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          forked_from_definition_id?: string | null
          forked_from_version?: number | null
          graph?: NonNullable<Json>
          id?: string
          is_default?: boolean
          key: string
          metadata?: NonNullable<Json>
          name: string
          organization_id?: string | null
          owner_scope: string
          published_at?: string | null
          purpose?: string
          status?: string
          subject_type?: string | null
          updated_at?: string
          version?: number
          visibility?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          forked_from_definition_id?: string | null
          forked_from_version?: number | null
          graph?: NonNullable<Json>
          id?: string
          is_default?: boolean
          key?: string
          metadata?: NonNullable<Json>
          name?: string
          organization_id?: string | null
          owner_scope?: string
          published_at?: string | null
          purpose?: string
          status?: string
          subject_type?: string | null
          updated_at?: string
          version?: number
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "workflow_definitions_forked_from_definition_id_fkey"
            columns: ["forked_from_definition_id"]
            isOneToOne: false
            referencedRelation: "workflow_definitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_definitions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      workflow_events: {
        Row: {
          created_at: string
          id: string
          idempotency_key: string | null
          kind: string
          organization_id: string | null
          payload: NonNullable<Json>
          source: string
        }
        Insert: {
          created_at?: string
          id?: string
          idempotency_key?: string | null
          kind: string
          organization_id?: string | null
          payload?: NonNullable<Json>
          source: string
        }
        Update: {
          created_at?: string
          id?: string
          idempotency_key?: string | null
          kind?: string
          organization_id?: string | null
          payload?: NonNullable<Json>
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "workflow_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      workflow_grants: {
        Row: {
          created_at: string
          created_by: string | null
          definition_id: string
          id: string
          organization_id: string
          team_id: number | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          definition_id: string
          id?: string
          organization_id: string
          team_id?: number | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          definition_id?: string
          id?: string
          organization_id?: string
          team_id?: number | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "workflow_grants_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "workflow_definitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_grants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_grants_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
        ]
      }
      workflow_lifecycle_events: {
        Row: {
          actor_customer_contact_id: string | null
          actor_user_id: string | null
          cleared_at: string | null
          created_at: string
          display: string
          id: string
          label: string
          lifecycle_id: string
          organization_id: string
          outcome: string
          reached_at: string
          run_step_id: string | null
          source_run_id: string | null
          stage_key: string
        }
        Insert: {
          actor_customer_contact_id?: string | null
          actor_user_id?: string | null
          cleared_at?: string | null
          created_at?: string
          display?: string
          id?: string
          label: string
          lifecycle_id: string
          organization_id: string
          outcome?: string
          reached_at?: string
          run_step_id?: string | null
          source_run_id?: string | null
          stage_key: string
        }
        Update: {
          actor_customer_contact_id?: string | null
          actor_user_id?: string | null
          cleared_at?: string | null
          created_at?: string
          display?: string
          id?: string
          label?: string
          lifecycle_id?: string
          organization_id?: string
          outcome?: string
          reached_at?: string
          run_step_id?: string | null
          source_run_id?: string | null
          stage_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "workflow_lifecycle_events_actor_customer_contact_id_fkey"
            columns: ["actor_customer_contact_id"]
            isOneToOne: false
            referencedRelation: "customer_contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_lifecycle_events_lifecycle_id_fkey"
            columns: ["lifecycle_id"]
            isOneToOne: false
            referencedRelation: "workflow_lifecycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_lifecycle_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_lifecycle_events_run_step_id_fkey"
            columns: ["run_step_id"]
            isOneToOne: false
            referencedRelation: "workflow_run_steps"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_lifecycle_events_source_run_id_fkey"
            columns: ["source_run_id"]
            isOneToOne: false
            referencedRelation: "workflow_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      workflow_lifecycles: {
        Row: {
          created_at: string
          current_stage_key: string | null
          definition_id: string
          definition_version: number
          ended_at: string | null
          id: string
          organization_id: string
          pause_reason: string | null
          paused_at: string | null
          paused_by: string | null
          paused_until: string | null
          run_id: string | null
          started_at: string
          subject_id: string
          subject_type: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          current_stage_key?: string | null
          definition_id: string
          definition_version: number
          ended_at?: string | null
          id?: string
          organization_id: string
          pause_reason?: string | null
          paused_at?: string | null
          paused_by?: string | null
          paused_until?: string | null
          run_id?: string | null
          started_at?: string
          subject_id: string
          subject_type: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          current_stage_key?: string | null
          definition_id?: string
          definition_version?: number
          ended_at?: string | null
          id?: string
          organization_id?: string
          pause_reason?: string | null
          paused_at?: string | null
          paused_by?: string | null
          paused_until?: string | null
          run_id?: string | null
          started_at?: string
          subject_id?: string
          subject_type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "workflow_lifecycles_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "workflow_definitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_lifecycles_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_lifecycles_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "workflow_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      workflow_opt_outs: {
        Row: {
          created_at: string
          created_by: string | null
          definition_key: string
          organization_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          definition_key: string
          organization_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          definition_key?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workflow_opt_outs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      workflow_run_steps: {
        Row: {
          attempt: number
          completed_at: string | null
          created_at: string
          error: Json | null
          id: string
          input: Json | null
          node_id: string
          node_kind: string
          organization_id: string | null
          output: Json | null
          run_id: string
          started_at: string | null
          status: string
          updated_at: string
        }
        Insert: {
          attempt?: number
          completed_at?: string | null
          created_at?: string
          error?: Json | null
          id?: string
          input?: Json | null
          node_id: string
          node_kind: string
          organization_id?: string | null
          output?: Json | null
          run_id: string
          started_at?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          attempt?: number
          completed_at?: string | null
          created_at?: string
          error?: Json | null
          id?: string
          input?: Json | null
          node_id?: string
          node_kind?: string
          organization_id?: string | null
          output?: Json | null
          run_id?: string
          started_at?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "workflow_run_steps_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_run_steps_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "workflow_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      workflow_runs: {
        Row: {
          completed_at: string | null
          created_at: string
          created_by: string | null
          definition_id: string
          definition_version: number
          error: Json | null
          graph_snapshot: NonNullable<Json>
          id: string
          idempotency_key: string | null
          input: NonNullable<Json>
          organization_id: string | null
          output: Json | null
          started_at: string | null
          status: string
          subject_id: string | null
          subject_type: string | null
          trigger_event_id: string | null
          trigger_kind: string
          updated_at: string
          workflow_run_id: string | null
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          definition_id: string
          definition_version?: number
          error?: Json | null
          graph_snapshot?: NonNullable<Json>
          id?: string
          idempotency_key?: string | null
          input?: NonNullable<Json>
          organization_id?: string | null
          output?: Json | null
          started_at?: string | null
          status?: string
          subject_id?: string | null
          subject_type?: string | null
          trigger_event_id?: string | null
          trigger_kind: string
          updated_at?: string
          workflow_run_id?: string | null
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          definition_id?: string
          definition_version?: number
          error?: Json | null
          graph_snapshot?: NonNullable<Json>
          id?: string
          idempotency_key?: string | null
          input?: NonNullable<Json>
          organization_id?: string | null
          output?: Json | null
          started_at?: string | null
          status?: string
          subject_id?: string | null
          subject_type?: string | null
          trigger_event_id?: string | null
          trigger_kind?: string
          updated_at?: string
          workflow_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "workflow_runs_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "workflow_definitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_runs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_runs_trigger_event_id_fkey"
            columns: ["trigger_event_id"]
            isOneToOne: false
            referencedRelation: "workflow_events"
            referencedColumns: ["id"]
          },
        ]
      }
      workflow_schedules: {
        Row: {
          created_at: string
          cron: string
          definition_id: string
          id: string
          last_run_at: string | null
          leased_until: string | null
          next_run_at: string
          node_id: string
          organization_id: string | null
          timezone: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          cron: string
          definition_id: string
          id?: string
          last_run_at?: string | null
          leased_until?: string | null
          next_run_at: string
          node_id: string
          organization_id?: string | null
          timezone?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          cron?: string
          definition_id?: string
          id?: string
          last_run_at?: string | null
          leased_until?: string | null
          next_run_at?: string
          node_id?: string
          organization_id?: string | null
          timezone?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "workflow_schedules_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "workflow_definitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workflow_schedules_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_organization_invitation: {
        Args: { p_token: string }
        Returns: Json
      }
      accept_quote_for_portal: {
        Args: {
          p_ip?: string
          p_org_slug: string
          p_payload: Json
          p_quote_id: string
          p_user_agent?: string
        }
        Returns: string
      }
      accrue_time_off: {
        Args: { p_on?: string; p_organization_id: string }
        Returns: number
      }
      acknowledge_equipment_assignment: {
        Args: { p_assignment_id: string }
        Returns: boolean
      }
      actor_may_assign_role: {
        Args: {
          p_actor_user_id: string
          p_organization_id: string
          p_role_id: string
        }
        Returns: boolean
      }
      add_task_material_from_quote: {
        Args: {
          p_organization_id: string
          p_product_id: string
          p_quantity: number
          p_quote_id: string
          p_task_id: string
        }
        Returns: string
      }
      agenda_default_time_zone: {
        Args: {
          p_organization_id: string
          p_prefer_profile?: boolean
          p_user_id?: string
        }
        Returns: string
      }
      agenda_user_has_org_permission: {
        Args: {
          p_organization_id: string
          p_permission: string
          p_user_id: string
        }
        Returns: boolean
      }
      allocate_order: {
        Args: { p_order_id: string; p_organization_id: string }
        Returns: Json
      }
      allocate_order_lines: {
        Args: { p_order_id: string; p_organization_id: string }
        Returns: Json
      }
      allocate_product_stock: {
        Args: {
          p_created_by: string
          p_invoice_id: string
          p_invoice_line_id: string
          p_location_id?: string
          p_order_line_id?: string
          p_organization_id: string
          p_product_id: string
          p_quantity: number
          p_quote_id: string
          p_quote_version_line_id: string
          p_reason: string
          p_task_material_id: string
        }
        Returns: number
      }
      allocate_username: {
        Args: { p_base: string; p_user_id: string }
        Returns: string
      }
      allocation_owner_quantity: {
        Args: {
          p_invoice_line_id: string
          p_organization_id: string
          p_quote_version_line_id: string
          p_state: Database["public"]["Enums"]["inventory_allocation_state"]
          p_task_material_id: string
        }
        Returns: number
      }
      allocation_owner_variant: {
        Args: {
          p_invoice_line_id: string
          p_order_line_id?: string
          p_product_id: string
          p_quote_version_line_id: string
          p_task_material_id: string
        }
        Returns: string
      }
      anonymize_expired_candidates: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      apply_task_material_consumption: {
        Args: {
          p_consume: boolean
          p_organization_id: string
          p_task_id: string
        }
        Returns: undefined
      }
      apply_task_parts_hold: {
        Args: { p_organization_id: string; p_task_id: string }
        Returns: undefined
      }
      assign_task_agenda_projection: {
        Args: {
          p_calendar_id: string
          p_ends_at: string
          p_organization_id: string
          p_starts_at: string
          p_task_id: string
          p_user_ids: string[]
        }
        Returns: string
      }
      attach_permissions: {
        Args: { p_permission_keys: string[]; p_role_id: string }
        Returns: undefined
      }
      authorize_scope: {
        Args: {
          p_permission: string
          p_scope: Database["public"]["Enums"]["scope_type"]
          p_scope_id: string
        }
        Returns: boolean
      }
      authorize_scope_batch: {
        Args: {
          p_permissions: string[]
          p_scope: Database["public"]["Enums"]["scope_type"]
          p_scope_id: string
        }
        Returns: string[]
      }
      begin_ai_chat_turn: {
        Args: {
          p_active_stream_id: string
          p_approval_responses: Json
          p_dispatch_id: string
          p_event_payload: Json
          p_expected_active_stream_id: string
          p_history_limit?: number
          p_message_id: string
          p_mode: string
          p_model: string
          p_organization_id: string
          p_request_id: string
          p_route: string
          p_run_id: string
          p_run_metadata: Json
          p_target_message_id: string
          p_thread_id: string
          p_trigger: string
          p_user_client_message_id: string
          p_user_message_parts: Json
        }
        Returns: Json
      }
      can_access_agent_run: { Args: { p_run_id: string }; Returns: boolean }
      can_access_employee: {
        Args: { p_employee_id: string; p_permission: string }
        Returns: boolean
      }
      can_access_file_storage_object: {
        Args: {
          p_bucket_id: string
          p_object_name: string
          p_operation: string
        }
        Returns: boolean
      }
      can_create_file_child: {
        Args: {
          p_drive_id: string
          p_organization_id: string
          p_parent_id: string
        }
        Returns: boolean
      }
      can_decide_approval_request: {
        Args: {
          p_request: Database["public"]["Tables"]["approval_requests"]["Row"]
        }
        Returns: boolean
      }
      can_emit_workflow_event: {
        Args: { p_organization_id: string }
        Returns: boolean
      }
      can_read_knowledge_collection_row: {
        Args: {
          p_collection_id: string
          p_created_by: string
          p_organization_id: string
          p_visibility: string
        }
        Returns: boolean
      }
      can_read_workflow_definition_row: {
        Args: {
          p_created_by: string
          p_definition_id: string
          p_organization_id: string
          p_owner_scope: string
          p_status: string
          p_visibility: string
        }
        Returns: boolean
      }
      cancel_order: {
        Args: {
          p_order_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Database["public"]["Enums"]["order_status"]
      }
      cancel_shipment: {
        Args: { p_organization_id: string; p_shipment_id: string }
        Returns: undefined
      }
      check_inventory_allocation_integrity: {
        Args: { p_organization_id: string }
        Returns: undefined
      }
      claim_agenda_external_calendars_for_sync: {
        Args: {
          p_limit?: number
          p_min_age_seconds?: number
          p_stale_seconds?: number
        }
        Returns: {
          agenda_collection_id: string
          organization_id: string
        }[]
      }
      claim_ai_agent_tool_checkpoint: {
        Args: {
          p_call_key: string
          p_input_hash: string
          p_run_id: string
          p_tool_name: string
        }
        Returns: Json
      }
      claim_ai_message_dispatch: {
        Args: {
          p_dispatch_id: string
          p_message_id: string
          p_organization_id: string
          p_thread_id: string
        }
        Returns: boolean
      }
      claim_due_people_reminders: {
        Args: { p_on: string }
        Returns: {
          due_on: string
          employee_id: string
          employee_name: string
          kind: string
          label: string
          organization_id: string
          recipient_user_ids: string[]
          subject_id: string
        }[]
      }
      claim_due_workflow_schedules: {
        Args: { p_lease_for_ms?: number; p_limit?: number; p_now: string }
        Returns: {
          created_at: string
          cron: string
          definition_id: string
          id: string
          last_run_at: string | null
          leased_until: string | null
          next_run_at: string
          node_id: string
          organization_id: string | null
          timezone: string
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "workflow_schedules"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      claim_inbox_automation: {
        Args: {
          p_channel_thread_id: string
          p_lease_seconds?: number
          p_lease_token: string
          p_organization_id: string
          p_source_message_id: string
        }
        Returns: Json
      }
      claim_inbox_webhook_jobs: {
        Args: { p_lease_seconds?: number; p_limit?: number }
        Returns: {
          available_at: string
          connection_id: string
          continuation_cursor: string | null
          created_at: string
          id: string
          last_error: string | null
          leased_until: string | null
          organization_id: string
          payload: NonNullable<Json>
          processed_at: string | null
          provider: string
          provider_cursor: string | null
          provider_delivery_id: string
          retry_count: number
          status: string
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "inbox_webhook_jobs"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      claim_stripe_webhook_event: {
        Args: {
          p_livemode: boolean
          p_stripe_created_at: string
          p_stripe_event_id: string
          p_type: string
        }
        Returns: {
          claim_id: string
          disposition: string
          event_id: string
          processing_started_at: string
        }[]
      }
      claim_webhook_deliveries: {
        Args: { p_lease_seconds?: number; p_limit?: number }
        Returns: {
          attempt: number
          available_at: string
          created_at: string
          destination_id: string
          duration_ms: number | null
          event_id: string | null
          event_kind: string
          id: string
          last_error: string | null
          leased_until: string | null
          organization_id: string
          payload: NonNullable<Json>
          processed_at: string | null
          response_body: string | null
          response_status: number | null
          status: string
          updated_at: string
          workflow_run_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "webhook_deliveries"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      close_purchase_order_short: {
        Args: { p_organization_id: string; p_purchase_order_id: string }
        Returns: undefined
      }
      commit_promotion_redemptions: {
        Args: {
          p_subject_id: string
          p_subject_type: Database["public"]["Enums"]["promotion_subject_type"]
        }
        Returns: undefined
      }
      complete_stripe_webhook_event: {
        Args: {
          p_claim_id: string
          p_error_message?: string
          p_event_id: string
          p_succeeded: boolean
        }
        Returns: boolean
      }
      compute_customer_sort_name: {
        Args: { p_customer_id: number }
        Returns: string
      }
      compute_time_off_hours: {
        Args: {
          p_employee_id: string
          p_end_part: Database["public"]["Enums"]["time_off_partial_day"]
          p_end_time?: string
          p_ends_on: string
          p_start_part: Database["public"]["Enums"]["time_off_partial_day"]
          p_start_time?: string
          p_starts_on: string
        }
        Returns: number
      }
      confirm_order: {
        Args: { p_order_id: string; p_organization_id: string }
        Returns: Json
      }
      consume_allocations: {
        Args: {
          p_created_by: string
          p_invoice_id: string
          p_invoice_line_id: string
          p_organization_id: string
          p_quote_id: string
          p_quote_version_line_id: string
          p_reason: string
          p_task_material_id: string
        }
        Returns: number
      }
      consume_approval_request: {
        Args: { p_input_fingerprint?: string; p_request_id: string }
        Returns: {
          action_key: string
          agent_run_id: string | null
          agent_step_id: string | null
          allow_self: boolean
          approver_employee_id: string | null
          approver_mode: Database["public"]["Enums"]["approval_approver_mode"]
          approver_permission: string | null
          approver_user_id: string | null
          approver_user_ids: string[]
          consumed_at: string | null
          decided_at: string | null
          decision_reason: string | null
          employee_id: string | null
          escalate_at: string | null
          escalate_to_permission: string | null
          escalated_at: string | null
          expires_at: string | null
          explanation: Json | null
          id: string
          input: NonNullable<Json>
          input_fingerprint: string | null
          metadata: NonNullable<Json>
          on_behalf_of_user_id: string | null
          organization_id: string | null
          policy: NonNullable<Json>
          quorum: number
          requested_at: string
          requested_by: string | null
          requester_kind: Database["public"]["Enums"]["approval_actor_kind"]
          requirement: Database["public"]["Enums"]["approval_requirement"]
          response_active_stream_id: string | null
          response_approved: boolean | null
          response_idempotency_key: string | null
          response_message_id: string | null
          response_reason: string | null
          response_recorded_at: string | null
          response_run_id: string | null
          response_tool_call_id: string | null
          response_workflow_run_id: string | null
          risk: string
          source: Database["public"]["Enums"]["approval_source"]
          status: string
          step: number
          subject_id: string | null
          subject_type: string | null
          thread_id: string | null
          title: string | null
          tool_call_id: string | null
          tool_name: string | null
          updated_at: string
          workflow_node_id: string | null
          workflow_run_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "approval_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      consume_free_product_stock: {
        Args: {
          p_created_by: string
          p_invoice_id: string
          p_invoice_line_id: string
          p_organization_id: string
          p_product_id: string
          p_quantity: number
          p_reason: string
        }
        Returns: number
      }
      copy_comment_thread: {
        Args: {
          p_from_subject_id: string
          p_from_subject_type: string
          p_organization_id: string
          p_to_subject_id: string
          p_to_subject_type: string
        }
        Returns: undefined
      }
      count_unread_inbox_threads: {
        Args: { p_organization_id: string }
        Returns: number
      }
      create_agenda_item_aggregate: {
        Args: {
          p_item: Json
          p_metadata: Json
          p_organization_id: string
          p_user_ids: string[]
        }
        Returns: string
      }
      create_ai_contextual_artifact: {
        Args: {
          p_action_id: string
          p_action_version: string
          p_actor_user_id: string
          p_apply_handler: string
          p_context_fingerprint: string
          p_context_kinds: Json
          p_idempotency_key: string
          p_kind: string
          p_message_id: string
          p_organization_id: string
          p_origin_execution_policy: string
          p_origin_permission: string
          p_origin_risk: string
          p_origin_route: string
          p_payload: Json
          p_run_id: string
          p_schema_version: number
          p_source_references: Json
          p_thread_id: string
        }
        Returns: Json
      }
      create_customer_contact: {
        Args: {
          p_customer_id: number
          p_display_name: string
          p_email: string
          p_first_name: string
          p_is_primary: boolean
          p_job_title: string
          p_last_name: string
          p_org_id: string
          p_phone: string
        }
        Returns: string
      }
      create_file_copy_operation: {
        Args: {
          p_conflict_strategy?: string
          p_destination_drive_id: string
          p_destination_parent_id: string
          p_idempotency_key: string
          p_operation_id: string
          p_organization_id: string
          p_source_node_ids: string[]
        }
        Returns: {
          completed_at: string | null
          completed_items: number
          conflict_strategy: string
          created_at: string
          created_by: string
          destination_drive_id: string
          destination_parent_id: string | null
          error_message: string | null
          id: string
          idempotency_key: string
          organization_id: string
          source_node_ids: string[]
          started_at: string | null
          status: string
          total_items: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "file_copy_operations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_file_version: {
        Args: {
          p_byte_size: number
          p_checksum?: string
          p_etag?: string
          p_media_type: string
          p_node_id: string
          p_source_modified_at?: string
          p_storage_bucket: string
          p_storage_path: string
        }
        Returns: {
          byte_size: number
          checksum: string | null
          created_at: string
          created_by: string | null
          drive_id: string
          etag: string | null
          id: string
          legal_hold_until: string | null
          media_type: string
          node_id: string
          organization_id: string
          retention_until: string
          source_modified_at: string | null
          storage_bucket: string
          storage_path: string
          version_number: number
        }
        SetofOptions: {
          from: "*"
          to: "file_versions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_file_zip_export: {
        Args: {
          p_direct_max_bytes: number
          p_direct_max_items: number
          p_export_id: string
          p_file_name: string
          p_idempotency_key: string
          p_organization_id: string
          p_source_node_ids: string[]
        }
        Returns: {
          artifact_expires_at: string | null
          artifact_storage_bucket: string | null
          artifact_storage_path: string | null
          completed_at: string | null
          completed_items: number
          created_at: string
          created_by: string
          delivery_mode: string
          error_message: string | null
          file_name: string
          id: string
          idempotency_key: string
          organization_id: string
          source_node_ids: string[]
          started_at: string | null
          status: string
          total_bytes: number
          total_items: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "file_zip_exports"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_invoice_aggregate: {
        Args: {
          p_header: Json
          p_lines: Json
          p_organization_id: string
          p_task_ids: string[]
        }
        Returns: string
      }
      create_organization_for_current_user: {
        Args: {
          p_address_city?: string
          p_address_country?: string
          p_address_line1?: string
          p_address_line2?: string
          p_address_postal_code?: string
          p_address_state?: string
          p_brand_primary_color?: string
          p_brand_secondary_color?: string
          p_name: string
          p_slug: string
          p_socials?: Json
          p_website?: string
        }
        Returns: string
      }
      create_purchase_orders_from_reorder: {
        Args: { p_organization_id: string; p_variant_ids?: string[] }
        Returns: string[]
      }
      create_shipment: {
        Args: {
          p_direction: Database["public"]["Enums"]["shipment_direction"]
          p_header?: Json
          p_lines?: Json
          p_order_id?: string
          p_organization_id: string
          p_purchase_order_id?: string
        }
        Returns: string
      }
      current_employee_id: {
        Args: { p_organization_id: string }
        Returns: string
      }
      custom_access_token_hook: { Args: { event: Json }; Returns: Json }
      customer_portal_assert_access: {
        Args: { p_organization_id: string }
        Returns: undefined
      }
      customer_portal_get_asset: {
        Args: { p_customer_asset_id: number; p_organization_id: string }
        Returns: Json
      }
      customer_portal_get_context: {
        Args: { p_organization_slug: string }
        Returns: Json
      }
      customer_portal_get_dashboard: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      customer_portal_get_invoice: {
        Args: { p_invoice_id: string; p_organization_id: string }
        Returns: Json
      }
      customer_portal_get_order: {
        Args: { p_order_id: string; p_organization_id: string }
        Returns: Json
      }
      customer_portal_get_quote: {
        Args: { p_organization_id: string; p_quote_id: string }
        Returns: Json
      }
      customer_portal_list_assets: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      customer_portal_list_invoices: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      customer_portal_list_orders: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      customer_portal_list_organizations: {
        Args: Record<PropertyKey, never>
        Returns: Json
      }
      customer_portal_list_quotes: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      customer_portal_open_download: {
        Args: { p_grant_id: string; p_organization_id: string }
        Returns: Json
      }
      decide_ai_contextual_artifact: {
        Args: {
          p_apply_claim_id: string
          p_artifact_id: string
          p_decision: string
          p_expected_context_fingerprint: string
          p_idempotency_key: string
          p_metadata: Json
        }
        Returns: Json
      }
      decide_approval_request: {
        Args: { p_approved: boolean; p_comment?: string; p_request_id: string }
        Returns: {
          action_key: string
          agent_run_id: string | null
          agent_step_id: string | null
          allow_self: boolean
          approver_employee_id: string | null
          approver_mode: Database["public"]["Enums"]["approval_approver_mode"]
          approver_permission: string | null
          approver_user_id: string | null
          approver_user_ids: string[]
          consumed_at: string | null
          decided_at: string | null
          decision_reason: string | null
          employee_id: string | null
          escalate_at: string | null
          escalate_to_permission: string | null
          escalated_at: string | null
          expires_at: string | null
          explanation: Json | null
          id: string
          input: NonNullable<Json>
          input_fingerprint: string | null
          metadata: NonNullable<Json>
          on_behalf_of_user_id: string | null
          organization_id: string | null
          policy: NonNullable<Json>
          quorum: number
          requested_at: string
          requested_by: string | null
          requester_kind: Database["public"]["Enums"]["approval_actor_kind"]
          requirement: Database["public"]["Enums"]["approval_requirement"]
          response_active_stream_id: string | null
          response_approved: boolean | null
          response_idempotency_key: string | null
          response_message_id: string | null
          response_reason: string | null
          response_recorded_at: string | null
          response_run_id: string | null
          response_tool_call_id: string | null
          response_workflow_run_id: string | null
          risk: string
          source: Database["public"]["Enums"]["approval_source"]
          status: string
          step: number
          subject_id: string | null
          subject_type: string | null
          thread_id: string | null
          title: string | null
          tool_call_id: string | null
          tool_name: string | null
          updated_at: string
          workflow_node_id: string | null
          workflow_run_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "approval_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      delete_organization_for_current_user: {
        Args: { p_organization_id: string }
        Returns: undefined
      }
      delete_task_material: {
        Args: { p_organization_id: string; p_task_material_id: string }
        Returns: undefined
      }
      derive_username_base: {
        Args: {
          p_email: string
          p_first_name: string
          p_full_name: string
          p_last_name: string
        }
        Returns: string
      }
      easter_sunday: { Args: { p_year: number }; Returns: string }
      employee_contract_on: {
        Args: { p_date: string; p_employee_id: string }
        Returns: {
          created_at: string
          created_by: string | null
          currency: string
          document_storage_path: string | null
          employee_id: string
          ending_notified_at: string | null
          ends_on: string | null
          holiday_allowance_pct: number
          hours_per_week: number | null
          id: string
          is_flexible: boolean
          leave_entitlement_hours_override: number | null
          notes: string | null
          notice_period_days: number | null
          organization_id: string
          pay_amount: number | null
          pay_basis: Database["public"]["Enums"]["employee_pay_basis"]
          pay_frequency: Database["public"]["Enums"]["employee_pay_frequency"]
          probation_ends_on: string | null
          signature_provider: string | null
          signature_request_id: string | null
          signed_at: string | null
          starts_on: string
          type: Database["public"]["Enums"]["employee_contract_type"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "employee_contracts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      employee_cycle_week: {
        Args: { p_date: string; p_employee_id: string }
        Returns: number
      }
      employee_hourly_cost: {
        Args: { p_date: string; p_employee_id: string }
        Returns: number
      }
      employee_scheduled_hours: {
        Args: { p_date: string; p_employee_id: string }
        Returns: number
      }
      employee_week_summary: {
        Args: { p_employee_id: string; p_week_start: string }
        Returns: {
          day: string
          is_holiday: boolean
          logged_hours: number
          scheduled_hours: number
          time_off_hours: number
        }[]
      }
      ensure_agenda_planning_calendar: {
        Args: { p_organization_id: string }
        Returns: string
      }
      ensure_all_permissions: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      ensure_comment_thread: {
        Args: {
          p_customer_asset_id?: number
          p_customer_id?: number
          p_organization_id: string
          p_subject_id: string
          p_subject_type: string
          p_task_id?: string
        }
        Returns: string
      }
      ensure_contact_profile_for_user: {
        Args: { p_user_id: string }
        Returns: string
      }
      ensure_customer_file_folder: {
        Args: { p_customer_id: number; p_organization_id: string }
        Returns: {
          created_at: string
          created_by: string | null
          current_version_id: string | null
          customer_id: number | null
          deleted_at: string | null
          deleted_by: string | null
          deletion_batch_id: string | null
          drive_id: string
          external_id: string | null
          external_metadata: NonNullable<Json>
          id: string
          kind: string
          legal_hold_until: string | null
          name: string
          organization_id: string
          parent_id: string | null
          purge_after: string | null
          source: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "file_nodes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ensure_customer_file_folders: {
        Args: { p_organization_id: string }
        Returns: number
      }
      ensure_customers_file_drive: {
        Args: { p_organization_id: string }
        Returns: string
      }
      ensure_notification_subscription: {
        Args: {
          p_organization_id: string
          p_subject_id: string
          p_subject_type: string
          p_user_id: string
        }
        Returns: string
      }
      ensure_people_defaults: {
        Args: { p_organization_id: string }
        Returns: undefined
      }
      ensure_system_roles: {
        Args: Record<PropertyKey, never>
        Returns: undefined
      }
      ensure_user_file_drives: {
        Args: { p_organization_id: string }
        Returns: {
          company_drive_id: string
          personal_drive_id: string
        }[]
      }
      evaluate_promotion: {
        Args: {
          p_code?: string
          p_customer_id: number
          p_organization_id: string
          p_promotion_id?: string
          p_quantity?: number
          p_subject_id?: string
          p_subject_type: Database["public"]["Enums"]["promotion_subject_type"]
          p_subtotal?: number
        }
        Returns: Json
      }
      file_access_role_rank: { Args: { p_role: string }; Returns: number }
      fill_backorders: {
        Args: {
          p_location_id?: string
          p_organization_id: string
          p_variant_id: string
        }
        Returns: number
      }
      fill_variant_backorders: {
        Args: {
          p_location_id: string
          p_organization_id: string
          p_variant_id: string
        }
        Returns: number
      }
      finalize_file_copy_item: {
        Args: {
          p_item_id: string
          p_storage_bucket: string
          p_storage_path: string
        }
        Returns: {
          created_at: string
          error_message: string | null
          id: string
          operation_id: string
          organization_id: string
          source_node_id: string
          source_version_id: string | null
          status: string
          target_node_id: string
          target_storage_path: string | null
          target_version_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "file_copy_operation_items"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      finalize_file_upload: {
        Args: {
          p_actual_bytes: number
          p_checksum?: string
          p_etag?: string
          p_reservation_id: string
        }
        Returns: {
          actual_bytes: number | null
          checksum: string | null
          created_at: string
          created_by: string
          drive_id: string
          etag: string | null
          expected_bytes: number
          expires_at: string
          file_name: string
          finalized_at: string | null
          finalized_version_id: string | null
          id: string
          idempotency_key: string
          media_type: string
          node_id: string | null
          organization_id: string
          parent_id: string | null
          status: string
          storage_bucket: string
          storage_path: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "file_upload_reservations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      find_expense_duplicates: {
        Args: { p_expense_id: string }
        Returns: {
          expense_id: string
          reason: string
        }[]
      }
      finish_ai_agent_tool: {
        Args: {
          p_active_stream_id: string
          p_actor_user_id: string
          p_completed_at: string
          p_duration_ms: number
          p_error: Json
          p_metadata: Json
          p_model: string
          p_organization_id: string
          p_output: Json
          p_request_id: string
          p_run_id: string
          p_status: string
          p_step_id: string
          p_thread_id: string
          p_title: string
          p_tool_call_id: string
          p_tool_name: string
          p_workflow_run_id: string
        }
        Returns: boolean
      }
      finish_inbox_automation: {
        Args: {
          p_channel_thread_id: string
          p_lease_token: string
          p_payload: Json
          p_source_message_id: string
          p_status: string
        }
        Returns: boolean
      }
      fulfill_digital_order: {
        Args: { p_order_id: string; p_organization_id: string }
        Returns: Json
      }
      get_admin_analytics: {
        Args: {
          p_comparison: string
          p_currencies: string[]
          p_end_date: string
          p_granularity: string
          p_start_date: string
          p_time_zone: string
        }
        Returns: Json
      }
      get_admin_operations_attention: {
        Args: { p_now?: string }
        Returns: Json
      }
      get_admin_operations_metrics: { Args: { p_now?: string }; Returns: Json }
      get_admin_operations_plans: { Args: { p_now?: string }; Returns: Json }
      get_agenda_feed_by_token: { Args: { p_token: string }; Returns: Json }
      get_ai_agent_execution_manifest: {
        Args: {
          p_active_stream_id: string
          p_actor_user_id: string
          p_delegation_id: string
          p_organization_id: string
          p_run_id: string
          p_thread_id: string
          p_workflow_run_id: string
        }
        Returns: {
          authorized_integration_ids: string[]
          organization_permission_keys: string[]
          system_permission_keys: string[]
        }[]
      }
      get_ai_chat_suggestion_snapshot: {
        Args: {
          p_organization_slug: string
          p_route_domain: string
          p_surface: string
        }
        Returns: Json
      }
      get_ai_usage_allowance: {
        Args: { p_at?: string; p_organization_id: string }
        Returns: {
          allowed: boolean
          code: string
          reason: string
        }[]
      }
      get_employee_history: {
        Args: { p_employee_id: string; p_limit?: number }
        Returns: {
          actor_display_name: string
          actor_id: string
          event_type: string
          id: string
          occurred_at: string
          target_id: string
          target_type: string
        }[]
      }
      get_file_node_path: {
        Args: { p_max_depth?: number; p_node_id: string }
        Returns: {
          created_at: string
          created_by: string
          current_version_id: string
          deleted_at: string
          depth: number
          drive_id: string
          external_id: string
          external_metadata: Json
          id: string
          kind: string
          name: string
          organization_id: string
          parent_id: string
          source: string
          updated_at: string
        }[]
      }
      get_file_retention_days: {
        Args: { p_organization_id: string }
        Returns: number
      }
      get_file_storage_quota_bytes: {
        Args: { p_organization_id: string }
        Returns: number
      }
      get_file_storage_summary: {
        Args: { p_organization_id: string }
        Returns: {
          available_bytes: number
          quota_bytes: number
          reserved_bytes: number
          retention_days: number
          segments: Json
          stored_bytes: number
        }[]
      }
      get_invitation_by_token: { Args: { p_token: string }; Returns: Json }
      get_invoice_for_portal: {
        Args: { p_invoice_id: string; p_org_slug: string }
        Returns: Json
      }
      get_organization_analytics: {
        Args: {
          p_comparison: string
          p_currencies: string[]
          p_end_date: string
          p_granularity: string
          p_organization_id: string
          p_start_date: string
          p_time_zone: string
        }
        Returns: Json
      }
      get_organization_dashboard_totals: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_product_for_portal: {
        Args: { p_org_slug: string; p_product_id: string }
        Returns: Json
      }
      get_quote_for_portal: {
        Args: { p_org_slug: string; p_quote_id: string; p_version?: number }
        Returns: Json
      }
      get_time_off_feed_by_token: { Args: { p_token: string }; Returns: Json }
      has_agenda_collection_access: {
        Args: {
          p_calendar_id: string
          p_min_role?: string
          p_organization_id: string
        }
        Returns: boolean
      }
      has_any_org_permission: {
        Args: { p_org_id: string; p_permissions: string[] }
        Returns: boolean
      }
      has_chat_thread_access: {
        Args: { p_thread_id: string }
        Returns: boolean
      }
      has_comment_subject_permission: {
        Args: {
          p_action: string
          p_organization_id: string
          p_subject_type: string
        }
        Returns: boolean
      }
      has_comment_thread_permission: {
        Args: { p_action: string; p_thread_id: string }
        Returns: boolean
      }
      has_file_drive_access: {
        Args: { p_drive_id: string; p_min_role?: string }
        Returns: boolean
      }
      has_file_node_access: {
        Args: { p_min_role?: string; p_node_id: string }
        Returns: boolean
      }
      has_knowledge_collection_access: {
        Args: { p_collection_id: string }
        Returns: boolean
      }
      has_org_permission: {
        Args: { p_org_id: string; p_permission: string }
        Returns: boolean
      }
      has_workflow_definition_access: {
        Args: { p_definition_id: string }
        Returns: boolean
      }
      has_workflow_run_access: { Args: { p_run_id: string }; Returns: boolean }
      hydrate_task_list_items: { Args: { p_task_ids: string[] }; Returns: Json }
      inventory_reorder_suggestions: {
        Args: { p_organization_id: string }
        Returns: {
          available: number
          currency: string
          incoming: number
          product_id: string
          product_name: string
          product_supplier_link_id: string
          reorder_point: number
          sku: string
          suggested_quantity: number
          supplier_id: string
          supplier_name: string
          supplier_sku: string
          unit_cost: number
          variant_id: string
          variant_title: string
        }[]
      }
      inventory_variant_incoming: {
        Args: { p_variant_id: string }
        Returns: number
      }
      inventory_variant_levels: {
        Args: { p_organization_id: string; p_product_ids?: string[] }
        Returns: {
          allocated: number
          available: number
          backordered: number
          incoming: number
          is_default: boolean
          on_hand: number
          product_id: string
          reorder_point: number
          sku: string
          stock_status: string
          variant_id: string
          variant_position: number
          variant_title: string
        }[]
      }
      is_agenda_collection_subscribed: {
        Args: { p_calendar_id: string; p_organization_id: string }
        Returns: boolean
      }
      is_approval_approver: {
        Args: {
          p_request: Database["public"]["Tables"]["approval_requests"]["Row"]
        }
        Returns: boolean
      }
      is_approval_requester: {
        Args: {
          p_request: Database["public"]["Tables"]["approval_requests"]["Row"]
        }
        Returns: boolean
      }
      is_employee_manager_of: {
        Args: { p_employee_id: string }
        Returns: boolean
      }
      is_org_staff_member: {
        Args: { p_organization_id: string }
        Returns: boolean
      }
      is_own_employee: { Args: { p_employee_id: string }; Returns: boolean }
      is_system_user_with: { Args: { p_permission: string }; Returns: boolean }
      lifecycle_subject_view_permission: {
        Args: { p_subject_type: string }
        Returns: string
      }
      link_ai_agent_workflow_ownership: {
        Args: {
          p_active_stream_id: string
          p_dispatch_id: string
          p_message_id: string
          p_organization_id: string
          p_run_id: string
          p_thread_id: string
          p_workflow_run_id: string
        }
        Returns: boolean
      }
      link_ai_message_dispatch: {
        Args: {
          p_dispatch_id: string
          p_message_id: string
          p_organization_id: string
          p_thread_id: string
          p_workflow_run_id: string
        }
        Returns: boolean
      }
      link_expenses_to_invoice: {
        Args: {
          p_expense_ids: string[]
          p_invoice_id: string
          p_organization_id: string
        }
        Returns: number
      }
      list_admin_billing: {
        Args: {
          p_limit?: number
          p_offset?: number
          p_plan_keys?: string[]
          p_search?: string
          p_statuses?: string[]
        }
        Returns: Json
      }
      list_agenda_collections_for_user: {
        Args: { p_calendar_id?: string; p_organization_id: string }
        Returns: {
          can_edit: boolean
          can_manage: boolean
          color: string
          created_at: string
          created_by: string
          default_time_zone: string
          description: string
          external_calendar_id: string
          id: string
          is_default: boolean
          is_subscribed: boolean
          kind: string
          name: string
          organization_id: string
          owner_user_id: string
          position: number
          pref_is_visible: boolean
          pref_position: number
          source: string
          updated_at: string
          visibility: string
        }[]
      }
      list_decidable_approval_requests: {
        Args: { p_limit?: number; p_organization_id: string }
        Returns: {
          action_key: string
          agent_run_id: string | null
          agent_step_id: string | null
          allow_self: boolean
          approver_employee_id: string | null
          approver_mode: Database["public"]["Enums"]["approval_approver_mode"]
          approver_permission: string | null
          approver_user_id: string | null
          approver_user_ids: string[]
          consumed_at: string | null
          decided_at: string | null
          decision_reason: string | null
          employee_id: string | null
          escalate_at: string | null
          escalate_to_permission: string | null
          escalated_at: string | null
          expires_at: string | null
          explanation: Json | null
          id: string
          input: NonNullable<Json>
          input_fingerprint: string | null
          metadata: NonNullable<Json>
          on_behalf_of_user_id: string | null
          organization_id: string | null
          policy: NonNullable<Json>
          quorum: number
          requested_at: string
          requested_by: string | null
          requester_kind: Database["public"]["Enums"]["approval_actor_kind"]
          requirement: Database["public"]["Enums"]["approval_requirement"]
          response_active_stream_id: string | null
          response_approved: boolean | null
          response_idempotency_key: string | null
          response_message_id: string | null
          response_reason: string | null
          response_recorded_at: string | null
          response_run_id: string | null
          response_tool_call_id: string | null
          response_workflow_run_id: string | null
          risk: string
          source: Database["public"]["Enums"]["approval_source"]
          status: string
          step: number
          subject_id: string | null
          subject_type: string | null
          thread_id: string | null
          title: string | null
          tool_call_id: string | null
          tool_name: string | null
          updated_at: string
          workflow_node_id: string | null
          workflow_run_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "approval_requests"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_document_promotions: {
        Args: {
          p_customer_id: number
          p_organization_id: string
          p_subject_type: Database["public"]["Enums"]["promotion_subject_type"]
        }
        Returns: Json
      }
      list_inbox_threads: {
        Args: { p_limit?: number; p_offset?: number; p_organization_id: string }
        Returns: {
          archived_at: string
          assigned_team_id: number
          assigned_user_id: string
          chat_thread_id: string
          chat_thread_title: string
          connection_id: string
          connection_kind: string
          connection_name: string
          connection_status: string
          contact_avatar_path: string
          contact_display_name: string
          contact_email: string
          contact_first_name: string
          contact_last_name: string
          contact_phone: string
          continuation_cursor: string
          created_at: string
          customer_id: number
          external_actor_id: string
          external_channel_id: string
          external_thread_id: string
          id: string
          last_delivery_error: string
          last_delivery_status: string
          last_message_at: string
          last_message_id: string
          last_message_role: string
          last_message_text: string
          metadata: Json
          organization_id: string
          pinned_at: string
          read_at: string
          stream_status: string
          takeover_at: string
          takeover_reason: string
          takeover_status: string
          unread: boolean
          updated_at: string
        }[]
      }
      list_notification_ignored_user_ids: {
        Args: {
          p_organization_id: string
          p_subject_id: string
          p_subject_type: string
        }
        Returns: string[]
      }
      list_notification_subscriber_user_ids: {
        Args: {
          p_activity?: string
          p_organization_id: string
          p_subject_id: string
          p_subject_type: string
        }
        Returns: string[]
      }
      list_org_working_hour_profiles: {
        Args: { p_organization_id: string }
        Returns: {
          employee_id: string
          is_flexible: boolean
          schedule_cycle_anchor: string
          timezone: string
          user_id: string
        }[]
      }
      list_promotions: { Args: { p_organization_id: string }; Returns: Json }
      list_workflow_fan_out_organizations: {
        Args: { p_definition_key: string }
        Returns: string[]
      }
      lock_product_stock: {
        Args: { p_organization_id: string; p_product_id: string }
        Returns: undefined
      }
      managed_employee_ids: {
        Args: { p_organization_id: string }
        Returns: string[]
      }
      mark_ai_memory_items_used: {
        Args: { p_memory_ids: string[]; p_used_at: string; p_why_used: string }
        Returns: number
      }
      mark_organization_used_for_current_user: {
        Args: { p_organization_id: string }
        Returns: undefined
      }
      move_file_node: {
        Args: { p_node_id: string; p_parent_id: string }
        Returns: {
          created_at: string
          created_by: string | null
          current_version_id: string | null
          customer_id: number | null
          deleted_at: string | null
          deleted_by: string | null
          deletion_batch_id: string | null
          drive_id: string
          external_id: string | null
          external_metadata: NonNullable<Json>
          id: string
          kind: string
          legal_hold_until: string | null
          name: string
          organization_id: string
          parent_id: string | null
          purge_after: string | null
          source: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "file_nodes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      next_organization_number: {
        Args: { p_entity: string; p_organization_id: string; p_period?: string }
        Returns: number
      }
      normalize_username_component: {
        Args: { p_value: string }
        Returns: string
      }
      order_digital_overview: {
        Args: { p_order_id: string; p_organization_id: string }
        Returns: Json
      }
      order_line_progress: {
        Args: { p_order_id: string; p_organization_id: string }
        Returns: {
          allocated: number
          backordered: number
          fulfilled: number
          invoiced: number
          order_line_id: string
          returned: number
        }[]
      }
      org_permission_holder_user_ids: {
        Args: { p_organization_id: string; p_permission: string }
        Returns: string[]
      }
      patch_ai_message_outbox_metadata: {
        Args: {
          p_active_stream_id: string
          p_actor_user_id: string
          p_expected_state: string
          p_message_id: string
          p_organization_id: string
          p_run_id: string
          p_state: string
          p_thread_id: string
          p_workflow_run_id: string
        }
        Returns: boolean
      }
      process_open_sick_leave: {
        Args: { p_on?: string }
        Returns: {
          case_id: string
          employee_id: string
          needs_follow_up: boolean
          organization_id: string
          reported_on: string
        }[]
      }
      product_default_variant_id: {
        Args: { p_product_id: string }
        Returns: string
      }
      promotion_document_basis: {
        Args: {
          p_subject_id: string
          p_subject_type: Database["public"]["Enums"]["promotion_subject_type"]
        }
        Returns: Record<string, unknown>
      }
      promotion_is_inherited: {
        Args: { p_promotion_id: string; p_row: Json; p_table: string }
        Returns: boolean
      }
      promotion_redemption_amount: {
        Args: {
          p_promotion_id: string
          p_subject_id: string
          p_subject_type: Database["public"]["Enums"]["promotion_subject_type"]
        }
        Returns: number
      }
      promotion_rejection: {
        Args: {
          p_check_limits?: boolean
          p_customer_id: number
          p_promotion_id: string
          p_quantity?: number
          p_subject_id?: string
          p_subject_type: Database["public"]["Enums"]["promotion_subject_type"]
          p_subtotal?: number
        }
        Returns: string
      }
      publish_quote_version: {
        Args: { p_actor_user_id?: string; p_quote_id: string }
        Returns: number
      }
      publish_workflow_definition: {
        Args: { p_definition_id: string }
        Returns: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          description: string | null
          forked_from_definition_id: string | null
          forked_from_version: number | null
          graph: NonNullable<Json>
          id: string
          is_default: boolean
          key: string
          metadata: NonNullable<Json>
          name: string
          organization_id: string | null
          owner_scope: string
          published_at: string | null
          purpose: string
          status: string
          subject_type: string | null
          updated_at: string
          version: number
          visibility: string
        }
        SetofOptions: {
          from: "*"
          to: "workflow_definitions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      purge_expired_audit_logs: {
        Args: { p_batch_size?: number; p_now?: string }
        Returns: number
      }
      rbac_trusted_assignment_active: {
        Args: Record<PropertyKey, never>
        Returns: boolean
      }
      reassign_personal_file_drive: {
        Args: { p_drive_id: string; p_new_owner_user_id: string }
        Returns: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          drive_type: string
          id: string
          lifecycle_state: string
          name: string
          organization_id: string
          owner_released_at: string | null
          owner_user_id: string | null
          purge_after: string | null
          trashed_at: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "file_drives"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      receive_inbound_shipment: {
        Args: {
          p_location_id?: string
          p_organization_id: string
          p_shipment_id: string
        }
        Returns: Json
      }
      receive_purchase_order: {
        Args: {
          p_allow_over_receipt?: boolean
          p_lines: Json
          p_location_id?: string
          p_organization_id: string
          p_purchase_order_id: string
          p_shipment_id?: string
        }
        Returns: Json
      }
      receive_return_shipment: {
        Args: {
          p_location_id?: string
          p_organization_id: string
          p_shipment_id: string
        }
        Returns: Json
      }
      recompute_invoice_amounts: {
        Args: { p_invoice_id: string }
        Returns: undefined
      }
      recompute_invoice_totals: {
        Args: { p_invoice_id: string }
        Returns: undefined
      }
      recompute_order_totals: {
        Args: { p_order_id: string }
        Returns: undefined
      }
      recompute_purchase_order_totals: {
        Args: { p_purchase_order_id: string }
        Returns: undefined
      }
      recompute_quote_totals: {
        Args: { p_quote_id: string; p_selected_optional_line_ids?: Json }
        Returns: undefined
      }
      reconcile_owner_allocations: {
        Args: {
          p_created_by: string
          p_invoice_id: string
          p_invoice_line_id: string
          p_organization_id: string
          p_product_id: string
          p_quote_id: string
          p_quote_version_line_id: string
          p_reason: string
          p_target_quantity: number
          p_task_material_id: string
        }
        Returns: number
      }
      reconcile_quote_version_stock: {
        Args: {
          p_actor_user_id: string
          p_quote_id: string
          p_version_id: string
        }
        Returns: undefined
      }
      record_ai_turn_usage: {
        Args: {
          p_at?: string
          p_duration_ms: number
          p_function_id: string
          p_idempotency_key: string
          p_input_tokens: number
          p_metadata: Json
          p_model: string
          p_name: string
          p_organization_id: string
          p_output_tokens: number
          p_provider: string
          p_request_id: string
          p_source_id: string
          p_status: string
          p_thread_id: string
          p_user_id: string
          p_workflow_run_id: string
        }
        Returns: Json
      }
      record_audit_log_event: {
        Args: {
          p_actor_display_name: string
          p_actor_id: string
          p_actor_is_platform_admin: boolean
          p_actor_kind: string
          p_category: string
          p_correlation_id?: string
          p_event_type: string
          p_idempotency_key?: string
          p_ip_address?: unknown
          p_organization_id: string
          p_outcome: string
          p_request_id?: string
          p_restricted_metadata?: Json
          p_safe_metadata?: Json
          p_scope: string
          p_session_id?: string
          p_source: string
          p_summary?: string
          p_target_display_name?: string
          p_target_id?: string
          p_target_type?: string
          p_user_agent?: string
        }
        Returns: string
      }
      record_document_view: {
        Args: {
          p_org_slug: string
          p_subject_id: string
          p_subject_type: Database["public"]["Enums"]["document_view_subject_type"]
        }
        Returns: number
      }
      record_usage_events_bulk: {
        Args: { p_at?: string; p_events: Json; p_organization_id: string }
        Returns: Json
      }
      refresh_ai_chat_suggestion_snapshot: {
        Args: { p_organization_id: string }
        Returns: boolean
      }
      refresh_customer_sort_name: {
        Args: { p_customer_id: number }
        Returns: undefined
      }
      refresh_integration_definition_usage_count: {
        Args: { target_definition_id: string }
        Returns: undefined
      }
      refresh_order_status: {
        Args: { p_order_id: string; p_organization_id: string }
        Returns: Database["public"]["Enums"]["order_status"]
      }
      refresh_purchase_order_status: {
        Args: { p_purchase_order_id: string }
        Returns: Database["public"]["Enums"]["purchase_order_status"]
      }
      reject_quote_for_portal: {
        Args: {
          p_ip?: string
          p_org_slug: string
          p_payload: Json
          p_quote_id: string
          p_user_agent?: string
        }
        Returns: string
      }
      release_ai_message_dispatch: {
        Args: {
          p_dispatch_id: string
          p_message_id: string
          p_organization_id: string
          p_thread_id: string
        }
        Returns: boolean
      }
      release_allocations: {
        Args: {
          p_created_by: string
          p_invoice_line_id: string
          p_organization_id: string
          p_quantity: number
          p_quote_version_line_id: string
          p_reason: string
          p_task_material_id: string
        }
        Returns: number
      }
      release_order_line_allocations: {
        Args: {
          p_order_line_id: string
          p_organization_id: string
          p_quantity: number
          p_reason: string
        }
        Returns: number
      }
      release_promotion_redemptions: {
        Args: {
          p_subject_id: string
          p_subject_type: Database["public"]["Enums"]["promotion_subject_type"]
        }
        Returns: undefined
      }
      release_quote_allocations: {
        Args: { p_organization_id: string; p_quote_id: string }
        Returns: undefined
      }
      remember_private_ai_memory: {
        Args: {
          p_confidence: number
          p_content: string
          p_embedding?: unknown
          p_expires_at: string
          p_kind: string
          p_metadata?: Json
          p_now?: string
          p_organization_id: string
          p_scope: string
          p_source: string
          p_subject_id: string
          p_subject_type: string
          p_thread_id: string
          p_user_id: string
        }
        Returns: {
          confidence: number
          content: string
          content_hash: string | null
          content_tsv: unknown
          created_at: string
          created_by: string | null
          deleted_at: string | null
          embedding: unknown
          expires_at: string | null
          id: string
          kind: string
          last_used_at: string | null
          metadata: NonNullable<Json>
          organization_id: string | null
          scope: string
          source: string
          subject_id: string
          subject_type: string
          thread_id: string | null
          updated_at: string
          use_count: number
          user_id: string | null
          visibility: string
        }
        SetofOptions: {
          from: "*"
          to: "ai_memory_items"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      replace_agenda_collection_grants: {
        Args: {
          p_calendar_id: string
          p_created_by?: string
          p_grants: Json
          p_organization_id: string
        }
        Returns: {
          agenda_collection_id: string
          created_at: string
          created_by: string | null
          id: string
          organization_id: string
          position: number
          role: string
          team_id: number | null
          updated_at: string
          user_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "agenda_collection_grants"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      replace_agenda_collection_notification_settings: {
        Args: {
          p_calendar_id: string
          p_organization_id: string
          p_preferences: Json
          p_reminders: Json
        }
        Returns: undefined
      }
      replace_agenda_item_children: {
        Args: {
          p_agenda_item_id: string
          p_metadata: Json
          p_organization_id: string
          p_user_ids: string[]
        }
        Returns: undefined
      }
      replace_customer_assignees: {
        Args: {
          p_customer_id: number
          p_organization_id: string
          p_user_ids: string[]
        }
        Returns: undefined
      }
      replace_invoice_aggregate_children: {
        Args: {
          p_invoice_id: string
          p_lines: Json
          p_organization_id: string
          p_replace_lines: boolean
          p_replace_tasks: boolean
          p_task_ids: string[]
        }
        Returns: undefined
      }
      replace_organization_ai_policy: {
        Args: {
          p_action_policies: Json
          p_organization_id: string
          p_policy: Json
        }
        Returns: boolean
      }
      replace_organization_vat_rates: {
        Args: { p_organization_id: string; p_rates: Json }
        Returns: undefined
      }
      replace_role_permissions: {
        Args: { p_permission_ids: string[]; p_role_id: string }
        Returns: undefined
      }
      replace_task_assignees: {
        Args: {
          p_organization_id: string
          p_task_id: string
          p_user_ids: string[]
        }
        Returns: undefined
      }
      replace_workflow_grants: {
        Args: {
          p_created_by?: string
          p_definition_id: string
          p_organization_id: string
          p_team_ids: number[]
          p_user_ids: string[]
        }
        Returns: {
          created_at: string
          created_by: string | null
          definition_id: string
          id: string
          organization_id: string
          team_id: number | null
          user_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "workflow_grants"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      request_quote_changes_for_portal: {
        Args: {
          p_ip?: string
          p_org_slug: string
          p_payload: Json
          p_quote_id: string
          p_user_agent?: string
        }
        Returns: string
      }
      reserve_file_upload: {
        Args: {
          p_drive_id: string
          p_expected_bytes: number
          p_expires_at: string
          p_file_name: string
          p_idempotency_key: string
          p_media_type: string
          p_node_id: string
          p_organization_id: string
          p_parent_id: string
          p_storage_bucket: string
          p_storage_path: string
        }
        Returns: {
          actual_bytes: number | null
          checksum: string | null
          created_at: string
          created_by: string
          drive_id: string
          etag: string | null
          expected_bytes: number
          expires_at: string
          file_name: string
          finalized_at: string | null
          finalized_version_id: string | null
          id: string
          idempotency_key: string
          media_type: string
          node_id: string | null
          organization_id: string
          parent_id: string | null
          status: string
          storage_bucket: string
          storage_path: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "file_upload_reservations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      resolve_actor_scope_permissions: {
        Args: {
          p_actor_user_id: string
          p_permissions: string[]
          p_scope: Database["public"]["Enums"]["scope_type"]
          p_scope_id: string
        }
        Returns: string[]
      }
      resolve_lifecycle_definition: {
        Args: {
          p_organization_id: string
          p_subject_type: string
          p_template_id?: string
        }
        Returns: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          description: string | null
          forked_from_definition_id: string | null
          forked_from_version: number | null
          graph: NonNullable<Json>
          id: string
          is_default: boolean
          key: string
          metadata: NonNullable<Json>
          name: string
          organization_id: string | null
          owner_scope: string
          published_at: string | null
          purpose: string
          status: string
          subject_type: string | null
          updated_at: string
          version: number
          visibility: string
        }
        SetofOptions: {
          from: "*"
          to: "workflow_definitions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      resolve_notification_recipients: {
        Args: {
          p_organization_id: string
          p_subject_id: string
          p_subject_type: string
          p_type: string
        }
        Returns: number
      }
      restore_allocations: {
        Args: {
          p_created_by: string
          p_invoice_id: string
          p_invoice_line_id: string
          p_organization_id: string
          p_quote_id: string
          p_quote_version_line_id: string
          p_reason: string
          p_task_material_id: string
        }
        Returns: number
      }
      restore_file_node: { Args: { p_node_id: string }; Returns: number }
      restore_file_version: {
        Args: { p_node_id: string; p_version_id: string }
        Returns: {
          byte_size: number
          checksum: string | null
          created_at: string
          created_by: string | null
          drive_id: string
          etag: string | null
          id: string
          legal_hold_until: string | null
          media_type: string
          node_id: string
          organization_id: string
          retention_until: string
          source_modified_at: string | null
          storage_bucket: string
          storage_path: string
          version_number: number
        }
        SetofOptions: {
          from: "*"
          to: "file_versions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      return_consumed_allocations: {
        Args: {
          p_created_by: string
          p_invoice_id: string
          p_invoice_line_id: string
          p_organization_id: string
          p_quantity: number
          p_reason: string
        }
        Returns: number
      }
      return_invoice_stock: {
        Args: {
          p_credit_note_id?: string
          p_invoice_id: string
          p_organization_id: string
        }
        Returns: number
      }
      safe_uuid: { Args: { p_value: string }; Returns: string }
      search_knowledge_chunks: {
        Args: {
          p_collection_ids?: string[]
          p_include_system?: boolean
          p_limit?: number
          p_organization_id?: string
          p_query: string
          p_query_embedding?: unknown
        }
        Returns: {
          chunk_id: string
          chunk_position: number
          collection_id: string
          content: string
          file_id: string
          organization_id: string
          score: number
        }[]
      }
      search_private_ai_memory: {
        Args: {
          p_limit?: number
          p_now?: string
          p_organization_id: string
          p_query: string
          p_query_embedding?: unknown
          p_scopes: string[]
          p_thread_id: string
          p_user_id: string
        }
        Returns: {
          confidence: number
          content: string
          content_hash: string
          created_at: string
          created_by: string
          deleted_at: string
          expires_at: string
          id: string
          kind: string
          last_used_at: string
          metadata: Json
          organization_id: string
          scope: string
          score: number
          source: string
          subject_id: string
          subject_type: string
          thread_id: string
          updated_at: string
          use_count: number
          user_id: string
          visibility: string
        }[]
      }
      seed_organization_document_templates: {
        Args: { p_created_by?: string; p_organization_id: string }
        Returns: undefined
      }
      seed_organization_task_hold_reasons: {
        Args: { p_organization_id: string }
        Returns: undefined
      }
      seed_organization_vat_rates: {
        Args: { p_organization_id: string }
        Returns: undefined
      }
      seed_public_holidays: {
        Args: { p_organization_id: string; p_year: number }
        Returns: number
      }
      set_default_system_lifecycle: {
        Args: { p_definition_id: string }
        Returns: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          description: string | null
          forked_from_definition_id: string | null
          forked_from_version: number | null
          graph: NonNullable<Json>
          id: string
          is_default: boolean
          key: string
          metadata: NonNullable<Json>
          name: string
          organization_id: string | null
          owner_scope: string
          published_at: string | null
          purpose: string
          status: string
          subject_type: string | null
          updated_at: string
          version: number
          visibility: string
        }
        SetofOptions: {
          from: "*"
          to: "workflow_definitions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_expenses_billable: {
        Args: {
          p_billable: boolean
          p_expense_ids: string[]
          p_organization_id: string
        }
        Returns: number
      }
      set_product_options: {
        Args: { p_options: Json; p_product_id: string }
        Returns: undefined
      }
      set_task_billing_items_billable: {
        Args: {
          p_billable: boolean
          p_organization_id: string
          p_task_ids: string[]
        }
        Returns: undefined
      }
      set_task_material_billable: {
        Args: {
          p_billable: boolean
          p_material_id: string
          p_organization_id: string
          p_task_id: string
        }
        Returns: string
      }
      set_task_status_with_materials: {
        Args: {
          p_organization_id: string
          p_position?: number
          p_status: Database["public"]["Enums"]["task_status"]
          p_task_id: string
        }
        Returns: undefined
      }
      set_task_time_entry_billable: {
        Args: {
          p_billable: boolean
          p_entry_id: string
          p_organization_id: string
        }
        Returns: string
      }
      ship_shipment: {
        Args: {
          p_organization_id: string
          p_shipment_id: string
          p_status?: Database["public"]["Enums"]["shipment_status"]
        }
        Returns: Json
      }
      start_ai_agent_tool: {
        Args: {
          p_active_stream_id: string
          p_actor_user_id: string
          p_input: Json
          p_metadata: Json
          p_model: string
          p_organization_id: string
          p_request_id: string
          p_run_id: string
          p_sequence: number
          p_step_id: string
          p_thread_id: string
          p_title: string
          p_tool_call_id: string
          p_tool_name: string
          p_workflow_run_id: string
        }
        Returns: string
      }
      sweep_approval_requests: {
        Args: Record<PropertyKey, never>
        Returns: {
          kind: string
          request_id: string
        }[]
      }
      sync_employee_for_member: {
        Args: { p_organization_id: string; p_user_id: string }
        Returns: string
      }
      sync_order_line_backorder: {
        Args: {
          p_order_line_id: string
          p_organization_id: string
          p_shortfall: number
        }
        Returns: boolean
      }
      sync_promotion_redemptions: {
        Args: {
          p_subject_id: string
          p_subject_type: Database["public"]["Enums"]["promotion_subject_type"]
        }
        Returns: undefined
      }
      sync_task_material_backorder: {
        Args: {
          p_organization_id: string
          p_shortfall: number
          p_task_material_id: string
        }
        Returns: undefined
      }
      time_off_balance: {
        Args: {
          p_employee_id: string
          p_on?: string
          p_time_off_type_id: string
        }
        Returns: number
      }
      time_off_requires_approval: {
        Args: { p_time_off_type_id: string }
        Returns: boolean
      }
      transfer_allocations: {
        Args: {
          p_created_by: string
          p_from_invoice_line_id: string
          p_from_quote_version_line_id: string
          p_from_task_material_id: string
          p_organization_id: string
          p_product_id: string
          p_quantity: number
          p_reason: string
          p_to_invoice_line_id: string
          p_to_quote_version_line_id: string
          p_to_task_material_id: string
        }
        Returns: number
      }
      transfer_promotion_redemptions: {
        Args: {
          p_from_id: string
          p_from_type: Database["public"]["Enums"]["promotion_subject_type"]
          p_to_id: string
          p_to_type: Database["public"]["Enums"]["promotion_subject_type"]
        }
        Returns: undefined
      }
      transfer_quote_allocations_to_invoice: {
        Args: {
          p_invoice_id: string
          p_organization_id: string
          p_quote_id: string
        }
        Returns: undefined
      }
      transfer_quote_allocations_to_order: {
        Args: {
          p_order_id: string
          p_organization_id: string
          p_quote_id: string
        }
        Returns: number
      }
      trash_customer_file_folder: {
        Args: { p_customer_id: number }
        Returns: string
      }
      trash_file_node: { Args: { p_node_id: string }; Returns: string }
      unassign_task_agenda_projection: {
        Args: { p_organization_id: string; p_task_id: string }
        Returns: string
      }
      update_agenda_item_aggregate: {
        Args: {
          p_agenda_item_id: string
          p_item: Json
          p_metadata: Json
          p_organization_id: string
          p_user_ids: string[]
        }
        Returns: string
      }
      update_invoice_aggregate: {
        Args: {
          p_header: Json
          p_invoice_id: string
          p_lines: Json
          p_organization_id: string
          p_replace_lines: boolean
          p_replace_tasks: boolean
          p_task_ids: string[]
        }
        Returns: string
      }
      update_shipment_status: {
        Args: {
          p_occurred_at?: string
          p_organization_id: string
          p_shipment_id: string
          p_status: Database["public"]["Enums"]["shipment_status"]
        }
        Returns: Database["public"]["Enums"]["shipment_status"]
      }
      upsert_external_agenda_item_aggregate: {
        Args: {
          p_etag: string
          p_external_calendar_id: string
          p_external_event_id: string
          p_item: Json
          p_metadata: Json
          p_organization_id: string
          p_status: string
          p_user_ids: string[]
        }
        Returns: string
      }
      upsert_reserved_allocation: {
        Args: {
          p_invoice_line_id: string
          p_order_line_id?: string
          p_organization_id: string
          p_product_id: string
          p_quantity: number
          p_quote_version_line_id: string
          p_stock_record_id: string
          p_task_material_id: string
        }
        Returns: undefined
      }
      upsert_task_material: {
        Args: { p_material: Json; p_organization_id: string; p_task_id: string }
        Returns: string
      }
      workflow_email_recipient_allowed: {
        Args: { p_email: string; p_organization_id: string }
        Returns: boolean
      }
      workflow_grant_targets_valid: {
        Args: {
          p_definition_id: string
          p_organization_id: string
          p_team_id: number
          p_user_id: string
        }
        Returns: boolean
      }
      write_inventory_movement: {
        Args: {
          p_allocated_after: number
          p_allocated_delta: number
          p_created_by: string
          p_invoice_id: string
          p_location_id: string
          p_movement_type: Database["public"]["Enums"]["inventory_movement_type"]
          p_on_hand_delta: number
          p_order_id?: string
          p_organization_id: string
          p_product_id: string
          p_quantity_after: number
          p_quote_id: string
          p_reason: string
          p_stock_record_id: string
          p_task_material_id: string
        }
        Returns: undefined
      }
    }
    Enums: {
      app_locale: "en" | "nl"
      approval_actor_kind: "human" | "agent" | "workflow" | "mcp" | "api"
      approval_approver_mode: "any" | "all" | "sequential"
      approval_requirement: "confirm" | "authorize"
      approval_source: "ai" | "workflow" | "mcp" | "domain" | "hr"
      asset_attribute_value_type: "text" | "number" | "boolean" | "date" | "url"
      billing_invoice_status:
        | "draft"
        | "open"
        | "paid"
        | "uncollectible"
        | "void"
        | "deleted"
        | "upcoming"
      billing_payment_method_status: "active" | "expired" | "detached"
      billing_payment_method_type:
        | "card"
        | "sepa_debit"
        | "ideal"
        | "link"
        | "other"
      billing_plan_interval: "month" | "year"
      billing_plan_key: "starter" | "pro" | "business" | "enterprise"
      billing_provider: "stripe"
      billing_subscription_status:
        | "none"
        | "incomplete"
        | "incomplete_expired"
        | "trialing"
        | "active"
        | "past_due"
        | "canceled"
        | "unpaid"
        | "paused"
      contact_method_type: "email" | "phone" | "whatsapp"
      customer_asset_condition: "new" | "good" | "fair" | "poor" | "unknown"
      customer_asset_status:
        | "active"
        | "inactive"
        | "maintenance"
        | "retired"
        | "archived"
      customer_status: "prospect" | "active" | "archived"
      digital_delivery_kind: "file" | "license_key" | "link" | "manual"
      discount_kind: "none" | "percentage" | "fixed"
      document_line_stock_mode: "auto" | "task" | "none"
      document_vat_regime:
        | "standard"
        | "reverse_charge"
        | "exempt"
        | "kor"
        | "margin_scheme"
      document_view_subject_type: "quote" | "invoice" | "order"
      document_viewer_kind: "contact" | "guest"
      email_delivery_status:
        | "sent"
        | "failed"
        | "delivered"
        | "bounced"
        | "complained"
        | "opened"
        | "clicked"
        | "received"
      employee_bonus_frequency: "once" | "monthly" | "quarterly" | "yearly"
      employee_bonus_kind: "fixed" | "percentage" | "discretionary"
      employee_contract_type:
        | "permanent"
        | "fixed_term"
        | "on_call"
        | "freelance"
      employee_document_type:
        | "id_copy"
        | "drivers_licence"
        | "certificate"
        | "contract"
        | "other"
      employee_field_type: "text" | "number" | "date" | "select" | "boolean"
      employee_journey_kind: "onboarding" | "offboarding"
      employee_journey_status: "active" | "completed" | "cancelled"
      employee_kind: "employee" | "contractor" | "intern"
      employee_pay_basis: "hourly" | "monthly" | "annual" | "fixed_fee"
      employee_pay_frequency: "weekly" | "four_weekly" | "monthly"
      employee_skill_kind: "skill" | "certification"
      employee_status: "onboarding" | "active" | "offboarding" | "ended"
      equipment_status: "available" | "assigned" | "repair" | "retired"
      expense_flag_kind:
        | "limit_exceeded"
        | "receipt_missing"
        | "duplicate"
        | "per_diem_overlap"
      expense_kind: "company" | "claim"
      expense_payment_method:
        | "company_card"
        | "out_of_pocket"
        | "mileage"
        | "per_diem"
      expense_policy_period: "per_expense" | "per_day" | "per_trip"
      expense_receipt_status: "attached" | "missing" | "not_required"
      expense_source: "manual" | "email" | "photo" | "card_feed"
      expense_status:
        | "draft"
        | "submitted"
        | "approved"
        | "rejected"
        | "reimbursed"
      hiring_application_source:
        | "careers_page"
        | "manual"
        | "referral"
        | "agency"
      hiring_application_status: "active" | "rejected" | "hired" | "withdrawn"
      hiring_job_status: "draft" | "open" | "closed"
      hr_approval_subject: "time_off_request" | "timesheet" | "expense"
      hr_enforcement_mode: "warn" | "block"
      hr_rounding_mode: "up" | "nearest"
      inventory_allocation_state: "reserved" | "consumed" | "backordered"
      inventory_movement_type:
        | "initial_count"
        | "purchase_receipt"
        | "sale"
        | "reservation"
        | "reservation_release"
        | "reservation_transfer"
        | "adjustment"
        | "transfer_out"
        | "transfer_in"
        | "return"
        | "write_off"
        | "cycle_count"
      inventory_status: "available" | "quarantined" | "expired" | "archived"
      invoice_charge_kind:
        | "collection_costs"
        | "statutory_interest"
        | "late_fee"
      invoice_direct_cost_confidence: "allocated" | "catalog"
      invoice_direct_cost_source: "inventory_allocation" | "product_catalog"
      invoice_kind: "invoice" | "credit_note" | "deposit"
      invoice_line_kind: "line" | "section_header"
      invoice_line_pricing_mode: "unit" | "hourly" | "fixed"
      invoice_line_type: "product" | "labor" | "custom"
      invoice_payment_method: "stripe" | "bank_transfer" | "cash" | "other"
      invoice_payment_status:
        | "requires_payment_method"
        | "requires_action"
        | "processing"
        | "succeeded"
        | "canceled"
        | "failed"
        | "refunded"
        | "disputed"
      invoice_status:
        | "draft"
        | "sent"
        | "paid"
        | "overdue"
        | "cancelled"
        | "uncollectible"
      journey_assignee_role: "employee" | "manager" | "hr" | "user"
      journey_item_kind:
        | "task"
        | "equipment_request"
        | "document_request"
        | "preboarding_form"
      journey_relative_to: "start" | "end"
      license_key_status: "available" | "assigned" | "revoked"
      order_channel: "manual" | "quote" | "inbox" | "api" | "integration"
      order_delivery_method:
        | "pickup"
        | "own_delivery"
        | "carrier"
        | "digital"
        | "none"
      order_invoicing_policy: "before_fulfillment" | "on_fulfillment" | "manual"
      order_line_type: "product" | "custom" | "shipping"
      order_status:
        | "draft"
        | "confirmed"
        | "on_hold"
        | "completed"
        | "cancelled"
      organization_payment_account_status:
        | "pending"
        | "restricted"
        | "enabled"
        | "disabled"
      organization_tag_kind: "task" | "customer" | "product"
      payroll_period_status: "open" | "exported" | "locked"
      product_scan_purpose: "product-create" | "invoice-line"
      product_scan_status:
        | "pending"
        | "running"
        | "completed"
        | "failed"
        | "expired"
      product_status: "active" | "discontinued" | "archived"
      product_type: "physical" | "digital"
      promotion_applies_to: "document" | "lines"
      promotion_eligibility_kind:
        | "all"
        | "business"
        | "individual"
        | "customer"
        | "customer_tag"
      promotion_kind: "percentage" | "fixed_amount" | "free_shipping"
      promotion_redemption_state: "pending" | "committed" | "released"
      promotion_status: "draft" | "active" | "archived"
      promotion_subject_type: "quote" | "order" | "invoice"
      promotion_target_kind: "product" | "variant" | "category"
      purchase_order_status:
        | "draft"
        | "sent"
        | "partially_received"
        | "received"
        | "closed"
        | "cancelled"
      quote_deposit_kind: "none" | "percent" | "fixed"
      quote_line_kind: "line" | "section_header"
      quote_line_pricing_mode: "unit" | "hourly" | "subscription" | "fixed"
      quote_line_type: "product" | "labor" | "custom"
      quote_status:
        | "draft"
        | "sent"
        | "accepted"
        | "rejected"
        | "expired"
        | "withdrawn"
        | "changes_requested"
      quote_subscription_interval: "weekly" | "monthly" | "quarterly" | "yearly"
      scope_type: "system" | "organization" | "user" | "team"
      shipment_direction: "outbound" | "inbound" | "return"
      shipment_return_disposition: "restock" | "quarantine" | "write_off"
      shipment_status:
        | "draft"
        | "packed"
        | "ready_for_pickup"
        | "in_transit"
        | "delivered"
        | "picked_up"
        | "exception"
        | "cancelled"
      sick_leave_status: "open" | "partially_returned" | "closed"
      stripe_webhook_processing_status:
        | "pending"
        | "processed"
        | "failed"
        | "processing"
      subscription_history_change_kind:
        | "created"
        | "plan_changed"
        | "status_changed"
        | "quantity_changed"
        | "schedule_changed"
        | "updated"
      supplier_status: "active" | "inactive" | "archived"
      task_material_stock_state: "untracked" | "reserved" | "consumed"
      task_priority: "low" | "medium" | "high" | "urgent"
      task_status: "todo" | "in_progress" | "on_hold" | "done"
      team_status: "active" | "archived"
      template_type: "invoice" | "quote" | "task" | "onboarding"
      time_entry_source:
        | "manual"
        | "timer"
        | "agenda"
        | "planning"
        | "suggestion"
      time_off_accrual_method: "upfront" | "monthly"
      time_off_category:
        | "vacation"
        | "sick"
        | "special"
        | "unpaid"
        | "parental"
        | "compensatory"
      time_off_ledger_kind:
        | "grant"
        | "accrual"
        | "taken"
        | "adjustment"
        | "carryover"
        | "expiry"
      time_off_partial_day: "full" | "morning" | "afternoon" | "hours"
      time_off_request_status: "pending" | "approved" | "rejected" | "cancelled"
      timesheet_status: "open" | "submitted" | "approved" | "rejected"
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
  public: {
    Enums: {
      app_locale: ["en", "nl"],
      approval_actor_kind: ["human", "agent", "workflow", "mcp", "api"],
      approval_approver_mode: ["any", "all", "sequential"],
      approval_requirement: ["confirm", "authorize"],
      approval_source: ["ai", "workflow", "mcp", "domain", "hr"],
      asset_attribute_value_type: ["text", "number", "boolean", "date", "url"],
      billing_invoice_status: [
        "draft",
        "open",
        "paid",
        "uncollectible",
        "void",
        "deleted",
        "upcoming",
      ],
      billing_payment_method_status: ["active", "expired", "detached"],
      billing_payment_method_type: [
        "card",
        "sepa_debit",
        "ideal",
        "link",
        "other",
      ],
      billing_plan_interval: ["month", "year"],
      billing_plan_key: ["starter", "pro", "business", "enterprise"],
      billing_provider: ["stripe"],
      billing_subscription_status: [
        "none",
        "incomplete",
        "incomplete_expired",
        "trialing",
        "active",
        "past_due",
        "canceled",
        "unpaid",
        "paused",
      ],
      contact_method_type: ["email", "phone", "whatsapp"],
      customer_asset_condition: ["new", "good", "fair", "poor", "unknown"],
      customer_asset_status: [
        "active",
        "inactive",
        "maintenance",
        "retired",
        "archived",
      ],
      customer_status: ["prospect", "active", "archived"],
      digital_delivery_kind: ["file", "license_key", "link", "manual"],
      discount_kind: ["none", "percentage", "fixed"],
      document_line_stock_mode: ["auto", "task", "none"],
      document_vat_regime: [
        "standard",
        "reverse_charge",
        "exempt",
        "kor",
        "margin_scheme",
      ],
      document_view_subject_type: ["quote", "invoice", "order"],
      document_viewer_kind: ["contact", "guest"],
      email_delivery_status: [
        "sent",
        "failed",
        "delivered",
        "bounced",
        "complained",
        "opened",
        "clicked",
        "received",
      ],
      employee_bonus_frequency: ["once", "monthly", "quarterly", "yearly"],
      employee_bonus_kind: ["fixed", "percentage", "discretionary"],
      employee_contract_type: [
        "permanent",
        "fixed_term",
        "on_call",
        "freelance",
      ],
      employee_document_type: [
        "id_copy",
        "drivers_licence",
        "certificate",
        "contract",
        "other",
      ],
      employee_field_type: ["text", "number", "date", "select", "boolean"],
      employee_journey_kind: ["onboarding", "offboarding"],
      employee_journey_status: ["active", "completed", "cancelled"],
      employee_kind: ["employee", "contractor", "intern"],
      employee_pay_basis: ["hourly", "monthly", "annual", "fixed_fee"],
      employee_pay_frequency: ["weekly", "four_weekly", "monthly"],
      employee_skill_kind: ["skill", "certification"],
      employee_status: ["onboarding", "active", "offboarding", "ended"],
      equipment_status: ["available", "assigned", "repair", "retired"],
      expense_flag_kind: [
        "limit_exceeded",
        "receipt_missing",
        "duplicate",
        "per_diem_overlap",
      ],
      expense_kind: ["company", "claim"],
      expense_payment_method: [
        "company_card",
        "out_of_pocket",
        "mileage",
        "per_diem",
      ],
      expense_policy_period: ["per_expense", "per_day", "per_trip"],
      expense_receipt_status: ["attached", "missing", "not_required"],
      expense_source: ["manual", "email", "photo", "card_feed"],
      expense_status: [
        "draft",
        "submitted",
        "approved",
        "rejected",
        "reimbursed",
      ],
      hiring_application_source: [
        "careers_page",
        "manual",
        "referral",
        "agency",
      ],
      hiring_application_status: ["active", "rejected", "hired", "withdrawn"],
      hiring_job_status: ["draft", "open", "closed"],
      hr_approval_subject: ["time_off_request", "timesheet", "expense"],
      hr_enforcement_mode: ["warn", "block"],
      hr_rounding_mode: ["up", "nearest"],
      inventory_allocation_state: ["reserved", "consumed", "backordered"],
      inventory_movement_type: [
        "initial_count",
        "purchase_receipt",
        "sale",
        "reservation",
        "reservation_release",
        "reservation_transfer",
        "adjustment",
        "transfer_out",
        "transfer_in",
        "return",
        "write_off",
        "cycle_count",
      ],
      inventory_status: ["available", "quarantined", "expired", "archived"],
      invoice_charge_kind: [
        "collection_costs",
        "statutory_interest",
        "late_fee",
      ],
      invoice_direct_cost_confidence: ["allocated", "catalog"],
      invoice_direct_cost_source: ["inventory_allocation", "product_catalog"],
      invoice_kind: ["invoice", "credit_note", "deposit"],
      invoice_line_kind: ["line", "section_header"],
      invoice_line_pricing_mode: ["unit", "hourly", "fixed"],
      invoice_line_type: ["product", "labor", "custom"],
      invoice_payment_method: ["stripe", "bank_transfer", "cash", "other"],
      invoice_payment_status: [
        "requires_payment_method",
        "requires_action",
        "processing",
        "succeeded",
        "canceled",
        "failed",
        "refunded",
        "disputed",
      ],
      invoice_status: [
        "draft",
        "sent",
        "paid",
        "overdue",
        "cancelled",
        "uncollectible",
      ],
      journey_assignee_role: ["employee", "manager", "hr", "user"],
      journey_item_kind: [
        "task",
        "equipment_request",
        "document_request",
        "preboarding_form",
      ],
      journey_relative_to: ["start", "end"],
      license_key_status: ["available", "assigned", "revoked"],
      order_channel: ["manual", "quote", "inbox", "api", "integration"],
      order_delivery_method: [
        "pickup",
        "own_delivery",
        "carrier",
        "digital",
        "none",
      ],
      order_invoicing_policy: [
        "before_fulfillment",
        "on_fulfillment",
        "manual",
      ],
      order_line_type: ["product", "custom", "shipping"],
      order_status: ["draft", "confirmed", "on_hold", "completed", "cancelled"],
      organization_payment_account_status: [
        "pending",
        "restricted",
        "enabled",
        "disabled",
      ],
      organization_tag_kind: ["task", "customer", "product"],
      payroll_period_status: ["open", "exported", "locked"],
      product_scan_purpose: ["product-create", "invoice-line"],
      product_scan_status: [
        "pending",
        "running",
        "completed",
        "failed",
        "expired",
      ],
      product_status: ["active", "discontinued", "archived"],
      product_type: ["physical", "digital"],
      promotion_applies_to: ["document", "lines"],
      promotion_eligibility_kind: [
        "all",
        "business",
        "individual",
        "customer",
        "customer_tag",
      ],
      promotion_kind: ["percentage", "fixed_amount", "free_shipping"],
      promotion_redemption_state: ["pending", "committed", "released"],
      promotion_status: ["draft", "active", "archived"],
      promotion_subject_type: ["quote", "order", "invoice"],
      promotion_target_kind: ["product", "variant", "category"],
      purchase_order_status: [
        "draft",
        "sent",
        "partially_received",
        "received",
        "closed",
        "cancelled",
      ],
      quote_deposit_kind: ["none", "percent", "fixed"],
      quote_line_kind: ["line", "section_header"],
      quote_line_pricing_mode: ["unit", "hourly", "subscription", "fixed"],
      quote_line_type: ["product", "labor", "custom"],
      quote_status: [
        "draft",
        "sent",
        "accepted",
        "rejected",
        "expired",
        "withdrawn",
        "changes_requested",
      ],
      quote_subscription_interval: ["weekly", "monthly", "quarterly", "yearly"],
      scope_type: ["system", "organization", "user", "team"],
      shipment_direction: ["outbound", "inbound", "return"],
      shipment_return_disposition: ["restock", "quarantine", "write_off"],
      shipment_status: [
        "draft",
        "packed",
        "ready_for_pickup",
        "in_transit",
        "delivered",
        "picked_up",
        "exception",
        "cancelled",
      ],
      sick_leave_status: ["open", "partially_returned", "closed"],
      stripe_webhook_processing_status: [
        "pending",
        "processed",
        "failed",
        "processing",
      ],
      subscription_history_change_kind: [
        "created",
        "plan_changed",
        "status_changed",
        "quantity_changed",
        "schedule_changed",
        "updated",
      ],
      supplier_status: ["active", "inactive", "archived"],
      task_material_stock_state: ["untracked", "reserved", "consumed"],
      task_priority: ["low", "medium", "high", "urgent"],
      task_status: ["todo", "in_progress", "on_hold", "done"],
      team_status: ["active", "archived"],
      template_type: ["invoice", "quote", "task", "onboarding"],
      time_entry_source: [
        "manual",
        "timer",
        "agenda",
        "planning",
        "suggestion",
      ],
      time_off_accrual_method: ["upfront", "monthly"],
      time_off_category: [
        "vacation",
        "sick",
        "special",
        "unpaid",
        "parental",
        "compensatory",
      ],
      time_off_ledger_kind: [
        "grant",
        "accrual",
        "taken",
        "adjustment",
        "carryover",
        "expiry",
      ],
      time_off_partial_day: ["full", "morning", "afternoon", "hours"],
      time_off_request_status: ["pending", "approved", "rejected", "cancelled"],
      timesheet_status: ["open", "submitted", "approved", "rejected"],
    },
  },
} as const
