// شاخص‌های PPI آمریکا (BLS) که برنامه از آن‌ها استفاده می‌کند — مقادیر سالانه = میانگین ماهانه‌ی FRED (NSA).
// PCU333912333912 = Air & gas compressor manufacturing (Jun 1984 = 100)؛ از شیت Escalation_Index بانک
// Air_Compressor_Price_Bank v8 (دریافت 2026-10-15؛ ۲۰۲۶ = میانگین ژانویه تا اوت؛ ۲۰۲۷ منتشر نشده — کاربر وارد کند).

import 'eurostat_ppi.dart' show PpiSeriesSeed;

const blsPpiSeeds = <PpiSeriesSeed>[
  PpiSeriesSeed('PPI_US_333912_GREG', 'PPI کمپرسور هوا و گاز آمریکا (میلادی)',
      'US BLS PPI PCU333912333912 — air & gas compressor manufacturing (Jun 1984=100)', 'NAICS 333912', [
    (2005, 161.0, 'official'),
    (2006, 165.8, 'official'),
    (2007, 171.7, 'official'),
    (2008, 181.0, 'official'),
    (2009, 188.3, 'official'),
    (2010, 190.1, 'official'),
    (2011, 200.25, 'official'),
    (2012, 205.7, 'official'),
    (2013, 212.4, 'official'),
    (2014, 217.9, 'official'),
    (2015, 220.7, 'official'),
    (2016, 221.5, 'official'),
    (2017, 225.4, 'official'),
    (2018, 234.2, 'official'),
    (2019, 241.9, 'official'),
    (2020, 248.1, 'official'),
    (2021, 259.7, 'official'),
    (2022, 304.7, 'official'),
    (2023, 333.3, 'official'),
    (2024, 348.8, 'official'),
    (2025, 371.2, 'official'),
    (2026, 387.3, 'partial'),
  ]),
];
