# Changelog — l10n_sa_edi_pos_direct

---

## [18.0.1.5.0] — 2026-08-02

### Contributors
- Ibrahim Aljuhani

**Added:**
- Re-added `queue_job` (OCA) dependency and wired it into `_schedule_zatca_submission`: orders are now submitted to ZATCA near-instantly via `with_delay()` instead of waiting for the next cron tick. Verified end-to-end on the test server: jobrunner thread starts on boot (`server_wide_modules = web,queue_job`), a manually dispatched job reached `state = done` within ~75ms.
- `batch_submit_pending_zatca` / `cron_retry_failed_zatca` cron jobs are kept as-is and now act as a fallback safety net (in case the immediate job was never enqueued or the runner was briefly unavailable) rather than the primary submission path.
- Job dispatch is wrapped in try/except so a `with_delay()` failure only logs a warning and never blocks or rolls back the POS payment flow.

---

## [18.0.1.4.4] — 2026-08-02

### Contributors
- Ibrahim Aljuhani

**Fixed:**
- Critical: `<xpath expr="//p[text()='Powered by Odoo']" position="replace"/>` in `order_receipt.xml` crashed the entire receipt screen with an uncaught `OwlError` ("Element cannot be located in element tree") on any non-English POS interface, because the text node is translated before QWeb inheritance is applied, so the literal English match fails. Reported by user: blank white screen after payment, receipt preview/auto-print never appeared. Replaced the text-matching xpath with a structural CSS rule (`.pos-receipt-order-data > p { display: none !important; }`) that doesn't depend on translated text.
- Critical: the `t-inherit="point_of_sale.ReceiptHeader"` xpath fix from 18.0.1.4.2 also crashed the receipt screen with `OwlError: Element '<xpath expr="//img[@id='qrcode']" ...>' cannot be located in element tree` — the `img#qrcode` element that `l10n_sa_pos` is expected to insert wasn't present at inheritance-resolution time in this environment. Two consecutive xpath/t-inherit failures on this template means xpath-based inheritance against `point_of_sale.ReceiptHeader` is not reliable in this deployment. Removed the `t-inherit` block entirely; header-QR hiding is now done purely via CSS (`img#qrcode` force-hide, restored in `zatca_pos.css`), which cannot crash template rendering since it doesn't touch QWeb inheritance at all.
- Confirmed working: receipt preview renders correctly after both fixes above.

---

## [18.0.1.4.3] — 2026-08-02

### Contributors
- Ibrahim Aljuhani

**Fixed:**
- ZATCA BR-16 / BR-S-08 rejection ("An Invoice shall have at least one Invoice line") on orders where every line is a negative-price discount/promo product with no regular product line. The AllowanceCharge logic added in 18.0.1.4.1 diverts all negative lines out of `invoice_data['lines']`, so an all-discount order produced zero `InvoiceLine` elements and a malformed XML that ZATCA rejected with a confusing schema error. Confirmed against real rejected submissions (2026-04-02, 2026-04-16, 2026-06-06 — all orders with no actual product line). Now raises a clear `UserError` before submission instead of sending an invalid document.

---

## [18.0.1.4.2] — 2026-08-02

### Contributors
- Ibrahim Aljuhani

**Fixed:**
- `order_receipt.xml` extended a non-existent template (`l10n_sa_pos.ReceiptHeader`) — corrected to `point_of_sale.ReceiptHeader` (the actual template `l10n_sa_pos` itself patches), so the header-QR removal for direct-mode orders now applies at the QWeb level instead of relying entirely on CSS/JS force-hiding
- `.zatca-qr-img` used a fixed `450px` size with `min-width`/`min-height`, which overflows Odoo's actual print container (`.render-container .pos-receipt` is `266px` in `@media print` per `point_of_sale`'s own `receipt_screen.scss`) — could clip the QR on real printed receipts. Changed to `width: 100%; max-width: 300px;` so it scales down to fit the real paper width instead of overflowing
- Removed duplicate `image-rendering` declaration (`pixelated` was dead code, overridden by `crisp-edges` on the next line)

**Removed:**
- Redundant `MutationObserver` in `pos_store.js` that force-hid the header QR via inline styles — no longer needed now that the QWeb-level fix above correctly omits the header QR for direct-mode orders

---

## [18.0.1.4.1] — 2026-08-02

### Contributors
- Ibrahim Aljuhani

**Fixed:**
- BR-KSA-F-04 violation: negative-price promo/discount lines are now emitted as document-level `AllowanceCharge` (reason code 95) instead of negative `InvoiceLine` amounts
- Line `unit_price` now derived from `price_subtotal` instead of raw `price_unit`, keeping `InvoiceLine`/`Price` consistent with line-level POS discounts (BR-KSA-EN16931-11)
- Duplicate ZATCA submission handling for HTTP 409 ("Invoice was already Reported successfully earlier"): detection now matches the actual ZATCA reporting API response shape (`validationResults.errorMessages[].message`), since the upstream fix checked a top-level `error` key and enum-style strings that do not exist in the real response
- `batch_submit_pending_zatca` now commits and persists `error` status/message per order instead of losing state on exception

**Removed:**
- Unused `queue_job` dependency from `__manifest__.py` — background processing is done via `ir.cron`, not `queue_job`; no `with_delay`/`@job` usage existed in the codebase. Will be reintroduced once actually wired up and tested.

---

## [18.0.1.4.0] — 2026-03-25

### Contributors
- Ibrahim Aljuhani

**Added:**
- QR Code moved to bottom of receipt (after order number and date)
- QR Code size set to 450×450px for better readability
- Hide "Powered by Odoo" from POS receipt
- Hide Odoo logo from Customer Display (sidebar and main area)

**Changed:**
- Improved `MutationObserver` — auto-disconnects after first successful execution for better performance
- Cleaned `zatca_pos.css` — removed unused dead CSS classes
- Updated `__manifest__.py` — replaced CSS wildcard with explicit file list
- Removed empty `customer_display.xml`

**Fixed:**
- QR Code duplication when ZATCA Direct Mode is enabled

---

## [18.0.1.3.0] — 2025-08-29

### Changed
- 🔧 **Enhanced QR Code Integration:** Improved override of compute_sa_qr_code method to properly use l10n_sa_pos functions
- 🚀 **Code Optimization:** Removed redundant QR generation methods and streamlined date formatting

---

## [18.0.1.2.0] — 2025-08-22

### Fixed
- 🔧 **Fixed Arabic Character Encoding:** Resolved btoa() InvalidCharacterError when using Arabic language interface
- 🛡️ **Improved Unicode Support:** Enhanced base64 encoding for ZATCA compliance with Arabic text

---

## [18.0.1.1.0] — 2025-08-20

### Added
- ✅ **Added ZATCA Refund Features:** Interactive refund reason popup with 6 predefined codes and full ZATCA compliance (BR-KSA-17, BR-KSA-F-04)
