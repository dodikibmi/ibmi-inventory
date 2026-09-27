-- ==========================================================================
--  IBM i Warehouse Inventory - stored procedure for the REST API
--  Run with : RUNSQLSTM SRCSTMF('/home/DODIKIBMI/inventory/sql/03_api.sql')
--                       COMMIT(*NONE) NAMING(*SQL) DECMPT(*PERIOD)
--
--  POST_MOVEMENT holds the posting rules of the green-screen program
--  INV200R in the database, so every channel (REST API, batch, a future
--  web page) applies the same checks:
--    - movement type I / O / A, active item, active warehouse,
--      quantity not zero (positive for I and O), date not in the future
--    - the stock row is read with an exclusive lock, so two callers
--      cannot both take the last units
--    - stock update (or first stock row) + movement insert
--  The procedure does NOT commit: the caller commits or rolls back the
--  unit of work. Business errors are raised with SQLSTATE 75001-75006 so
--  the caller can map them (the API turns 75006 into HTTP 409).
-- ==========================================================================

SET SCHEMA DODIKIBMI2;
SET PATH = DODIKIBMI2, SYSTEM PATH;

CREATE OR REPLACE PROCEDURE POST_MOVEMENT (
  IN  P_TYPE    CHAR(1),
  IN  P_ITEM    CHAR(10),
  IN  P_WHS     CHAR(3),
  IN  P_QTY     DECIMAL(9, 0),
  IN  P_DATE    DATE,
  IN  P_REF     CHAR(20),
  OUT P_MVNO    DECIMAL(9, 0),
  OUT P_NEWQTY  DECIMAL(9, 0))
  LANGUAGE SQL
  SPECIFIC INVPOSTMV
  MODIFIES SQL DATA
  SET OPTION DATFMT = *ISO, COMMIT = *CHG
BEGIN
  DECLARE V_DELTA  DECIMAL(9, 0);
  DECLARE V_ONHAND DECIMAL(9, 0) DEFAULT NULL;
  DECLARE V_FOUND  CHAR(1) DEFAULT 'Y';
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET V_FOUND = 'N';

  IF P_TYPE NOT IN ('I', 'O', 'A') THEN
    SIGNAL SQLSTATE '75001'
      SET MESSAGE_TEXT = 'Movement type must be I, O or A';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM ITEM_MASTER
                  WHERE ITITEM = P_ITEM AND ITSTAT = 'A') THEN
    SIGNAL SQLSTATE '75002'
      SET MESSAGE_TEXT = 'Item does not exist or is inactive';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM WAREHOUSE_MASTER
                  WHERE WHCODE = P_WHS AND WHSTAT = 'A') THEN
    SIGNAL SQLSTATE '75003'
      SET MESSAGE_TEXT = 'Warehouse does not exist or is inactive';
  END IF;

  IF P_QTY IS NULL OR P_QTY = 0 OR (P_TYPE <> 'A' AND P_QTY < 0) THEN
    SIGNAL SQLSTATE '75004'
      SET MESSAGE_TEXT = 'Quantity must be non-zero (positive for I and O)';
  END IF;

  IF P_DATE IS NULL OR P_DATE > CURRENT DATE THEN
    SIGNAL SQLSTATE '75005'
      SET MESSAGE_TEXT = 'Movement date is missing or in the future';
  END IF;

  SET V_DELTA = CASE P_TYPE WHEN 'O' THEN -P_QTY ELSE P_QTY END;

  -- read the stock row and keep an exclusive lock until commit/rollback
  SELECT STQTY INTO V_ONHAND
    FROM STOCK_BALANCE
   WHERE STITEM = P_ITEM AND STWHS = P_WHS
    WITH RS USE AND KEEP EXCLUSIVE LOCKS;

  IF V_FOUND = 'N' THEN
    SET V_ONHAND = 0;
  END IF;

  IF V_ONHAND + V_DELTA < 0 THEN
    SIGNAL SQLSTATE '75006'
      SET MESSAGE_TEXT = 'Insufficient stock for this movement';
  END IF;

  IF V_FOUND = 'N' THEN
    INSERT INTO STOCK_BALANCE (STITEM, STWHS, STQTY, STLSTD)
      VALUES (P_ITEM, P_WHS, V_DELTA, P_DATE);
  ELSE
    UPDATE STOCK_BALANCE
       SET STQTY  = STQTY + V_DELTA,
           STLSTD = MAX(STLSTD, P_DATE)
     WHERE STITEM = P_ITEM AND STWHS = P_WHS;
  END IF;

  SELECT MVNO INTO P_MVNO
    FROM FINAL TABLE (
      INSERT INTO STOCK_MOVEMENT (MVDATE, MVTYPE, MVITEM, MVWHS, MVQTY, MVREF)
        VALUES (P_DATE, P_TYPE, P_ITEM, P_WHS, P_QTY, P_REF));

  SET P_NEWQTY = V_ONHAND + V_DELTA;
END;

LABEL ON SPECIFIC PROCEDURE INVPOSTMV IS 'Inventory - post a stock movement';
