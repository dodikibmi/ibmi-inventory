     HDFTACTGRP(*NO) OPTION(*SRCSTMT:*NODEBUGIO)
     HDATFMT(*ISO) TIMFMT(*ISO)
     HACTGRP(*NEW)
      * ------------------------------------------------------------
      * INV810R - Stock inquiry server over data queues
      * Waits on data queue INVREQQ for requests from any client
      * (Node.js, Python, Java, another RPG program):
      *     {"id":"REQ-0001","item":"OF-0001"}   stock of one item
      *     {"cmd":"stop"}                       end the server
      * Request ids use only A-Z, 0-9 and '-' (same bytes in every
      * EBCDIC CCSID), because the id is also the reply key.
      * and answers on the keyed data queue INVRPYQ, key = request id,
      * so each client receives only its own reply:
      *     {"id":"REQ-0001","item":"OF-0001","description":"...",
      *      "stock":[{"warehouse":"CTR","quantity":120,...}]}
      * Messages are UTF-8 JSON. Db2 parses the request (JSON_TABLE)
      * and builds the reply (JSON_OBJECT / JSON_ARRAYAGG).
      * Normally started once as a batch job (SBMJOB or an autostart
      * job entry); it ends after pIdle seconds without a request.
      * Parameter (optional): idle seconds, packed(5,0), default 300.
      * ------------------------------------------------------------
     DINV810R          PR                  EXTPGM('INV810R')
     D   pIdle                        5P 0 CONST OPTIONS(*NOPASS)
     DINV810R          PI
     D   pIdle                        5P 0 CONST OPTIONS(*NOPASS)
      *
     DQRcvDtaQ         PR                  EXTPGM('QRCVDTAQ')
     D   DtaQ                        10A   CONST
     D   DtaQLib                     10A   CONST
     D   DataLen                      5P 0
     D   Data                       512A   CCSID(*UTF8)
     D   Wait                         5P 0 CONST
      *
     DQSndDtaQ         PR                  EXTPGM('QSNDDTAQ')
     D   DtaQ                        10A   CONST
     D   DtaQLib                     10A   CONST
     D   DataLen                      5P 0 CONST
     D   Data                      4000A   CONST CCSID(*UTF8)
     D   KeyLen                       3P 0 CONST
     D   Key                         16A   CONST
      *
     D  Raw            S            512A   CCSID(*UTF8)
     D  RawLen         S              5P 0
     D  Req            S            512A   VARYING CCSID(*UTF8)
     D  Rpy            S           4000A   VARYING CCSID(*UTF8)
     D  ReqId          S             16A
     D  ReqCmd         S             10A
     D  ReqItem        S             10A
     D  Wait           S              5P 0
     D  WkCode         S             10I 0
      /free
         exec sql set option commit = *none, closqlcsr = *endmod,
                             naming = *sys;

         Wait = 300;
         if %parms() >= %parmnum(pIdle) and pIdle > 0;
            Wait = pIdle;
         endif;

         dow '1';
            // the bytes on the queue are UTF-8, so are Raw and Req
            QRcvDtaQ('INVREQQ' : '*LIBL' : RawLen : Raw : Wait);
            if RawLen = 0;
               leave;                       // idle too long
            endif;
            %len(Req) = 0;
            Req = %subst(Raw : 1 : RawLen);

            clear ReqId;
            clear ReqCmd;
            clear ReqItem;
            exec sql
               select coalesce(id, ''), coalesce(cmd, ''),
                      coalesce(item, '')
                 into :ReqId, :ReqCmd, :ReqItem
                 from json_table(:Req, '$'
                        columns(id   varchar(16) path '$.id',
                                cmd  varchar(10) path '$.cmd',
                                item varchar(10) path '$.item')) j;
            if sqlcode <> 0;
               iter;                        // not JSON: ignore it
            endif;
            if ReqCmd = 'stop';
               leave;
            endif;
            if ReqId = *blanks;
               iter;                        // nobody to answer to
            endif;

            exec sql
               select json_object(
                        'id'          value trim(:ReqId),
                        'item'        value trim(i.ititem),
                        'description' value trim(i.itdesc),
                        'unit'        value trim(i.ituom),
                        'minimum'     value i.itminq,
                        'stock'       value (
                           select json_arrayagg(json_object(
                                    'warehouse' value trim(s.stwhs),
                                    'quantity'  value s.stqty,
                                    'reorder'   value s.reorder)
                                  order by s.stwhs)
                             from invstkv s
                            where s.stitem = i.ititem) format json)
                 into :Rpy
                 from invitm i
                where i.ititem = :ReqItem;
            if sqlcode = 100;
               exec sql
                  values json_object('id'    value trim(:ReqId),
                                     'item'  value trim(:ReqItem),
                                     'error' value 'item not found')
                    into :Rpy;
            elseif sqlcode < 0;
               WkCode = sqlcode;
               exec sql
                  values json_object('id'    value trim(:ReqId),
                                     'error' value 'database error '
                                                   concat char(:WkCode))
                    into :Rpy;
            endif;

            // %len of a UTF-8 field = number of bytes to send
            QSndDtaQ('INVRPYQ' : '*LIBL' : %len(Rpy) : Rpy : 16 : ReqId);
         enddo;

         *inlr = *on;
         return;
      /end-free
