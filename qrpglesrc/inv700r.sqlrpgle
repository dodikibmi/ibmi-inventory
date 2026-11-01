     HDFTACTGRP(*NO) OPTION(*SRCSTMT:*NODEBUGIO)
     HDATFMT(*ISO) TIMFMT(*ISO)
     HACTGRP(*NEW)
      * ------------------------------------------------------------
      * INV700R - Send a reorder alert to a webhook (REST POST)
      * Db2 builds the JSON message in ONE statement: LISTAGG turns the
      * items below their minimum into one readable line per warehouse
      * ("WST (CL-0001, OF-0001, ...)"), JSON_OBJECT/JSON_ARRAYAGG wrap
      * it for a chat or ERP webhook. QSYS2.HTTP_POST_VERBOSE sends it
      * and returns the HTTP status, so a failed call is not silent.
      * Default endpoint: https://httpbin.org/post (echo service).
      * Parameters (optional): webhook URL (in), HTTP status (out,
      * char(10); 'NONE' when no item needs a reorder).
      * A non-2xx answer or an SQL error ends with CPF9898 (MONMSG-able).
      * ------------------------------------------------------------
     DINV700R          PR                  EXTPGM('INV700R')
     D   pUrl                       200A   CONST OPTIONS(*NOPASS)
     D   pStatus                     10A   OPTIONS(*NOPASS)
     DINV700R          PI
     D   pUrl                       200A   CONST OPTIONS(*NOPASS)
     D   pStatus                     10A   OPTIONS(*NOPASS)
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
     D  Body           S                   SQLTYPE(CLOB:100000)
     D  WkUrl          S            200A   VARYING
     D  WkOpt          S            100A   VARYING
     D  WkItems        S             10I 0
     D  WkStatus       S             10I 0
     D  WkMsg          S            256A   VARYING
     D  WkKey          S              4A
      /free
         exec sql set option commit = *none, closqlcsr = *endmod,
                             naming = *sys;

         WkUrl = 'https://httpbin.org/post';
         if %parms() >= %parmnum(pUrl) and pUrl <> *blanks;
            WkUrl = %trim(pUrl);
         endif;
         WkOpt = '{"header":"content-type,application/json"}';

         // One line per warehouse with LISTAGG, then the JSON message
         exec sql
            with w as (
                 select trim(s.STWHS) as code, trim(s.WHNAME) as name,
                        count(*) as cnt,
                        listagg(trim(s.STITEM), ', ')
                           within group (order by s.STITEM) as items
                   from STOCK_STATUS s
                  where s.REORDER = 'Y'
                  group by s.STWHS, s.WHNAME)
            select coalesce(sum(w.cnt), 0),
                   json_object(
                     'source'    value 'IBM i Warehouse Inventory',
                     'generated' value varchar_format(current_timestamp,
                                         'YYYY-MM-DD HH24:MI:SS'),
                     'text'      value 'Reorder needed: ' concat
                                   listagg(w.code concat ' ('
                                           concat w.items concat ')', '; ')
                                      within group (order by w.code),
                     'warehouses' value json_arrayagg(
                                   json_object('code'      value w.code,
                                               'name'      value w.name,
                                               'itemCount' value w.cnt,
                                               'items'     value w.items)
                                   order by w.code))
              into :WkItems, :Body
              from w;
         if SQLCODE < 0;
            WkMsg = 'Building the alert failed, SQLSTATE ' + SQLSTATE;
            exsr SendEscape;
         endif;

         if WkItems = 0;
            if %parms() >= %parmnum(pStatus);
               pStatus = 'NONE';
            endif;
            *inlr = *on;
            return;
         endif;

         // POST the JSON; the status code comes back in the header JSON
         exec sql
            select json_value(v.RESPONSE_HTTP_HEADER, '$.HTTP_STATUS_CODE'
                              returning integer)
              into :WkStatus
              from table(QSYS2.HTTP_POST_VERBOSE(:WkUrl, :Body, :WkOpt)) v;
         if SQLCODE < 0;
            WkMsg = 'POST to ' + WkUrl + ' failed, SQLSTATE ' + SQLSTATE;
            exsr SendEscape;
         endif;

         if %parms() >= %parmnum(pStatus);
            pStatus = %char(WkStatus);
         endif;
         if WkStatus < 200 or WkStatus > 299;
            WkMsg = 'Webhook answered HTTP ' + %char(WkStatus);
            exsr SendEscape;
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
