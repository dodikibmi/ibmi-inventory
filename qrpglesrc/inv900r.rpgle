     HDFTACTGRP(*NO) OPTION(*SRCSTMT:*NODEBUGIO)
     HDATFMT(*ISO) TIMFMT(*ISO)
     HACTGRP(*CALLER)
      * ------------------------------------------------------------
      * INV900R - F4 prompt window
      * One reusable selection list in a window for every program:
      *   pType I = active items       (index INVITM1)
      *          W = active warehouses  (index INVWHS1)
      *          T = movement types     (fixed list, same values as
      *              the CHECK constraint on STOCK_MOVEMENT)
      * pCode comes in as the current value (used as position-to)
      * and goes back as the selected code; F12 leaves it unchanged.
      * ------------------------------------------------------------
     FINV900D   CF   E             WORKSTN INDDS(Ind)
     F                                     SFILE(SFL02:Rrn)
     FINVITM1   IF   E           K DISK
     FINVWHS1   IF   E           K DISK
      *
     DInd              DS                  QUALIFIED
     D  Exit                   3      3N
     D  Cancel                12     12N
     D  SflDsp                31     31N
     D  SflDspCtl             32     32N
     D  SflClr                33     33N
     D  SflEnd                34     34N
      *
     DINV900R          PR                  EXTPGM('INV900R')
     D   pType                        1A
     D   pCode                       10A
     DINV900R          PI
     D   pType                        1A
     D   pCode                       10A
      *
     D  Rrn            S              4S 0
     D  WkPicked       S               N
      /free
         select;
         when pType = 'I';
            W2TITLE = '              Select Item';
            W2POS   = pCode;
         when pType = 'W';
            W2TITLE = '           Select Warehouse';
            W2POS   = pCode;
         other;
            W2TITLE = '         Select Movement Type';
            W2POS   = *blanks;
         endsl;

         exsr LoadSfl;

         dow *on;
            exfmt CTL02;
            W2MSG = *blanks;
            if Ind.Exit or Ind.Cancel;
               leave;
            endif;

            WkPicked = *off;
            if Rrn > 0;
               readc SFL02;
               dow not %eof(INV900D);
                  if S2OPT = '1';
                     pCode = S2CODE;
                     WkPicked = *on;
                     leave;
                  elseif S2OPT <> *blanks;
                     W2MSG = 'Type 1 to select.';
                  endif;
                  readc SFL02;
               enddo;
            endif;

            if WkPicked;
               leave;
            endif;
            // no selection: position-to may have changed, reload
            exsr LoadSfl;
         enddo;

         *inlr = *on;
         return;

         //------------------------------------------------------------
         // LoadSfl - fill the window list for the requested type
         //------------------------------------------------------------
         begsr LoadSfl;
            Ind.SflClr = *on;
            write CTL02;
            Ind.SflClr = *off;
            Rrn = 0;

            select;
            when pType = 'I';
               setll (W2POS) INVITM1;
               read INVITM1;
               dow not %eof(INVITM1) and Rrn < 9999;
                  if ITSTAT = 'A';
                     S2CODE = ITITEM;
                     S2DESC = ITDESC;
                     exsr AddLine;
                  endif;
                  read INVITM1;
               enddo;
            when pType = 'W';
               setll (%subst(W2POS: 1: 3)) INVWHS1;
               read INVWHS1;
               dow not %eof(INVWHS1) and Rrn < 9999;
                  if WHSTAT = 'A';
                     S2CODE = WHCODE;
                     S2DESC = %trim(WHNAME) + ', ' + WHCITY;
                     exsr AddLine;
                  endif;
                  read INVWHS1;
               enddo;
            other;
               S2CODE = 'I';
               S2DESC = 'Goods in (receipt)';
               exsr AddLine;
               S2CODE = 'O';
               S2DESC = 'Goods out (issue)';
               exsr AddLine;
               S2CODE = 'A';
               S2DESC = 'Adjustment (stock count)';
               exsr AddLine;
            endsl;

            Ind.SflDsp    = (Rrn > 0);
            Ind.SflDspCtl = *on;
            Ind.SflEnd    = *on;
            if Rrn > 0;
               RRN02 = 1;
            else;
               W2MSG = 'Nothing found.';
            endif;
         endsr;

         begsr AddLine;
            S2OPT = *blanks;
            Rrn += 1;
            write SFL02;
         endsr;
      /end-free
