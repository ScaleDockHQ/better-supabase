-- Runs once on first start via /docker-entrypoint-initdb.d. Adjust the dimension to your embedding model.
CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE IF NOT EXISTS chunks (
  id bigserial PRIMARY KEY,
  doc_id bigint NOT NULL,
  content text NOT NULL,
  embedding vector(1024) NOT NULL
);
-- Create the ANN index after bulk loading:
-- CREATE INDEX CONCURRENTLY ON chunks USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
