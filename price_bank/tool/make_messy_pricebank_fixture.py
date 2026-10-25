# اجرا: python3 -I tool/make_messy_pricebank_fixture.py test/fixtures_private/PriceBank_test.xlsx test/fixtures_private/PriceBank_test_messy.xlsx
"""بانک قیمت تجمیعی «به‌هم‌ریخته» برای آزمون انعطاف: نام شیت‌ها و چند سرستون عوض، ردیف عنوان دو ردیف پایین‌تر، یک ستون حذف."""
import sys, openpyxl
src, dst = sys.argv[1], sys.argv[2]
wb = openpyxl.load_workbook(src)
ren = {'Tag No.': 'Tag Number', 'Unit Price (Reference)': 'Unit Price', 'Cost Year': 'Cost Year (Shamsi)',
       'Reference Currency': 'Currency', 'Equipment Name': 'Equipment  name'}
for ws in wb.worksheets:
    if ws.title == 'Vendor_Quotes':
        ws.title = 'Quotes'
        continue
    for c in ws[4]:
        if isinstance(c.value, str) and c.value in ren: c.value = ren[c.value]
    for c in ws[4]:
        if c.value == 'Incoterm':
            ws.delete_cols(c.column); break
    ws.insert_rows(2, 2)
    ws.title = ws.title + ' bank'
wb.save(dst)
