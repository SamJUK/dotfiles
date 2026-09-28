# Harness traps

These are **harness** faults. Every one of them looks like a product regression.

### Duplicate DOM ids on the login page

Magento renders two `#login-form` elements — the hidden authentication popup and the real
page form. 2.4.8 also renamed the visible password field from `#pass` to `#password` and
added a show-password toggle. Scope to `form#login-form:visible` and address fields by
`name` (`login[username]`, `login[password]`), which is stable across versions.

On Hyvä the page form is `#customer-login-form`. Hyvä's `#login-form` is the header popup,
with fields named `username`/`password`, not `login[...]`. Match either id.

### One Place Order button per payment method

Each payment block renders its own `button.action.primary.checkout`; all are visible, only
the selected method's is enabled. `.first()` grabs a disabled one. Use
`:visible:not([disabled])`.

### One-step checkout modules randomise field ids

Amasty OSC and similar regenerate element ids per page load. Only `name` attributes are
stable. Payment method radios keep real ids (`checkmo`, `purchaseorder`).

### Two-step checkout hides payment methods

Luma's checkout, and Hyvä's Luma checkout fallback, render payment methods only after "Next" on
the shipping step. One-step checkout modules show both at once. Click Next when it is visible.

### Configurable stock is not parent stock

Selecting a configurable fixture by joining stock on the **parent** returns out-of-stock
products with no Add to Cart button. Join through `catalog_product_super_link` to children
and require salable children.

### Admin URLs carry a per-route secret key

Constructing `.../catalog/product/edit/id/5/` by string-replacing a grid URL drops the key
and Magento silently redirects to the dashboard or grid. Harvest a real keyed link from the
rendered grid DOM instead.

### Captcha and email confirmation block registration

`customer/captcha/enable` covering `user_create` blocks automated registration, and
`customer/create_account/confirm` means a *successful* registration lands back on the login
page with a notice. Turn captcha off for the test window and **turn it back on**; clear
`confirmation` in `customer_entity` to log in.

### Registration logs the customer in

Without email confirmation, a successful registration leaves the customer signed in, and the
login page redirects to the dashboard. Log out before testing login.

---
