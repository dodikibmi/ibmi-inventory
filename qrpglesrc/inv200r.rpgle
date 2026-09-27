     HDFTACTGRP(*NO) OPTION(*SRCSTMT:*NODEBUGIO)
     HDATFMT(*ISO) TIMFMT(*ISO)
     HACTGRP('INVENTORY') BNDDIR('INVENTORY')
      * ------------------------------------------------------------
      * INV200R - Stock movement entry (goods in / out / adjust)
      * Enter validates the entry and previews the stock before and
      * after; F10 posts it. Posting updates STOCK_BALANCE and writes
      * STOCK_MOVEMENT as ONE unit of work under commitment control:
      * either both changes are committed or both are rolled back.
      * The stock row is re-read with a lock before posting, so two
      * users cannot both take the last units of an item.
      * Commitment control is started by the program itself (scope
      * *ACTGRP) and the journaled files are opened afterwards.
      * F4 on type, item or warehouse opens prompt window INV900R.
      * A movement dated on a weekend or holiday gets a warning from
      * service program DATEUTIL (DateIsWorkday) but can be posted.
      * ------------------------------------------------------------
     FINV200D   CF   E             WORKSTN INDDS(Ind)
     FINVITM1   IF   E           K DISK
     FINVWHS1   IF   E           K DISK
     FINVSTK1   UF A E           K DISK    COMMIT USROPN
     FINVMOV1   IF A E           K DISK    COMMIT USROPN
      *
      /COPY DODIKIBMI1/QRPGLESRC,DATEUTILPR
      *
     DPSDS            SDS
     D  psPgm                  1     10
     D  psUser               254    263
      *
     DInd              DS                  QUALIFIED
     D  Exit                   3      3N
     D  Clear                  5      5N
     D  Prompt                 4      4N
     D  Post                  10     10N
     D  Cancel                12     12N
     D  ErrType               61     61N
     D  ErrItem               62     62N
     D  ErrWhs                63     63N
     D  ErrQty                64     64N
     D  ErrDate               65     65N
     D  ErrAll                61     65
     D  Ready                 70     70N
      *
     DQCmdExc          PR                  EXTPGM('QCMDEXC')
     D   Cmd                       3000A   CONST OPTIONS(*VARSIZE)
     D   CmdLen                      15P 5 CONST
      *
      * F4 prompt window: type I=items W=warehouses T=movement types
     D  Inv900r        PR                  EXTPGM('INV900R')
     D   pType                        1A   CONST
     D   pCode                       10A
      *
     D  WkCode         S             10A
     D  WkCmd          S            200A   VARYING
     D  WkMsg          S             78A
     D  WkDelta        S              9P 0
     D  WkNew          S              9P 0
     D  WkMvNo         S              9P 0
     D  WkError        S               N
     D  WkFound        S               N
     D  WkFail         S               N
      /free
         exsr StartCmt;
         exsr ClearEntry;

         dow *on;
            exfmt ENTRY;
            D2MSG = *blanks;

            select;
            when Ind.Exit or Ind.Cancel;
               leave;
            when Ind.Prompt;
               exsr Prompt;
            when Ind.Clear;
               exsr ClearEntry;
            when Ind.Post;
               exsr Validate;
               if not WkError;
                  exsr PostMove;
               endif;
            other;
               exsr Validate;
               if not WkError and D2MSG = *blanks;
                  D2MSG = 'Check the result, then press F10 to post.';
               endif;
            endsl;
         enddo;

         exsr EndCmt;
         *inlr = *on;
         return;

         //------------------------------------------------------------
         // Prompt - F4: open the selection window for the field the
         // cursor is on (RTNCSRLOC fills D2CFLD) and copy the choice
         //------------------------------------------------------------
         begsr Prompt;
            Ind.Ready = *off;
            select;
            when D2CFLD = 'D2TYPE';
               WkCode = D2TYPE;
               Inv900r('T': WkCode);
               D2TYPE = WkCode;
            when D2CFLD = 'D2ITEM';
               WkCode = D2ITEM;
               Inv900r('I': WkCode);
               D2ITEM = WkCode;
               chain D2ITEM INVITM1;
               if %found(INVITM1);
                  D2DESC = ITDESC;
               endif;
            when D2CFLD = 'D2WHS';
               WkCode = D2WHS;
               Inv900r('W': WkCode);
               D2WHS = WkCode;
               chain D2WHS INVWHS1;
               if %found(INVWHS1);
                  D2WHNM = WHNAME;
               endif;
            other;
               D2MSG = 'F4 works on movement type, item code and warehouse.';
            endsl;
         endsr;

         //------------------------------------------------------------
         // StartCmt - start commitment control, then open the files
         //------------------------------------------------------------
         begsr StartCmt;
            monitor;
               WkCmd = 'STRCMTCTL LCKLVL(*CHG) CMTSCOPE(*ACTGRP)';
               QCmdExc(WkCmd: %len(WkCmd));
            on-error;
               // CPF8351: already started for this activation group
            endmon;
            open INVSTK1;
            open INVMOV1;
         endsr;

         //------------------------------------------------------------
         // EndCmt - close the files, then end commitment control
         //------------------------------------------------------------
         begsr EndCmt;
            if %open(INVSTK1);
               close INVSTK1;
            endif;
            if %open(INVMOV1);
               close INVMOV1;
            endif;
            monitor;
               WkCmd = 'ENDCMTCTL';
               QCmdExc(WkCmd: %len(WkCmd));
            on-error;
            endmon;
         endsr;

         //------------------------------------------------------------
         // ClearEntry - empty screen; movement type I and today's date
         //------------------------------------------------------------
         begsr ClearEntry;
            clear ENTRY;
            D2PGM  = psPgm;
            D2TYPE = 'I';
            D2DATE = %date();
            Ind.ErrAll = *all'0';
            Ind.Ready  = *off;
         endsr;

         //------------------------------------------------------------
         // Validate - check the entry and compute the preview
         //------------------------------------------------------------
         begsr Validate;
            WkError = *off;
            Ind.ErrAll = *all'0';
            Ind.Ready  = *off;
            D2DESC = *blanks;
            D2WHNM = *blanks;

            if D2TYPE <> 'I' and D2TYPE <> 'O' and D2TYPE <> 'A';
               Ind.ErrType = *on;
               WkMsg = 'Movement type must be I, O or A.';
               exsr AddErr;
            endif;

            chain D2ITEM INVITM1;
            if not %found(INVITM1);
               Ind.ErrItem = *on;
               WkMsg = 'Item ' + %trim(D2ITEM) + ' does not exist.';
               exsr AddErr;
            elseif ITSTAT <> 'A';
               Ind.ErrItem = *on;
               WkMsg = 'Item ' + %trim(D2ITEM) + ' is inactive.';
               exsr AddErr;
            else;
               D2DESC = ITDESC;
            endif;

            chain D2WHS INVWHS1;
            if not %found(INVWHS1);
               Ind.ErrWhs = *on;
               WkMsg = 'Warehouse ' + %trim(D2WHS) + ' does not exist.';
               exsr AddErr;
            elseif WHSTAT <> 'A';
               Ind.ErrWhs = *on;
               WkMsg = 'Warehouse ' + %trim(D2WHS) + ' is inactive.';
               exsr AddErr;
            else;
               D2WHNM = WHNAME;
            endif;

            if D2QTY = 0;
               Ind.ErrQty = *on;
               WkMsg = 'Quantity is required.';
               exsr AddErr;
            elseif D2TYPE <> 'A' and D2QTY < 0;
               Ind.ErrQty = *on;
               WkMsg = 'Quantity must be positive for goods in or out.';
               exsr AddErr;
            endif;

            if D2DATE > %date();
               Ind.ErrDate = *on;
               WkMsg = 'Movement date cannot be in the future.';
               exsr AddErr;
            endif;

            if not WkError;
               exsr CalcNew;
               if WkNew < 0;
                  Ind.ErrQty = *on;
                  WkMsg = 'Insufficient stock: on hand is '
                        + %char(D2CURR) + '.';
                  exsr AddErr;
               else;
                  Ind.Ready = *on;
                  if not DateIsWorkday(D2DATE);
                     D2MSG = 'Note: ' + %char(D2DATE)
                           + ' is not a working day; F10 posts anyway.';
                  endif;
               endif;
            endif;
         endsr;

         begsr AddErr;
            WkError = *on;
            if D2MSG = *blanks;
               D2MSG = WkMsg;
            endif;
         endsr;

         //------------------------------------------------------------
         // CalcNew - signed change and stock before / after (no lock)
         //------------------------------------------------------------
         begsr CalcNew;
            select;
            when D2TYPE = 'I';
               WkDelta = D2QTY;
            when D2TYPE = 'O';
               WkDelta = -D2QTY;
            other;
               WkDelta = D2QTY;
            endsl;

            chain(n) (D2ITEM: D2WHS) INVSTK1;
            if %found(INVSTK1);
               D2CURR = STQTY;
            else;
               D2CURR = 0;
            endif;
            WkNew = D2CURR + WkDelta;
            D2NEW = WkNew;
         endsr;

         //------------------------------------------------------------
         // PostMove - stock update + movement insert in one transaction
         //------------------------------------------------------------
         begsr PostMove;
            // lock the stock row and check again: another user may have
            // posted since the preview was shown
            chain (D2ITEM: D2WHS) INVSTK1;
            WkFound = %found(INVSTK1);
            if WkFound;
               D2CURR = STQTY;
            else;
               D2CURR = 0;
            endif;
            WkNew = D2CURR + WkDelta;
            D2NEW = WkNew;

            if WkNew < 0;
               rolbk;
               Ind.ErrQty = *on;
               Ind.Ready  = *off;
               D2MSG = 'Stock changed meanwhile: on hand is now '
                     + %char(D2CURR) + '.';
               leavesr;
            endif;

            WkFail = *off;
            monitor;
               if WkFound;
                  STQTY = WkNew;
                  if D2DATE > STLSTD;
                     STLSTD = D2DATE;
                  endif;
                  update INVSTKR;
               else;
                  clear INVSTKR;
                  STITEM = D2ITEM;
                  STWHS  = D2WHS;
                  STQTY  = WkNew;
                  STLSTD = D2DATE;
                  write INVSTKR;
               endif;

               clear INVMOVR;
               MVDATE = D2DATE;
               MVTYPE = D2TYPE;
               MVITEM = D2ITEM;
               MVWHS  = D2WHS;
               MVQTY  = D2QTY;
               MVREF  = D2REF;
               MVUSER = psUser;
               MVTIME = %timestamp();
               write INVMOVR;
               exsr LastMovNo;

               commit;
            on-error;
               WkFail = *on;
            endmon;

            if WkFail;
               rolbk;
               Ind.Ready = *off;
               D2MSG = 'Posting failed; nothing was changed (see job log).';
               leavesr;
            endif;

            D2MSG = 'Movement ' + %char(WkMvNo) + ' posted: '
                  + %trim(D2ITEM) + ' in ' + D2WHS + ' is now '
                  + %char(WkNew) + '.';

            // ready for the next line: keep type, warehouse and date
            clear D2ITEM;
            clear D2DESC;
            clear D2QTY;
            clear D2REF;
            Ind.Ready = *off;
         endsr;

         //------------------------------------------------------------
         // LastMovNo - number the database assigned to the movement.
         // MVNO is an identity column, so RPG does not know it after
         // WRITE. Called before COMMIT while the stock row is still
         // locked: postings for the same item/warehouse wait for that
         // lock, so the highest MVNO for item/warehouse/date is ours.
         //------------------------------------------------------------
         begsr LastMovNo;
            WkMvNo = 0;
            setgt (D2ITEM: D2WHS: D2DATE) INVMOV1;
            readpe (D2ITEM: D2WHS: D2DATE) INVMOV1;
            if not %eof(INVMOV1);
               WkMvNo = MVNO;
            endif;
         endsr;
      /end-free
