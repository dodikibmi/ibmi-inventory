-- ==========================================================================
--  IBM i Warehouse Inventory - integration objects
--  Run with : RUNSQLSTM SRCSTMF('/home/DODIKIBMI/inventory/sql/04_integration.sql')
--                       COMMIT(*NONE) NAMING(*SQL) DECMPT(*PERIOD)
--
--  1. Data queues for the stock inquiry service (INV810R):
--       INVREQQ  requests  (FIFO)   {"id":"...","item":"OF-0001"}
--       INVRPYQ  replies   (keyed by the request id, so many clients can
--                           wait on the same queue for their own answer)
--     Messages are UTF-8 JSON, so RPG, Node.js and Python read the same text.
--  2. PRICE_UPDATE: staging table for the CSV price import (INV820C), and
--     APPLY_PRICE_UPDATE, which checks every row and applies the good ones.
--  3. POST_DELIVERY_NOTE (the XML program INV830R as a procedure) and two
--     SQL-only examples: read the delivery note with XMLTABLE, write the
--     stock list as XML.
-- ==========================================================================

SET SCHEMA DODIKIBMI2;
SET PATH = DODIKIBMI2, SYSTEM PATH;

-- --------------------------------------------------------------------------
--  1. Data queues (no SQL DDL for data queues: QCMDEXC runs the CL command)
-- --------------------------------------------------------------------------
BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;   -- already there
  CALL QSYS2.QCMDEXC('CRTDTAQ DTAQ(DODIKIBMI2/INVREQQ) MAXLEN(512) ' CONCAT
                     'TEXT(''Inventory - stock inquiry requests'')');
END;

BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
  CALL QSYS2.QCMDEXC('CRTDTAQ DTAQ(DODIKIBMI2/INVRPYQ) MAXLEN(4000) ' CONCAT
                     'SEQ(*KEYED) KEYLEN(16) ' CONCAT
                     'TEXT(''Inventory - stock inquiry replies'')');
END;

-- --------------------------------------------------------------------------
--  2. CSV price import: staging table (same columns as the CSV file) and
--     the result of the last import
-- --------------------------------------------------------------------------
CREATE OR REPLACE TABLE PRICE_UPDATE FOR SYSTEM NAME INVPRCU (
  PUITEM   CHAR(10)       NOT NULL DEFAULT '',
  PUPRICE  DECIMAL(11, 2),
  PUMINQ   DECIMAL(7, 0)
) ON REPLACE DELETE ROWS;

LABEL ON TABLE PRICE_UPDATE IS 'Inventory - CSV price import (staging)';

CREATE OR REPLACE TABLE PRICE_UPDATE_RESULT FOR SYSTEM NAME INVPRCR (
  PRITEM   CHAR(10)       NOT NULL,
  PRPRICE  DECIMAL(11, 2),
  PRMINQ   DECIMAL(7, 0),
  PRRESULT VARCHAR(40)    NOT NULL,
  PRTIME   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
) ON REPLACE DELETE ROWS;

LABEL ON TABLE PRICE_UPDATE_RESULT IS 'Inventory - result of the last price import';

CREATE OR REPLACE PROCEDURE APPLY_PRICE_UPDATE ()
  LANGUAGE SQL
  SPECIFIC INVPRCAP
  MODIFIES SQL DATA
  SET OPTION DATFMT = *ISO, COMMIT = *NONE
BEGIN
  DELETE FROM PRICE_UPDATE_RESULT;

  -- every staged row gets a result: the first rule it breaks, or OK
  INSERT INTO PRICE_UPDATE_RESULT (PRITEM, PRPRICE, PRMINQ, PRRESULT)
    SELECT U.PUITEM, U.PUPRICE, U.PUMINQ,
           CASE WHEN I.ITITEM IS NULL            THEN 'unknown item'
                WHEN I.ITSTAT <> 'A'             THEN 'item not active'
                WHEN U.PUPRICE IS NULL
                  OR U.PUPRICE < 0               THEN 'price missing or negative'
                WHEN U.PUMINQ < 0                THEN 'minimum quantity negative'
                WHEN (SELECT COUNT(*) FROM PRICE_UPDATE D
                       WHERE D.PUITEM = U.PUITEM) > 1
                                                 THEN 'item twice in the file'
                ELSE 'OK' END
      FROM PRICE_UPDATE U
      LEFT JOIN ITEM_MASTER I ON I.ITITEM = U.PUITEM;

  -- only the good rows change the item master
  MERGE INTO ITEM_MASTER I
    USING (SELECT PRITEM, PRPRICE, PRMINQ FROM PRICE_UPDATE_RESULT
            WHERE PRRESULT = 'OK') R
       ON I.ITITEM = R.PRITEM
     WHEN MATCHED THEN UPDATE SET
          ITPRICE = R.PRPRICE,
          ITMINQ  = COALESCE(R.PRMINQ, I.ITMINQ),
          ITCHGU  = USER,
          ITCHGT  = CURRENT_TIMESTAMP;
END;

LABEL ON SPECIFIC PROCEDURE INVPRCAP IS 'Inventory - apply the CSV price import';

-- --------------------------------------------------------------------------
--  3. The XML delivery note program INV830R as an SQL procedure, so any
--     SQL client (Node.js, Python, Java, ACS) can post a note:
--       CALL POST_DELIVERY_NOTE('/path/delivery-note.xml', ?)
-- --------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE POST_DELIVERY_NOTE (
  IN  P_PATH    CHAR(200),
  OUT P_RESULT  CHAR(80))
  LANGUAGE RPGLE
  SPECIFIC INVPOSTDN
  MODIFIES SQL DATA
  EXTERNAL NAME DODIKIBMI1.INV830R
  PARAMETER STYLE GENERAL;

LABEL ON SPECIFIC PROCEDURE INVPOSTDN IS 'Inventory - post an XML delivery note';

-- --------------------------------------------------------------------------
--  3a. Read a delivery note XML with SQL only (preview before INV830R posts it)
--
--  SELECT X.*
--    FROM XMLTABLE('/deliveryNote/line'
--           PASSING XMLPARSE(DOCUMENT GET_XML_FILE(
--                   '/home/DODIKIBMI/inventory/integration/samples/delivery-note.xml'))
--           COLUMNS NOTE_NO   VARCHAR(20) PATH '../@number',
--                   WAREHOUSE CHAR(3)     PATH '../@warehouse',
--                   ITEM      CHAR(10)    PATH '@item',
--                   QUANTITY  DEC(9, 0)   PATH '@quantity') X;
--
--  3b. Stock list as XML (for a partner that wants XML instead of CSV)
--
--  SELECT XMLSERIALIZE(
--           XMLELEMENT(NAME "stock",
--             XMLATTRIBUTES(CURRENT DATE AS "date"),
--             XMLAGG(XMLELEMENT(NAME "item",
--                      XMLATTRIBUTES(TRIM(STITEM) AS "code",
--                                    TRIM(STWHS)  AS "warehouse",
--                                    STQTY        AS "quantity",
--                                    REORDER      AS "reorder"))
--                    ORDER BY STITEM, STWHS))
--           AS CLOB(1M) INCLUDING XMLDECLARATION)
--    FROM STOCK_STATUS;
-- --------------------------------------------------------------------------
