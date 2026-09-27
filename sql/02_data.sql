-- ==========================================================================
--  IBM i Warehouse Inventory - sample data (all fictional)
--  Run with : RUNSQLSTM SRCSTMF('/home/DODIKIBMI/inventory/sql/02_data.sql')
--                       COMMIT(*NONE) NAMING(*SQL) DECMPT(*PERIOD)
--  Re-runnable: existing rows are removed first (children before parents).
-- ==========================================================================

SET SCHEMA DODIKIBMI2;

DELETE FROM STOCK_MOVEMENT;
DELETE FROM STOCK_BALANCE;
DELETE FROM ITEM_MASTER;
DELETE FROM WAREHOUSE_MASTER;
DELETE FROM HOLIDAY_CALENDAR;
ALTER TABLE STOCK_MOVEMENT ALTER COLUMN MVNO RESTART WITH 1;

INSERT INTO WAREHOUSE_MASTER (WHCODE, WHNAME, WHCITY, WHSTAT) VALUES
  ('CTR', 'Central Warehouse',      'Semarang', 'A'),
  ('EST', 'East Distribution Hub',  'Surabaya', 'A'),
  ('WST', 'West Distribution Hub',  'Bandung',  'A'),
  ('OLD', 'Old Storage (closed)',   'Semarang', 'I');

INSERT INTO ITEM_MASTER (ITITEM, ITDESC, ITCATG, ITUOM, ITPRICE, ITMINQ) VALUES
  ('OF-0001', 'A4 COPY PAPER 80GSM (REAM)',        'OFFC', 'RIM',   52000.00,  50),
  ('OF-0002', 'BALLPOINT PEN BLUE (BOX OF 12)',    'OFFC', 'BOX',   24000.00,  30),
  ('OF-0003', 'STAPLER HEAVY DUTY',                'OFFC', 'PCS',   85000.00,  10),
  ('OF-0004', 'LEVER ARCH FILE FOLIO',             'OFFC', 'PCS',   27500.00,  40),
  ('OF-0005', 'WHITEBOARD MARKER BLACK (BOX 12)',  'OFFC', 'BOX',   96000.00,  15),
  ('EL-0001', 'USB FLASH DRIVE 64GB',              'ELEC', 'PCS',   89000.00,  20),
  ('EL-0002', 'WIRELESS MOUSE',                    'ELEC', 'PCS',  135000.00,  15),
  ('EL-0003', 'USB KEYBOARD',                      'ELEC', 'PCS',  175000.00,  15),
  ('EL-0004', 'LED MONITOR 24 INCH',               'ELEC', 'PCS', 1850000.00,   5),
  ('EL-0005', 'UPS 1200VA',                        'ELEC', 'PCS', 1450000.00,   3),
  ('EL-0006', 'HDMI CABLE 2M',                     'ELEC', 'PCS',   45000.00,  25),
  ('CL-0001', 'FLOOR CLEANER 5L',                  'CLNG', 'GAL',   78000.00,  12),
  ('CL-0002', 'HAND SOAP REFILL 1L',               'CLNG', 'BTL',   32000.00,  24),
  ('CL-0003', 'TISSUE ROLL (PACK OF 10)',          'CLNG', 'PAK',   41000.00,  30),
  ('CL-0004', 'GARBAGE BAG LARGE (ROLL)',          'CLNG', 'ROL',   18500.00,  40),
  ('PK-0001', 'CARTON BOX 40X30X30',               'PACK', 'PCS',    9500.00, 100),
  ('PK-0002', 'BUBBLE WRAP ROLL 50M',              'PACK', 'ROL',  165000.00,   6),
  ('PK-0003', 'PACKING TAPE CLEAR 48MM',           'PACK', 'PCS',   12000.00,  60),
  ('PK-0004', 'STRETCH FILM 500MM',                'PACK', 'ROL',   98000.00,  10),
  ('PK-0005', 'PALLET WOODEN 120X100',             'PACK', 'PCS',  210000.00,   8);

UPDATE ITEM_MASTER SET ITSTAT = 'I' WHERE ITITEM = 'EL-0006';

