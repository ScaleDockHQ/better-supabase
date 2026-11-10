DROP POLICY "bsb_reaction_scores_read" ON "better_supabase"."reaction_scores";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."reaction_scores";

DROP POLICY "bsb_reactions_insert" ON "better_supabase"."reactions";

DROP POLICY "bsb_reactions_read" ON "better_supabase"."reactions";

DROP POLICY "bsb_tenant_scope_insert" ON "better_supabase"."reactions";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."reactions";

CREATE POLICY "bsb_reaction_scores_read" ON "better_supabase"."reaction_scores"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('reactions.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.tenant_id = reaction_scores.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.tenant_id = reaction_scores.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.tenant_id = reaction_scores.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.tenant_id = reaction_scores.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.organization_id = reaction_scores.tenant_id) AND (s.archived_at IS NULL)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (reaction_scores.subject_id)::uuid) AND (s.tenant_id = reaction_scores.tenant_id) AND (s.archived_at IS NULL) AND ((reaction_scores.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.id = reaction_scores.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.organization_id = reaction_scores.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.organization_id = reaction_scores.tenant_id) AND (s.deleted_at IS NULL))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.organization_id = reaction_scores.tenant_id))))
    ELSE better_supabase.reaction_subject_visible(subject_type, subject_id, tenant_id)
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."reaction_scores"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('reactions.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.tenant_id = reaction_scores.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.tenant_id = reaction_scores.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.tenant_id = reaction_scores.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.tenant_id = reaction_scores.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.organization_id = reaction_scores.tenant_id) AND (s.archived_at IS NULL)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (reaction_scores.subject_id)::uuid) AND (s.tenant_id = reaction_scores.tenant_id) AND (s.archived_at IS NULL) AND ((reaction_scores.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.id = reaction_scores.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.organization_id = reaction_scores.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.organization_id = reaction_scores.tenant_id) AND (s.deleted_at IS NULL))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (reaction_scores.subject_id)::uuid) AND (s.organization_id = reaction_scores.tenant_id))))
    ELSE better_supabase.reaction_subject_visible(subject_type, subject_id, tenant_id)
END)));

CREATE POLICY "bsb_reactions_insert" ON "better_supabase"."reactions"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND (actor = (( SELECT auth.uid() AS uid))::text) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('reactions.create'::text)
    AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id) AND (s.archived_at IS NULL)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id) AND (s.archived_at IS NULL) AND ((reactions.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.id = reactions.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id) AND (s.deleted_at IS NULL))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id))))
    ELSE better_supabase.reaction_subject_visible(subject_type, subject_id, tenant_id)
END AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_reactions_read" ON "better_supabase"."reactions"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('reactions.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id) AND (s.archived_at IS NULL)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id) AND (s.archived_at IS NULL) AND ((reactions.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.id = reactions.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id) AND (s.deleted_at IS NULL))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id))))
    ELSE better_supabase.reaction_subject_visible(subject_type, subject_id, tenant_id)
END));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."reactions"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH
    CHECK
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) AND (actor = (( SELECT auth.uid() AS
    uid))::text) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('reactions.create'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id) AND (s.archived_at IS NULL)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id) AND (s.archived_at IS NULL) AND ((reactions.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.id = reactions.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id) AND (s.deleted_at IS NULL))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id))))
    ELSE better_supabase.reaction_subject_visible(subject_type, subject_id, tenant_id)
END)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."reactions"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('reactions.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id) AND (s.archived_at IS NULL)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (reactions.subject_id)::uuid) AND (s.tenant_id = reactions.tenant_id) AND (s.archived_at IS NULL) AND ((reactions.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.id = reactions.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id) AND (s.deleted_at IS NULL))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (reactions.subject_id)::uuid) AND (s.organization_id = reactions.tenant_id))))
    ELSE better_supabase.reaction_subject_visible(subject_type, subject_id, tenant_id)
END)));
