     HNOMAIN OPTION(*SRCSTMT:*NODEBUGIO) DATFMT(*ISO)
      * ------------------------------------------------------------
      * DATEUTIL - date service program of the inventory application
      * NOMAIN module: no RPG cycle, only exported procedures. The
      * export list and signatures are in binder source DATEUTILB.
      * Holidays come from table HOLIDAY_CALENDAR (index INVHOL1),
      * opened on the first call because a NOMAIN module has no
      * cycle to open it.
      * ------------------------------------------------------------
     FINVHOL1   IF   E           K DISK    USROPN
      *
      /COPY dateutilpr.rpgleinc
      * ------------------------------------------------------------
     PDateMonthBeg     B                   EXPORT
     D  DateMonthBeg   PI              D
     D   Dt                            D   CONST
      /free
         return Dt - %days(%subdt(Dt: *days) - 1);
      /end-free
     PDateMonthBeg     E
      * ------------------------------------------------------------
     PDateMonthEnd     B                   EXPORT
     D  DateMonthEnd   PI              D
     D   Dt                            D   CONST
      /free
         return DateMonthBeg(Dt) + %months(1) - %days(1);
      /end-free
     PDateMonthEnd     E
      * ------------------------------------------------------------
     PDateIsLeap       B                   EXPORT
     D  DateIsLeap     PI              N
     D   Year                        10I 0 CONST
      /free
         return %rem(Year: 4) = 0
                and (%rem(Year: 100) <> 0 or %rem(Year: 400) = 0);
      /end-free
     PDateIsLeap       E
      * ------------------------------------------------------------
     PDateDayOfWeek    B                   EXPORT
     D  DateDayOfWeek  PI            10I 0
     D   Dt                            D   CONST
      /free
         // 0001-01-01 (proleptic Gregorian calendar) was a Monday
         return %rem(%diff(Dt: D'0001-01-01': *days): 7) + 1;
      /end-free
     PDateDayOfWeek    E
      * ------------------------------------------------------------
     PDateDayName      B                   EXPORT
     D  DateDayName    PI             9A   VARYING
     D   Dt                            D   CONST
      /free
         select;
         when DateDayOfWeek(Dt) = 1;
            return 'Monday';
         when DateDayOfWeek(Dt) = 2;
            return 'Tuesday';
         when DateDayOfWeek(Dt) = 3;
            return 'Wednesday';
         when DateDayOfWeek(Dt) = 4;
            return 'Thursday';
         when DateDayOfWeek(Dt) = 5;
            return 'Friday';
         when DateDayOfWeek(Dt) = 6;
            return 'Saturday';
         other;
            return 'Sunday';
         endsl;
      /end-free
     PDateDayName      E
      * ------------------------------------------------------------
     PDateIsHoliday    B                   EXPORT
     D  DateIsHoliday  PI              N
     D   Dt                            D   CONST
      /free
         if not %open(INVHOL1);
            open INVHOL1;
         endif;
         chain Dt INVHOL1;
         return %found(INVHOL1);
      /end-free
     PDateIsHoliday    E
      * ------------------------------------------------------------
     PDateIsWorkday    B                   EXPORT
     D  DateIsWorkday  PI              N
     D   Dt                            D   CONST
      /free
         return DateDayOfWeek(Dt) <= 5 and not DateIsHoliday(Dt);
      /end-free
     PDateIsWorkday    E
      * ------------------------------------------------------------
     PDateAddWdays     B                   EXPORT
     D  DateAddWdays   PI              D
     D   Dt                            D   CONST
     D   Days                        10I 0 CONST
     D  WkDate         S               D
     D  WkLeft         S             10I 0
     D  WkStep         S             10I 0
      /free
         WkDate = Dt;
         WkLeft = %abs(Days);
         if Days < 0;
            WkStep = -1;
         else;
            WkStep = 1;
         endif;

         dow WkLeft > 0;
            WkDate += %days(WkStep);
            if DateIsWorkday(WkDate);
               WkLeft -= 1;
            endif;
         enddo;
         return WkDate;
      /end-free
     PDateAddWdays     E
