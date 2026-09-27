     HDFTACTGRP(*NO) OPTION(*SRCSTMT:*NODEBUGIO)
     HDATFMT(*ISO) TIMFMT(*ISO)
     HACTGRP('INVENTORY') BNDDIR('INVENTORY')
      * ------------------------------------------------------------
      * INV300R - Stock card
      * Movements of one item in one warehouse from a start date, with
      * opening, running and closing balance.
      * The sample data loads stock without a movement for every unit,
      * so the opening balance is derived backwards from the current
      * stock:  opening = on hand - sum(movements since the start date).
      * The list is then built forwards, adding each movement.
      * Parameters (both optional): item, warehouse. Without a
      * warehouse the first warehouse holding the item is used.
      * ------------------------------------------------------------
     FINV300D   CF   E             WORKSTN INDDS(Ind)
     F                                     SFILE(SFL03:Rrn)
     FINVITM1   IF   E           K DISK
     FINVWHS1   IF   E           K DISK
     FINVSTK1   IF   E           K DISK
     FINVMOV1   IF   E           K DISK
      *
      /COPY DODIKIBMI1/QRPGLESRC,DATEUTILPR
      *
     DPSDS            SDS
     D  psPgm                  1     10
     D  psUser               254    263
      *
     DInd              DS                  QUALIFIED
     D  Exit                   3      3N
     D  Prompt                 4      4N
     D  Refresh                5      5N
     D  Cancel                12     12N
     D  SflDsp                31     31N
     D  SflDspCtl             32     32N
     D  SflClr                33     33N
     D  SflEnd                34     34N
     D  ErrItem               61     61N
     D  ErrWhs                62     62N
     D  ErrAll                61     62
      *
     DINV300R          PR                  EXTPGM('INV300R')
     D   pItem                       10A   CONST OPTIONS(*NOPASS)
     D   pWhs                         3A   CONST OPTIONS(*NOPASS)
     DINV300R          PI
     D   pItem                       10A   CONST OPTIONS(*NOPASS)
     D   pWhs                         3A   CONST OPTIONS(*NOPASS)
      *
     D  Inv900r        PR                  EXTPGM('INV900R')
     D   pType                        1A   CONST
     D   pCode                       10A
      *
     D  Rrn            S              4S 0
     D  WkCode         S             10A
     D  WkDelta        S              9P 0
     D  WkSum          S             11P 0
     D  WkBal          S             11P 0
     D  WkCurr         S              9P 0
     D  WkOk           S               N
      /free
         C3PGM  = psPgm;
         C3FROM = DateMonthBeg(%date());

         if %parms() >= %parmnum(pItem);
            C3ITEM = pItem;
         endif;
         if %parms() >= %parmnum(pWhs);
            C3WHS = pWhs;
         endif;
         if C3ITEM <> *blanks and C3WHS = *blanks;
            // first warehouse that holds the item
            setll C3ITEM INVSTK1;
            reade C3ITEM INVSTK1;
            if not %eof(INVSTK1);
               C3WHS = STWHS;
            endif;
         endif;

         exsr LoadSfl;

         dow *on;
            write FKEY03;
            exfmt CTL03;
            K3MSG = *blanks;

            select;
            when Ind.Exit or Ind.Cancel;
               leave;
            when Ind.Prompt;
               exsr Prompt;
            endsl;

            exsr LoadSfl;
         enddo;

         *inlr = *on;
         return;

         //------------------------------------------------------------
         // LoadSfl - validate the selection and build the stock card
         //------------------------------------------------------------
         begsr LoadSfl;
            Ind.SflClr = *on;
            write CTL03;
            Ind.SflClr = *off;
            Rrn = 0;
            Ind.ErrAll = *all'0';
            C3DESC  = *blanks;
            C3WHNM  = *blanks;
            C3OPEN  = 0;
            K3CLOSE = 0;

            exsr CheckKeys;
            if WkOk;
               // current stock of the item in the warehouse
               chain(n) (C3ITEM: C3WHS) INVSTK1;
               if %found(INVSTK1);
                  WkCurr = STQTY;
               else;
                  WkCurr = 0;
               endif;

               // pass 1: sum of movements since the start date
               WkSum = 0;
               setll (C3ITEM: C3WHS: C3FROM) INVMOV1;
               reade (C3ITEM: C3WHS) INVMOV1;
               dow not %eof(INVMOV1);
                  exsr Delta;
                  WkSum += WkDelta;
                  reade (C3ITEM: C3WHS) INVMOV1;
               enddo;

               // pass 2: list forwards with the running balance
               WkBal  = WkCurr - WkSum;
               C3OPEN = WkBal;
               setll (C3ITEM: C3WHS: C3FROM) INVMOV1;
               reade (C3ITEM: C3WHS) INVMOV1;
               dow not %eof(INVMOV1) and Rrn < 9999;
                  exsr Delta;
                  WkBal += WkDelta;
                  S3DATE = MVDATE;
                  S3NO   = MVNO;
                  S3TYPE = MVTYPE;
                  S3REF  = MVREF;
                  if WkDelta > 0;
                     S3IN  = WkDelta;
                     S3OUT = 0;
                  else;
                     S3IN  = 0;
                     S3OUT = -WkDelta;
                  endif;
                  S3BAL = WkBal;
                  Rrn += 1;
                  write SFL03;
                  reade (C3ITEM: C3WHS) INVMOV1;
               enddo;
               K3CLOSE = WkBal;

               if Rrn = 0 and K3MSG = *blanks;
                  K3MSG = 'No movements since ' + %char(C3FROM) + '.';
               endif;
            endif;

            Ind.SflDsp    = (Rrn > 0);
            Ind.SflDspCtl = *on;
            Ind.SflEnd    = *on;
            if Rrn > 0;
               RRN03 = 1;
            endif;
         endsr;

         //------------------------------------------------------------
         // CheckKeys - item and warehouse must exist (any status)
         //------------------------------------------------------------
         begsr CheckKeys;
            WkOk = *on;

            if C3ITEM = *blanks;
               Ind.ErrItem = *on;
               WkOk = *off;
               K3MSG = 'Enter an item code (F4 for a list).';
            else;
               chain C3ITEM INVITM1;
               if %found(INVITM1);
                  C3DESC = ITDESC;
               else;
                  Ind.ErrItem = *on;
                  WkOk = *off;
                  K3MSG = 'Item ' + %trim(C3ITEM) + ' does not exist.';
               endif;
            endif;

            if C3WHS = *blanks;
               Ind.ErrWhs = *on;
               if WkOk;
                  K3MSG = 'Enter a warehouse (F4 for a list).';
               endif;
               WkOk = *off;
            else;
               chain C3WHS INVWHS1;
               if %found(INVWHS1);
                  C3WHNM = WHNAME;
               else;
                  Ind.ErrWhs = *on;
                  if WkOk;
                     K3MSG = 'Warehouse ' + %trim(C3WHS) + ' does not exist.';
                  endif;
                  WkOk = *off;
               endif;
            endif;
         endsr;

         //------------------------------------------------------------
         // Delta - signed effect of the current movement on the stock
         //------------------------------------------------------------
         begsr Delta;
            select;
            when MVTYPE = 'I';
               WkDelta = MVQTY;
            when MVTYPE = 'O';
               WkDelta = -MVQTY;
            other;
               WkDelta = MVQTY;
            endsl;
         endsr;

         //------------------------------------------------------------
         // Prompt - F4 on item or warehouse
         //------------------------------------------------------------
         begsr Prompt;
            select;
            when C3CFLD = 'C3ITEM';
               WkCode = C3ITEM;
               Inv900r('I': WkCode);
               C3ITEM = WkCode;
            when C3CFLD = 'C3WHS';
               WkCode = C3WHS;
               Inv900r('W': WkCode);
               C3WHS = WkCode;
            other;
               K3MSG = 'F4 works on item code and warehouse.';
            endsl;
         endsr;
      /end-free
