-- The engagement tables take the activity noun of their block (ADR 0380). Renames only.
-- destructive: reviewed
do $$
begin
  if exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'better_supabase' and c.relname = 'bookings' and t.tgname = 'bookings_engagement' and not t.tgisinternal) then
    alter trigger "bookings_engagement" on "better_supabase"."bookings" rename to "bsb_bookings_activity";
  end if;
  if to_regclass('"better_supabase"."engagement_subjects"') is not null then
    alter table "better_supabase"."engagement_subjects" rename to "activity_subjects";
    declare
      x record;
    begin
      for x in
        select 'constraint' as kind, k.conname::text as name from pg_catalog.pg_constraint k where k.conrelid = '"better_supabase"."activity_subjects"'::regclass
        union all
        select 'index', i.relname::text from pg_catalog.pg_index ix join pg_catalog.pg_class i on i.oid = ix.indexrelid
          where ix.indrelid = '"better_supabase"."activity_subjects"'::regclass and not exists (select 1 from pg_catalog.pg_constraint k where k.conindid = i.oid)
        union all
        select 'policy', p.polname::text from pg_catalog.pg_policy p where p.polrelid = '"better_supabase"."activity_subjects"'::regclass
        order by 1 desc, 2
      loop
        if x.name ~ ('^(bsb_)?' || 'engagement_subjects' || '(_|$)') then
          execute case x.kind
            when 'constraint' then format('alter table %s rename constraint %I to %I', '"better_supabase"."activity_subjects"', x.name, regexp_replace(x.name, '^(bsb_)?' || 'engagement_subjects', '\1' || 'activity_subjects'))
            when 'index' then format('alter index %I.%I rename to %I', 'better_supabase', x.name, regexp_replace(x.name, '^(bsb_)?' || 'engagement_subjects', '\1' || 'activity_subjects'))
            else format('alter policy %I on %s rename to %I', x.name, '"better_supabase"."activity_subjects"', regexp_replace(x.name, '^(bsb_)?' || 'engagement_subjects', '\1' || 'activity_subjects'))
          end;
        end if;
      end loop;
    end;
  end if;
  if to_regclass('"better_supabase"."engagement_recordings"') is not null then
    alter table "better_supabase"."engagement_recordings" rename to "activity_recordings";
    declare
      x record;
    begin
      for x in
        select 'constraint' as kind, k.conname::text as name from pg_catalog.pg_constraint k where k.conrelid = '"better_supabase"."activity_recordings"'::regclass
        union all
        select 'index', i.relname::text from pg_catalog.pg_index ix join pg_catalog.pg_class i on i.oid = ix.indexrelid
          where ix.indrelid = '"better_supabase"."activity_recordings"'::regclass and not exists (select 1 from pg_catalog.pg_constraint k where k.conindid = i.oid)
        union all
        select 'policy', p.polname::text from pg_catalog.pg_policy p where p.polrelid = '"better_supabase"."activity_recordings"'::regclass
        order by 1 desc, 2
      loop
        if x.name ~ ('^(bsb_)?' || 'engagement_recordings' || '(_|$)') then
          execute case x.kind
            when 'constraint' then format('alter table %s rename constraint %I to %I', '"better_supabase"."activity_recordings"', x.name, regexp_replace(x.name, '^(bsb_)?' || 'engagement_recordings', '\1' || 'activity_recordings'))
            when 'index' then format('alter index %I.%I rename to %I', 'better_supabase', x.name, regexp_replace(x.name, '^(bsb_)?' || 'engagement_recordings', '\1' || 'activity_recordings'))
            else format('alter policy %I on %s rename to %I', x.name, '"better_supabase"."activity_recordings"', regexp_replace(x.name, '^(bsb_)?' || 'engagement_recordings', '\1' || 'activity_recordings'))
          end;
        end if;
      end loop;
    end;
  end if;
  if to_regclass('"better_supabase"."engagement_notes"') is not null then
    alter table "better_supabase"."engagement_notes" rename to "activity_notes";
    declare
      x record;
    begin
      for x in
        select 'constraint' as kind, k.conname::text as name from pg_catalog.pg_constraint k where k.conrelid = '"better_supabase"."activity_notes"'::regclass
        union all
        select 'index', i.relname::text from pg_catalog.pg_index ix join pg_catalog.pg_class i on i.oid = ix.indexrelid
          where ix.indrelid = '"better_supabase"."activity_notes"'::regclass and not exists (select 1 from pg_catalog.pg_constraint k where k.conindid = i.oid)
        union all
        select 'policy', p.polname::text from pg_catalog.pg_policy p where p.polrelid = '"better_supabase"."activity_notes"'::regclass
        order by 1 desc, 2
      loop
        if x.name ~ ('^(bsb_)?' || 'engagement_notes' || '(_|$)') then
          execute case x.kind
            when 'constraint' then format('alter table %s rename constraint %I to %I', '"better_supabase"."activity_notes"', x.name, regexp_replace(x.name, '^(bsb_)?' || 'engagement_notes', '\1' || 'activity_notes'))
            when 'index' then format('alter index %I.%I rename to %I', 'better_supabase', x.name, regexp_replace(x.name, '^(bsb_)?' || 'engagement_notes', '\1' || 'activity_notes'))
            else format('alter policy %I on %s rename to %I', x.name, '"better_supabase"."activity_notes"', regexp_replace(x.name, '^(bsb_)?' || 'engagement_notes', '\1' || 'activity_notes'))
          end;
        end if;
      end loop;
    end;
  end if;
  if to_regclass('"better_supabase"."engagement_transcript_segments"') is not null then
    alter table "better_supabase"."engagement_transcript_segments" rename to "activity_transcript_segments";
    declare
      x record;
    begin
      for x in
        select 'constraint' as kind, k.conname::text as name from pg_catalog.pg_constraint k where k.conrelid = '"better_supabase"."activity_transcript_segments"'::regclass
        union all
        select 'index', i.relname::text from pg_catalog.pg_index ix join pg_catalog.pg_class i on i.oid = ix.indexrelid
          where ix.indrelid = '"better_supabase"."activity_transcript_segments"'::regclass and not exists (select 1 from pg_catalog.pg_constraint k where k.conindid = i.oid)
        union all
        select 'policy', p.polname::text from pg_catalog.pg_policy p where p.polrelid = '"better_supabase"."activity_transcript_segments"'::regclass
        order by 1 desc, 2
      loop
        if x.name ~ ('^(bsb_)?' || 'engagement_transcript_segments' || '(_|$)') then
          execute case x.kind
            when 'constraint' then format('alter table %s rename constraint %I to %I', '"better_supabase"."activity_transcript_segments"', x.name, regexp_replace(x.name, '^(bsb_)?' || 'engagement_transcript_segments', '\1' || 'activity_transcript_segments'))
            when 'index' then format('alter index %I.%I rename to %I', 'better_supabase', x.name, regexp_replace(x.name, '^(bsb_)?' || 'engagement_transcript_segments', '\1' || 'activity_transcript_segments'))
            else format('alter policy %I on %s rename to %I', x.name, '"better_supabase"."activity_transcript_segments"', regexp_replace(x.name, '^(bsb_)?' || 'engagement_transcript_segments', '\1' || 'activity_transcript_segments'))
          end;
        end if;
      end loop;
    end;
  end if;
  if to_regclass('"better_supabase"."mail_threads_engagement_idx"') is not null then
    alter index "better_supabase"."mail_threads_engagement_idx" rename to "mail_threads_activity_idx";
  end if;
end
$$;

