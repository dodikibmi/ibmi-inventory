# Service program DATEUTIL: NOMAIN module + binder source with two signatures
DATEUTIL.MODULE: dateutil.rpgle dateutilpr.rpgleinc
DATEUTIL.SRVPGM: dateutilb.bnd DATEUTIL.MODULE

# Binding directory used by the programs that call DATEUTIL
INVENTORY.BNDDIR: DATEUTIL.SRVPGM
	-system -q "CRTBNDDIR BNDDIR($(OBJLIB)/INVENTORY) TEXT('Warehouse inventory')"
	-system -q "RMVBNDDIRE BNDDIR($(OBJLIB)/INVENTORY) OBJ((*LIBL/DATEUTIL *SRVPGM))"
	system "ADDBNDDIRE BNDDIR($(OBJLIB)/INVENTORY) OBJ((*LIBL/DATEUTIL *SRVPGM))"

# Bound programs (CRTBNDRPG / CRTSQLRPGI from the stream file)
INV900R.PGM: inv900r.rpgle INV900D.FILE
INV110R.PGM: inv110r.rpgle INV110D.FILE
INV100R.PGM: inv100r.rpgle INV100D.FILE
INV200R.PGM: inv200r.rpgle INV200D.FILE INVENTORY.BNDDIR dateutilpr.rpgleinc
INV300R.PGM: inv300r.rpgle INV300D.FILE INVENTORY.BNDDIR dateutilpr.rpgleinc

%.PGM: private COMMIT := *NONE
INV400R.PGM: inv400r.sqlrpgle INV400P.FILE
INV500R.PGM: inv500r.sqlrpgle
INV600R.PGM: inv600r.sqlrpgle
INV700R.PGM: inv700r.sqlrpgle

# Integration (P4): data queue server, XML delivery note
INV810R.PGM: inv810r.sqlrpgle
INV830R.PGM: inv830r.sqlrpgle
