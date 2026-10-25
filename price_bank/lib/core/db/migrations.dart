// مهاجرت‌های ساختار دیتابیس.
//
// قانون: هرگز یک مهاجرت منتشرشده را تغییر ندهید؛ برای هر تغییر، مهاجرت جدید با
// شماره‌ی بعدی اضافه کنید. به این ترتیب دیتابیس هر کاربر با هر نسخه‌ی قبلی
// بدون از دست رفتن داده به آخرین نسخه می‌رسد.

class Migration {
  const Migration(this.version, this.description, this.statements);
  final int version;
  final String description;
  final List<String> statements;
}

const _audit = '''
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  created_by INTEGER,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_by INTEGER''';

const migrations = <Migration>[
  Migration(1, 'ساختار اولیه: کاربران، رشته‌ها، قالب‌ها، اقلام، قیمت‌ها، شاخص‌ها، تاریخچه', [
    '''
CREATE TABLE app_meta(
  key TEXT PRIMARY KEY,
  value TEXT
)''',
    '''
CREATE TABLE settings(
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''',
    // ---------------- کاربران و دسترسی
    '''
CREATE TABLE users(
  id INTEGER PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('admin','editor','reviewer','viewer')),
  active INTEGER NOT NULL DEFAULT 1,
  $_audit
)''',
    '''
CREATE TABLE disciplines(
  code TEXT PRIMARY KEY,
  name_fa TEXT NOT NULL,
  name_en TEXT,
  sort INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1
)''',
    '''
CREATE TABLE user_scopes(
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  discipline_code TEXT NOT NULL REFERENCES disciplines(code),
  can_view INTEGER NOT NULL DEFAULT 1,
  can_edit INTEGER NOT NULL DEFAULT 0,
  can_approve INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(user_id, discipline_code)
)''',
    // ---------------- رده‌بندی و قالب مشخصات
    '''
CREATE TABLE categories(
  id INTEGER PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  discipline_code TEXT NOT NULL REFERENCES disciplines(code),
  parent_id INTEGER REFERENCES categories(id),
  name_fa TEXT NOT NULL,
  name_en TEXT,
  description_fa TEXT,
  sort INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1,
  escalation_method TEXT NOT NULL DEFAULT 'M6'
)''',
    '''
CREATE TABLE field_defs(
  id INTEGER PRIMARY KEY,
  category_id INTEGER NOT NULL REFERENCES categories(id),
  key TEXT NOT NULL,
  label_fa TEXT NOT NULL,
  label_en TEXT,
  group_key TEXT,
  group_fa TEXT,
  storage TEXT NOT NULL CHECK(storage IN ('core','spec','price','calc')),
  data_type TEXT NOT NULL CHECK(data_type IN ('text','number','enum')),
  list_key TEXT,
  unit TEXT,
  help_fa TEXT,
  source_ref TEXT,
  sort INTEGER NOT NULL DEFAULT 0,
  UNIQUE(category_id, key)
)''',
    '''
CREATE TABLE enum_options(
  list_key TEXT NOT NULL,
  value TEXT NOT NULL,
  label_fa TEXT,
  description TEXT,
  sort INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(list_key, value)
)''',
    // ---------------- پروژه، سند، فروشنده
    '''
CREATE TABLE projects(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  name_fa TEXT,
  capacity_bpd REAL,
  location TEXT,
  notes TEXT,
  $_audit
)''',
    '''
CREATE TABLE documents(
  id INTEGER PRIMARY KEY,
  project_id INTEGER REFERENCES projects(id),
  title TEXT NOT NULL,
  doc_ref TEXT,
  revision TEXT NOT NULL DEFAULT '',
  doc_type TEXT,
  issue_year INTEGER,
  issue_month INTEGER,
  source_fx_eur REAL,
  source_fx_usd REAL,
  fx_rate_type TEXT,
  consultant TEXT,
  file_name TEXT,
  notes TEXT,
  $_audit,
  UNIQUE(project_id, title, revision)
)''',
    '''
CREATE TABLE vendors(
  id INTEGER PRIMARY KEY,
  code TEXT UNIQUE,
  name TEXT NOT NULL,
  country TEXT,
  origin TEXT,
  avl_status TEXT,
  rank TEXT,
  types_supplied TEXT,
  licensor TEXT,
  notes TEXT,
  $_audit
)''',
    // ---------------- اقلام و مقادیر
    '''
CREATE TABLE items(
  id INTEGER PRIMARY KEY,
  category_id INTEGER NOT NULL REFERENCES categories(id),
  project_id INTEGER REFERENCES projects(id),
  tag TEXT,
  name TEXT NOT NULL,
  quantity REAL,
  include_in_totals INTEGER NOT NULL DEFAULT 1,
  remarks TEXT,
  legacy_ref TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','archived')),
  $_audit
)''',
    'CREATE INDEX ix_items_cat ON items(category_id, status)',
    'CREATE INDEX ix_items_tag ON items(tag)',
    'CREATE INDEX ix_items_project ON items(project_id)',
    '''
CREATE TABLE item_values(
  item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  field_key TEXT NOT NULL,
  value_text TEXT,
  value_num REAL,
  PRIMARY KEY(item_id, field_key)
) WITHOUT ROWID''',
    'CREATE INDEX ix_values_key ON item_values(field_key, value_text)',
    // برچسب هر فیلد: inferred = مقدار استنباطی، fx = تبدیل‌شده با نرخ بانک؛ و یادداشت شاهد
    '''
CREATE TABLE field_meta(
  item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  field_key TEXT NOT NULL,
  flag TEXT,
  note TEXT,
  PRIMARY KEY(item_id, field_key)
) WITHOUT ROWID''',
    // هر مشاهده‌ی قیمت (استعلام، برآورد، قرارداد) — هرگز بازنویسی نمی‌شود، فقط اصلاح با تاریخچه
    '''
CREATE TABLE price_obs(
  id INTEGER PRIMARY KEY,
  item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  document_id INTEGER REFERENCES documents(id),
  vendor_id INTEGER REFERENCES vendors(id),
  kind TEXT NOT NULL DEFAULT 'estimate'
    CHECK(kind IN ('quote','estimate','contract','escalated','other')),
  is_primary INTEGER NOT NULL DEFAULT 0,
  currency TEXT,
  amount REAL,
  amount_text TEXT,
  cost_year INTEGER,
  cost_year_text TEXT,
  cost_month INTEGER,
  incoterm TEXT,
  price_basis TEXT,
  source_location TEXT,
  source_fx_rate REAL,
  extra_json TEXT,
  notes TEXT,
  $_audit
)''',
    'CREATE INDEX ix_obs_item ON price_obs(item_id, is_primary)',
    'CREATE INDEX ix_obs_doc ON price_obs(document_id)',
    // ---------------- شاخص‌ها و نرخ ارز
    '''
CREATE TABLE index_series(
  code TEXT PRIMARY KEY,
  name_fa TEXT NOT NULL,
  name_en TEXT,
  kind TEXT NOT NULL CHECK(kind IN ('level','annual_rate')),
  grp TEXT,
  unit TEXT,
  base TEXT,
  source TEXT,
  calendar TEXT NOT NULL DEFAULT 'jalali',
  sort INTEGER NOT NULL DEFAULT 0,
  user_defined INTEGER NOT NULL DEFAULT 0
)''',
    '''
CREATE TABLE index_values(
  series_code TEXT NOT NULL REFERENCES index_series(code) ON DELETE CASCADE,
  period_key TEXT NOT NULL,
  year INTEGER NOT NULL,
  quarter INTEGER,
  month INTEGER,
  value REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'official',
  source TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_by INTEGER,
  PRIMARY KEY(series_code, period_key)
)''',
    '''
CREATE TABLE fx_rate_types(
  code TEXT PRIMARY KEY,
  name_fa TEXT NOT NULL,
  sort INTEGER NOT NULL DEFAULT 0
)''',
    // ---------------- ضرایب نرمال‌سازی
    '''
CREATE TABLE factors(
  set_code TEXT NOT NULL,
  grp TEXT NOT NULL,
  option TEXT NOT NULL,
  provisional REAL NOT NULL,
  calibrated REAL,
  description TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_by INTEGER,
  PRIMARY KEY(set_code, grp, option)
)''',
    // ---------------- تاریخچه‌ی همه‌ی تغییرات
    '''
CREATE TABLE audit_log(
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL DEFAULT (datetime('now')),
  user_id INTEGER,
  entity TEXT NOT NULL,
  entity_id TEXT,
  field TEXT,
  old_value TEXT,
  new_value TEXT,
  reason TEXT,
  batch_id TEXT
)''',
    'CREATE INDEX ix_audit_entity ON audit_log(entity, entity_id)',
    'CREATE INDEX ix_audit_ts ON audit_log(ts)',
  ]),
  Migration(2, 'نام «جدول پیش‌فرض» برای نرخ ارز مرجع، تنظیم روش تعدیل، جدول‌های نرخ ارز کاربر', [
    "UPDATE fx_rate_types SET name_fa = 'جدول پیش‌فرض' WHERE code = 'V8'",
    "UPDATE index_series SET name_fa = replace(name_fa, 'جدول مرجع v8', 'جدول پیش‌فرض') "
        "WHERE code IN ('FX_USD_V8', 'FX_EUR_V8')",
    "INSERT OR IGNORE INTO settings(key, value) VALUES ('escalation_method', 'M6')",
    'ALTER TABLE fx_rate_types ADD COLUMN user_defined INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE fx_rate_types ADD COLUMN description TEXT',
  ]),
  // بند ۱ و ۵ برنامه‌ی تغییرات (۱۴۰۵/۰۸/۰۴): پنهان کردن یک سند از مشاهده و محاسبات؛ سند مبدأ هر قلم
  Migration(3, 'پنهان کردن سند؛ سند مبدأ هر قلم', [
    'ALTER TABLE documents ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE items ADD COLUMN source_document_id INTEGER',
    // سند مبدأ = سند نخستین قیمت (جز سند کمکی «قیمت‌های بازنگری قبلی»)
    '''
UPDATE items SET source_document_id = (
  SELECT o.document_id FROM price_obs o JOIN documents d ON d.id = o.document_id
  WHERE o.item_id = items.id ORDER BY (d.doc_type = 'mto_previous'), o.id LIMIT 1)''',
    // قلم بی‌قیمت: از شرح ورود در تاریخچه («ورود MTO <عنوان> (…)»)
    '''
UPDATE items SET source_document_id = (
  SELECT d.id FROM audit_log a JOIN documents d ON d.project_id IS items.project_id
    AND substr(a.reason, 1, length(d.title) + 11) = 'ورود MTO ' || d.title || ' ('
  WHERE a.entity = 'item' AND a.entity_id = CAST(items.id AS TEXT) AND a.field = '*' ORDER BY a.id LIMIT 1)
WHERE source_document_id IS NULL''',
    'CREATE INDEX ix_items_srcdoc ON items(source_document_id)',
  ]),
];
