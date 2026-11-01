     HDFTACTGRP(*NO) OPTION(*SRCSTMT:*NODEBUGIO)
     HDATFMT(*ISO) TIMFMT(*ISO)
     HACTGRP(*NEW)
      * ------------------------------------------------------------
      * INV600R - Load public holidays from a REST API
      * RPG as a REST client, without HTTPAPI or sockets: Db2 calls the
      * web service (QSYS2.HTTP_GET), JSON_TABLE turns the JSON array
      * into rows and MERGE inserts new dates or updates their names in
      * HOLIDAY_CALENDAR. DATEUTIL (DateIsWorkday, DateAddWdays) then
      * knows the official holidays. Loads this year and next year.
      * HTTP_GET returns the body of an error answer (404, 500) without
      * an SQL error, so the call uses HTTP_GET_VERBOSE and checks the
      * status first: a non-2xx answer ends with CPF9898.
      * Source: https://date.nager.at (free, no API key).
      * Parameter (optional, output): number of rows merged, char(10).
      * ------------------------------------------------------------
     DINV600R          PR                  EXTPGM('INV600R')
     D   pRows                       10A   OPTIONS(*NOPASS)
     DINV600R          PI
     D   pRows                       10A   OPTIONS(*NOPASS)
      *
     DQMhSndPm         PR                  EXTPGM('QMHSNDPM')
     D   MsgId                        7A   CONST
     D   MsgFile                     20A   CONST
     D   MsgDta                     256A   CONST OPTIONS(*VARSIZE)
     D   MsgLen                      10I 0 CONST
     D   MsgType                     10A   CONST
     D   CallStk                     10A   CONST
     D   CallCnt                     10I 0 CONST
     D   MsgKey                       4A
     D   ErrCode                      8A
      *
     DApiErr           DS
     D  BytesProv                    10I 0 INZ(0)
     D  BytesAvl                     10I 0
      *
      * Country code of the holiday calendar (ISO 3166)
     D  COUNTRY        C                   'ID'
     D  WkUrl          S            200A   VARYING
     D  Json           S                   SQLTYPE(CLOB:1000000)
     D  WkStatus       S             10I 0
     D  WkYear         S             10I 0
     D  WkRows         S             10I 0
     D  WkTotal        S             10I 0
     D  WkMsg          S            256A   VARYING
     D  WkKey          S              4A
      /free
         exec sql set option commit = *none, closqlcsr = *endmod,
                             naming = *sys;

         WkTotal = 0;
         for WkYear = %subdt(%date(): *years) to %subdt(%date(): *years) + 1;
            WkUrl = 'https://date.nager.at/api/v3/PublicHolidays/'
                  + %char(WkYear) + '/' + COUNTRY;

            // Call the API; the status code comes back in the header JSON
            exec sql
               select json_value(v.RESPONSE_HTTP_HEADER,
                                 '$.HTTP_STATUS_CODE' returning integer),
                      v.RESPONSE_MESSAGE
                 into :WkStatus, :Json
                 from table(QSYS2.HTTP_GET_VERBOSE(:WkUrl, '')) v;
            if SQLCODE < 0;
               WkMsg = 'Calling ' + WkUrl + ' failed, SQLSTATE ' + SQLSTATE;
               exsr SendEscape;
            endif;
            if WkStatus < 200 or WkStatus > 299;
               WkMsg = 'Holiday API answered HTTP ' + %char(WkStatus)
                     + ' for ' + %char(WkYear);
               exsr SendEscape;
            endif;

            exec sql
               merge into HOLIDAY_CALENDAR t
               using (select h.hdate, min(substr(h.hname, 1, 30)) as hname
                        from json_table(:Json, 'lax $[*]'
                               columns (hdate date         path 'lax $.date',
                                        hname varchar(100) path 'lax $.name')) h
                       where h.hdate is not null
                       group by h.hdate) s
                  on t.HLDATE = s.hdate
                when matched then
                     update set t.HLDESC = s.hname
                when not matched then
                     insert (HLDATE, HLDESC) values (s.hdate, s.hname);

            if SQLCODE < 0;
               WkMsg = 'Loading holidays ' + %char(WkYear)
                     + ' failed, SQLSTATE ' + SQLSTATE;
               exsr SendEscape;
            endif;

            exec sql get diagnostics :WkRows = ROW_COUNT;
            WkTotal += WkRows;
         endfor;

         if %parms() >= %parmnum(pRows);
            pRows = %char(WkTotal);
         endif;

         *inlr = *on;
         return;

         //------------------------------------------------------------
         // SendEscape - end with CPF9898 to the caller (MONMSG-able)
         //------------------------------------------------------------
         begsr SendEscape;
            QMhSndPm('CPF9898': 'QCPFMSG   *LIBL': WkMsg: %len(WkMsg):
                     '*ESCAPE': '*': 1: WkKey: ApiErr);
         endsr;
      /end-free
