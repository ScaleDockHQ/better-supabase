DROP POLICY "bs_realtime_tables_receive" ON "realtime"."messages";

CREATE POLICY "bs_realtime_tables_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'bs:t:%'::text) AND (NOT COALESCE(((( SELECT auth.jwt() AS jwt) ->>
    'is_anonymous'::text))::boolean,
    false)) AND
    ((split_part(( SELECT realtime.topic() AS topic), ':'::text, 4) = ''::text) OR (split_part(( SELECT realtime.topic() AS topic), ':'::text, 4) = COALESCE((( SELECT auth.jwt() AS
    jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text), ''::text)))));
