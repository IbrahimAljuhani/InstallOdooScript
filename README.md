# l10n_sa_edi_pos_direct

**Enhanced Saudi Arabia ZATCA Integration for Point of Sale**

An optimized replacement for the standard `l10n_sa_edi_pos` module, providing direct ZATCA integration with significant performance improvements and enhanced functionality.

## Overview / نظرة عامة

An optimized replacement for the standard `l10n_sa_edi_pos` module, providing direct ZATCA integration with significant performance improvements and enhanced functionality designed specifically for high-volume retail environments in Saudi Arabia.

موديول محسن بديل عن `l10n_sa_edi_pos` الافتراضي، يوفر تكامل مباشر مع هيئة الزكاة والضريبة مع تحسينات كبيرة في الأداء ووظائف محسنة

## Module Comparison / مقارنة الموديولات

| Feature / الخاصية | l10n_sa_edi_pos (Standard / الافتراضي) | l10n_sa_edi_pos_direct (Enhanced / المحسن) |
|---------|---------------------------|-----------------------------------|
| **Customer Data Requirement / متطلبات بيانات العميل** | ❌ Requires full customer data for every POS transaction<br/>يتطلب بيانات العميل كاملة مع كل عملية | ✅ Cash customer support (no customer data needed)<br/>دعم العميل النقدي (لا يتطلب بيانات العميل) |
| **PDF Generation / إنشاء ملف PDF** | ❌ Creates A4 PDF invoice for every POS order<br/>ينشئ فاتورة PDF مع كل طلب | ✅ No PDF generation - POS receipts only<br/>لا ينشئ PDF - إيصالات نقاط البيع فقط |
| **Database Load / حمل قاعدة البيانات** | ❌ Need to connect database with every transaction<br/>يتطلب الاتصال بقاعدة البيانات مع كل عملية | ✅ Minimal database impact - frontend processing<br/>تأثير قليل على قاعدة البيانات - معالجة على واجهة نقاط البيع فقط |
| **QR Code Compliance / امتثال رمز QR** | ❌ POS Receipts QR Code with Basic Phase 1 (only 5 fields)<br/>رمز QR بالمرحلة الأولى الأساسية (5 حقول فقط) | ✅ POS Receipts QR Code with Full Phase 2 (9 fields + digital signatures)<br/>رمز QR بالمرحلة الثانية كاملة (9 حقول + توقيعات رقمية) |
| **ZATCA Synchronization / مزامنة هيئة الزكاة** | ❌ Immediate sync required (not required for simplified)<br/>مزامنة فورية مطلوبة (غير مطلوبة للمبسطة) | ✅ Compliant 24-hour async reporting<br/>تقارير غير متزامنة خلال 24 ساعة حسب اللوائح |
| **Record Duplication / تكرار السجلات** | ❌ POS Order + Account Invoice (double records)<br/>طلب نقاط البيع + فاتورة محاسبية (سجلات مضاعفة) | ✅ Single POS record - no duplication<br/>سجل نقاط البيع واحد - لا تكرار |



## Installation & Configuration

1. **Remove Standard Module**: Uninstall the existing `l10n_sa_edi_pos` module from your system to avoid conflicts
2. **Install Enhanced Module**: Install `l10n_sa_edi_pos_direct` through the Apps menu or via command line
3. **Verify Configuration**: Ensure your ZATCA certificate is properly configured in the invoice journal settings
4. **Enable Direct Mode**: Navigate to POS Configuration and enable "ZATCA Direct Mode" for your point of sale
5. **Test Transactions**: Perform test transactions to verify QR code generation and ZATCA submission workflow

## Changelog

### Version 18.0.1.5.0 — 2026-08-02
**Contributor:** Ibrahim Aljuhani

**Added:**
- Re-added `queue_job` (OCA) dependency and wired it into `_schedule_zatca_submission`: orders are now submitted to ZATCA near-instantly via `with_delay()` instead of waiting for the next cron tick. Verified end-to-end on the test server (jobrunner starts on boot, a test job completed in ~75ms).
- Cron jobs are kept as a fallback safety net rather than the primary submission path. Job dispatch failures are logged only and never block the POS payment flow.

---

### Version 18.0.1.4.4 — 2026-08-02
**Contributor:** Ibrahim Aljuhani

**Fixed:**
- Critical: an xpath matching the literal English text "Powered by Odoo" crashed the entire receipt screen with an uncaught OWL error on any non-English POS interface (text is translated before inheritance is applied, so the match failed) — reported as a blank white screen after payment with no receipt preview/auto-print. Replaced with a structural CSS rule that doesn't depend on translated text.
- Critical: the `point_of_sale.ReceiptHeader` xpath fix from 18.0.1.4.2 also crashed the receipt screen in production (`img#qrcode` element not found at inheritance-resolution time in this environment). Two consecutive xpath/t-inherit failures on this template means it isn't reliable in this deployment. Removed the `t-inherit` block entirely; header-QR hiding is now done purely via CSS, which cannot crash template rendering.
- Confirmed working: receipt preview renders correctly after both fixes above.

---

### Version 18.0.1.4.3 — 2026-08-02
**Contributor:** Ibrahim Aljuhani

**Fixed:**
- ZATCA BR-16 / BR-S-08 rejection ("An Invoice shall have at least one Invoice line") on orders where every line is a negative-price discount/promo product with no regular product line. The AllowanceCharge logic added in 18.0.1.4.1 diverted all negative lines out of the invoice lines list, producing zero `InvoiceLine` elements and a malformed XML rejected by ZATCA. Confirmed against real rejected submissions (2026-04-02, 2026-04-16, 2026-06-06 — all orders with no actual product line). Now raises a clear error before submission instead of sending an invalid document.

---

For older versions and full history, see [CHANGELOG.md](https://github.com/IbrahimAljuhani/l10n_sa_edi_pos_direct/blob/18.0/CHANGELOG.md).

## Support

This module is designed for **Saudi Arabian businesses** requiring **high-performance ZATCA compliance** in retail environments.

---

**Author**: EasyERPS, AMR Hawsawi, Ibrahim Aljuhani  
**License**: LGPL-3  
**Website**: https://easyerps.com
