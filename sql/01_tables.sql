-- ==========================================================================
--  IBM i Warehouse Inventory - database objects
--  Target schema : DODIKIBMI2 (data library)
--  Run with      : RUNSQLSTM SRCSTMF('/home/DODIKIBMI/inventory/sql/01_tables.sql')
--                            COMMIT(*NONE) NAMING(*SQL) DECMPT(*PERIOD)
--
--  Each table has a long SQL name, a 10-character system name and an explicit
--  record format, so RPG programs can use native I/O (CHAIN / READE / WRITE)
--  on the tables and indexes. Indexes are what RPG uses as keyed files.
--  User columns are CHAR(18): DEFAULT USER needs room for the special
--  register USER, which is VARCHAR(18) (SQL0574 otherwise).
--  SQL names are longer than 10 characters on purpose: FOR SYSTEM NAME is
--  rejected (SQL7029) when the SQL name is itself a valid system name.
--  DECMPT(*PERIOD) keeps '.' as the decimal point on jobs whose locale
--  uses a comma (PUB400 runs with a German locale).
--
--  The schema must already contain journal QSQJRN (see README): tables created
--  in a library with QSQJRN are journaled automatically, which is required for
--  commitment control in the stock movement program.
-- ==========================================================================

SET SCHEMA DODIKIBMI2;

-- --------------------------------------------------------------------------
--  WAREHOUSE - storage locations
-- --------------------------------------------------------------------------
CREATE OR REPLACE TABLE WAREHOUSE_MASTER FOR SYSTEM NAME INVWHS (
  WHCODE  CHAR(3)   NOT NULL,
  WHNAME  CHAR(30)  NOT NULL DEFAULT '',
  WHCITY  CHAR(20)  NOT NULL DEFAULT '',
  WHSTAT  CHAR(1)   NOT NULL DEFAULT 'A',
  CONSTRAINT WAREHOUSE_PK PRIMARY KEY (WHCODE),
  CONSTRAINT WAREHOUSE_STAT_CK CHECK (WHSTAT IN ('A', 'I'))
) RCDFMT INVWHSR;

LABEL ON TABLE WAREHOUSE_MASTER IS 'Inventory - warehouse';
LABEL ON COLUMN WAREHOUSE_MASTER (
  WHCODE IS 'Warehouse code',
  WHNAME IS 'Warehouse name',
  WHCITY IS 'City',
  WHSTAT IS 'Status A=Active I=Inactive'
);
LABEL ON COLUMN WAREHOUSE_MASTER (
  WHCODE TEXT IS 'Warehouse code',
  WHNAME TEXT IS 'Warehouse name',
  WHCITY TEXT IS 'City',
  WHSTAT TEXT IS 'Status A=Active I=Inactive'
);

-- --------------------------------------------------------------------------
--  ITEM - item master
-- --------------------------------------------------------------------------
CREATE OR REPLACE TABLE ITEM_MASTER FOR SYSTEM NAME INVITM (
  ITITEM   CHAR(10)      NOT NULL,
  ITDESC   CHAR(40)      NOT NULL DEFAULT '',
  ITCATG   CHAR(4)       NOT NULL DEFAULT '',
  ITUOM    CHAR(3)       NOT NULL DEFAULT 'PCS',
  ITPRICE  DECIMAL(11, 2) NOT NULL DEFAULT 0,
  ITMINQ   DECIMAL(7, 0)  NOT NULL DEFAULT 0,
  ITSTAT   CHAR(1)       NOT NULL DEFAULT 'A',
  ITCRTU   CHAR(18)      NOT NULL DEFAULT USER,
  ITCRTT   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ITCHGU   CHAR(18)      NOT NULL DEFAULT USER,
  ITCHGT   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ITEM_PK PRIMARY KEY (ITITEM),
  CONSTRAINT ITEM_STAT_CK CHECK (ITSTAT IN ('A', 'I')),
  CONSTRAINT ITEM_PRICE_CK CHECK (ITPRICE >= 0),
  CONSTRAINT ITEM_MINQ_CK CHECK (ITMINQ >= 0)
) RCDFMT INVITMR;

