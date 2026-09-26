/**
 * Magento critical-path harness.
 *
 *   LABEL=before DISCOVERY=./discovery.json ADMIN_PASS=... node critical-paths.js
 *
 * Reads discovery.json (see reference/discovery.md), runs the same checks before and after
 * an upgrade, and writes $OUT_DIR/results.json (default ./results-<LABEL>) for diffing.
 *
 * Offline payment methods only. Never drives a gateway.
 *
 * It registers a customer, places and invoices orders, and saves a product and a CMS page, so it
 * refuses any store that is not local (*.test, *.localhost, localhost, 127.0.0.1, *.ddev.site).
 * ALLOW_REMOTE=1 overrides that, for a disposable environment only.
 *
 * DB_CMD is run through sh with the query as "$1", so quoted arguments work:
 *   DB_CMD='warden db connect -e'   (default)     DB_CMD='ddev mysql -e'
 *
 * Needs playwright-core. If the project has no local install, a global @playwright/test
 * bundles one:
 *   NODE_PATH=$(npm root -g)/@playwright/test/node_modules node critical-paths.js
 * Set CHROME_PATH if the bundled browser revision does not match.
 */
const { chromium } = require('playwright-core');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const LABEL = process.env.LABEL || 'run';
const D = JSON.parse(fs.readFileSync(process.env.DISCOVERY || './discovery.json', 'utf8'));
const OUT = path.resolve(process.env.OUT_DIR || `./results-${LABEL}`);
const ADMIN_PASS = process.env.ADMIN_PASS;
const PROJECT = process.env.PROJECT_DIR || process.cwd();
const DB_CMD = process.env.DB_CMD || 'warden db connect -e';
const PREFIX = D.tablePrefix || '';

const LOCAL_HOST = /(^|\.)(localhost|test|ddev\.site)$|^127\.0\.0\.1$/;
for (const store of D.stores) {
  const host = new URL(store.baseUrl).hostname;
  if (!LOCAL_HOST.test(host) && process.env.ALLOW_REMOTE !== '1') {
    console.error(`Refusing ${store.baseUrl}: this harness creates customers, orders and invoices. ` +
      'Local stores only (*.test, *.localhost, localhost, 127.0.0.1, *.ddev.site); ' +
      'ALLOW_REMOTE=1 is for disposable environments only.');
    process.exit(2);
  }
}

const primary = D.stores[0];
const BASE = primary.baseUrl;
const results = [];
const pageErrors = [];