INSERT INTO STOCK_BALANCE (STITEM, STWHS, STQTY, STLSTD) VALUES
  ('OF-0001', 'CTR', 320, '2026-09-21'), ('OF-0001', 'EST', 140, '2026-09-18'),
  ('OF-0001', 'WST',  35, '2026-09-15'), ('OF-0002', 'CTR', 120, '2026-09-10'),
  ('OF-0002', 'EST',  22, '2026-09-11'), ('OF-0003', 'CTR',  18, '2026-08-30'),
  ('OF-0004', 'CTR', 210, '2026-09-19'), ('OF-0004', 'WST',  60, '2026-09-12'),
  ('OF-0005', 'CTR',   9, '2026-09-22'), ('EL-0001', 'CTR',  75, '2026-09-20'),
  ('EL-0001', 'EST',  12, '2026-09-16'), ('EL-0002', 'CTR',  40, '2026-09-17'),
  ('EL-0003', 'CTR',  33, '2026-09-17'), ('EL-0004', 'CTR',   7, '2026-09-08'),
  ('EL-0004', 'EST',   2, '2026-09-09'), ('EL-0005', 'CTR',   4, '2026-09-01'),
  ('EL-0006', 'CTR',  15, '2026-07-14'), ('CL-0001', 'CTR',  30, '2026-09-23'),
  ('CL-0001', 'WST',   8, '2026-09-20'), ('CL-0002', 'CTR',  48, '2026-09-23'),
  ('CL-0003', 'CTR',  90, '2026-09-24'), ('CL-0003', 'EST',  25, '2026-09-24'),
  ('CL-0004', 'CTR', 150, '2026-09-24'), ('PK-0001', 'CTR', 640, '2026-09-25'),
  ('PK-0001', 'EST', 280, '2026-09-25'), ('PK-0001', 'WST',  95, '2026-09-22'),
  ('PK-0002', 'CTR',  14, '2026-09-14'), ('PK-0003', 'CTR', 180, '2026-09-25'),
  ('PK-0003', 'WST',  44, '2026-09-19'), ('PK-0004', 'CTR',  21, '2026-09-13'),
  ('PK-0005', 'CTR',  12, '2026-09-05'), ('PK-0005', 'EST',   6, '2026-09-06');

INSERT INTO STOCK_MOVEMENT (MVDATE, MVTYPE, MVITEM, MVWHS, MVQTY, MVREF, MVUSER) VALUES
  ('2026-09-01', 'I', 'OF-0001', 'CTR',  400, 'PO-2026-0901',   'SYSLOAD'),
  ('2026-09-01', 'I', 'PK-0001', 'CTR',  800, 'PO-2026-0902',   'SYSLOAD'),
  ('2026-09-05', 'O', 'OF-0001', 'CTR',   30, 'DO-2026-0911',   'SYSLOAD'),
  ('2026-09-08', 'I', 'EL-0004', 'CTR',   10, 'PO-2026-0915',   'SYSLOAD'),
  ('2026-09-09', 'O', 'EL-0004', 'CTR',    3, 'DO-2026-0920',   'SYSLOAD'),
  ('2026-09-12', 'O', 'OF-0001', 'CTR',   25, 'DO-2026-0931',   'SYSLOAD'),
  ('2026-09-15', 'A', 'OF-0001', 'CTR',   -5, 'STOCK COUNT SEP', 'SYSLOAD'),
  ('2026-09-18', 'O', 'OF-0001', 'CTR',   20, 'DO-2026-0944',   'SYSLOAD'),
  ('2026-09-21', 'I', 'PK-0001', 'CTR',   40, 'PO-2026-0950',   'SYSLOAD'),
  ('2026-09-25', 'O', 'PK-0001', 'CTR',  200, 'DO-2026-0962',   'SYSLOAD');

INSERT INTO HOLIDAY_CALENDAR (HLDATE, HLDESC) VALUES
  ('2026-01-01', 'NEW YEAR'),
  ('2026-05-01', 'LABOUR DAY'),
  ('2026-08-17', 'INDEPENDENCE DAY'),
  ('2026-12-25', 'CHRISTMAS DAY'),
  ('2027-01-01', 'NEW YEAR');
