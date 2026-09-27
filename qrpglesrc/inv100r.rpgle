     HDFTACTGRP(*NO) OPTION(*SRCSTMT:*NODEBUGIO)
     HDATFMT(*ISO) TIMFMT(*ISO)
     HACTGRP('INVENTORY')
      * ------------------------------------------------------------
      * INV100R - Work with Items
      * Load-all subfile over the item master (index INVITM1) with the
      * total quantity on hand per item. Options 2/4/5 and F6 call the
      * maintenance program INV110R, option 6 the stock card INV300R;
      * the list is reloaded afterwards so changes are visible at once.
      * ------------------------------------------------------------
     FINV100D   CF   E             WORKSTN INDDS(Ind)
     F                                     SFILE(SFL01:Rrn)
     FINVITM1   IF   E           K DISK
     FINVSTK1   IF   E           K DISK
      *
     DPSDS            SDS
     D  psPgm                  1     10
     D  psUser               254    263
      *
      * Indicators of the display file (INDARA)
     DInd              DS                  QUALIFIED
     D  Exit                   3      3N
     D  Refresh                5      5N
     D  Add                    6      6N
     D  Cancel                12     12N
     D  SflDsp                31     31N
     D  SflDspCtl             32     32N
     D  SflClr                33     33N
     D  SflEnd                34     34N
      *
     D  Rrn            S              4S 0
      *
      * Item maintenance: mode A=Add C=Change D=Delete V=Display
     D  Inv110r        PR                  EXTPGM('INV110R')
     D   pMode                        1A   CONST
     D   pItem                       10A   CONST
      *
      * Stock card of an item (warehouse defaults to its first stock)
     D  Inv300r        PR                  EXTPGM('INV300R')
     D   pItem                       10A   CONST OPTIONS(*NOPASS)
      /free
         C1PGM = psPgm;
         exsr LoadSfl;

         dow *on;
            write FKEY01;
            exfmt CTL01;
            F1MSG = *blanks;

            select;
            when Ind.Exit or Ind.Cancel;
               leave;
            when Ind.Refresh;
               C1POS = *blanks;
            when Ind.Add;
               Inv110r('A': *blanks);
            other;
               exsr ProcessOpt;
            endsl;

            exsr LoadSfl;
         enddo;

         *inlr = *on;
         return;

         //------------------------------------------------------------
         // LoadSfl - clear the subfile and load it from C1POS onwards
         //------------------------------------------------------------
         begsr LoadSfl;
            Ind.SflClr = *on;
            write CTL01;
            Ind.SflClr = *off;
            Rrn = 0;

            setll C1POS INVITM1;
            read INVITM1;
            dow not %eof(INVITM1) and Rrn < 9999;
               S1OPT  = *blanks;
               S1ITEM = ITITEM;
               S1DESC = ITDESC;
               S1UOM  = ITUOM;
               S1STAT = ITSTAT;
               exsr SumStock;
               Rrn += 1;
               write SFL01;
               read INVITM1;
            enddo;

            Ind.SflDsp    = (Rrn > 0);
            Ind.SflDspCtl = *on;
            Ind.SflEnd    = *on;
            if Rrn > 0;
               RRN01 = 1;
            elseif F1MSG = *blanks;
               F1MSG = 'No items found from the position entered.';
            endif;
         endsr;

         //------------------------------------------------------------
         // SumStock - quantity on hand of ITITEM over all warehouses
         //------------------------------------------------------------
         begsr SumStock;
            S1QTY = 0;
            setll ITITEM INVSTK1;
            reade ITITEM INVSTK1;
            dow not %eof(INVSTK1);
               S1QTY += STQTY;
               reade ITITEM INVSTK1;
            enddo;
         endsr;

         //------------------------------------------------------------
         // ProcessOpt - handle every subfile line that has an option
         //------------------------------------------------------------
         begsr ProcessOpt;
            readc SFL01;
            dow not %eof(INV100D);
               select;
               when S1OPT = '2';
                  Inv110r('C': S1ITEM);
               when S1OPT = '4';
                  Inv110r('D': S1ITEM);
               when S1OPT = '5';
                  Inv110r('V': S1ITEM);
               when S1OPT = '6';
                  Inv300r(S1ITEM);
               when S1OPT <> *blanks;
                  F1MSG = 'Option ' + S1OPT + ' is not valid for item '
                        + %trim(S1ITEM) + '.';
               endsl;
               readc SFL01;
            enddo;
         endsr;
      /end-free
