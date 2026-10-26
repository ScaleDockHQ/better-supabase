DROP POLICY "bsb_realtime_tables_receive" ON "realtime"."messages";

CREATE POLICY "bsb_realtime_tables_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'bsb:t:%'::text) AND (NOT COALESCE(((( SELECT auth.jwt() AS jwt) ->>
    'is_anonymous'::text))::boolean,
    false)) AND
    ((split_part(( SELECT realtime.topic() AS topic), ':'::text, 4) = ''::text) OR ((split_part(( SELECT realtime.topic() AS topic), ':'::text, 5) = ''::text) AND (split_part((
    SELECT realtime.topic() AS topic), ':'::text, 4) IN ( SELECT (t.m)::text AS m
   FROM ( SELECT better_supabase.member_organization_ids() AS m) t))) OR
     ((split_part(( SELECT realtime.topic() AS topic), ':'::text, 4) = 'u'::text) AND (split_part(( SELECT realtime.topic() AS topic), ':'::text, 5) = (( SELECT auth.uid() AS
     uid))::text)))));
