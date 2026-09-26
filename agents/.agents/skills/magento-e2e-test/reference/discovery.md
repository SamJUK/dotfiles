# Runtime discovery

There is no per-project config file. Everything the harness needs is derived at phase 2 and
written to `discovery.json` in the session scratchpad.

Run these against the project's own DB. Table prefix varies — read it from `env.php`
(`db/table_prefix`) and prefix every table below with it. Under Warden:
`warden db connect -e "<sql>"`.

**MySQL 8 runs `ONLY_FULL_GROUP_BY`.** Every non-aggregated column must be in the `GROUP BY`
or the query errors out.

---

## Table prefix and base URLs

```bash
php -r '$c = include "app/etc/env.php"; echo ($c["db"]["table_prefix"] ?? "") . "\n";'
```

Base URLs come from the human at phase 0. These confirm what the store itself believes:

```sql
SELECT s.store_id, s.code, w.code AS website, c.value AS base_url
FROM store s
JOIN store_website w ON w.website_id = s.website_id
LEFT JOIN core_config_data c
       ON c.scope = 'stores' AND c.scope_id = s.store_id
      AND c.path = 'web/unsecure/base_url'
WHERE s.store_id > 0
ORDER BY s.store_id;
```

More than one website means **more than one storefront to test**. Second stores are the most
commonly forgotten surface in an upgrade.

---

## Product types actually present

Only build fixtures for types the catalogue really has.

```sql
SELECT type_id, COUNT(*) n FROM catalog_product_entity GROUP BY type_id ORDER BY n DESC;
```

### Simple — in stock, with a clean URL

```sql
SELECT e.sku, r.request_path
FROM catalog_product_entity e
JOIN cataloginventory_stock_item si
     ON si.product_id = e.entity_id AND si.is_in_stock = 1 AND si.qty > 5
JOIN url_rewrite r
     ON r.entity_id = e.entity_id AND r.entity_type = 'product'
    AND r.store_id = 1 AND r.request_path NOT LIKE '%/%'
WHERE e.type_id = 'simple'
LIMIT 5;
```

### Configurable — must have SALABLE CHILDREN

Joining stock on the parent returns out-of-stock products with no Add to Cart button. Go
through the children:

```sql
SELECT p.sku, r.request_path, COUNT(*) AS salable_children
FROM catalog_product_entity p
JOIN catalog_product_super_link sl ON sl.parent_id = p.entity_id
JOIN catalog_product_entity c ON c.entity_id = sl.product_id
JOIN cataloginventory_stock_item si
     ON si.product_id = c.entity_id AND si.is_in_stock = 1 AND si.qty > 0
JOIN url_rewrite r
     ON r.entity_id = p.entity_id AND r.entity_type = 'product'
    AND r.store_id = 1 AND r.request_path NOT LIKE '%/%'
WHERE p.type_id = 'configurable'
GROUP BY p.sku, r.request_path
HAVING salable_children > 1
LIMIT 4;
```

### Custom options

```sql
SELECT e.sku, r.request_path, COUNT(o.option_id) AS opts
FROM catalog_product_entity e
JOIN catalog_product_option o ON o.product_id = e.entity_id
JOIN url_rewrite r
     ON r.entity_id = e.entity_id AND r.entity_type = 'product'
    AND r.store_id = 1 AND r.request_path NOT LIKE '%/%'
GROUP BY e.sku, r.request_path
LIMIT 3;
```

Custom-option pricing is worth testing wherever the project carries a patch touching option
price rendering.

### Categories, per store

```sql
SELECT request_path FROM url_rewrite
WHERE entity_type = 'category' AND store_id = 1 AND request_path NOT LIKE '%/%'
LIMIT 5;
```

**Verify every candidate URL with a real request before using it.** Rewrites exist for
categories that 404 — one bad rewrite is not a store-wide break, but it will fail the run.

---

## Payment methods, ranked by real usage

This is what makes the coverage report honest.

```sql
SELECT p.method, COUNT(*) n
FROM sales_order_payment p
GROUP BY p.method
ORDER BY n DESC
LIMIT 10;
```

Test only the offline methods. Record the order share of everything else so the report can
state exactly what is untested — "checkout works" must never be read as "the gateway works".

```sql
SELECT path, value FROM core_config_data
WHERE path IN ('payment/checkmo/active', 'payment/purchaseorder/active');
```

Values **locked in `env.php`** cannot be changed with `bin/magento config:set` — it refuses
with "the value you set has already been locked". Check there too:

```bash
php -r '$c = include "app/etc/env.php"; print_r($c["system"]["default"]["payment"] ?? []);'
```

---

## Checkout implementation

Core checkout and one-step checkout modules need different selector strategies.

```bash
php -r '$c = include "app/etc/config.php";
foreach ($c["modules"] as $m => $on) {
    if ($on && preg_match("/Checkout/i", $m)) echo "$m\n";
}'
```

A third-party one-step checkout means: randomised element ids, address fields by `name` only,
and shipping methods that appear **only after a complete address including postcode**.

---

## Settings that block automated testing

```sql
SELECT path, value FROM core_config_data
WHERE path IN (
  'customer/captcha/enable',
  'customer/create_account/confirm',
  'dev/js/enable_js_bundling',
  'dev/js/minify_files'
) OR path LIKE 'csp/%';
```

- `customer/captcha/enable` = 1 blocks registration. Disable for the test window, **restore
  after**.
- `customer/create_account/confirm` = 1 means successful registration lands on the login page
  with a notice — that is a pass, not a failure. Clear `confirmation` in `customer_entity`
  to log in.
- `enable_js_bundling` + `minify_files` both on = the SRI corruption trigger.
- No `csp/%` rows means module defaults, which are `report_only`.

---

## Admin access

Create a throwaway admin for the run and **delete it afterwards**:

```bash
bin/magento admin:user:create --admin-user=upgradetest \
  --admin-password="$(openssl rand -base64 18)" --admin-email=upgradetest@example.test \
  --admin-firstname=Upgrade --admin-lastname=Test
```

There is no `admin:user:delete` command. Remove the row directly, with the table prefix from
`env.php` (`db/table_prefix`) if the store has one:

```sql
DELETE FROM admin_user WHERE username = 'upgradetest';
```

Phase 9 does not finish until this row is gone.

---

## discovery.json

```json
{
  "tablePrefix": "",
  "stores": [
    { "name": "default", "storeId": 1, "baseUrl": "https://app.example.test" },
    { "name": "second",  "storeId": 2, "baseUrl": "https://app.second.test" }
  ],
  "fixtures": {
    "simple": "/example-simple-product.html",
    "configurable": "/example-configurable-product.html",
    "customOptions": "/example-product-with-options.html",
    "category": "/example-category.html",
    "searchTerm": "shirt"
  },
  "checkout": { "type": "luma" },
  "address": {
    "firstname": "Upgrade", "lastname": "Tester",
    "street": "1 Example Street", "city": "Exampletown",
    "postcode": "AB1 2CD", "country": "GB", "telephone": "01234567890"
  },
  "payments": {
    "test": ["checkmo", "purchaseorder"],
    "untested": [
      { "method": "stripe_payments", "orders": 1200 },
      { "method": "paypal_express",  "orders": 450 }
    ]
  },
  "admin": { "path": "/admin", "user": "upgradetest" }
}
```

The address must be one that **produces a shipping quote** — table or matrix rate carriers
return nothing for an out-of-area postcode, and no shipping method means no order.