const rec = (name, ok, detail) => {
  results.push({ name, ok, detail: String(detail || '').slice(0, 400) });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + String(detail).replace(/\s+/g, ' ').slice(0, 170) : ''}`);
};
async function step(name, fn) {
  try { const d = await fn(); rec(name, true, d); return d; }
  catch (e) { rec(name, false, e.message); return null; }
}
const sql = q => execFileSync('sh', ['-c', `${DB_CMD} "$1"`, 'sh', q],
  { cwd: PROJECT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });

const stamp = Date.now();
const CUST = {
  email: `upgrade.test.${stamp}@example.test`,
  pass: `Cust-Test-${stamp.toString(36)}!A`,
  ...D.address,
};

const shot = async (p, n) => { try { await p.screenshot({ path: `${OUT}/${n}.png` }); } catch (e) {} };

async function gotoRetry(p, url) {
  for (let i = 0; i < 3; i++) {
    try { return await p.goto(url, { waitUntil: 'domcontentloaded' }); }
    catch (e) { if (i === 2) throw e; await p.waitForTimeout(4000); }
  }
}
async function dismissCookies(p) {
  try {
    const b = p.locator('#btn-cookie-allow, a:has-text("ALLOW COOKIES"), .cookie-status-message a').first();
    if (await b.isVisible({ timeout: 2500 })) { await b.click(); await p.waitForTimeout(800); }
  } catch (e) { /* no banner */ }
}
// Developer mode turns PHP warnings into exceptions, so HTTP 200 is not sufficient.
async function assertNoAppError(p, label) {
  const body = await p.locator('body').innerText();
  if (/exception\(s\):|An error has happened during application run|Report ID:/i.test(body)) {
    await shot(p, 'err-' + label);
    throw new Error('application error: ' + body.replace(/\s+/g, ' ').slice(0, 200));
  }
  return body;
}
const productCount = p => p.locator('.product-item, li.item.product').count();

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const b = await chromium.launch(
    process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {});
  const ctx = await b.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 1100 } });
  ctx.setDefaultTimeout(60000);
  ctx.setDefaultNavigationTimeout(180000);
  const p = await ctx.newPage();
  p.on('pageerror', e => pageErrors.push(e.message.slice(0, 200)));

  // ---------------------------------------------------------------- storefront
  await step('storefront: homepage', async () => {
    const r = await gotoRetry(p, BASE + '/');
    await dismissCookies(p);
    await assertNoAppError(p, 'home');
    if (r.status() !== 200) throw new Error('HTTP ' + r.status());
    if (!(await p.locator('nav, .nav-sections, .megamenu').count())) throw new Error('no nav');
    return 'HTTP 200, nav present';
  });

  await step('storefront: category lists products', async () => {
    const r = await gotoRetry(p, BASE + D.fixtures.category);
    await assertNoAppError(p, 'plp');
    if (r.status() !== 200) throw new Error('HTTP ' + r.status());
    await p.waitForTimeout(3000);
    const n = await productCount(p);
    if (n < 1) throw new Error('0 products on category page');
    return `${n} products`;
  });

  await step('storefront: search (exercises the search engine)', async () => {
    const r = await gotoRetry(p, `${BASE}/catalogsearch/result/?q=${encodeURIComponent(D.fixtures.searchTerm)}`);
    await assertNoAppError(p, 'search');
    if (r.status() !== 200) throw new Error('HTTP ' + r.status());
    await p.waitForTimeout(3000);
    const n = await productCount(p);
    const body = await p.locator('body').innerText();
    if (/we can'?t find any items/i.test(body) || n < 1) throw new Error('no search results');
    return `${n} results`;
  });

  for (const [type, url] of Object.entries(D.fixtures)) {
    if (!['simple', 'configurable', 'customOptions', 'grouped', 'virtual', 'bundle'].includes(type)) continue;
    await step(`product: ${type} PDP renders`, async () => {
      const r = await gotoRetry(p, BASE + url);
      await dismissCookies(p);
      await assertNoAppError(p, 'pdp-' + type);
      if (r.status() !== 200) throw new Error('HTTP ' + r.status());
      const price = await p.locator('.price-box .price, .product-info-price .price')
        .first().innerText().catch(() => '');
      if (!price.trim()) throw new Error('no price rendered');
      return `HTTP 200, price ${price.trim()}`;
    });
  }

  async function addToCart(url, label) {
    await gotoRetry(p, BASE + url);
    await dismissCookies(p);
    await assertNoAppError(p, 'atc-' + label);
    // configurables need an option chosen before the button enables
    const opts = p.locator('.swatch-option, .super-attribute-select');
    if (await opts.count()) {
      const first = opts.first();
      if ((await first.evaluate(e => e.tagName)) === 'SELECT') await first.selectOption({ index: 1 });
      else await first.click();
      await p.waitForTimeout(3000);
    }
    const btn = p.locator('#product-addtocart-button, button.tocart').first();
    if (!(await btn.isVisible().catch(() => false))) {
      await shot(p, 'no-addtocart-' + label);
      throw new Error('no Add to Cart button — fixture may be out of stock');
    }
    await btn.click();
    await p.waitForTimeout(8000);
  }

  await step('storefront: add simple product to cart', async () => {
    await addToCart(D.fixtures.simple, 'simple');
    const r = await gotoRetry(p, BASE + '/checkout/cart/');
    await assertNoAppError(p, 'cart');
    if (r.status() !== 200) throw new Error('cart HTTP ' + r.status());
    const rows = await p.locator('.cart.item, tbody.cart.item').count();
    if (rows < 1) throw new Error('cart empty after add');
    return `${rows} line item(s)`;
  });

  if (D.fixtures.configurable) {
    await step('storefront: add configurable to cart', async () => {
      await addToCart(D.fixtures.configurable, 'configurable');
      const r = await gotoRetry(p, BASE + '/checkout/cart/');
      await assertNoAppError(p, 'cart-conf');
      if (r.status() !== 200) throw new Error('cart HTTP ' + r.status());
      const rows = await p.locator('.cart.item, tbody.cart.item').count();
      if (rows < 1) throw new Error('cart empty after configurable add');
      return `${rows} line item(s)`;
    });
  }

  // ---------------------------------------------------------------- customer
  await step('customer: register', async () => {
    await gotoRetry(p, BASE + '/customer/account/create/');
    await dismissCookies(p);
    await p.fill('#firstname', CUST.firstname);
    await p.fill('#lastname', CUST.lastname);
    await p.fill('#email_address', CUST.email);
    await p.fill('#password', CUST.pass);
    await p.fill('#password-confirmation', CUST.pass);
    await Promise.all([
      p.waitForNavigation({ waitUntil: 'domcontentloaded' }).catch(() => {}),
      p.locator('button[title="Create an Account"], .action.submit.primary').first().click(),
    ]);
    await p.waitForTimeout(5000);
    const row = sql(`select entity_id from ${PREFIX}customer_entity where email='${CUST.email}';`);
    if (!/\d/.test(row.replace(/entity_id/, ''))) {
      await shot(p, 'register-fail');
      throw new Error('no customer row created. url=' + p.url());
    }
    // confirm-required stores bounce to login with a notice — that is a pass
    const confirmed = /confirm your account/i.test(await p.locator('body').innerText());
    return `customer row created${confirmed ? ', email confirmation required (expected)' : ''}`;
  });

  await step('customer: log in', async () => {
    sql(`update ${PREFIX}customer_entity set confirmation=NULL where email='${CUST.email}';`);
    await gotoRetry(p, BASE + '/customer/account/login/');
    await dismissCookies(p);
    // two #login-form elements exist (hidden auth popup + page form); 2.4.8 renamed
    // the visible password field. Scope to the visible form, address fields by name.
    const form = p.locator('form#login-form:visible').first();
    await form.locator('input[name="login[username]"]').fill(CUST.email);
    await form.locator('input[name="login[password]"]').fill(CUST.pass);
    await Promise.all([
      p.waitForNavigation({ waitUntil: 'domcontentloaded' }).catch(() => {}),
      form.locator('button[type=submit]').first().click(),
    ]);
    await p.waitForTimeout(6000);
    const r = await gotoRetry(p, BASE + '/customer/account/');
    const body = await assertNoAppError(p, 'account');
    if (/Customer Login/i.test(body)) { await shot(p, 'login-fail'); throw new Error('still on login page'); }
    if (r.status() !== 200) throw new Error('dashboard HTTP ' + r.status());
    return 'logged in, dashboard renders';
  });

  await step('customer: account pages', async () => {
    const out = [];
    for (const route of ['/sales/order/history/', '/customer/address/']) {
      const r = await gotoRetry(p, BASE + route);
      const body = await assertNoAppError(p, 'acct' + route.replace(/\W+/g, '-'));
      if (r.status() !== 200) throw new Error(route + ' HTTP ' + r.status());
      if (/Customer Login/i.test(body)) throw new Error(route + ' bounced to login');
      out.push(route + ' 200');
    }
    return out.join(', ');
  });

  // ---------------------------------------------------------------- checkout
  async function placeOrder(method) {
    await p.waitForLoadState('load').catch(() => {});
    await addToCart(D.fixtures.simple, 'order-' + method);
    await gotoRetry(p, BASE + '/checkout/');
    await dismissCookies(p);
    await p.waitForTimeout(20000);
    await assertNoAppError(p, 'checkout-' + method);

    // a logged-in customer with a saved address shows a selector, not the fields
    const newAddress = await p.locator('[name="firstname"]').first().isVisible().catch(() => false);
    const set = async (sel, val) => {
      if (!newAddress) return;
      const el = p.locator(sel).first();
      await el.waitFor({ state: 'visible', timeout: 45000 });
      await el.fill(val);
      await el.dispatchEvent('change');
      await el.dispatchEvent('blur');
      await p.waitForTimeout(500);
    };
    const email = p.locator('#customer-email');
    if (await email.isVisible().catch(() => false) && !(await email.inputValue().catch(() => ''))) {
      await set('#customer-email', CUST.email);
    }
    await set('[name="firstname"]', CUST.firstname);
    await set('[name="lastname"]', CUST.lastname);
    await set('[name="street[0]"]', CUST.street);
    await set('[name="city"]', CUST.city);
    if (newAddress) await p.selectOption('[name="country_id"]', CUST.country).catch(() => {});
    await set('[name="postcode"]', CUST.postcode);
    await set('[name="telephone"]', CUST.telephone);
    await p.waitForTimeout(20000);

    // shipping rates only appear once the address is complete
    const ship = p.locator('input[type=radio]:not([name="payment[method]"])');
    await ship.first().waitFor({ state: 'visible', timeout: 90000 }).catch(() => {});
    if (!(await ship.count())) { await shot(p, 'no-shipping'); throw new Error('no shipping method offered'); }
    if (!(await ship.first().isChecked().catch(() => false))) {
      await ship.first().check({ force: true });
      await p.waitForTimeout(10000);
    }

    if (!(await p.locator(`#${method}`).isChecked().catch(() => false))) {
      const lbl = p.locator(`label[for="${method}"]`).first();
      if (await lbl.isVisible().catch(() => false)) await lbl.click();
      else await p.locator(`#${method}`).check({ force: true });
      await p.waitForTimeout(5000);
    }
    if (!(await p.locator(`#${method}`).isChecked())) throw new Error('could not select ' + method);

    if (method === 'purchaseorder') {
      const po = p.locator('[name="payment[po_number]"], #po_number').first();
      await po.waitFor({ state: 'visible', timeout: 30000 });
      await po.fill('PO-' + stamp);
      await po.dispatchEvent('change');
      await po.dispatchEvent('blur');
      await p.waitForTimeout(4000);
    }
    await shot(p, 'checkout-' + method);

    // every payment block renders a Place Order button; only the selected one is enabled
    const place = p.locator('button.action.primary.checkout:visible:not([disabled])').first();
    await place.waitFor({ state: 'visible', timeout: 45000 });
    await place.click();
    await p.waitForTimeout(30000);

    const body = await p.locator('body').innerText();
    if (!/Thank you for your purchase|order number/i.test(body)) {
      await shot(p, 'order-fail-' + method);
      throw new Error('no success page. url=' + p.url() + ' body=' + body.replace(/\s+/g, ' ').slice(0, 250));
    }
    await shot(p, 'success-' + method);
    const m = body.match(/(?:order number is|order number|order #)[:\s#]*([0-9]{6,})/i);
    if (m) return m[1];
    return (sql(`select increment_id from ${PREFIX}sales_order order by entity_id desc limit 1;`)
      .match(/\d{6,}/) || ['placed'])[0];
  }

  const orders = {};
  for (const method of (D.payments.test || ['checkmo'])) {
    orders[method] = await step(`checkout: place order with ${method}`, () => placeOrder(method));
  }

  await step('order: stored correctly in database', async () => {
    const id = Object.values(orders).find(Boolean);
    if (!id) throw new Error('no order placed');
    // every non-aggregated column must be grouped under ONLY_FULL_GROUP_BY
    const row = sql(
      `select o.increment_id, o.state, o.status, o.grand_total, p.method, count(i.item_id) items ` +
      `from ${PREFIX}sales_order o ` +
      `join ${PREFIX}sales_order_payment p on p.parent_id=o.entity_id ` +
      `join ${PREFIX}sales_order_item i on i.order_id=o.entity_id ` +
      `where o.increment_id='${id}' ` +
      `group by o.entity_id, o.increment_id, o.state, o.status, o.grand_total, p.method;`);
    if (!row.includes(String(id))) throw new Error('order row not found: ' + row);
    return row.replace(/\s+/g, ' ').trim();
  });

  // ---------------------------------------------------------------- other stores
  for (const store of D.stores.slice(1)) {
    await step(`store ${store.name}: storefront renders`, async () => {
      const r = await gotoRetry(p, store.baseUrl + '/');
      await dismissCookies(p);
      await assertNoAppError(p, 'store-' + store.name);
      if (r.status() !== 200) throw new Error('HTTP ' + r.status());
      await shot(p, 'store-' + store.name);
      return 'HTTP 200';
    });
    await step(`store ${store.name}: search returns results`, async () => {
      const r = await gotoRetry(p,
        `${store.baseUrl}/catalogsearch/result/?q=${encodeURIComponent(D.fixtures.searchTerm)}`);
      await assertNoAppError(p, 'store-search-' + store.name);
      if (r.status() !== 200) throw new Error('HTTP ' + r.status());
      const n = await productCount(p);
      if (n < 1) throw new Error('no results on this store');
      return `${n} results`;
    });
  }

  // ---------------------------------------------------------------- admin
  const adminPath = (D.admin && D.admin.path) || '/admin';
  await step('admin: login', async () => {
    if (!ADMIN_PASS) throw new Error('ADMIN_PASS not provided');
    await gotoRetry(p, BASE + adminPath);
    await p.fill('#username', (D.admin && D.admin.user) || 'upgradetest');
    await p.fill('#login', ADMIN_PASS);
    await Promise.all([
      p.waitForNavigation({ waitUntil: 'domcontentloaded' }).catch(() => {}),
      p.locator('button.action-login, .actions .action-primary').first().click(),
    ]);
    await p.waitForTimeout(10000);
    if (/Welcome, please sign in|Invalid Form Key|incorrect/i.test(await p.locator('body').innerText())) {
      await shot(p, 'admin-login-fail');
      throw new Error('admin login rejected');
    }
    return 'signed in';
  });

  // Admin URLs carry a per-route secret key — harvest real links, never build them.
  async function adminMenu(frag) {
    await gotoRetry(p, `${BASE}${adminPath}/admin/dashboard/`);
    await p.waitForTimeout(3000);
    const href = await p.evaluate(f => {
      const a = [...document.querySelectorAll('a[href]')].find(x => x.href.includes(f));
      return a ? a.href : null;
    }, frag);
    if (!href) throw new Error('no admin menu link for ' + frag);
    return gotoRetry(p, href);
  }
  async function keyedLinkFromGrid(menuFrag, pattern) {
    await adminMenu(menuFrag);
    await p.waitForTimeout(20000);
    const href = await p.evaluate(pat => {
      const re = new RegExp(pat);
      const a = [...document.querySelectorAll('a[href]')].find(x => re.test(x.href));
      return a ? a.href : null;
    }, pattern);
    if (!href) throw new Error('no keyed link matching ' + pattern);
    return href;
  }

  const adminPage = (name, frag, expect) => step(name, async () => {
    const r = await adminMenu(frag);
    const status = r ? r.status() : 200;
    if (status !== 200) throw new Error('HTTP ' + status);
    await p.locator('.page-title-wrapper h1, h1.page-title').first()
      .waitFor({ state: 'visible', timeout: 120000 }).catch(() => {});
    await p.waitForTimeout(5000);
    await assertNoAppError(p, name.replace(/\W+/g, '-'));
    const h1 = await p.locator('.page-title-wrapper h1, h1.page-title').first().innerText().catch(() => '');
    if (expect && !new RegExp(expect, 'i').test(h1)) {
      await shot(p, 'miss-' + name.replace(/\W+/g, '-'));
      throw new Error(`expected h1 ~ "${expect}", got "${h1.trim()}"`);
    }
    return `HTTP ${status}, h1="${h1.trim().slice(0, 40)}"`;
  });

  await adminPage('admin: order grid', 'sales/order/index', 'Orders');
  await adminPage('admin: product grid', 'catalog/product/index', 'Products');
  await adminPage('admin: category page', 'catalog/category/index', 'Categor');
  await adminPage('admin: customer grid', 'customer/index/index', 'Customers');
  await adminPage('admin: CMS pages', 'cms/page/index', 'Pages');
  await adminPage('admin: cache management', 'admin/cache/index', 'Cache');

  // write operations — a read-only grid check proves very little
  await step('admin: save a product', async () => {
    const href = await keyedLinkFromGrid('catalog/product/index', 'catalog/product/edit');
    await gotoRetry(p, href);
    await p.waitForTimeout(20000);
    await assertNoAppError(p, 'admin-product-edit');
    const save = p.locator('#save-button, button[data-ui-id="product-edit-form-save-button"]').first();
    await save.waitFor({ state: 'visible', timeout: 120000 });
    await save.click();
    await p.waitForTimeout(30000);
    const body = await assertNoAppError(p, 'admin-product-save');
    if (!/You saved the product/i.test(body)) throw new Error('no save confirmation');
    return 'product saved';
  });

  await step('admin: save a CMS page', async () => {
    const href = await keyedLinkFromGrid('cms/page/index', 'cms/page/edit');
    await gotoRetry(p, href);
    await p.waitForTimeout(35000);
    await assertNoAppError(p, 'admin-cms-edit');
    const save = p.locator('#save-button, button[data-ui-id="page-actions-toolbar-save-button"], button:has-text("Save Page")').first();
    await save.waitFor({ state: 'visible', timeout: 120000 });
    await save.click();
    await p.waitForTimeout(30000);
    const body = await assertNoAppError(p, 'admin-cms-save');
    if (!/You saved the page/i.test(body)) throw new Error('no save confirmation');
    return 'CMS page saved';
  });

  await step('admin: invoice the order this run placed', async () => {
    const id = Object.values(orders).find(x => /^\d+$/.test(String(x)));
    if (!id) throw new Error('no order from this run to invoice');
    const entity = (sql(`select entity_id from ${PREFIX}sales_order where increment_id='${id}';`)
      .match(/^\d+$/m) || [])[0];
    if (!entity) throw new Error(`order ${id} not found in ${PREFIX}sales_order`);
    // Any keyed order-view link works as a template: the admin secret key covers route,
    // controller and action only, not order_id (Magento\Backend\Model\Url::getSecretKey).
    // An empty grid means async grid indexing has not caught up; see SKILL.md phase 2.
    const template = await keyedLinkFromGrid('sales/order/index', 'sales/order/view/order_id');
    const viewHref = template.replace(/order_id\/\d+/, `order_id/${entity}`);
    await gotoRetry(p, viewHref);
    const shown = await p.locator('body').innerText();
    if (!shown.includes(String(id))) throw new Error(`order view did not show order ${id}`);
    await p.waitForTimeout(20000);
    await assertNoAppError(p, 'admin-order-view');
    const invoice = p.locator('#order_invoice, button:has-text("Invoice")').first();
    if (!(await invoice.isVisible().catch(() => false))) {
      await shot(p, 'admin-no-invoice-button');
      return 'order not invoiceable — order view rendered clean';
    }
    await invoice.click();
    await p.waitForTimeout(30000);
    await assertNoAppError(p, 'admin-invoice-new');
    const submit = p.locator('button.action-submit, button[title="Submit Invoice"], button:has-text("Submit Invoice")').first();
    await submit.waitFor({ state: 'visible', timeout: 120000 });
    await submit.click();
    await p.waitForTimeout(30000);
    const body = await assertNoAppError(p, 'admin-invoice-submit');
    if (!/The invoice has been created/i.test(body)) throw new Error('no invoice confirmation');
    return 'invoice created';
  });

  fs.writeFileSync(`${OUT}/results.json`, JSON.stringify({
    label: LABEL, when: new Date().toISOString(),
    customer: CUST.email, orders,
    untestedPayments: (D.payments && D.payments.untested) || [],
    results, pageErrors: [...new Set(pageErrors)].slice(0, 20),
  }, null, 2));

  const failed = results.filter(r => !r.ok);
  console.log(`\n=== ${LABEL}: ${results.length - failed.length}/${results.length} passed ===`);
  if (failed.length) console.log('FAILED: ' + failed.map(f => f.name).join(' | '));
  if (pageErrors.length) console.log('JS page errors: ' + [...new Set(pageErrors)].slice(0, 8).join(' || '));

  await b.close();
  process.exit(0);
})().catch(e => { console.error('FATAL', e.stack); process.exit(1); });
