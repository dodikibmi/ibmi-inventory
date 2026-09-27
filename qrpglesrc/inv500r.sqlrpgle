     HDFTACTGRP(*NO) OPTION(*SRCSTMT:*NODEBUGIO)
     HDATFMT(*ISO) TIMFMT(*ISO)
     HACTGRP(*NEW)
      * ------------------------------------------------------------
      * INV500R - Export stock status as JSON to the IFS
      * The whole document is built by Db2 in ONE statement:
      * JSON_OBJECT per item, JSON_ARRAYAGG per warehouse (with item
      * count and total value), JSON_ARRAYAGG of the warehouses.
      * QSYS2.IFS_WRITE_UTF8 then writes it as a UTF-8 stream file,
      * ready for a web front end or an API gateway.
      * Parameter (optional): IFS path of the output file.
      * On an SQL error an escape message goes to the caller, so a CL
      * program can MONMSG it.
      * ------------------------------------------------------------
     DINV500R          PR                  EXTPGM('INV500R')
     D   pPath                      200A   CONST OPTIONS(*NOPASS)
     DINV500R          PI
     D   pPath                      200A   CONST OPTIONS(*NOPASS)
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
     D  Json           S                   SQLTYPE(CLOB:1000000)
     D  WkPath         S            200A   VARYING
     D  WkMsg          S            256A   VARYING
     D  WkKey          S              4A
      /free
         exec sql set option commit = *none, closqlcsr = *endmod,
                             naming = *sys;

         WkPath = '/home/DODIKIBMI/inventory/stock_status.json';
         if %parms() >= %parmnum(pPath) and pPath <> *blanks;
            WkPath = %trim(pPath);
         endif;

         exec sql
            select json_object(
                     'application' value 'IBM i Warehouse Inventory',
                     'generated'   value varchar_format(current_timestamp,
                                           'YYYY-MM-DD HH24:MI:SS'),
                     'warehouses'  value json_arrayagg(
                                           w.doc format json order by w.code))
              into :Json
              from (select s.STWHS as code,
                           json_object(
                             'code'       value trim(s.STWHS),
                             'name'       value trim(s.WHNAME),
                             'itemCount'  value count(*),
                             'totalValue' value sum(s.STVALUE),
                             'items'      value json_arrayagg(
                                json_object(
                                  'item'        value trim(s.STITEM),
                                  'description' value trim(s.ITDESC),
                                  'category'    value trim(s.ITCATG),
                                  'onHand'      value s.STQTY,
                                  'minimum'     value s.ITMINQ,
                                  'reorder'     value
                                     case when s.REORDER = 'Y'
                                          then 'true' else 'false' end
                                     format json)
                                order by s.STITEM)) as doc
                      from STOCK_STATUS s
                     group by s.STWHS, s.WHNAME) w;
         if SQLCODE < 0;
            WkMsg = 'JSON build failed, SQLSTATE ' + SQLSTATE;
            exsr SendEscape;
         endif;

         exec sql call QSYS2.IFS_WRITE_UTF8(
                          PATH_NAME   => :WkPath,
                          LINE        => :Json,
                          OVERWRITE   => 'REPLACE',
                          END_OF_LINE => 'NONE');
         if SQLCODE < 0;
            WkMsg = 'Writing ' + WkPath + ' failed, SQLSTATE ' + SQLSTATE;
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
