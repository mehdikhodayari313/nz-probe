// ساخت یک فایل xlsx کوچک در حافظه برای خودآزمایی خواننده‌ی اکسل.
// این فایل شبیه قالب کاری مشاور (پازنان ۲) است و عمداً سه ایراد شناخته‌شده دارد:
//   ۱) قیمت فرمولی (J8)   ۲) عدد متنی (K8)   ۳) تاریخ ناموجود 2/29/2025 (M8)
// پس خواننده باید دقیقاً ۱ قلم، ۲ قیمت و ۳ ایراد گزارش کند.

import 'dart:convert';

import 'package:archive/archive.dart';

const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _nsR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _nsRel = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _wsType = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet';

List<int> buildSampleXlsx() {
  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '</Types>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8"?>'
        '<workbook xmlns="$_ns" xmlns:r="$_nsR"><sheets>'
        '<sheet name="PUMPS" sheetId="1" r:id="rId1"/>'
        '<sheet name="Hidden" sheetId="2" state="hidden" r:id="rId2"/>'
        '</sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="$_nsRel">'
        '<Relationship Id="rId1" Type="$_wsType" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="$_wsType" Target="/xl/worksheets/sheet2.xml"/>'
        '</Relationships>',
    // رشته‌ی ۰ عمداً به صورت rich text (دو تکه) است.
    'xl/sharedStrings.xml': '<?xml version="1.0" encoding="UTF-8"?>'
        '<sst xmlns="$_ns">'
        '<si><r><t xml:space="preserve">Item </t></r><r><t>No.</t></r></si>'
        '<si><t>Description</t></si>'
        '<si><t>استعلام 1</t></si>'
        '<si><t>P-101 A/B</t></si>'
        '<si><t>پمپ آزمایشی\nType: Centrifugal (OH2)\nRated Flow (m3/hr): 45</t></si>'
        '</sst>',
    'xl/worksheets/sheet1.xml': '<?xml version="1.0" encoding="UTF-8"?>'
        '<worksheet xmlns="$_ns"><sheetData>'
        '<row r="6"><c r="I6" t="s"><v>2</v></c></row>'
        '<row r="7"><c r="A7" t="s"><v>0</v></c><c r="B7" t="s"><v>1</v></c></row>'
        '<row r="8">'
        '<c r="A8" t="s"><v>3</v></c>'
        '<c r="B8" t="s"><v>4</v></c>'
        '<c r="C8"><v>2</v></c>'
        '<c r="J8"><f>4*1000</f><v>4000</v></c>'
        '<c r="K8" t="inlineStr"><is><t>43000</t></is></c>'
        '<c r="M8" t="inlineStr"><is><t>2/29/2025</t></is></c>'
        '</row>'
        '<row r="9"><c r="B9" t="inlineStr"><is><t>برآورد هزینه بدون سربار</t></is></c></row>'
        '</sheetData></worksheet>',
    'xl/worksheets/sheet2.xml': '<?xml version="1.0" encoding="UTF-8"?>'
        '<worksheet xmlns="$_ns"><sheetData><row r="1"><c r="A1"><v>1</v></c></row></sheetData></worksheet>',
  };

  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) throw StateError('ساخت فایل نمونه ناموفق بود');
  return encoded;
}