LABEL ON TABLE ITEM_MASTER IS 'Inventory - item master';
LABEL ON COLUMN ITEM_MASTER (
  ITITEM  TEXT IS 'Item code',
  ITDESC  TEXT IS 'Description',
  ITCATG  TEXT IS 'Category',
  ITUOM   TEXT IS 'Unit of measure',
  ITPRICE TEXT IS 'Unit price',
  ITMINQ  TEXT IS 'Minimum stock (reorder point)',
  ITSTAT  TEXT IS 'Status A=Active I=Inactive',
  ITCRTU  TEXT IS 'Created by',
  ITCRTT  TEXT IS 'Created at',
  ITCHGU  TEXT IS 'Changed by',
  ITCHGT  TEXT IS 'Changed at'
);

-- --------------------------------------------------------------------------
--  STOCK - on-hand quantity per item and warehouse
--  The CHECK constraint is the last line of defence against negative stock;
--  the movement program validates first and rolls back on failure.
-- --------------------------------------------------------------------------
CREATE OR REPLACE TABLE STOCK_BALANCE FOR SYSTEM NAME INVSTK (
  STITEM  CHAR(10)     NOT NULL,
  STWHS   CHAR(3)      NOT NULL,
  STQTY   DECIMAL(9, 0) NOT NULL DEFAULT 0,
  STLSTD  DATE         NOT NULL DEFAULT CURRENT_DATE,
  CONSTRAINT STOCK_PK PRIMARY KEY (STITEM, STWHS),
  CONSTRAINT STOCK_ITEM_FK FOREIGN KEY (STITEM) REFERENCES ITEM_MASTER (ITITEM),
  CONSTRAINT STOCK_WHS_FK FOREIGN KEY (STWHS) REFERENCES WAREHOUSE_MASTER (WHCODE),
  CONSTRAINT STOCK_QTY_CK CHECK (STQTY >= 0)
) RCDFMT INVSTKR;

LABEL ON TABLE STOCK_BALANCE IS 'Inventory - stock on hand';
LABEL ON COLUMN STOCK_BALANCE (
  STITEM TEXT IS 'Item code',
  STWHS  TEXT IS 'Warehouse code',
  STQTY  TEXT IS 'Quantity on hand',
  STLSTD TEXT IS 'Last movement date'
);

-- --------------------------------------------------------------------------
--  MOVEMENT - every stock change (goods in, goods out, adjustment)
--  MVNO is an identity column: the database assigns it, also on RPG WRITE.
-- --------------------------------------------------------------------------
CREATE OR REPLACE TABLE STOCK_MOVEMENT FOR SYSTEM NAME INVMOV (
  MVNO    DECIMAL(9, 0) GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1),
  MVDATE  DATE         NOT NULL DEFAULT CURRENT_DATE,
  MVTYPE  CHAR(1)      NOT NULL,
  MVITEM  CHAR(10)     NOT NULL,
  MVWHS   CHAR(3)      NOT NULL,
  MVQTY   DECIMAL(9, 0) NOT NULL,
  MVREF   CHAR(20)     NOT NULL DEFAULT '',
  MVUSER  CHAR(18)     NOT NULL DEFAULT USER,
  MVTIME  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT MOVEMENT_PK PRIMARY KEY (MVNO),
  CONSTRAINT MOVEMENT_ITEM_FK FOREIGN KEY (MVITEM) REFERENCES ITEM_MASTER (ITITEM),
  CONSTRAINT MOVEMENT_WHS_FK FOREIGN KEY (MVWHS) REFERENCES WAREHOUSE_MASTER (WHCODE),
  CONSTRAINT MOVEMENT_TYPE_CK CHECK (MVTYPE IN ('I', 'O', 'A')),
  CONSTRAINT MOVEMENT_QTY_CK CHECK (MVQTY <> 0)
) RCDFMT INVMOVR;

