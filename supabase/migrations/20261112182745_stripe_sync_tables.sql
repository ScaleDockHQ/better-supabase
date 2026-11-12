CREATE SCHEMA "stripe";

CREATE TABLE "stripe"."customers" (
  "id"      text    NOT NULL,
  "email"   text,
  "name"    text,
  "created" integer,
  CONSTRAINT "customers_pkey" PRIMARY KEY (id)
);

ALTER TABLE "stripe"."customers"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "stripe"."invoices" (
  "id"                 text    NOT NULL,
  "customer"           text,
  "number"             text,
  "status"             text,
  "currency"           text,
  "total"              integer,
  "created"            integer,
  "hosted_invoice_url" text,
  CONSTRAINT "invoices_pkey" PRIMARY KEY (id)
);

ALTER TABLE "stripe"."invoices"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "stripe"."payment_methods" (
  "id"       text    NOT NULL,
  "customer" text,
  "type"     text,
  "created"  integer,
  CONSTRAINT "payment_methods_pkey" PRIMARY KEY (id)
);

ALTER TABLE "stripe"."payment_methods"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "stripe"."prices" (
  "id"          text    NOT NULL,
  "product"     text,
  "currency"    text,
  "unit_amount" integer,
  "created"     integer,
  CONSTRAINT "prices_pkey" PRIMARY KEY (id)
);

ALTER TABLE "stripe"."prices"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "stripe"."subscription_items" (
  "id"           text    NOT NULL,
  "subscription" text,
  "price"        text,
  "quantity"     integer,
  "created"      integer,
  CONSTRAINT "subscription_items_pkey" PRIMARY KEY (id)
);

ALTER TABLE "stripe"."subscription_items"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "stripe"."subscriptions" (
  "id"                   text    NOT NULL,
  "customer"             text,
  "status"               text,
  "created"              integer,
  "current_period_end"   integer,
  "cancel_at_period_end" boolean,
  CONSTRAINT "subscriptions_pkey" PRIMARY KEY (id)
);

ALTER TABLE "stripe"."subscriptions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "stripe"."tax_ids" (
  "id"       text    NOT NULL,
  "customer" text,
  "type"     text,
  "value"    text,
  "created"  integer,
  CONSTRAINT "tax_ids_pkey" PRIMARY KEY (id)
);

ALTER TABLE "stripe"."tax_ids"
  ENABLE ROW LEVEL SECURITY;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "stripe"."customers" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "stripe"."invoices" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "stripe"."payment_methods" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "stripe"."prices" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "stripe"."subscription_items" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "stripe"."subscriptions" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "stripe"."tax_ids" TO "service_role";
