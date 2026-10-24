# اجرا: python3 -I tool/make_estimate_fixture.py <برآورد.xlsx> test/fixtures/<نام>.xlsx [--values]
"""نسخه‌ی ناشناس یک فایل برآورد/MTO برای آزمون خواننده (ساختار، ادغام‌ها و فرمول‌ها همان می‌ماند).

- نام پروژه و متن‌های شناسه (نام فایل/پروژه در جلد، سازنده، شرکت) جایگزین می‌شوند.
- هر عدد ≥ ۱۰۰۰ (ثابت یا مقدار ذخیره‌شده‌ی فرمول) × ضریب ثابت K و گرد می‌شود؛ جمع‌ها و حاصل‌ضرب‌های «یک عدد بزرگ × عدد کوچک»
  سازگار می‌مانند، پس کنترل جمع شیت‌ها در آزمون معتبر است.
- --values: نسخه‌ی «فقط مقدار» (فرمول‌ها حذف) برای آزمون فایلی که کاربر Paste Values کرده است.
- تصویرها (آرم شرکت‌ها) با تصویر سفید هم‌اندازه جایگزین می‌شوند.
- XML مستقیم ویرایش می‌شود (openpyxl مقدار ذخیره‌شده‌ی فرمول را نگه نمی‌دارد).
"""
import io
import re
import sys
import zipfile

from PIL import Image

K = 1.013
src, dst = sys.argv[1], sys.argv[2]
values_only = '--values' in sys.argv[3:]
REPL = [
    (re.compile(r'karanj', re.I), 'Sample-K'),
]


def scale(m):
    v = float(m.group(2))
    if abs(v) >= 1000:
        v = round(v * K)
        txt = str(int(v))
    else:
        txt = m.group(2)
    return m.group(1) + txt + m.group(3)


def fix_sheet(xml):
    # <v>عدد</v> در خانه‌های عددی (نه رشته‌ی مشترک t="s" یا t="str")
    def cell(m):
        c = m.group(0)
        if re.search(r'\st="(s|str|inlineStr|b|e)"', m.group(1)):
            return c
        c = re.sub(r'(<v>)(-?\d+(?:\.\d+)?(?:E[-+]?\d+)?)(</v>)', scale, c)
        if values_only:
            c = re.sub(r'<f[^>]*/>|<f[^>]*>.*?</f>', '', c, flags=re.S)
        return c
    return re.sub(r'<c(\s[^>]*)?>.*?</c>', cell, xml, flags=re.S)


def fix_text(xml):
    for p, r in REPL:
        xml = p.sub(r, xml)
    return xml


with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zout:
    for info in zin.infolist():
        data = zin.read(info.filename)
        name = info.filename
        if name.startswith('xl/worksheets/sheet') and name.endswith('.xml'):
            data = fix_text(fix_sheet(data.decode('utf-8'))).encode('utf-8')
        elif name in ('xl/sharedStrings.xml', 'xl/workbook.xml') or name.startswith('xl/comments'):
            data = fix_text(data.decode('utf-8')).encode('utf-8')
        elif name.startswith('xl/media/'):
            im = Image.open(io.BytesIO(data))
            buf = io.BytesIO()
            Image.new('RGB', im.size, 'white').save(buf, format='JPEG' if name.lower().endswith(('.jpg', '.jpeg')) else 'PNG')
            data = buf.getvalue()
        elif name.startswith('docProps/'):
            data = re.sub(rb'<(dc:creator|cp:lastModifiedBy|Company|Manager)>[^<]*</', rb'<\1></', data)
        zout.writestr(info, data)
