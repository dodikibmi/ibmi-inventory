# ILE COBOL (P6): SQL module + the RPG service program DATEUTIL in one program.
# *APOSTSQL: in the SQL statements 'Y' is a string. The COBOL default is
# *QUOTESQL, where SQL strings need quotation marks and 'Y' would be read as
# a name (SQL0206 Column Y not found).
INV850C.MODULE: private OPTION := *EVENTF *APOSTSQL
INV850C.MODULE: inv850c.sqlcblle
INV850C.PGM: INV850C.MODULE DATEUTIL.SRVPGM