LABEL ON TABLE STOCK_MOVEMENT IS 'Inventory - stock movement';
LABEL ON COLUMN STOCK_MOVEMENT (
  MVNO   TEXT IS 'Movement number',
  MVDATE TEXT IS 'Movement date',
  MVTYPE TEXT IS 'Type I=In O=Out A=Adjust',
  MVITEM TEXT IS 'Item code',
  MVWHS  TEXT IS 'Warehouse code',
  MVQTY  TEXT IS 'Quantity (signed for A)',
  MVREF  TEXT IS 'Reference document',
  MVUSER TEXT IS 'Entered by',
  MVTIME TEXT IS 'Entered at'
);

-- --------------------------------------------------------------------------
--  HOLIDAY - non-working days used by the date service program
-- --------------------------------------------------------------------------
CREATE OR REPLACE TABLE HOLIDAY_CALENDAR FOR SYSTEM NAME INVHOL (
  HLDATE  DATE      NOT NULL,
  HLDESC  CHAR(30)  NOT NULL DEFAULT '',
  CONSTRAINT HOLIDAY_PK PRIMARY KEY (HLDATE)
) RCDFMT INVHOLR;

LABEL ON TABLE HOLIDAY_CALENDAR IS 'Inventory - holiday calendar';
LABEL ON COLUMN HOLIDAY_CALENDAR (
  HLDATE TEXT IS 'Holiday date',
  HLDESC TEXT IS 'Description'
);

-- --------------------------------------------------------------------------
--  Indexes = keyed access paths for RPG (F-spec, CHAIN, SETLL/READE).
--  An SQL index shares the record format of its table.
-- --------------------------------------------------------------------------
CREATE UNIQUE INDEX WAREHOUSE_BY_CODE FOR SYSTEM NAME INVWHS1
  ON WAREHOUSE_MASTER (WHCODE);
CREATE UNIQUE INDEX ITEM_BY_CODE FOR SYSTEM NAME INVITM1
  ON ITEM_MASTER (ITITEM);
CREATE INDEX ITEM_BY_DESC FOR SYSTEM NAME INVITM2
  ON ITEM_MASTER (ITDESC, ITITEM);
CREATE UNIQUE INDEX STOCK_BY_ITEM_WHS FOR SYSTEM NAME INVSTK1
  ON STOCK_BALANCE (STITEM, STWHS);
CREATE UNIQUE INDEX MOVEMENT_BY_ITEM FOR SYSTEM NAME INVMOV1
  ON STOCK_MOVEMENT (MVITEM, MVWHS, MVDATE, MVNO);
CREATE UNIQUE INDEX HOLIDAY_BY_DATE FOR SYSTEM NAME INVHOL1
  ON HOLIDAY_CALENDAR (HLDATE);

LABEL ON INDEX WAREHOUSE_BY_CODE IS 'Inventory - warehouse by code';
LABEL ON INDEX ITEM_BY_CODE IS 'Inventory - item by code';
LABEL ON INDEX ITEM_BY_DESC IS 'Inventory - item by description';
LABEL ON INDEX STOCK_BY_ITEM_WHS IS 'Inventory - stock by item/warehouse';
LABEL ON INDEX MOVEMENT_BY_ITEM IS 'Inventory - movement by item/date';
LABEL ON INDEX HOLIDAY_BY_DATE IS 'Inventory - holiday by date';

-- --------------------------------------------------------------------------
--  View for reports and the JSON export: stock with item and warehouse data
--  and a reorder flag.
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW STOCK_STATUS FOR SYSTEM NAME INVSTKV AS
  SELECT S.STWHS, W.WHNAME, S.STITEM, I.ITDESC, I.ITCATG, I.ITUOM,
         S.STQTY, I.ITMINQ, I.ITPRICE,
         S.STQTY * I.ITPRICE AS STVALUE,
         CASE WHEN S.STQTY < I.ITMINQ THEN 'Y' ELSE 'N' END AS REORDER,
         S.STLSTD
    FROM STOCK_BALANCE S
    JOIN ITEM_MASTER I      ON I.ITITEM = S.STITEM
    JOIN WAREHOUSE_MASTER W ON W.WHCODE = S.STWHS;

LABEL ON TABLE STOCK_STATUS IS 'Inventory - stock status view';
