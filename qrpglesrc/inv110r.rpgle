     HDFTACTGRP(*NO) OPTION(*SRCSTMT:*NODEBUGIO)
     HDATFMT(*ISO) TIMFMT(*ISO)
     HACTGRP(*CALLER)
      * ------------------------------------------------------------
      * INV110R - Item maintenance (add / change / delete / display)
      * Called from INV100R with a mode and an item code.
      * Change uses optimistic locking: the record is read without a
      * lock for the screen and re-read with a lock before the update.
      * If ITCHGT differs, another user changed the item meanwhile and
      * the screen is reloaded instead of overwriting their change.
      * Delete is refused while stock or movement records exist; the
      * foreign keys in the database would reject it anyway.
      * ------------------------------------------------------------
     FINV110D   CF   E             WORKSTN INDDS(Ind)
     FINVITM1   UF A E           K DISK
     FINVSTK1   IF   E           K DISK
     FINVMOV1   IF   E           K DISK
      *
     DPSDS            SDS
     D  psPgm                  1     10
     D  psUser               254    263
      *
     DInd              DS                  QUALIFIED
     D  Exit                   3      3N
     D  Cancel                12     12N
     D  ProtAll               50     50N
     D  ProtKey               51     51N
     D  DelMode               52     52N
     D  ErrItem               61     61N
     D  ErrDesc               62     62N
     D  ErrCatg               63     63N
     D  ErrUom                64     64N
     D  ErrPrice              65     65N
     D  ErrMinq               66     66N
     D  ErrStat               67     67N
     D  ErrAll                61     67
      *
     DINV110R          PR                  EXTPGM('INV110R')
     D   pMode                        1A
     D   pItem                       10A
     DINV110R          PI
     D   pMode                        1A
     D   pItem                       10A
      *
     D  WkItem         S             10A
     D  WkChgT         S               Z
     D  WkMsg          S             78A
     D  WkError        S               N
     D  WkDone         S               N
     D  WkFail         S               N
      /free
         clear DETAIL;
         D1PGM = psPgm;
         Ind.ProtAll = (pMode = 'V' or pMode = 'D');
         Ind.ProtKey = (pMode <> 'A');
         Ind.DelMode = (pMode = 'D');

         select;
         when pMode = 'A';
            D1TITLE = '           Add Item';
         when pMode = 'C';
            D1TITLE = '         Change Item';
         when pMode = 'D';
            D1TITLE = '         Delete Item';
         other;
            D1TITLE = '        Display Item';
         endsl;

         if pMode = 'A';
            D1UOM  = 'PCS';
            D1STAT = 'A';
         else;
            chain(n) pItem INVITM1;
            if not %found(INVITM1);
               *inlr = *on;
               return;
            endif;
            exsr ToScreen;
         endif;

         if pMode = 'D';
            D1MSG = 'Check the item, then press Enter to delete it.';
         endif;

         dow *on;
            exfmt DETAIL;
            Ind.ErrAll = *all'0';
            D1MSG = *blanks;

            if Ind.Exit or Ind.Cancel or pMode = 'V';
               leave;
            endif;

            if pMode = 'D';
               exsr DoDelete;
            else;
               exsr Validate;
               if not WkError;
                  if pMode = 'A';
                     exsr DoAdd;
                  else;
                     exsr DoChange;
                  endif;
               endif;
            endif;

            if WkDone;
               leave;
            endif;
         enddo;

         *inlr = *on;
         return;

         //------------------------------------------------------------
         // ToScreen - item record to screen fields
         //------------------------------------------------------------
         begsr ToScreen;
            D1ITEM  = ITITEM;
            D1DESC  = ITDESC;
            D1CATG  = ITCATG;
            D1UOM   = ITUOM;
            D1PRICE = ITPRICE;
            D1MINQ  = ITMINQ;
            D1STAT  = ITSTAT;
            D1CRT   = %trim(ITCRTU) + '  ' + %subst(%char(ITCRTT): 1: 16);
            D1CHG   = %trim(ITCHGU) + '  ' + %subst(%char(ITCHGT): 1: 16);
            WkItem  = ITITEM;
            WkChgT  = ITCHGT;
            exsr SumStock;
         endsr;

         //------------------------------------------------------------
         // FromScreen - screen fields to item record
         //------------------------------------------------------------
         begsr FromScreen;
            ITDESC  = D1DESC;
            ITCATG  = D1CATG;
            ITUOM   = D1UOM;
            ITPRICE = D1PRICE;
            ITMINQ  = D1MINQ;
            ITSTAT  = D1STAT;
         endsr;

         //------------------------------------------------------------
         // SumStock - quantity on hand of WkItem over all warehouses
         //------------------------------------------------------------
         begsr SumStock;
            D1QTY = 0;
            setll WkItem INVSTK1;
            reade WkItem INVSTK1;
            dow not %eof(INVSTK1);
               D1QTY += STQTY;
               reade WkItem INVSTK1;
            enddo;
         endsr;

         //------------------------------------------------------------
         // Validate - check every input field; the first error found
         // (top of the screen first) is the message shown
         //------------------------------------------------------------
         begsr Validate;
            WkError = *off;

            if pMode = 'A';
               if D1ITEM = *blanks;
                  Ind.ErrItem = *on;
                  WkMsg = 'Item code is required.';
                  exsr AddErr;
               else;
                  setll D1ITEM INVITM1;
                  if %equal(INVITM1);
                     Ind.ErrItem = *on;
                     WkMsg = 'Item ' + %trim(D1ITEM) + ' already exists.';
                     exsr AddErr;
                  endif;
               endif;
            endif;

            if D1DESC = *blanks;
               Ind.ErrDesc = *on;
               WkMsg = 'Description is required.';
               exsr AddErr;
            endif;

            if D1CATG = *blanks;
               Ind.ErrCatg = *on;
               WkMsg = 'Category is required.';
               exsr AddErr;
            endif;

            if D1UOM = *blanks;
               Ind.ErrUom = *on;
               WkMsg = 'Unit of measure is required.';
               exsr AddErr;
            endif;

            if D1PRICE < 0;
               Ind.ErrPrice = *on;
               WkMsg = 'Unit price cannot be negative.';
               exsr AddErr;
            endif;

            if D1MINQ < 0;
               Ind.ErrMinq = *on;
               WkMsg = 'Minimum stock cannot be negative.';
               exsr AddErr;
            endif;

            if D1STAT <> 'A' and D1STAT <> 'I';
               Ind.ErrStat = *on;
               WkMsg = 'Status must be A or I.';
               exsr AddErr;
            endif;
         endsr;

         begsr AddErr;
            WkError = *on;
            if D1MSG = *blanks;
               D1MSG = WkMsg;
            endif;
         endsr;

         //------------------------------------------------------------
         // DoAdd - write a new item
         //------------------------------------------------------------
         begsr DoAdd;
            clear INVITMR;
            ITITEM = D1ITEM;
            exsr FromScreen;
            ITCRTU = psUser;
            ITCRTT = %timestamp();
            ITCHGU = psUser;
            ITCHGT = ITCRTT;
            monitor;
               write INVITMR;
               WkDone = *on;
            on-error;
               D1MSG = 'Item could not be added (see job log).';
            endmon;
         endsr;

         //------------------------------------------------------------
         // DoChange - optimistic locking update
         //------------------------------------------------------------
         begsr DoChange;
            chain WkItem INVITM1;
            if not %found(INVITM1);
               D1MSG = 'Item was deleted by another user.';
               leavesr;
            endif;

            if ITCHGT <> WkChgT;
               unlock INVITM1;
               exsr ToScreen;
               D1MSG = 'Item was changed by another user; data reloaded.';
               leavesr;
            endif;

            exsr FromScreen;
            ITCHGU = psUser;
            ITCHGT = %timestamp();
            monitor;
               update INVITMR;
               WkDone = *on;
            on-error;
               unlock INVITM1;
               D1MSG = 'Item could not be changed (see job log).';
            endmon;
         endsr;

         //------------------------------------------------------------
         // DoDelete - refuse while stock or movements exist
         //------------------------------------------------------------
         begsr DoDelete;
            setll WkItem INVSTK1;
            if %equal(INVSTK1);
               D1MSG = 'Item has stock: use option 2=Change, set status I.';
               leavesr;
            endif;

            setll WkItem INVMOV1;
            if %equal(INVMOV1);
               D1MSG = 'Item has movements: use option 2=Change, set status I.';
               leavesr;
            endif;

            WkFail = *off;
            chain WkItem INVITM1;
            if %found(INVITM1);
               monitor;
                  delete INVITMR;
               on-error;
                  unlock INVITM1;
                  WkFail = *on;
               endmon;
            endif;

            if WkFail;
               D1MSG = 'Item could not be deleted (see job log).';
            else;
               WkDone = *on;
            endif;
         endsr;
      /end-free
