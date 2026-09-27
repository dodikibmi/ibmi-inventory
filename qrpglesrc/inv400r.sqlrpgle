     HDFTACTGRP(*NO) OPTION(*SRCSTMT:*NODEBUGIO)
     HDATFMT(*ISO) TIMFMT(*ISO)
     HACTGRP(*NEW)
      * ------------------------------------------------------------
      * INV400R - Stock status report (batch, 132 columns)
      * Reads view STOCK_STATUS with embedded SQL, ordered by
      * warehouse and item, 100 rows per FETCH (multi-row fetch into
      * a data structure array). Level break per warehouse with item
      * count, reorder count, quantity and value; grand total at the
      * end. Items below their minimum stock are flagged with '*'.
      * Parameters (optional): warehouse ('*' = all), reorder only
      * ('Y' / 'N'). Submitted from the menu with SBMJOB.
      * ------------------------------------------------------------
     FINV400P   O    E             PRINTER OFLIND(WkOvf)
      *
     DPSDS            SDS
     D  psPgm                  1     10
     D  psUser               254    263
      *
     DINV400R          PR                  EXTPGM('INV400R')
     D   pWhs                         3A   CONST OPTIONS(*NOPASS)
     D   pReorder                     1A   CONST OPTIONS(*NOPASS)
     DINV400R          PI
     D   pWhs                         3A   CONST OPTIONS(*NOPASS)
     D   pReorder                     1A   CONST OPTIONS(*NOPASS)
      *
      * One FETCH block: 100 rows of the view
     DRows             DS                  QUALIFIED DIM(100)
     D  Whs                           3A
     D  WhName                       30A
     D  Item                         10A
     D  Desc                         40A
     D  Catg                          4A
     D  Uom                           3A
     D  Qty                           9P 0
     D  MinQ                          7P 0
     D  Price                        11P 2
     D  Value                        20P 2
     D  Reorder                       1A
      *
     D  WkWhs          S              3A
     D  WkRod          S              1A
     D  WkText         S             10A
     D  WkPrvWhs       S              3A
     D  WkGot          S             10I 0
     D  i              S             10I 0
     D  WkOvf          S               N
      /free
         exec sql set option commit = *none, closqlcsr = *endmod,
                             datfmt = *iso, naming = *sys;

         WkWhs = '*';
         WkRod = 'N';
         if %parms() >= %parmnum(pWhs) and pWhs <> *blanks;
            WkWhs = pWhs;
         endif;
         if %parms() >= %parmnum(pReorder) and pReorder = 'Y';
            WkRod = 'Y';
         endif;

         H1PGM  = psPgm;
         H1USER = psUser;
         H1LINE = *all'-';
         if WkWhs = '*';
            WkText = 'all';
         else;
            WkText = WkWhs;
         endif;
         H1SEL = 'Selection: warehouse ' + %trim(WkText)
               + ', reorder items only: ' + WkRod;
         write HEADER;

         exec sql declare C1 cursor for
            select STWHS, WHNAME, STITEM, ITDESC, ITCATG, ITUOM,
                   STQTY, ITMINQ, ITPRICE, STVALUE, REORDER
              from STOCK_STATUS
             where (:WkWhs = '*' or STWHS = :WkWhs)
               and (:WkRod <> 'Y' or REORDER = 'Y')
             order by STWHS, STITEM
             for read only;

         exec sql open C1;

         dow SQLCODE = 0;
            exec sql fetch next from C1 for 100 rows into :Rows;
            WkGot = SQLERRD(3);
            for i = 1 to WkGot;
               exsr PrintRow;
            endfor;
            if WkGot < %elem(Rows);
               leave;
            endif;
         enddo;

         exec sql close C1;

         if WkPrvWhs = *blanks;
            write NODATA;
         else;
            exsr WhsTotal;
            write GRDTOT;
         endif;
         write ENDRPT;

         *inlr = *on;
         return;

         //------------------------------------------------------------
         // PrintRow - level break on warehouse, then the detail line
         //------------------------------------------------------------
         begsr PrintRow;
            if Rows(i).Whs <> WkPrvWhs;
               if WkPrvWhs <> *blanks;
                  exsr WhsTotal;
               endif;
               WkPrvWhs = Rows(i).Whs;
               W4WHS    = Rows(i).Whs;
               W4NAME   = Rows(i).WhName;
               exsr NewPage;
               write WHSHDR;
            endif;

            if WkOvf;
               exsr NewPage;
               write WHSHDR;
            endif;

            D4ITEM  = Rows(i).Item;
            D4DESC  = Rows(i).Desc;
            D4CATG  = Rows(i).Catg;
            D4UOM   = Rows(i).Uom;
            D4QTY   = Rows(i).Qty;
            D4MINQ  = Rows(i).MinQ;
            D4PRICE = Rows(i).Price;
            D4VALUE = Rows(i).Value;
            if Rows(i).Reorder = 'Y';
               D4FLAG = '*';
               T4REORD += 1;
               G4REORD += 1;
            else;
               D4FLAG = ' ';
            endif;
            write DETAIL;

            T4CNT   += 1;
            T4QTY   += Rows(i).Qty;
            T4VALUE += Rows(i).Value;
            G4CNT   += 1;
            G4QTY   += Rows(i).Qty;
            G4VALUE += Rows(i).Value;
         endsr;

         //------------------------------------------------------------
         // WhsTotal - totals of one warehouse, then reset them
         //------------------------------------------------------------
         begsr WhsTotal;
            exsr NewPage;
            write WHSTOT;
            clear T4CNT;
            clear T4REORD;
            clear T4QTY;
            clear T4VALUE;
         endsr;

         //------------------------------------------------------------
         // NewPage - page heading again after printer overflow
         //------------------------------------------------------------
         begsr NewPage;
            if WkOvf;
               write HEADER;
               WkOvf = *off;
            endif;
         endsr;
      /end-free
