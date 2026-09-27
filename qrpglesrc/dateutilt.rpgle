     HNOMAIN OPTION(*SRCSTMT:*NODEBUGIO) DATFMT(*ISO)
      * ------------------------------------------------------------
      * DATEUTILT - RPGUnit test suite for service program DATEUTIL
      * Every exported procedure named test... is one test case.
      * Holiday tests use the sample row 2026-08-17 (Monday).
      * Build: RUCRTRPG TSTPGM(DODIKIBMI1/DATEUTILT)
      *          SRCFILE(DODIKIBMI1/QRPGLESRC) SRCMBR(DATEUTILT)
      *          BNDSRVPGM(DODIKIBMI1/DATEUTIL)
      * Run:   RUCALLTST TSTPGM(DODIKIBMI1/DATEUTILT)
      * ------------------------------------------------------------
      /COPY DODIKIBMI2/QINCLUDE,TESTCASE
      /COPY DODIKIBMI1/QRPGLESRC,DATEUTILPR
      * ------------------------------------------------------------
     PtestMonthBeg     B                   EXPORT
     D  testMonthBeg   PI
      /free
         aEqual('2026-09-01': %char(DateMonthBeg(D'2026-09-26')));
         aEqual('2026-09-01': %char(DateMonthBeg(D'2026-09-01')));
      /end-free
     PtestMonthBeg     E
      * ------------------------------------------------------------
     PtestMonthEnd     B                   EXPORT
     D  testMonthEnd   PI
      /free
         aEqual('2026-09-30': %char(DateMonthEnd(D'2026-09-26')));
         aEqual('2026-12-31': %char(DateMonthEnd(D'2026-12-05')));
         aEqual('2024-02-29': %char(DateMonthEnd(D'2024-02-10')));
         aEqual('2026-02-28': %char(DateMonthEnd(D'2026-02-10')));
      /end-free
     PtestMonthEnd     E
      * ------------------------------------------------------------
     PtestIsLeap       B                   EXPORT
     D  testIsLeap     PI
      /free
         assert(DateIsLeap(2024): '2024 is a leap year');
         assert(DateIsLeap(2000): '2000 is a leap year (divisible by 400)');
         assert(not DateIsLeap(2100): '2100 is not a leap year');
         assert(not DateIsLeap(2026): '2026 is not a leap year');
      /end-free
     PtestIsLeap       E
      * ------------------------------------------------------------
     PtestDayOfWeek    B                   EXPORT
     D  testDayOfWeek  PI
      /free
         iEqual(6: DateDayOfWeek(D'2026-09-26'));
         iEqual(1: DateDayOfWeek(D'2026-09-28'));
         iEqual(7: DateDayOfWeek(D'2026-09-27'));
      /end-free
     PtestDayOfWeek    E
      * ------------------------------------------------------------
     PtestDayName      B                   EXPORT
     D  testDayName    PI
      /free
         aEqual('Saturday': DateDayName(D'2026-09-26'));
         aEqual('Monday': DateDayName(D'2026-08-17'));
      /end-free
     PtestDayName      E
      * ------------------------------------------------------------
     PtestHoliday      B                   EXPORT
     D  testHoliday    PI
      /free
         assert(DateIsHoliday(D'2026-08-17'): '2026-08-17 is a holiday');
         assert(not DateIsHoliday(D'2026-08-18'): '2026-08-18 is no holiday');
      /end-free
     PtestHoliday      E
      * ------------------------------------------------------------
     PtestWorkday      B                   EXPORT
     D  testWorkday    PI
      /free
         assert(not DateIsWorkday(D'2026-08-17'): 'holiday on a Monday');
         assert(DateIsWorkday(D'2026-08-18'): 'normal Tuesday');
         assert(not DateIsWorkday(D'2026-09-26'): 'Saturday');
      /end-free
     PtestWorkday      E
      * ------------------------------------------------------------
     PtestAddWdays     B                   EXPORT
     D  testAddWdays   PI
      /free
         // Friday + 1 skips the weekend AND the Monday holiday
         aEqual('2026-08-18': %char(DateAddWdays(D'2026-08-14': 1)));
         aEqual('2026-08-14': %char(DateAddWdays(D'2026-08-18': -1)));
         aEqual('2026-09-28': %char(DateAddWdays(D'2026-09-25': 1)));
         aEqual('2026-09-26': %char(DateAddWdays(D'2026-09-26': 0)));
      /end-free
     PtestAddWdays     E
