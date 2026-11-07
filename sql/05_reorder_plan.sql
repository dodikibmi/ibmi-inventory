-- ==========================================================================
--  IBM i Warehouse Inventory - reorder plan written by the COBOL program
--  Run with : RUNSQLSTM SRCSTMF('/home/DODIKIBMI/inventory/sql/05_reorder_plan.sql')
--                       COMMIT(*NONE) NAMING(*SQL) DECMPT(*PERIOD)
--
--  INV850C (ILE COBOL + embedded SQL, bound to the RPG service program
--  DATEUTIL) fills REORDER_PLAN once per order date. BUILD_REORDER_PLAN
--  makes it callable from any SQL client: CALL BUILD_REORDER_PLAN(?)
-- ==========================================================================

SET SCHEMA DODIKIBMI2;

CREATE OR REPLACE TABLE REORDER_PLAN FOR SYSTEM NAME INVRPLN (
  RPORDD    DATE          NOT NULL,
  RPWHS     CHAR(3)       NOT NULL,
  RPITEM    CHAR(10)      NOT NULL,
  RPONHAND  DECIMAL(9, 0) NOT NULL,
  RPMINQ    DECIMAL(7, 0) NOT NULL,
  RPORDQ    DECIMAL(9, 0) NOT NULL,
  RPLEAD    INTEGER       NOT NULL,
  RPEXPD    DATE          NOT NULL,
  RPEXPDAY  CHAR(9)       NOT NULL DEFAULT '',
  RPCRTT    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT REORDER_PLAN_PK PRIMARY KEY (RPORDD, RPWHS, RPITEM)
) ON REPLACE PRESERVE ROWS;

LABEL ON TABLE REORDER_PLAN IS 'Inventory - reorder plan (COBOL INV850C)';

LABEL ON COLUMN REORDER_PLAN (
  RPORDD   TEXT IS 'Order date',
  RPWHS    TEXT IS 'Warehouse',
  RPITEM   TEXT IS 'Item',
  RPONHAND TEXT IS 'On hand at planning',
  RPMINQ   TEXT IS 'Minimum quantity',
  RPORDQ   TEXT IS 'Quantity to order',
  RPLEAD   TEXT IS 'Lead time (working days)',
  RPEXPD   TEXT IS 'Expected delivery date',
  RPEXPDAY TEXT IS 'Expected delivery weekday',
  RPCRTT   TEXT IS 'Created at'
);

CREATE OR REPLACE PROCEDURE BUILD_REORDER_PLAN (
  OUT P_RESULT CHAR(80))
  LANGUAGE COBOLLE
  SPECIFIC INVRPLNB
  MODIFIES SQL DATA
  EXTERNAL NAME DODIKIBMI1.INV850C
  PARAMETER STYLE GENERAL;

LABEL ON SPECIFIC PROCEDURE INVRPLNB IS 'Inventory - build the reorder plan (COBOL)';
