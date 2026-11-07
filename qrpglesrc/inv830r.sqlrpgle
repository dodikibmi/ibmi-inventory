     HDFTACTGRP(*NO) OPTION(*SRCSTMT:*NODEBUGIO)
     HDATFMT(*ISO) TIMFMT(*ISO)
     HACTGRP(*NEW)
      * ------------------------------------------------------------
      * INV830R - Post a supplier delivery note from an XML file
      * The supplier sends one XML file per delivery (file interface):
      *   <deliveryNote number="DN-2026-0042" supplier="..."
      *                 date="2026-11-07" warehouse="CTR">
      *     <line item="OF-0001" quantity="20"/> ...
      *   </deliveryNote>
      * XML-INTO reads the file straight into a data structure (the
      * attributes become subfields). Every line is posted as goods in
      * (type I) through the SQL procedure POST_MOVEMENT, the same rules
      * as the green-screen program and the REST APIs, with the note
      * number as reference. All lines are one unit of work: one bad
      * line and the whole note is rolled back, so a note is never half
      * posted. A note number already in the movement history is
      * rejected (the supplier sent the same file twice).
      * Parameters: IFS path (in), result (out, char(80)).
      * ------------------------------------------------------------
     DINV830R          PR                  EXTPGM('INV830R')
     D   pPath                      200A   CONST
     D   pResult                     80A
     DINV830R          PI
     D   pPath                      200A   CONST
     D   pResult                     80A
      *
     DLineT            DS                  QUALIFIED TEMPLATE
     D  item                         10A
     D  quantity                      9P 0
      *
     DNote             DS                  QUALIFIED
     D  number                       20A
     D  supplier                     40A
     D  date                         10A
     D  warehouse                     3A
     D  num_line                      5I 0
     D  line                               LIKEDS(LineT) DIM(100)
      *
     D  i              S              5I 0
     D  WkDate         S               D
     D  WkRef          S             20A
     D  WkMvNo         S              9P 0
     D  WkNewQty       S              9P 0
     D  WkCount        S             10I 0
     D  WkItem         S             10A
     D  WkQty          S              9P 0
     D  WkWhs          S              3A
     D  WkMsg          S             70A   VARYING
      /free
         exec sql set option commit = *chg, closqlcsr = *endmod,
                             naming = *sys, datfmt = *iso;

         clear pResult;
         monitor;
            xml-into Note %xml(%trim(pPath) : 'doc=file case=any +
                     path=deliveryNote countprefix=num_ +
                     allowmissing=yes');
         on-error;
            pResult = 'ERROR cannot read XML file ' + %trim(pPath);
            return;
         endmon;

         if Note.number = *blanks or Note.num_line = 0;
            pResult = 'ERROR note number or lines missing';
            return;
         endif;
         monitor;
            WkDate = %date(Note.date : *iso);
         on-error;
            pResult = 'ERROR invalid date ' + Note.date;
            return;
         endmon;
         WkRef = Note.number;

         // the same file sent twice must not double the stock
         exec sql select count(*) into :WkCount from invmov
                   where mvref = :WkRef and mvtype = 'I';
         if WkCount > 0;
            pResult = 'ERROR note ' + %trim(WkRef) + ' already posted';
            return;
         endif;

         WkWhs = Note.warehouse;
         for i = 1 to Note.num_line;
            WkItem = Note.line(i).item;
            WkQty  = Note.line(i).quantity;
            exec sql call post_movement('I', :WkItem, :WkWhs, :WkQty,
                          :WkDate, :WkRef, :WkMvNo, :WkNewQty);
            if sqlcode < 0;
               exec sql get diagnostics condition 1
                        :WkMsg = message_text;
               exec sql rollback;
               pResult = 'ERROR line ' + %char(i) + ' '
                       + %trim(WkItem) + ': ' + WkMsg;
               return;
            endif;
         endfor;

         exec sql commit;
         pResult = 'OK note ' + %trim(WkRef) + ', '
                 + %char(Note.num_line) + ' lines posted';
         *inlr = *on;
         return;
      /end-free
