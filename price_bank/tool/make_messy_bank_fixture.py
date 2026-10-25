# اجرا: python3 -I tool/make_messy_bank_fixture.py test/fixtures_private/<بانک>_test.xlsx test/fixtures_private/<بانک>_test_messy.xlsx cmp|des
# نسخه‌ی «به‌هم‌ریخته» از فیکسچر کوچک بانک برای آزمون انعطاف خواننده
import sys, openpyxl
src, dst, kind = sys.argv[1], sys.argv[2], sys.argv[3]
wb = openpyxl.load_workbook(src, data_only=True)
if 'App_Meta' in wb.sheetnames: del wb['App_Meta']
for name in ['Expected', 'Test_Cases']:
    if name in wb.sheetnames: del wb[name]
ms = wb['Master Database']
ren = {'Cost Year (Jalali)': 'Cost Year (Shamsi)', 'Unit Price (Reference)': 'Unit Price', 'Tag No.': 'Tag Number',
       'Equipment Name': 'Equipment  name', 'Reference Currency': 'Currency'}
for c in ms[4]:
    if isinstance(c.value, str) and c.value.strip() in ren: c.value = ren[c.value.strip()]
drop = {'cmp': 'Compressors per Price Unit', 'des': 'No. of Transformers', 'pump': 'Incoterm'}[kind]
for c in ms[4]:
    if c.value == drop:
        ms.delete_cols(c.column); break
# ستون تازه‌ی کاربر (در قالب برنامه نیست) — باید به‌صورت مشخصه ثبت شود
nc = ms.max_column + 1
ms.cell(4, nc, 'Site Altitude (m)')
for r in range(5, ms.max_row + 1):
    if ms.cell(r, 1).value is not None: ms.cell(r, nc, 700 + r)
ms.insert_rows(1, 2)  # عنوان دو ردیف پایین‌تر
ms.title = 'Master DB'
vq = wb['Vendor_Quotes']; vq.insert_rows(1, 1)
wb.save(dst)
