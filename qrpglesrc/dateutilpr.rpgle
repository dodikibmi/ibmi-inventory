      * ------------------------------------------------------------
      * DATEUTILPR - prototypes of service program DATEUTIL
      * Copy into every caller:  /COPY DODIKIBMI1/QRPGLESRC,DATEUTILPR
      * and bind with BNDDIR('INVENTORY').
      * ------------------------------------------------------------
      /IF DEFINED(DATEUTILPR)
      /EOF
      /ENDIF
      /DEFINE DATEUTILPR
      *
      * First / last day of the month of Dt
     D  DateMonthBeg   PR              D
     D   Dt                            D   CONST
     D  DateMonthEnd   PR              D
     D   Dt                            D   CONST
      *
      * *ON for a leap year (Gregorian rules)
     D  DateIsLeap     PR              N
     D   Year                        10I 0 CONST
      *
      * Day of the week: 1 = Monday ... 7 = Sunday
     D  DateDayOfWeek  PR            10I 0
     D   Dt                            D   CONST
      *
      * English day name, e.g. 'Saturday'
     D  DateDayName    PR             9A   VARYING
     D   Dt                            D   CONST
      *
      * *ON when Dt is in table HOLIDAY_CALENDAR
     D  DateIsHoliday  PR              N
     D   Dt                            D   CONST
      *
      * *ON for Monday to Friday that is not a holiday
     D  DateIsWorkday  PR              N
     D   Dt                            D   CONST
      *
      * Move Days working days forward (negative = backward)
     D  DateAddWdays   PR              D
     D   Dt                            D   CONST
     D   Days                        10I 0 CONST
