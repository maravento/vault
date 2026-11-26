-- ----------------------------------------------------------
-- MDB Tools - A library for reading MS Access database files
-- Copyright (C) 2000-2011 Brian Bruns and others.
-- Files in libmdb are licensed under LGPL and the utilities under
-- the GPL, see COPYING.LIB and COPYING files respectively.
-- Check out http://mdbtools.sourceforge.net
-- ----------------------------------------------------------

-- That file uses encoding UTF-8

CREATE TABLE `CAUDITORIA`
 (
	`Fecha`			varchar (10), 
	`Hora`			varchar (8), 
	`Usuario`			varchar (20), 
	`TipoAuditoria`			varchar (2), 
	`Detalle`			text
);

-- CREATE INDEXES ...

CREATE TABLE `CGRUPOS`
 (
	`Codigo`			varchar (5), 
	`Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `CGRUPOSXUSUARIO`
 (
	`CodGrupo`			varchar (5), 
	`CodUsuario`			varchar (20)
);

-- CREATE INDEXES ...

CREATE TABLE `CIDEAVERSION`
 (
	`sSistema`			varchar (20), 
	`sParam`			varchar (20), 
	`lValor`			int, 
	`bPublica`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `CIDEAVERSION` ADD PRIMARY KEY (`sSistema`);


-- CREATE INDEXES ...

CREATE TABLE `CPERMISOS`
 (
	`Codigo`			varchar (5), 
	`Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `CPERMISOSXMUDULO`
 (
	`CodigoPermiso`			varchar (5), 
	`CodigoModulo`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `CPERMISOSXMUDULO` ADD PRIMARY KEY (`CodigoPermiso`, `CodigoModulo`);

CREATE TABLE `CPERMXGRUPXMOD`
 (
	`CodPermiso`			varchar (5), 
	`CodGrupo`			varchar (5), 
	`CodModulo`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `CPERMXGRUPXMOD` ADD PRIMARY KEY (`CodPermiso`, `CodGrupo`, `CodModulo`);

CREATE TABLE `CRPTTEMCARTERA`
 (
	`Id`			varchar (50), 
	`Text1`			varchar (255), 
	`Text2`			varchar (255), 
	`Text3`			varchar (255), 
	`Text4`			varchar (255), 
	`Text5`			varchar (255), 
	`Text6`			varchar (255), 
	`Text7`			varchar (255), 
	`Text8`			varchar (255), 
	`Text9`			varchar (255), 
	`Text10`			varchar (255), 
	`Text11`			varchar (255), 
	`Text12`			varchar (255), 
	`Text13`			varchar (255), 
	`Text14`			varchar (255), 
	`Text15`			varchar (255), 
	`Text16`			varchar (255), 
	`Text17`			varchar (255), 
	`Text18`			varchar (255), 
	`Text19`			varchar (255), 
	`Text20`			varchar (255), 
	`Text21`			varchar (255), 
	`Text22`			varchar (255), 
	`Text23`			varchar (255), 
	`Text24`			varchar (255), 
	`Text25`			varchar (255), 
	`Text26`			varchar (255), 
	`Text27`			varchar (255), 
	`Text28`			varchar (255), 
	`Text29`			varchar (255), 
	`Text30`			varchar (255), 
	`Text31`			varchar (255), 
	`Text32`			varchar (255), 
	`Text33`			varchar (255), 
	`Text34`			varchar (255), 
	`Moneda1`			float, 
	`Moneda2`			float, 
	`Moneda3`			float, 
	`Moneda4`			float, 
	`Moneda5`			float, 
	`Moneda6`			float, 
	`Numero1`			int, 
	`Numero2`			int, 
	`Numero3`			int, 
	`Numero4`			int, 
	`Fecha1`			datetime, 
	`Fecha2`			datetime, 
	`Fecha3`			datetime, 
	`Fecha4`			datetime, 
	`Memo1`			varchar (255), 
	`Memo2`			varchar (255), 
	`Memo3`			varchar (255), 
	`Memo4`			varchar (255), 
	`Object1`			blob
);

-- CREATE INDEXES ...
ALTER TABLE `CRPTTEMCARTERA` ADD INDEX `Id` (`Id`);

CREATE TABLE `CRPTTEMFACTURA`
 (
	`Id`			varchar (50), 
	`Text1`			varchar (255), 
	`Text2`			varchar (255), 
	`Text3`			varchar (255), 
	`Text4`			varchar (255), 
	`Text5`			varchar (255), 
	`Text6`			varchar (255), 
	`Text7`			varchar (255), 
	`Text8`			varchar (255), 
	`Text9`			varchar (255), 
	`Text10`			varchar (255), 
	`Text11`			varchar (255), 
	`Text12`			varchar (255), 
	`Text13`			varchar (255), 
	`Text14`			varchar (255), 
	`Text15`			varchar (255), 
	`Text16`			varchar (255), 
	`Text17`			varchar (255), 
	`Text18`			varchar (255), 
	`Moneda1`			float, 
	`Moneda2`			float, 
	`Moneda3`			float, 
	`Moneda4`			float, 
	`Moneda5`			float, 
	`Moneda6`			float, 
	`Numero1`			int, 
	`Numero2`			int, 
	`Numero3`			int, 
	`Numero4`			int, 
	`Fecha1`			datetime, 
	`Fecha2`			datetime, 
	`Fecha3`			datetime, 
	`Fecha4`			datetime, 
	`Memo1`			text, 
	`Memo2`			text, 
	`Memo3`			text, 
	`Memo4`			text, 
	`Object1`			blob
);

-- CREATE INDEXES ...
ALTER TABLE `CRPTTEMFACTURA` ADD INDEX `Id` (`Id`);

CREATE TABLE `CRPTTEMFACTURACOMPLE`
 (
	`Id`			varchar (50), 
	`Text1`			varchar (255), 
	`Text2`			varchar (255), 
	`Text3`			varchar (255), 
	`Text4`			varchar (255), 
	`Text5`			varchar (255), 
	`Text6`			varchar (255), 
	`Text7`			varchar (255), 
	`Text8`			varchar (255), 
	`Text9`			varchar (255), 
	`Text10`			varchar (255), 
	`Text11`			varchar (255), 
	`Text12`			varchar (255), 
	`Text13`			varchar (255), 
	`Text14`			varchar (255), 
	`Text15`			varchar (255), 
	`Text16`			varchar (255), 
	`Text17`			varchar (255), 
	`Text18`			varchar (255), 
	`Moneda1`			float, 
	`Moneda2`			float, 
	`Moneda3`			float, 
	`Moneda4`			float, 
	`Moneda5`			float, 
	`Moneda6`			float, 
	`Numero1`			int, 
	`Numero2`			int, 
	`Numero3`			int, 
	`Numero4`			int, 
	`Fecha1`			datetime, 
	`Fecha2`			datetime, 
	`Fecha3`			datetime, 
	`Fecha4`			datetime, 
	`Memo1`			text, 
	`Memo2`			text, 
	`Memo3`			text, 
	`Memo4`			text, 
	`Object1`			blob, 
	`Text19`			varchar (255), 
	`Text20`			varchar (255), 
	`Text21`			varchar (255), 
	`Text22`			varchar (255), 
	`Text23`			varchar (255), 
	`Text24`			varchar (255), 
	`Text25`			varchar (255), 
	`Text26`			varchar (255), 
	`Text27`			varchar (255), 
	`Text28`			varchar (255), 
	`Text29`			varchar (255), 
	`Text30`			varchar (255), 
	`Text31`			varchar (255), 
	`Text32`			varchar (255), 
	`Text33`			varchar (255), 
	`Text34`			varchar (255), 
	`Text35`			varchar (255), 
	`Moneda7`			float, 
	`Moneda8`			float, 
	`Moneda9`			float, 
	`Moneda10`			float, 
	`Moneda11`			float, 
	`Moneda12`			float, 
	`Moneda13`			float, 
	`Moneda14`			float, 
	`Moneda15`			float, 
	`Moneda16`			float, 
	`Moneda17`			float, 
	`Moneda18`			float, 
	`Moneda19`			float, 
	`Moneda20`			float, 
	`Numero5`			int, 
	`Numero6`			int, 
	`Numero7`			int, 
	`Numero8`			int, 
	`Numero9`			int, 
	`Numero10`			int, 
	`Numero11`			int, 
	`Numero12`			int, 
	`Numero13`			int, 
	`Numero14`			int, 
	`Numero15`			int, 
	`Fecha5`			datetime, 
	`Fecha6`			datetime, 
	`Fecha7`			datetime, 
	`Fecha8`			datetime, 
	`Fecha9`			datetime, 
	`Fecha10`			datetime, 
	`Fecha11`			datetime, 
	`Fecha12`			datetime, 
	`Fecha13`			datetime, 
	`Fecha14`			datetime, 
	`Fecha15`			datetime, 
	`Memo5`			varchar (255), 
	`Memo6`			varchar (255), 
	`Memo7`			varchar (255), 
	`Memo8`			varchar (255), 
	`Memo9`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `CRPTTEMFACTURACOMPLE` ADD INDEX `Id` (`Id`);

CREATE TABLE `CTIPOAUDITORIA`
 (
	`Codigo`			varchar (2), 
	`Nombre`			varchar (50)
);

-- CREATE INDEXES ...

CREATE TABLE `CUSUARIO`
 (
	`CodUsuario`			varchar (20) NOT NULL, 
	`Contrasena`			varchar (20), 
	`Descripcion`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `CUSUARIO` ADD PRIMARY KEY (`CodUsuario`);


-- CREATE INDEXES ...

CREATE TABLE `municipalities`
 (
	`Id`			int, 
	`code`			varchar (5), 
	`name`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `municipalities` ADD PRIMARY KEY (`Id`);

CREATE TABLE `RPT_EXOGENA2012_DATOS`
 (
	`T106CodEmpresa`			varchar (100), 
	`T106Agno`			varchar (100), 
	`T106CodTipoDoc`			varchar (100), 
	`T106NumeroDoc`			varchar (100), 
	`T106CodCta`			varchar (100), 
	`T106Nit`			varchar (100), 
	`T106ValorDebito`			varchar (100), 
	`T106ValorCredito`			varchar (100), 
	`T142CodFormato`			varchar (100), 
	`T142CodGrupo`			varchar (100), 
	`T142Valor`			varchar (100), 
	`T142Informacion`			varchar (100), 
	`T54CuantiaMinima`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `RPT_EXOGENA2012_DATOS` ADD INDEX `T142Informacion` (`T142Informacion`);
ALTER TABLE `RPT_EXOGENA2012_DATOS` ADD INDEX `T142Valor` (`T142Valor`);

CREATE TABLE `T08ESTADOCIVIL`
 (
	`T08Codigo`			varchar (2), 
	`T08Nombre`			varchar (20)
);

-- CREATE INDEXES ...

CREATE TABLE `T09SEXO`
 (
	`T09Codigo`			varchar (5), 
	`T09Nombre`			varchar (50)
);

-- CREATE INDEXES ...

CREATE TABLE `T100CUENTA`
 (
	`T100CodEmpresa`			varchar (5), 
	`T100Agno`			varchar (4), 
	`T100CodCta`			varchar (20), 
	`T100CodAlterno`			varchar (20), 
	`T100Naturaleza`			varchar (1), 
	`T100Nombre`			varchar (255), 
	`T100Movimiento`			varchar (1), 
	`T100CentroCosto`			varchar (1), 
	`T100Tercero`			varchar (1), 
	`T100CodTipoMoneda`			varchar (5), 
	`T100CodCtaAjuMoneda`			varchar (20), 
	`T100Observacion`			varchar (255), 
	`T100CodCtaAjuCruce`			varchar (20), 
	`T100CodCtaAjuAplic`			varchar (20), 
	`T100Nivel`			varchar (2), 
	`T100CodTributaria`			varchar (5), 
	`T100Nit`			varchar (20), 
	`T100Presupuesto`			varchar (20), 
	`T100PorcRetencion`			varchar (15), 
	`T100NombreNIIF`			varchar (250), 
	`T100CodigoNIIF`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T100CUENTA` ADD PRIMARY KEY (`T100CodEmpresa`, `T100Agno`, `T100CodCta`);
ALTER TABLE `T100CUENTA` ADD INDEX `T100CodCta` (`T100CodCta`);
ALTER TABLE `T100CUENTA` ADD INDEX `T100Movimiento` (`T100Movimiento`);

CREATE TABLE `T100CUENTANIIF`
 (
	`T100CodEmpresa`			varchar (5), 
	`T100Agno`			varchar (4), 
	`T100CodCta`			varchar (20), 
	`T100CodAlterno`			varchar (20), 
	`T100Naturaleza`			varchar (1), 
	`T100Nombre`			varchar (255), 
	`T100Movimiento`			varchar (1), 
	`T100CentroCosto`			varchar (1), 
	`T100Tercero`			varchar (1), 
	`T100CodTipoMoneda`			varchar (5), 
	`T100CodCtaAjuMoneda`			varchar (20), 
	`T100Observacion`			varchar (255), 
	`T100CodCtaAjuCruce`			varchar (20), 
	`T100CodCtaAjuAplic`			varchar (20), 
	`T100Nivel`			varchar (2), 
	`T100CodTributaria`			varchar (5), 
	`T100Nit`			varchar (20), 
	`T100Presupuesto`			varchar (20), 
	`T100PorcRetencion`			varchar (15), 
	`T100NombreNIIF`			varchar (250), 
	`T100CodigoNIIF`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T100CUENTANIIF` ADD PRIMARY KEY (`T100CodEmpresa`, `T100Agno`, `T100CodCta`);

CREATE TABLE `T102CUENTAGRUPOCUENTA`
 (
	`T102CodEmpresa`			varchar (5), 
	`T102Agno`			varchar (4), 
	`T102CodCta`			varchar (20), 
	`T102CodGrupoCta`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T102CUENTAGRUPOCUENTA` ADD PRIMARY KEY (`T102CodEmpresa`, `T102Agno`, `T102CodCta`, `T102CodGrupoCta`);

CREATE TABLE `T102CUENTAGRUPOCUENTANIIF`
 (
	`T102CodEmpresa`			varchar (5), 
	`T102Agno`			varchar (4), 
	`T102CodCta`			varchar (20), 
	`T102CodGrupoCta`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T102CUENTAGRUPOCUENTANIIF` ADD PRIMARY KEY (`T102CodEmpresa`, `T102Agno`, `T102CodCta`, `T102CodGrupoCta`);

CREATE TABLE `T104DOCUMENTO`
 (
	`T104CodEmpresa`			varchar (5), 
	`T104Agno`			varchar (4), 
	`T104CodTipoDoc`			varchar (5), 
	`T104NumeroDoc`			varchar (15), 
	`T104Fecha`			varchar (10), 
	`T104Concepto`			varchar (255), 
	`T104Anulado`			varchar (100), 
	`T104Aplicacion`			varchar (10), 
	`T104ValorTotal`			varchar (20), 
	`T104NombreCheque`			varchar (255), 
	`NumeroAnterior`			varchar (255), 
	`NuevoNumero`			varchar (255), 
	`T104Bloqueado`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T104DOCUMENTO` ADD PRIMARY KEY (`T104CodEmpresa`, `T104Agno`, `T104CodTipoDoc`, `T104NumeroDoc`);
ALTER TABLE `T104DOCUMENTO` ADD INDEX `T104Anulado` (`T104Anulado`);

CREATE TABLE `T104DOCUMENTONIIF`
 (
	`T104CodEmpresa`			varchar (5), 
	`T104Agno`			varchar (4), 
	`T104CodTipoDoc`			varchar (5), 
	`T104NumeroDoc`			varchar (15), 
	`T104Fecha`			varchar (10), 
	`T104Concepto`			varchar (255), 
	`T104Anulado`			varchar (100), 
	`T104Aplicacion`			varchar (10), 
	`T104ValorTotal`			varchar (20), 
	`T104NombreCheque`			varchar (255), 
	`NumeroAnterior`			varchar (255), 
	`NuevoNumero`			varchar (255), 
	`T104Bloqueado`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T104DOCUMENTONIIF` ADD PRIMARY KEY (`T104CodEmpresa`, `T104Agno`, `T104CodTipoDoc`, `T104NumeroDoc`);

CREATE TABLE `T106MOVIMIENTONIIF`
 (
	`T106CodEmpresa`			varchar (5), 
	`T106Agno`			varchar (4), 
	`T106CodTipoDoc`			varchar (5), 
	`T106NumeroDoc`			varchar (15), 
	`T106CodCta`			varchar (20), 
	`T106ConsecCta`			varchar (5), 
	`T106Fecha`			varchar (10), 
	`T106CodCentro`			varchar (6), 
	`T106Nit`			varchar (15), 
	`T106Referencia`			varchar (10), 
	`T106Detalle`			varchar (100), 
	`T106ValorDebito`			varchar (15), 
	`T106ValorCredito`			varchar (15), 
	`T106CodSubTipoDoc`			varchar (10), 
	`T106SubNumeroDoc`			varchar (10), 
	`T106FechaConciliado`			varchar (10), 
	`Anterior`			varchar (255), 
	`Nuevo`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T106MOVIMIENTONIIF` ADD PRIMARY KEY (`T106CodEmpresa`, `T106Agno`, `T106CodTipoDoc`, `T106NumeroDoc`, `T106CodCta`, `T106ConsecCta`);

CREATE TABLE `T106MOVREPORTE`
 (
	`CodEmpresa`			varchar (20) NOT NULL, 
	`NombrePC`			varchar (50) NOT NULL, 
	`Id`			varchar (20) NOT NULL, 
	`Consec`			int, 
	`FechaIni`			varchar (10), 
	`FechaFin`			varchar (10), 
	`Cta`			varchar (20), 
	`NomCta`			varchar (255), 
	`Naturaleza`			varchar (5), 
	`TipoDoc`			varchar (10), 
	`NumeroDoc`			varchar (20), 
	`Detalle`			varchar (255), 
	`Tercero`			varchar (255), 
	`Nit`			varchar (20), 
	`CodCentroCosto`			varchar (20), 
	`Debito`			varchar (20), 
	`Credito`			varchar (20), 
	`Fecha`			varchar (10), 
	`DetalleMov`			varchar (255), 
	`ChequeFact`			varchar (20), 
	`NomCentroCosto`			varchar (255), 
	`SaldoInicial`			varchar (20), 
	`SaldoFinal`			varchar (20), 
	`PorcRete`			varchar (10), 
	`Plazo`			varchar (20), 
	`CodAlterno`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T106MOVREPORTE` ADD INDEX `Id` (`Id`);

CREATE TABLE `T106MOVREPORTESALDOINI`
 (
	`CodEmpresa`			varchar (20) NOT NULL, 
	`NombrePC`			varchar (50) NOT NULL, 
	`Id`			varchar (20) NOT NULL, 
	`CodCta`			varchar (20), 
	`CodTercero`			varchar (20), 
	`SaldoIni`			varchar (20), 
	`Existe`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T106MOVREPORTESALDOINI` ADD INDEX `Id` (`Id`);

CREATE TABLE `T106MOVREPORTESALDOINIR`
 (
	`CodEmpresa`			varchar (20) NOT NULL, 
	`NombrePC`			varchar (50) NOT NULL, 
	`Id`			varchar (20) NOT NULL, 
	`CodCta`			varchar (20), 
	`SaldoIni`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T106MOVREPORTESALDOINIR` ADD INDEX `Id` (`Id`);

CREATE TABLE `T107TOTALCUENTA`
 (
	`T107CodEmpresa`			varchar (5), 
	`T107Agno`			varchar (4), 
	`T107CodCta`			varchar (20), 
	`T107Mes`			varchar (2), 
	`T107MovDebito`			varchar (20), 
	`T107MovCredito`			varchar (20), 
	`T107CentroCosto`			varchar (6)
);

-- CREATE INDEXES ...

CREATE TABLE `T107TOTALCUENTANIIF`
 (
	`T107CodEmpresa`			varchar (5), 
	`T107Agno`			varchar (4), 
	`T107CodCta`			varchar (20), 
	`T107Mes`			varchar (2), 
	`T107MovDebito`			varchar (20), 
	`T107MovCredito`			varchar (20), 
	`T107CentroCosto`			varchar (6)
);

-- CREATE INDEXES ...
ALTER TABLE `T107TOTALCUENTANIIF` ADD PRIMARY KEY (`T107CodEmpresa`, `T107Agno`, `T107CodCta`, `T107Mes`, `T107CentroCosto`);

CREATE TABLE `T10EMPRESA`
 (
	`T10CodEmpresa`			varchar (5), 
	`T10CodTipoEmpresa`			varchar (5), 
	`T10Nit`			varchar (20), 
	`T10Nombre`			varchar (100), 
	`T10Sigla`			varchar (20), 
	`T10Direccion`			varchar (100), 
	`T10Telefono`			varchar (30), 
	`T10Fax`			varchar (30), 
	`T10EMail`			varchar (50), 
	`T10WebSite`			varchar (50), 
	`T10Observacion`			varchar (255), 
	`T10Logotipo`			varchar (100), 
	`T10TipoPersona`			varchar (5), 
	`T10TipoRegimen`			varchar (5), 
	`T10FacturaNegativo`			varchar (5), 
	`T10DocumentoDesbalance`			varchar (5), 
	`T10ComisionCredito`			varchar (15), 
	`T10ComisionContado`			varchar (15), 
	`T10ComisionRecaudo`			varchar (15), 
	`T10ValidarCupo`			varchar (5), 
	`T10ContabilidadBloque`			varchar (5), 
	`T10ManejaRegistradora`			varchar (5), 
	`T10ValidarCosto`			varchar (5), 
	`T10BaseInteres`			varchar (20), 
	`T10TemporalRPT`			varchar (20), 
	`T10ValidarTiempo`			varchar (5), 
	`T10ContabilidadAbono`			varchar (5), 
	`T10NomRepresentante`			varchar (100), 
	`T10IdeRepresentante`			varchar (100), 
	`T10NomContador`			varchar (100), 
	`T10IdeContador`			varchar (100), 
	`T10NomRevisor`			varchar (100), 
	`T10IdeRevisor`			varchar (100), 
	`T10NomTesorero`			varchar (100), 
	`T10IdeTesorero`			varchar (100), 
	`T10ManejaPaquetes`			varchar (1), 
	`T10EnviarDatosAFact`			varchar (1), 
	`T10Resolucion`			varchar (255), 
	`T10ObservacionFact1`			varchar (255), 
	`T10ObservacionFact2`			varchar (255), 
	`T10TipoFactAIU`			varchar (5), 
	`T10ClaveTecnica`			varchar (100), 
	`T10CodDpto`			varchar (2), 
	`T10CodCiudad`			varchar (3), 
	`T10Licencia`			varchar (200), 
	`T10LicenciaFact`			varchar (200), 
	`T10ClaveTecnicaF`			varchar (100), 
	`T10BaseFactElect`			varchar (20), 
	`T10FechaCertif`			varchar (10), 
	`T10Token`			varchar (200), 
	`T10POS`			varchar (200), 
	`T10NCPOS`			varchar (200), 
	`T10NDPOS`			varchar (200), 
	`T10BaseRete`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T10EMPRESA` ADD PRIMARY KEY (`T10CodEmpresa`, `T10CodTipoEmpresa`, `T10Nit`);

CREATE TABLE `T110PLAN`
 (
	`T110Codigo`			varchar (5), 
	`T110Nombre`			varchar (50)
);

-- CREATE INDEXES ...

CREATE TABLE `T112INDICESAJUSTE`
 (
	`T112Agno`			varchar (4), 
	`T112Mes`			varchar (2), 
	`T112Valor`			varchar (10)
);

-- CREATE INDEXES ...

CREATE TABLE `T113TASASCAMBIO`
 (
	`T113CodTipoMoneda`			varchar (5), 
	`T113Agno`			varchar (4), 
	`T113Mes`			varchar (2), 
	`T113Valor`			varchar (10)
);

-- CREATE INDEXES ...

CREATE TABLE `T114CONCILIACION`
 (
	`T106CodEmpresa`			varchar (5), 
	`T106Agno`			varchar (4), 
	`T106CodTipoDoc`			varchar (5), 
	`T106NumeroDoc`			varchar (5), 
	`T106CodCta`			varchar (20), 
	`T106ConsecCta`			varchar (5), 
	`T106Fecha`			varchar (10), 
	`T106CodCentro`			varchar (6), 
	`T106Nit`			varchar (15), 
	`T106Referencia`			varchar (10), 
	`T106Detalle`			varchar (100), 
	`T106ValorDebito`			varchar (10), 
	`T106ValorCredito`			varchar (10)
);

-- CREATE INDEXES ...

CREATE TABLE `T115CONCILIACIONBANCARIA`
 (
	`T115CodEmpresa`			varchar (5), 
	`T115Agno`			varchar (4), 
	`T115CodCuenta`			varchar (20), 
	`T115Numero`			varchar (3), 
	`T115Fecha`			varchar (10), 
	`T115CodConceptoConcilia`			varchar (5), 
	`T115Detalle`			varchar (100), 
	`T115Debito`			varchar (15), 
	`T115Credito`			varchar (15), 
	`T115Saldo`			varchar (15)
);

-- CREATE INDEXES ...

CREATE TABLE `T116PARAMETROSTRABAJO`
 (
	`T116CodEmpresa`			varchar (5), 
	`T116Agno`			varchar (4)
);

-- CREATE INDEXES ...

CREATE TABLE `T117CONFIGURACION`
 (
	`T117CodEmrpesa`			varchar (5), 
	`T117Agno`			varchar (4), 
	`T117EstrucPlanCuenta`			varchar (100), 
	`T117EstrucCentroCosto`			varchar (100), 
	`T117EstrucPlanCuentaIng`			varchar (255), 
	`T117EstrucPlanCuentaGast`			varchar (255)
);

-- CREATE INDEXES ...

CREATE TABLE `T118MESBLOQUEADO`
 (
	`T118CodEmpresa`			varchar (5), 
	`T118Agno`			varchar (4), 
	`T118Mes`			varchar (5)
);

-- CREATE INDEXES ...

CREATE TABLE `T11TIPOEMPRESA`
 (
	`T11Codigo`			varchar (5), 
	`T11Nombre`			varchar (50)
);

-- CREATE INDEXES ...

CREATE TABLE `T120FACTURADETALLE`
 (
	`T120CodEmpresa`			varchar (5), 
	`T120NumFactura`			varchar (5), 
	`T120Consecutivo`			varchar (5), 
	`T120Cantidad`			varchar (10), 
	`T120Articulo`			varchar (5), 
	`T120Detalle`			varchar (255), 
	`T120ValorUnitario`			varchar (15)
);

-- CREATE INDEXES ...

CREATE TABLE `T121DEPRECIACION`
 (
	`T121CodEmpresa`			varchar (255), 
	`T121Agno`			varchar (255), 
	`T121CodCta`			varchar (255), 
	`T121CodCtaCruce`			varchar (255), 
	`T121CodCtaAplication`			varchar (255), 
	`T121Fecha`			varchar (255), 
	`T121VidaUtil`			varchar (255), 
	`T121CodCentro`			varchar (20)
);

-- CREATE INDEXES ...

CREATE TABLE `T121DEPRECIACIONNIIF`
 (
	`T121CodEmpresa`			varchar (255), 
	`T121Agno`			varchar (255), 
	`T121CodCta`			varchar (255), 
	`T121CodCtaCruce`			varchar (255), 
	`T121CodCtaAplication`			varchar (255), 
	`T121Fecha`			varchar (255), 
	`T121VidaUtil`			varchar (255), 
	`T121CodCentro`			varchar (20)
);

-- CREATE INDEXES ...

CREATE TABLE `T122CPTOCONTAB`
 (
	`T122CodEmpresa`			varchar (5), 
	`T122Agno`			varchar (4), 
	`T122CodTipoDoc`			varchar (5), 
	`T122CodConcepto`			varchar (5), 
	`T122Consecutivo`			varchar (3), 
	`T122CuentaCruce`			varchar (1), 
	`T122CodCta`			varchar (255), 
	`T122CodCentro`			varchar (255), 
	`T122Nit`			varchar (255), 
	`T122Detalle`			varchar (255), 
	`T122ValorDebito`			varchar (255), 
	`T122ValorCredito`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T122CPTOCONTAB` ADD PRIMARY KEY (`T122CodEmpresa`, `T122Agno`, `T122CodTipoDoc`, `T122CodConcepto`, `T122Consecutivo`);

CREATE TABLE `T123CONCEPTO`
 (
	`T123CodEmpresa`			varchar (5), 
	`T123Agno`			varchar (4), 
	`T123Codigo`			varchar (5), 
	`T123Nombre`			varchar (50), 
	`T123Causacion`			varchar (1), 
	`T123Recaudo`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T123CONCEPTO` ADD PRIMARY KEY (`T123CodEmpresa`, `T123Agno`, `T123Codigo`);

CREATE TABLE `T125CAUSACION`
 (
	`T125CodEmpresa`			varchar (5), 
	`T125Agno`			varchar (4), 
	`T125Numero`			varchar (10), 
	`T125Nit`			varchar (15), 
	`T125Observacion`			varchar (255), 
	`T125Fecha`			varchar (10), 
	`T125Valor`			varchar (15), 
	`T125Prefijo`			varchar (5), 
	`T125PorcIva`			varchar (5), 
	`T125IVA`			varchar (15), 
	`T125ValorNeto`			varchar (15), 
	`T125IvaDescontable`			varchar (1), 
	`T125ReteIVARegSimpl`			varchar (1), 
	`T125TipoCausacion`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T125CAUSACION` ADD PRIMARY KEY (`T125CodEmpresa`, `T125Agno`, `T125Numero`, `T125Prefijo`, `T125TipoCausacion`);

CREATE TABLE `T126CAUSACIONCONCEPTO`
 (
	`T126CodEmpresa`			varchar (5), 
	`T126Agno`			varchar (4), 
	`T126Numero`			varchar (10), 
	`T126CodCpto`			varchar (5), 
	`T126Valor`			varchar (15), 
	`T126Prefijo`			varchar (5), 
	`T126ValorDescuento`			varchar (15), 
	`T126TipoCausacion`			varchar (5), 
	`T126CodCentro`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T126CAUSACIONCONCEPTO` ADD PRIMARY KEY (`T126CodEmpresa`, `T126Agno`, `T126Numero`, `T126CodCpto`, `T126Prefijo`, `T126TipoCausacion`);

CREATE TABLE `T127CAUSACIONDESCUENTO`
 (
	`T127CodEmpresa`			varchar (5), 
	`T127Agno`			varchar (4), 
	`T127Numero`			varchar (10), 
	`T127CodDescuento`			varchar (5), 
	`T127Valor`			varchar (15), 
	`T127Prefijo`			varchar (5), 
	`T127TipoCausacion`			varchar (5), 
	`T127ValorAsumido`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T127CAUSACIONDESCUENTO` ADD PRIMARY KEY (`T127CodEmpresa`, `T127Agno`, `T127Numero`, `T127CodDescuento`, `T127Prefijo`, `T127TipoCausacion`);

CREATE TABLE `T128PARAMETRIZACION`
 (
	`T128CodEmpresa`			varchar (5), 
	`T128Agno`			varchar (4), 
	`T128CodGrupo`			varchar (5), 
	`T128CodTipo`			varchar (5), 
	`T128CodConcepto`			varchar (5), 
	`T128SubCodConcepto`			varchar (5), 
	`T128Consecutivo`			varchar (3), 
	`T128CodCta`			varchar (255), 
	`T128CodCentro`			varchar (255), 
	`T128Nit`			varchar (255), 
	`T128Detalle`			varchar (255), 
	`T128ValorDebito`			varchar (255), 
	`T128ValorCredito`			varchar (255), 
	`T128NomCta`			varchar (255), 
	`T128NomCentro`			varchar (255), 
	`T128NomNit`			varchar (255), 
	`T128CruceDescuento`			varchar (1), 
	`T128CruceIVA`			varchar (1), 
	`T137Reporte`			varchar (255), 
	`T137Ugpp`			varchar (255), 
	`T137Planilla`			varchar (255), 
	`T137CertIngresos`			varchar (255), 
	`T137NominaElec`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T128PARAMETRIZACION` ADD PRIMARY KEY (`T128CodEmpresa`, `T128Agno`, `T128CodGrupo`, `T128CodTipo`, `T128CodConcepto`, `T128SubCodConcepto`, `T128Consecutivo`);

CREATE TABLE `T129PAGO`
 (
	`T129CodEmpresa`			varchar (5), 
	`T129Agno`			varchar (4), 
	`T129Numero`			varchar (10), 
	`T129Nit`			varchar (15), 
	`T129Observacion`			varchar (255), 
	`T129Fecha`			varchar (10), 
	`T129Valor`			varchar (15), 
	`T129ValorDescuento`			varchar (15), 
	`T129ValorNeto`			varchar (15), 
	`T129CuentaBanco`			varchar (20), 
	`T129Prefijo`			varchar (5), 
	`T129Digita`			varchar (20), 
	`T129TipoDoc`			varchar (5), 
	`T129Anulado`			varchar (5), 
	`T129Impresa`			varchar (1), 
	`T129Hora`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T129PAGO` ADD PRIMARY KEY (`T129CodEmpresa`, `T129Agno`, `T129Numero`, `T129TipoDoc`);

CREATE TABLE `T12TERCERO`
 (
	`T12CodEmpresa`			varchar (5), 
	`T12Nit`			varchar (20), 
	`T12LibretaMil`			varchar (20), 
	`T12MatriProf`			varchar (20), 
	`T12Nombre`			varchar (50), 
	`T12Apellido`			varchar (50), 
	`T12CodDpto`			varchar (2), 
	`T12CodCiudad`			varchar (3), 
	`T12Direccion`			varchar (100), 
	`T12Telefono`			varchar (30), 
	`T12Sexo`			varchar (5), 
	`T12Fax`			varchar (30), 
	`T12EMail`			varchar (50), 
	`T12WebSite`			varchar (50), 
	`T12CodTipoSociedad`			varchar (5), 
	`T12FechaIngreso`			varchar (10), 
	`T12CodCalifica`			varchar (5), 
	`T12Observacion`			varchar (255), 
	`T12Nombre2`			varchar (20), 
	`T12Apellido2`			varchar (20), 
	`T12RazonSocial`			varchar (80), 
	`T12Dv`			varchar (1), 
	`T12TipoPersona`			varchar (5), 
	`T12TipoRegimen`			varchar (5), 
	`T12CodAlterno`			varchar (15), 
	`T12Cupo`			varchar (20), 
	`T12FormaPago`			varchar (5), 
	`T12ListaValor`			varchar (5), 
	`T12Saldo`			varchar (15), 
	`T12DiasDeuda`			varchar (15), 
	`T12Vendedor`			varchar (5), 
	`T12TipoDoc`			varchar (5), 
	`T12Profesion`			varchar (5), 
	`T12Empresa`			varchar (20), 
	`T12CupoFacturas`			varchar (3), 
	`T12ImgHuella`			varchar (255), 
	`T12Viuda`			varchar (1), 
	`T12De`			varchar (1), 
	`T12NombreDe`			varchar (30), 
	`T12Extencion`			varchar (5), 
	`T12Indicador`			varchar (5), 
	`T12Telefono2`			varchar (30), 
	`T12Celular1`			varchar (30), 
	`T12Celular2`			varchar (30), 
	`T12FechaNace`			varchar (10), 
	`T12Cobrador`			varchar (20), 
	`T12Referido`			varchar (20), 
	`T12ActEconomica`			varchar (20), 
	`T12PorcActEconomica`			varchar (10), 
	`T12ReteCompras`			varchar (5), 
	`T12ReteVentas`			varchar (5), 
	`T12ReteIVAComp`			varchar (5), 
	`T12ReteICAComp`			varchar (5), 
	`T12ReteIVAVenta`			varchar (5), 
	`T12ReteICAVenta`			varchar (5), 
	`T12Tributo`			varchar (5), 
	`T12Obligacion1`			varchar (20), 
	`T12Obligacion2`			varchar (20), 
	`T12Pais`			varchar (10), 
	`T12CodPostal`			varchar (10)
);

-- CREATE INDEXES ...
ALTER TABLE `T12TERCERO` ADD PRIMARY KEY (`T12CodEmpresa`, `T12Nit`);

CREATE TABLE `T131PAGOCONCEPTO`
 (
	`T131CodEmpresa`			varchar (5), 
	`T131Agno`			varchar (4), 
	`T131Numero`			varchar (10), 
	`T131AgnoCausacion`			varchar (4), 
	`T131NumCausacion`			varchar (10), 
	`T131CodCpto`			varchar (5), 
	`T131Valor`			varchar (15), 
	`T131Prefijo`			varchar (5), 
	`T131ValorDescuento`			varchar (15), 
	`T131TipoDoc`			varchar (20), 
	`T131CodCentro`			varchar (20), 
	`T131Nit`			varchar (20), 
	`T131Cheque`			varchar (10), 
	`T131Plazo`			varchar (5), 
	`T131Observacion`			varchar (255), 
	`T131PrefijoCausa`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T131PAGOCONCEPTO` ADD PRIMARY KEY (`T131CodEmpresa`, `T131Agno`, `T131Numero`, `T131Prefijo`, `T131AgnoCausacion`, `T131NumCausacion`, `T131CodCpto`, `T131TipoDoc`, `T131Nit`, `T131CodCentro`);

CREATE TABLE `T132RECAUDO`
 (
	`T132CodEmpresa`			varchar (5), 
	`T132Agno`			varchar (4), 
	`T132Prefijo`			varchar (5), 
	`T132Numero`			varchar (10), 
	`T132Nit`			varchar (15), 
	`T132Observacion`			varchar (255), 
	`T132Fecha`			varchar (10), 
	`T132Valor`			varchar (15), 
	`T132CuentaBanco`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T132RECAUDO` ADD PRIMARY KEY (`T132CodEmpresa`, `T132Agno`, `T132Prefijo`, `T132Numero`);

CREATE TABLE `T133RECAUDOCONCEPTO`
 (
	`T133CodEmpresa`			varchar (5), 
	`T133Agno`			varchar (4), 
	`T133Prefijo`			varchar (5), 
	`T133Numero`			varchar (10), 
	`T133CodCpto`			varchar (5), 
	`T133Valor`			varchar (15)
);

-- CREATE INDEXES ...
ALTER TABLE `T133RECAUDOCONCEPTO` ADD PRIMARY KEY (`T133CodEmpresa`, `T133Agno`, `T133Prefijo`, `T133Numero`, `T133CodCpto`);

CREATE TABLE `T134CARGO`
 (
	`T134Codigo`			varchar (5), 
	`T134Nombre`			varchar (50), 
	`T134Valor`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T134CARGO` ADD PRIMARY KEY (`T134Codigo`);

CREATE TABLE `T135AREA`
 (
	`T135Codigo`			varchar (5), 
	`T135Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T135AREA` ADD PRIMARY KEY (`T135Codigo`);

CREATE TABLE `T136HOJAVIDA`
 (
	`T136CodEmpresa`			varchar (5), 
	`T136Nit`			varchar (20), 
	`T136AsignaBasica`			varchar (15), 
	`T136FechaAfiliaEPS`			varchar (10), 
	`T136NitEPS`			varchar (15), 
	`T136FechaAfiliaARS`			varchar (10), 
	`T136NitARS`			varchar (15), 
	`T136FechaAfiliaPENSION`			varchar (10), 
	`T136NitPENSION`			varchar (15), 
	`T136CodCargo`			varchar (5), 
	`T136CodArea`			varchar (5), 
	`T136Activo`			varchar (1), 
	`T136FechaIngreso`			varchar (10), 
	`T136Foto`			varchar (255), 
	`T136SubConcepto`			varchar (20), 
	`T136NivelRiesgo`			varchar (10), 
	`T136Funerario`			varchar (20), 
	`T136Seguro`			varchar (20), 
	`T136Sena`			varchar (20), 
	`T136Icbf`			varchar (20), 
	`T136CajaCompensa`			varchar (20), 
	`T136PorcFunerario`			varchar (20), 
	`T136PorcNitEPS`			varchar (20), 
	`T136PorcNitARS`			varchar (20), 
	`T136PorcNitPENSION`			varchar (20), 
	`T136PorcSeguro`			varchar (20), 
	`T136PorcSena`			varchar (20), 
	`T136PorcIcbf`			varchar (20), 
	`T136PorcCajaCompensa`			varchar (20), 
	`T136PorcESAP`			varchar (20), 
	`T136NitESAP`			varchar (20), 
	`T136PorcMINEDUC`			varchar (20), 
	`T136NitMINEDUC`			varchar (20), 
	`T136ValorAdmon`			varchar (20), 
	`T136ValorAfiliacion`			varchar (20), 
	`T136NitCaja`			varchar (20), 
	`T136TipoVincula`			varchar (5), 
	`T136TipoCondicion`			varchar (5), 
	`T136EstadoCivil`			varchar (5), 
	`T136FechaRetiro`			varchar (10), 
	`T136Banco`			varchar (20), 
	`T136Cuenta`			varchar (50), 
	`T136TipoCuenta`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T136HOJAVIDA` ADD PRIMARY KEY (`T136CodEmpresa`, `T136Nit`);

CREATE TABLE `T137CONCEPTONOMINA FF`
 (
	`T137CodEmpresa`			varchar (5), 
	`T137Codigo`			varchar (5), 
	`T137Nombre`			varchar (50), 
	`T137Tipo`			varchar (1), 
	`T137Valor`			varchar (15), 
	`T137Formula`			varchar (200), 
	`T137Devengado`			varchar (1), 
	`T137Deducido`			varchar (1), 
	`T137NitBeneficiario`			varchar (15), 
	`T137LiquidaPeriodico`			varchar (1), 
	`T137Otro`			varchar (1), 
	`T137Imprimir`			varchar (1), 
	`T137LiquidaNavidad`			varchar (2), 
	`T137LiquidaVacaciones`			varchar (2), 
	`T137LiquidaDefinitiva`			varchar (2), 
	`T137LiquidaServicios`			varchar (2), 
	`T137DiaLiquidacion`			varchar (2), 
	`T137UnicaFecha`			varchar (10), 
	`T137Reporte`			varchar (10), 
	`T137Ugpp`			varchar (2), 
	`T137Planilla`			varchar (2), 
	`T137CertIngresos`			varchar (2), 
	`T137NominaElec`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T137CONCEPTONOMINA FF` ADD PRIMARY KEY (`T137CodEmpresa`, `T137Codigo`);

CREATE TABLE `T138PERIODO`
 (
	`T138CodEmpresa`			varchar (5), 
	`T138Codigo`			varchar (5), 
	`T138Nombre`			varchar (50), 
	`T138FechaIni`			varchar (10), 
	`T138FechaFin`			varchar (10), 
	`T138LiquidaPeriodico`			varchar (1), 
	`T138LiquidaNavidad`			varchar (1), 
	`T138LiquidaServicios`			varchar (1), 
	`T138LiquidaVacaciones`			varchar (1), 
	`T138LiquidaDefinitiva`			varchar (1), 
	`T138Bloqueado`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T138PERIODO` ADD PRIMARY KEY (`T138CodEmpresa`, `T138Codigo`);

CREATE TABLE `T139NOVEDAD`
 (
	`T139CodEmpresa`			varchar (5), 
	`T139Nit`			varchar (15), 
	`T139CodPeriodo`			varchar (5), 
	`T139CodConcepto`			varchar (5), 
	`T139Valor`			varchar (15), 
	`T139Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T139NOVEDAD` ADD PRIMARY KEY (`T139CodEmpresa`, `T139Nit`, `T139CodPeriodo`, `T139CodConcepto`);

CREATE TABLE `T13TERCEROPORTIPO`
 (
	`T13CodEmpresa`			varchar (5), 
	`T13Nit`			varchar (20), 
	`T13CodTipoTer`			varchar (5)
);

-- CREATE INDEXES ...

CREATE TABLE `T140LIQUIDACION`
 (
	`T140CodEmpresa`			varchar (5) NOT NULL, 
	`T140Nit`			varchar (15) NOT NULL, 
	`T140CodPeriodo`			varchar (5) NOT NULL, 
	`T140CodConcepto`			varchar (5) NOT NULL, 
	`T140ValorDevengado`			varchar (15), 
	`T140ValorDeducido`			varchar (15), 
	`T140NitBeneficiario`			varchar (15), 
	`T140ValorOtro`			varchar (15), 
	`T140Observacion`			varchar (255), 
	`T140Consecutivo`			varchar (20), 
	`T140CUFE`			varchar (255), 
	`T140CufePdf`			varchar (255), 
	`T140FechaEmite`			varchar (10), 
	`T140ConsecAnterior`			varchar (20), 
	`T140DetalleEnvio`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T140LIQUIDACION` ADD PRIMARY KEY (`T140CodEmpresa`, `T140Nit`, `T140CodPeriodo`, `T140CodConcepto`);

CREATE TABLE `T140RPTLIQNOMINA`
 (
	`T140CodEmpresa`			varchar (5), 
	`T140Nit`			varchar (15), 
	`T140CodPeriodo`			varchar (5), 
	`T140CodConcepto`			varchar (5), 
	`T140ValorDevengado`			varchar (15), 
	`T140ValorDeducido`			varchar (15), 
	`T140NitBeneficiario`			varchar (15), 
	`T140ValorOtro`			varchar (15), 
	`T140Observacion`			varchar (255), 
	`T140CUFE`			varchar (255)
);

-- CREATE INDEXES ...

CREATE TABLE `T141RECAUDOCAUSACION`
 (
	`T141CodEmpresa`			varchar (5), 
	`T141Agno`			varchar (4), 
	`T141Numero`			varchar (10), 
	`T141AgnoCausacion`			varchar (15), 
	`T141NumCausacion`			varchar (10), 
	`T141Prefijo`			varchar (5), 
	`T141ValorDescuento`			varchar (15)
);

-- CREATE INDEXES ...
ALTER TABLE `T141RECAUDOCAUSACION` ADD PRIMARY KEY (`T141CodEmpresa`, `T141Agno`, `T141Numero`, `T141AgnoCausacion`, `T141NumCausacion`, `T141Prefijo`);

CREATE TABLE `T142CTAEXOGENA`
 (
	`T142CodEmpresa`			varchar (5), 
	`T142Agno`			varchar (4), 
	`T142CodCta`			varchar (20), 
	`T142CodFormato`			varchar (5), 
	`T142CodGrupo`			varchar (5), 
	`T142Valor`			varchar (255), 
	`T142Informacion`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T142CTAEXOGENA` ADD PRIMARY KEY (`T142CodEmpresa`, `T142Agno`, `T142CodFormato`, `T142CodGrupo`, `T142CodCta`, `T142Valor`);

CREATE TABLE `T143CONFIGURAFUNCIONARIO`
 (
	`T143CodEmpresa`			varchar (5), 
	`T143Nit`			varchar (15), 
	`T143CodConcepto`			varchar (5), 
	`T143Valor`			varchar (15), 
	`T143Cuotas`			varchar (5)
);

-- CREATE INDEXES ...

CREATE TABLE `T145TERCERODOCUMENTO`
 (
	`T145Nit`			varchar (20) NOT NULL, 
	`T145Numero`			varchar (20) NOT NULL, 
	`T145TipoHistorial`			varchar (5), 
	`T145Fecha`			varchar (10), 
	`T145Observacion`			varchar (255), 
	`T145Imagen`			varchar (255), 
	`T145Digita`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T145TERCERODOCUMENTO` ADD PRIMARY KEY (`T145Nit`, `T145Numero`);

CREATE TABLE `T146ACTIVECONOMICA`
 (
	`T146Codigo`			varchar (20) NOT NULL, 
	`T146Nombre`			varchar (200), 
	`T146Porcentaje`			varchar (10)
);

-- CREATE INDEXES ...
ALTER TABLE `T146ACTIVECONOMICA` ADD PRIMARY KEY (`T146Codigo`);

CREATE TABLE `T147ACTNOMINA`
 (
	`T147CodEmpresa`			varchar (20) NOT NULL, 
	`T147Nit`			varchar (20) NOT NULL, 
	`T147Fecha`			varchar (10) NOT NULL, 
	`T147CodConcepto`			varchar (20) NOT NULL, 
	`T147Valor`			varchar (20), 
	`T147Detalle`			varchar (200)
);

-- CREATE INDEXES ...
ALTER TABLE `T147ACTNOMINA` ADD PRIMARY KEY (`T147CodEmpresa`, `T147Nit`, `T147Fecha`, `T147CodConcepto`);

CREATE TABLE `T148TIPOVINCULA`
 (
	`T148Codigo`			varchar (20) NOT NULL, 
	`T148Nombre`			varchar (200)
);

-- CREATE INDEXES ...
ALTER TABLE `T148TIPOVINCULA` ADD PRIMARY KEY (`T148Codigo`);

CREATE TABLE `T149CONDICION`
 (
	`T149Codigo`			varchar (20) NOT NULL, 
	`T149Nombre`			varchar (200)
);

-- CREATE INDEXES ...
ALTER TABLE `T149CONDICION` ADD PRIMARY KEY (`T149Codigo`);

CREATE TABLE `T14TIPOTERCERO`
 (
	`T14Codigo`			varchar (5), 
	`T14Nombre`			varchar (50)
);

-- CREATE INDEXES ...

CREATE TABLE `T150TERCEROCONTRATO`
 (
	`T150CodEmpresa`			varchar (5) NOT NULL, 
	`T150Numero`			varchar (20) NOT NULL, 
	`T150Tipo`			varchar (50), 
	`T150Nit`			varchar (20), 
	`T150Fecha`			varchar (10), 
	`T150Labor`			varchar (255), 
	`T150LugarLabor`			varchar (255), 
	`T150Salarial`			varchar (20), 
	`T150NoSalarial`			varchar (20), 
	`T150Detalle`			varchar (255), 
	`T150TipoContrato`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T150TERCEROCONTRATO` ADD PRIMARY KEY (`T150CodEmpresa`, `T150TipoContrato`, `T150Numero`);

CREATE TABLE `T152TIPOCONTRATO`
 (
	`T152Codigo`			varchar (5) NOT NULL, 
	`T152Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T152TIPOCONTRATO` ADD PRIMARY KEY (`T152Codigo`);

CREATE TABLE `T153FESTIVOS`
 (
	`T153Fecha`			varchar (10) NOT NULL, 
	`T153Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T153FESTIVOS` ADD PRIMARY KEY (`T153Fecha`);

CREATE TABLE `T154BLOQUEAFECHA`
 (
	`T154CodEmpresa`			varchar (5) NOT NULL, 
	`T154Agno`			varchar (10) NOT NULL, 
	`T154Fecha`			varchar (10) NOT NULL
);

-- CREATE INDEXES ...
ALTER TABLE `T154BLOQUEAFECHA` ADD PRIMARY KEY (`T154CodEmpresa`, `T154Agno`, `T154Fecha`);

CREATE TABLE `T155EMPRESAPARTICIPA`
 (
	`T155CodEmpresa`			varchar (5) NOT NULL, 
	`T155Nit`			varchar (20) NOT NULL, 
	`T155Participa`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T155EMPRESAPARTICIPA` ADD PRIMARY KEY (`T155CodEmpresa`, `T155Nit`);

CREATE TABLE `T156TERCEROLABORAL`
 (
	`T156Nit`			varchar (20) NOT NULL, 
	`T156Numero`			varchar (20) NOT NULL, 
	`T156TipoLaboral`			varchar (5), 
	`T156Fecha`			varchar (10), 
	`T156Observacion`			varchar (255), 
	`T156Digita`			varchar (20), 
	`T156Mostrar`			varchar (1), 
	`T156Adjunto`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T156TERCEROLABORAL` ADD PRIMARY KEY (`T156Nit`, `T156Numero`);

CREATE TABLE `T15CALIFTERCERO`
 (
	`T15Codigo`			varchar (5), 
	`T15Nombre`			varchar (50)
);

-- CREATE INDEXES ...

CREATE TABLE `T17TIPORETENCION`
 (
	`T17CodEmpresa`			varchar (5), 
	`T17Agno`			varchar (4), 
	`T17CodTipoRet`			varchar (5), 
	`T17Nombre`			varchar (50), 
	`T17CodCta`			varchar (5)
);

-- CREATE INDEXES ...

CREATE TABLE `T18TIPORETENRANGO`
 (
	`T18CodEmpresa`			varchar (5), 
	`T18Agno`			varchar (4), 
	`T18CodTipoRet`			varchar (5), 
	`T18RangoDesde`			varchar (10), 
	`T18RangoHasta`			varchar (10), 
	`T18Porcentaje`			varchar (5), 
	`T18Valor`			varchar (15)
);

-- CREATE INDEXES ...

CREATE TABLE `T19DPTO`
 (
	`T19Codigo`			varchar (2), 
	`T19Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T19DPTO` ADD PRIMARY KEY (`T19Codigo`);

CREATE TABLE `T20CIUDAD`
 (
	`T20CodDpto`			varchar (2), 
	`T20Codigo`			varchar (3), 
	`T20Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T20CIUDAD` ADD PRIMARY KEY (`T20CodDpto`, `T20Codigo`);

CREATE TABLE `T21TIPOMONEDA`
 (
	`T21Codigo`			varchar (5), 
	`T21Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T222ORDENCARGUE`
 (
	`T222NumOrden`			varchar (20) NOT NULL, 
	`T222CodCliente`			varchar (20), 
	`T222CodConductor`			varchar (20), 
	`T222CodMovil`			varchar (10), 
	`T222CodTrailer`			varchar (10), 
	`T222CodProducto`			varchar (20), 
	`T222Cantidad`			varchar (10), 
	`T222CodDpto`			varchar (5), 
	`T222CodMunicipio`			varchar (5), 
	`T222Destinatario`			varchar (100), 
	`T222Observacion`			varchar (255), 
	`T222Detalle`			varchar (255), 
	`T222Fecha`			varchar (10), 
	`T222CapTonelada`			varchar (10), 
	`T222Comision`			varchar (10), 
	`T222Prefijo`			varchar (10)
);

-- CREATE INDEXES ...
ALTER TABLE `T222ORDENCARGUE` ADD PRIMARY KEY (`T222Prefijo`, `T222NumOrden`);

CREATE TABLE `T224OFICINA`
 (
	`T224Codigo`			varchar (5) NOT NULL, 
	`T224Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T224OFICINA` ADD PRIMARY KEY (`T224Codigo`);

CREATE TABLE `T225NATURALEZA`
 (
	`T225Codigo`			varchar (5) NOT NULL, 
	`T225Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T225NATURALEZA` ADD PRIMARY KEY (`T225Codigo`);

CREATE TABLE `T226TIPOORDEN`
 (
	`T226Codigo`			varchar (5) NOT NULL, 
	`T226Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T226TIPOORDEN` ADD PRIMARY KEY (`T226Codigo`);

CREATE TABLE `T227ORDEN`
 (
	`T227CodTipo`			varchar (5) NOT NULL, 
	`T227Numero`			varchar (20) NOT NULL, 
	`T227Fecha`			varchar (10), 
	`T227Hora`			varchar (10), 
	`T227CodTercero`			varchar (20), 
	`T227CodVehiculo`			varchar (20), 
	`T227Valor`			varchar (20), 
	`T227Detalle`			varchar (255), 
	`T227Observacion`			varchar (255), 
	`T227PolizaCC`			varchar (1), 
	`T227PolizaCEC`			varchar (1), 
	`T227PolizaPA`			varchar (1), 
	`T227PolizaCB`			varchar (1), 
	`T227TarjetaOpera`			varchar (1), 
	`T227Extracto`			varchar (1), 
	`T227Vence`			varchar (255), 
	`T227Orden`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T227ORDEN` ADD PRIMARY KEY (`T227CodTipo`, `T227Numero`);

CREATE TABLE `T228ORDENDETALLE`
 (
	`T228CodTipo`			varchar (5) NOT NULL, 
	`T228Numero`			varchar (20) NOT NULL, 
	`T228Consecutivo`			varchar (10) NOT NULL, 
	`T228CodCpto`			varchar (20), 
	`T228Detalle`			varchar (255), 
	`T228Cantidad`			varchar (20), 
	`T228Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T228ORDENDETALLE` ADD PRIMARY KEY (`T228CodTipo`, `T228Numero`, `T228Consecutivo`);

CREATE TABLE `T22FORMAAJUSTE`
 (
	`T22Codigo`			varchar (5), 
	`T22Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T24CENTROCOSTO`
 (
	`T24CodEmpresa`			varchar (5) NOT NULL, 
	`T24CodCentro`			varchar (6) NOT NULL, 
	`T24Nivel`			varchar (1), 
	`T24Nombre`			varchar (30), 
	`T24EsBodega`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T24CENTROCOSTO` ADD PRIMARY KEY (`T24CodEmpresa`, `T24CodCentro`);

CREATE TABLE `T25GRUPOCUENTA`
 (
	`T25CodEmpresa`			varchar (5), 
	`T25Codigo`			varchar (5), 
	`T25Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T25GRUPOCUENTA` ADD PRIMARY KEY (`T25CodEmpresa`, `T25Codigo`);

CREATE TABLE `T26TIPODOCUMENTOCIA`
 (
	`T26CodEmpresa`			varchar (5), 
	`T26Codigo`			varchar (5), 
	`T26Nombre`			varchar (30), 
	`T26Activo`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T26TIPODOCUMENTOCIA` ADD PRIMARY KEY (`T26CodEmpresa`, `T26Codigo`);

CREATE TABLE `T27TIPONATURALEZA`
 (
	`T27Codigo`			varchar (5), 
	`T27Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T28MES`
 (
	`T28Codigo`			int, 
	`T28Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T29TRIBUTARIA`
 (
	`T29Codigo`			varchar (5), 
	`T29Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T31FORMAPAGO`
 (
	`T31Codigo`			varchar (5), 
	`T31Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T32TIPOCOMPARACION`
 (
	`T32Codigo`			varchar (5), 
	`T32Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T33TIPOCUENTABANCO`
 (
	`T33Codigo`			varchar (5) NOT NULL, 
	`T33Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T33TIPOCUENTABANCO` ADD PRIMARY KEY (`T33Codigo`);

CREATE TABLE `T34OPERACIONCONCEPTO`
 (
	`T34Codigo`			varchar (5), 
	`T34Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T35ARTICULO`
 (
	`T35CodEmpresa`			varchar (5), 
	`T35Codigo`			varchar (5), 
	`T35Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T36TIPOPLANPPTO`
 (
	`T36Codigo`			varchar (5), 
	`T36Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T37TIPOCUENTAPPTO`
 (
	`T37Codigo`			varchar (5), 
	`T37Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T38TIPOCALCULOPPTO`
 (
	`T38Codigo`			varchar (5), 
	`T38Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T39LUGARRECIBEPAGO`
 (
	`T39Codigo`			varchar (5), 
	`T39Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T40FORMATOIMPRIMIR`
 (
	`T40CodEmpresa`			varchar (5), 
	`T40Codigo`			int, 
	`T40Nombre`			varchar (50), 
	`T40Grupo`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T40FORMATOIMPRIMIR` ADD PRIMARY KEY (`T40CodEmpresa`, `T40Codigo`);

CREATE TABLE `T42GRUPONOMINA`
 (
	`T42CodEmpresa`			varchar (5), 
	`T42Codigo`			varchar (5), 
	`T42Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T42GRUPONOMINA` ADD PRIMARY KEY (`T42CodEmpresa`, `T42Codigo`);

CREATE TABLE `T43TIPOMOVHISTORIAL`
 (
	`T43Codigo`			varchar (5), 
	`T43Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T43TIPOMOVHISTORIAL` ADD PRIMARY KEY (`T43Codigo`);

CREATE TABLE `T44TIPOCONCEPTO`
 (
	`T44Codigo`			varchar (5), 
	`T44Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T44TIPOCONCEPTO` ADD PRIMARY KEY (`T44Codigo`);

CREATE TABLE `T45HORAS`
 (
	`T45Codigo`			varchar (5), 
	`T45Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T45HORAS` ADD PRIMARY KEY (`T45Codigo`);

CREATE TABLE `T46RECORDATORIO`
 (
	`T46Fecha`			varchar (10), 
	`T46Hora`			varchar (50), 
	`T46Recordatorio`			varchar (255), 
	`T46Recordar`			varchar (1), 
	`T46RecordarEn`			varchar (10), 
	`T46Cantidad`			varchar (5), 
	`T46Cancelar`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T46RECORDATORIO` ADD PRIMARY KEY (`T46Fecha`, `T46Hora`);

CREATE TABLE `T47GRUPOCONTABLE`
 (
	`T47Codigo`			varchar (5), 
	`T47Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T47GRUPOCONTABLE` ADD PRIMARY KEY (`T47Codigo`);

CREATE TABLE `T48TIPOCONTABLE`
 (
	`T48Codigo`			varchar (5), 
	`T48Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T48TIPOCONTABLE` ADD PRIMARY KEY (`T48Codigo`);

CREATE TABLE `T50TIPOCALENDARIO`
 (
	`T50Codigo`			varchar (5), 
	`T50Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T50TIPOCALENDARIO` ADD PRIMARY KEY (`T50Codigo`);

CREATE TABLE `T51PERIODOTRIBUTARIO`
 (
	`T51TipoCalendario`			varchar (5), 
	`T51Codigo`			varchar (5), 
	`T51Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T51PERIODOTRIBUTARIO` ADD PRIMARY KEY (`T51TipoCalendario`, `T51Codigo`);

CREATE TABLE `T529TIPOORDEN`
 (
	`T529Codigo`			varchar (5) NOT NULL, 
	`T529Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T529TIPOORDEN` ADD PRIMARY KEY (`T529Codigo`);

CREATE TABLE `T52TIPODIGITOS`
 (
	`T52Codigo`			varchar (5), 
	`T52Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T52TIPODIGITOS` ADD PRIMARY KEY (`T52Codigo`);

CREATE TABLE `T530COMPROMISOCPTO`
 (
	`T530CodEmpresa`			varchar (5) NOT NULL, 
	`T530Agno`			varchar (4) NOT NULL, 
	`T530Vigencia`			varchar (4) NOT NULL, 
	`T530Numero`			varchar (20) NOT NULL, 
	`T530Consecutivo`			varchar (20) NOT NULL, 
	`T530CodConcepto`			varchar (20), 
	`T530Cantidad`			varchar (20), 
	`T530Valor`			varchar (20), 
	`T530ValorIVA`			varchar (20), 
	`T530PorcIVA`			varchar (10), 
	`T530ValorDescuento`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T530COMPROMISOCPTO` ADD PRIMARY KEY (`T530CodEmpresa`, `T530Agno`, `T530Vigencia`, `T530Numero`, `T530Consecutivo`);

CREATE TABLE `T53FORMATOEXOGENA`
 (
	`T53Codigo`			varchar (5), 
	`T53Nombre`			varchar (50), 
	`T53Agno`			varchar (4), 
	`T53Formato`			varchar (200), 
	`T53Detalle`			varchar (200)
);

-- CREATE INDEXES ...
ALTER TABLE `T53FORMATOEXOGENA` ADD PRIMARY KEY (`T53Agno`, `T53Codigo`);

CREATE TABLE `T53SUBCONCEPTO`
 (
	`T53Codigo`			varchar (5), 
	`T53Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T53SUBCONCEPTO` ADD PRIMARY KEY (`T53Codigo`);

CREATE TABLE `T55TIPODOCUMENTO`
 (
	`T55Codigo`			varchar (5) NOT NULL, 
	`T55Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T55TIPODOCUMENTO` ADD PRIMARY KEY (`T55Codigo`);

CREATE TABLE `T56UNIDADMEDIDA`
 (
	`T56Codigo`			varchar (5) NOT NULL, 
	`T56Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T56UNIDADMEDIDA` ADD PRIMARY KEY (`T56Codigo`);

CREATE TABLE `T57PROFESION`
 (
	`T57Codigo`			varchar (5) NOT NULL, 
	`T57Nombre`			varchar (50)
);

-- CREATE INDEXES ...

CREATE TABLE `T58AUTOCONCEPTO`
 (
	`T58Codigo`			varchar (5) NOT NULL, 
	`T58Nombre`			varchar (250)
);

-- CREATE INDEXES ...
ALTER TABLE `T58AUTOCONCEPTO` ADD PRIMARY KEY (`T58Codigo`);

CREATE TABLE `T59TIPOHISTORIAL`
 (
	`T59Codigo`			varchar (5) NOT NULL, 
	`T59Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T59TIPOHISTORIAL` ADD PRIMARY KEY (`T59Codigo`);

CREATE TABLE `T600PISOSHOTEL`
 (
	`T600CodEmpresa`			varchar (5), 
	`T600Codigo`			varchar (5), 
	`T600Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T600PISOSHOTEL` ADD PRIMARY KEY (`T600CodEmpresa`, `T600Codigo`);

CREATE TABLE `T602HABITACION`
 (
	`T602CodEmpresa`			varchar (5), 
	`T602CodPisosHotel`			varchar (5), 
	`T602CodAreaHotel`			varchar (5), 
	`T602Codigo`			varchar (5), 
	`T602Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T602HABITACION` ADD PRIMARY KEY (`T602CodEmpresa`, `T602CodPisosHotel`, `T602CodAreaHotel`, `T602Codigo`);

CREATE TABLE `T603CONCEPTO`
 (
	`T603CodEmpresa`			varchar (5), 
	`T603Codigo`			varchar (20), 
	`T603CodTemporada`			varchar (5), 
	`T603Nombre`			varchar (255), 
	`T603PorcComision`			varchar (3), 
	`T603CobroAut`			varchar (1), 
	`T603PorcMaxDesc`			varchar (5), 
	`T603Imprimir`			varchar (1), 
	`T603Tipo`			varchar (5), 
	`T603Detalle`			varchar (100), 
	`T603Operacion`			varchar (5), 
	`T603Peso`			varchar (10), 
	`T603ActivaValor`			varchar (1), 
	`T603ActivaDescuento`			varchar (1), 
	`T603UltValorCompra`			varchar (15), 
	`T603CostoPromedio`			varchar (15), 
	`T603CostoDigitado`			varchar (15), 
	`T603UnidadMedida`			varchar (5), 
	`T603BaseInteres`			varchar (1), 
	`T603GrupoCC`			varchar (2), 
	`T603Vendedor`			varchar (5), 
	`T603UltFlete`			varchar (20), 
	`T603Foto`			varchar (255), 
	`T603UltFlete1`			varchar (20), 
	`T603UltFlete2`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T603CONCEPTO` ADD PRIMARY KEY (`T603CodEmpresa`, `T603Codigo`, `T603CodTemporada`);
ALTER TABLE `T603CONCEPTO` ADD INDEX `T603Imprimir` (`T603Imprimir`);

CREATE TABLE `T604FACTURA`
 (
	`T604CodEmpresa`			varchar (5) NOT NULL, 
	`T604Prefijo`			varchar (5) NOT NULL, 
	`T604NumFactura`			varchar (10) NOT NULL, 
	`T604Fecha`			varchar (10), 
	`T604CodTercero`			varchar (15), 
	`T604Total`			varchar (15), 
	`T604TotalIVA`			varchar (15), 
	`T604TotalDescuento`			varchar (15), 
	`T604CodFormaPago`			varchar (5), 
	`T604Detalle`			varchar (100), 
	`T604Cancelado`			varchar (1), 
	`T604FechaIni`			varchar (10), 
	`T604HoraIni`			varchar (10), 
	`T604FechaFin`			varchar (10), 
	`T604HoraFin`			varchar (10), 
	`T604TiempoFactura`			varchar (10), 
	`T604Piso`			varchar (5), 
	`T604Area`			text, 
	`T604Habitacion`			varchar (5), 
	`T604FechaVence`			varchar (10), 
	`T604Vendedor`			varchar (15), 
	`T604Digita`			varchar (20), 
	`T604PorcRetencion`			varchar (15), 
	`T604Retencion`			varchar (15), 
	`T604Impresa`			varchar (1), 
	`T604PorcReteIVA`			varchar (15), 
	`T604ReteIVA`			varchar (15), 
	`T604PorcReteICA`			varchar (15), 
	`T604ReteICA`			varchar (15), 
	`T604PorcAUIAdmon`			varchar (5), 
	`T604AUIAdmon`			varchar (15), 
	`T604PorcAUIImprevisto`			varchar (5), 
	`T604AUIImprevisto`			varchar (15), 
	`T604PorcAUIUtilidad`			varchar (5), 
	`T604AUIUtilidad`			varchar (15), 
	`T604PorcAUIIVA`			varchar (5), 
	`T604AUIIVA`			varchar (15), 
	`T604ValorPagado`			varchar (20), 
	`T604DetalleLargo`			text, 
	`T604PorcOtrosDesc`			varchar (15), 
	`T604OtroDescuento`			varchar (20), 
	`T604CodFormaPago2`			varchar (5), 
	`T604TotalFormaPago1`			varchar (20), 
	`T604TotalFormaPago2`			varchar (20), 
	`T604OtroTercero`			varchar (15), 
	`T604NomOtroTercero`			varchar (100), 
	`T604ObservaOtroTercero`			varchar (100), 
	`T604NumAbono1`			varchar (20), 
	`T604NumAbono2`			varchar (20), 
	`T604CUFE`			varchar (255), 
	`T604DesComercial`			varchar (20), 
	`T604Placa`			varchar (20), 
	`T604Moneda`			varchar (5), 
	`T604CodFormaPagoFE`			varchar (5), 
	`T604MedioPagoFE`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T604FACTURA` ADD PRIMARY KEY (`T604CodEmpresa`, `T604Prefijo`, `T604NumFactura`);
ALTER TABLE `T604FACTURA` ADD INDEX `T604Cancelado` (`T604Cancelado`);
ALTER TABLE `T604FACTURA` ADD INDEX `T604CodFormaPago` (`T604CodFormaPago`);

CREATE TABLE `T604FACTURA2`
 (
	`T604CodEmpresa`			varchar (5), 
	`T604Prefijo`			varchar (5), 
	`T604NumFactura`			varchar (10), 
	`T604Fecha`			varchar (10), 
	`T604CodTercero`			varchar (15), 
	`T604Total`			varchar (15), 
	`T604TotalIVA`			varchar (15), 
	`T604TotalDescuento`			varchar (15), 
	`T604CodFormaPago`			varchar (5), 
	`T604Detalle`			varchar (100), 
	`T604Cancelado`			varchar (1), 
	`T604FechaIni`			varchar (10), 
	`T604HoraIni`			varchar (10), 
	`T604FechaFin`			varchar (10), 
	`T604HoraFin`			varchar (10), 
	`T604TiempoFactura`			varchar (10), 
	`T604Piso`			varchar (5), 
	`T604Area`			varchar (5), 
	`T604Habitacion`			varchar (5), 
	`T604FechaVence`			varchar (10), 
	`T604Vendedor`			varchar (15), 
	`T604Digita`			varchar (20), 
	`T604PorcRetencion`			varchar (15), 
	`T604Retencion`			varchar (15), 
	`T604Impresa`			varchar (1), 
	`T604PorcReteIVA`			varchar (15), 
	`T604ReteIVA`			varchar (15), 
	`T604PorcReteICA`			varchar (15), 
	`T604ReteICA`			varchar (15), 
	`T604PorcAUIAdmon`			varchar (5), 
	`T604AUIAdmon`			varchar (15), 
	`T604PorcAUIImprevisto`			varchar (5), 
	`T604AUIImprevisto`			varchar (15), 
	`T604PorcAUIUtilidad`			varchar (5), 
	`T604AUIUtilidad`			varchar (15), 
	`T604PorcAUIIVA`			varchar (5), 
	`T604AUIIVA`			varchar (15), 
	`T604ValorPagado`			varchar (20), 
	`T604DetalleLargo`			text, 
	`T604PorcOtrosDesc`			varchar (15), 
	`T604OtroDescuento`			varchar (20), 
	`T604CodFormaPago2`			varchar (5), 
	`T604TotalFormaPago1`			varchar (20), 
	`T604TotalFormaPago2`			varchar (20), 
	`T604OtroTercero`			varchar (15), 
	`T604NomOtroTercero`			varchar (100), 
	`T604ObservaOtroTercero`			varchar (100), 
	`T604NumAbono1`			varchar (20), 
	`T604NumAbono2`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T604FACTURA2` ADD PRIMARY KEY (`T604CodEmpresa`, `T604Prefijo`, `T604NumFactura`, `T604Digita`);

CREATE TABLE `T605FACTURADETALLE`
 (
	`T605CodEmpresa`			varchar (5), 
	`T605Prefijo`			varchar (5), 
	`T605NumFactura`			varchar (10), 
	`T605Consecutivo`			varchar (5), 
	`T605Cantidad`			varchar (5), 
	`T605CodConcepto`			varchar (20), 
	`T605Valor`			varchar (15), 
	`T605ValorIVA`			varchar (15), 
	`T605SubCodConcepto`			varchar (5), 
	`T605Descuento`			varchar (15), 
	`T605CodCentro`			varchar (20), 
	`T605Digita`			varchar (20), 
	`T605PorcIVA`			varchar (15), 
	`T605ValorCosto`			varchar (15), 
	`T605ValorPagado`			varchar (20), 
	`T605Observacion`			text, 
	`T605Fecha`			varchar (20), 
	`T605Tercero`			varchar (20), 
	`T605FechaVence`			varchar (10), 
	`T605Lote`			varchar (20), 
	`T605PorcIVA2`			varchar (20), 
	`T605ValorIVA2`			varchar (20), 
	`T605BaseImpAdic`			varchar (20), 
	`T605ImpuestoAdic`			varchar (5), 
	`T605PorcImpAdic`			varchar (20), 
	`T605ValorImpAdic`			varchar (20), 
	`T605TerceroAdic`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T605FACTURADETALLE` ADD PRIMARY KEY (`T605CodEmpresa`, `T605Prefijo`, `T605NumFactura`, `T605Consecutivo`, `T605Digita`);
ALTER TABLE `T605FACTURADETALLE` ADD INDEX `T605Prefijo` (`T605Prefijo`);

CREATE TABLE `T605FACTURADETALLE2`
 (
	`T605CodEmpresa`			varchar (5), 
	`T605Prefijo`			varchar (5), 
	`T605NumFactura`			varchar (10), 
	`T605Consecutivo`			varchar (5), 
	`T605Cantidad`			varchar (5), 
	`T605CodConcepto`			varchar (20), 
	`T605Valor`			varchar (15), 
	`T605ValorIVA`			varchar (15), 
	`T605SubCodConcepto`			varchar (5), 
	`T605Descuento`			varchar (15), 
	`T605CodCentro`			varchar (20), 
	`T605Digita`			varchar (20), 
	`T605PorcIVA`			varchar (15), 
	`T605ValorCosto`			varchar (15), 
	`T605ValorPagado`			varchar (20), 
	`T605Observacion`			text, 
	`T605Fecha`			varchar (20), 
	`T605Tercero`			varchar (20), 
	`T605FechaVence`			varchar (10), 
	`T605Lote`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T605FACTURADETALLE2` ADD PRIMARY KEY (`T605CodEmpresa`, `T605Prefijo`, `T605NumFactura`, `T605Consecutivo`, `T605Digita`);

CREATE TABLE `T607TIPOCONCEPTO`
 (
	`T607Codigo`			varchar (5), 
	`T607Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T607TIPOCONCEPTO` ADD PRIMARY KEY (`T607Codigo`);

CREATE TABLE `T608CONFIGURACPTO`
 (
	`T608CodEmpresa`			varchar (5), 
	`T608IdPertenece`			varchar (5), 
	`T608CodTemporada`			varchar (5), 
	`T608Codigo`			varchar (20), 
	`T608CodConcepto`			varchar (20), 
	`T608Valor`			varchar (15), 
	`T608CobroAut`			varchar (1), 
	`T608ValorIVA`			varchar (15)
);

-- CREATE INDEXES ...
ALTER TABLE `T608CONFIGURACPTO` ADD PRIMARY KEY (`T608CodEmpresa`, `T608IdPertenece`, `T608CodTemporada`, `T608Codigo`, `T608CodConcepto`);

CREATE TABLE `T609TEMPORADA`
 (
	`T609CodEmpresa`			varchar (5), 
	`T609Codigo`			varchar (5), 
	`T609Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T609TEMPORADA` ADD PRIMARY KEY (`T609CodEmpresa`, `T609Codigo`);

CREATE TABLE `T60TIPODOCSCANER`
 (
	`T60Codigo`			varchar (5) NOT NULL, 
	`T60Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T60TIPODOCSCANER` ADD PRIMARY KEY (`T60Codigo`);

CREATE TABLE `T610FACTURATMP`
 (
	`T610CodEmpresa`			varchar (5), 
	`T610CodPiso`			varchar (5), 
	`T610CodArea`			varchar (5), 
	`T610CodHabitacion`			varchar (5), 
	`T610Consecutivo`			varchar (5), 
	`T610IniciaFact`			varchar (1), 
	`T610Fecha`			varchar (10), 
	`T610FormaPago`			varchar (5), 
	`T610Tercero`			varchar (15), 
	`T610Detalle`			varchar (255), 
	`T610CodTemporada`			varchar (5), 
	`T610CodConcepto`			varchar (10), 
	`T610Cuenta`			varchar (1), 
	`T610Cantidad`			varchar (5), 
	`T610Valor`			varchar (15), 
	`T610PorcIVA`			varchar (5), 
	`T610TotalDescuento`			varchar (15), 
	`T610FechaInicioFact`			varchar (10), 
	`T610HoraInicio`			varchar (10)
);

-- CREATE INDEXES ...
ALTER TABLE `T610FACTURATMP` ADD PRIMARY KEY (`T610CodEmpresa`, `T610CodPiso`, `T610CodArea`, `T610CodHabitacion`, `T610Consecutivo`);

CREATE TABLE `T611DOCUMENTO`
 (
	`T611CodEmpresa`			varchar (5) NOT NULL, 
	`T611Agno`			varchar (4) NOT NULL, 
	`T611TipoTransaccion`			varchar (5) NOT NULL, 
	`T611NumeroDoc`			varchar (20) NOT NULL, 
	`T611Fecha`			varchar (10), 
	`T611CodProveedor`			varchar (15), 
	`T611ValorBase`			varchar (15), 
	`T611ValorIVA`			varchar (15), 
	`T611ValorDescuento`			varchar (15), 
	`T611ValorTtFactura`			varchar (15), 
	`T611FormaPago`			varchar (5), 
	`T611FechaVence`			varchar (10), 
	`T611Concepto`			text, 
	`T611Prefijo`			varchar (5), 
	`T611NumFactura`			varchar (20), 
	`T611Anular`			varchar (1), 
	`T611FechaPago`			varchar (10), 
	`T611ValorReteRenta`			varchar (15), 
	`T611ValorReteIVA`			varchar (15), 
	`T611ValorReteICA`			varchar (15), 
	`T611PorcRenta`			varchar (15), 
	`T611PorcIVA`			varchar (15), 
	`T611PorcICA`			varchar (15), 
	`T611Consecutivo`			varchar (10), 
	`T611Digita`			varchar (20), 
	`T611Impresa`			varchar (1), 
	`T611OtroDescuento`			varchar (20), 
	`T611Hora`			varchar (5), 
	`T611FechaDevol`			varchar (10), 
	`T611Obra`			varchar (50), 
	`T611Vendedor`			varchar (5), 
	`T611Conductor`			varchar (5), 
	`T611PorcOtro`			varchar (20), 
	`T611CUFE`			text, 
	`T611PdfCufe`			text, 
	`T611PorcAUIAdmon`			varchar (5), 
	`T611AUIAdmon`			varchar (20), 
	`T611PorcAUIImprevisto`			varchar (5), 
	`T611AUIImprevisto`			varchar (20), 
	`T611PorcAUIUtilidad`			varchar (5), 
	`T611AUIUtilidad`			varchar (20), 
	`T611PorcAUIIVA`			varchar (5), 
	`T611AUIIVA`			varchar (20), 
	`T611DescuentoCom`			varchar (20), 
	`T611Moneda`			varchar (10)
);

-- CREATE INDEXES ...
ALTER TABLE `T611DOCUMENTO` ADD PRIMARY KEY (`T611CodEmpresa`, `T611Agno`, `T611TipoTransaccion`, `T611NumeroDoc`);
ALTER TABLE `T611DOCUMENTO` ADD INDEX `Secundario` (`T611CodEmpresa`, `T611Agno`, `T611TipoTransaccion`, `T611NumFactura`, `T611Prefijo`);
ALTER TABLE `T611DOCUMENTO` ADD INDEX `T611Anular` (`T611Anular`);
ALTER TABLE `T611DOCUMENTO` ADD INDEX `T611FormaPago` (`T611FormaPago`);
ALTER TABLE `T611DOCUMENTO` ADD INDEX `T611TipoTransaccion` (`T611TipoTransaccion`);

CREATE TABLE `T612MOVIMIENTO`
 (
	`T612CodEmpresa`			varchar (5) NOT NULL, 
	`T612Agno`			varchar (4) NOT NULL, 
	`T612TipoTransaccion`			varchar (5) NOT NULL, 
	`T612NumeroDoc`			varchar (20) NOT NULL, 
	`T612CodArticulo`			varchar (20) NOT NULL, 
	`T612Cantidad`			varchar (10), 
	`T612ValorArticulo`			varchar (15), 
	`T612ValorDescuento`			varchar (15), 
	`T612ValorIVA`			varchar (15), 
	`T612SubCodConcepto`			varchar (5), 
	`T612Consecutivo`			varchar (5) NOT NULL, 
	`T612CodCentro`			varchar (20), 
	`T612PorcIVA`			varchar (15), 
	`T612Digita`			varchar (20), 
	`T612ValorVenta`			varchar (15), 
	`T612CodMetro2`			varchar (20), 
	`T612NumMetro2`			varchar (20), 
	`T612ValorFlete`			varchar (20), 
	`T612ValorVentaAct`			varchar (20), 
	`T612FechaVence`			varchar (10), 
	`T612Lote`			varchar (20), 
	`T612ValorBaseCafe`			varchar (20), 
	`T612BonificaCafe`			varchar (20), 
	`T612PorcTara`			varchar (10), 
	`T612PorcFR`			varchar (10), 
	`T612PorcHumedad`			varchar (10), 
	`T612PorcKgBruto`			varchar (10), 
	`T612BrocaBase`			varchar (10), 
	`T612Broca`			varchar (10), 
	`T612HumedBase`			varchar (10), 
	`T612BaseFR`			varchar (10), 
	`T612PorcIVA2`			varchar (5), 
	`T612ValorIVA2`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T612MOVIMIENTO` ADD PRIMARY KEY (`T612CodEmpresa`, `T612Agno`, `T612TipoTransaccion`, `T612NumeroDoc`, `T612CodArticulo`, `T612Consecutivo`);

CREATE TABLE `T612MOVIMIENTO_2`
 (
	`T612CodEmpresa`			varchar (5) NOT NULL, 
	`T612Agno`			varchar (4) NOT NULL, 
	`T612TipoTransaccion`			varchar (5) NOT NULL, 
	`T612NumeroDoc`			varchar (20) NOT NULL, 
	`T612CodArticulo`			varchar (20) NOT NULL, 
	`T612Cantidad`			varchar (10), 
	`T612ValorArticulo`			varchar (15), 
	`T612ValorDescuento`			varchar (15), 
	`T612ValorIVA`			varchar (15), 
	`T612SubCodConcepto`			varchar (5), 
	`T612Consecutivo`			varchar (5), 
	`T612CodCentro`			varchar (20), 
	`T612PorcIVA`			varchar (15), 
	`T612Digita`			varchar (20), 
	`T612ValorVenta`			varchar (15), 
	`T612CodMetro2`			varchar (20), 
	`T612NumMetro2`			varchar (20), 
	`T612ValorFlete`			varchar (20), 
	`T612ValorVentaAct`			varchar (20), 
	`T612FechaVence`			varchar (10), 
	`T612Lote`			varchar (20), 
	`T612ValorBaseCafe`			varchar (20), 
	`T612BonificaCafe`			varchar (20), 
	`T612PorcTara`			varchar (10), 
	`T612PorcFR`			varchar (10), 
	`T612PorcHumedad`			varchar (10), 
	`T612PorcKgBruto`			varchar (10), 
	`T612BrocaBase`			varchar (10), 
	`T612Broca`			varchar (10), 
	`T612HumedBase`			varchar (10), 
	`T612BaseFR`			varchar (10), 
	`T612PorcIVA2`			varchar (5), 
	`T612ValorIVA2`			varchar (20)
);

-- CREATE INDEXES ...

CREATE TABLE `T613OPERACION`
 (
	`T613Codigo`			varchar (5), 
	`T613Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T613OPERACION` ADD PRIMARY KEY (`T613Codigo`);

CREATE TABLE `T614CANCELAFACTURA`
 (
	`T614CodEmpresa`			varchar (5), 
	`T614NumCancelaFact`			varchar (10), 
	`T614CodPiso`			varchar (5), 
	`T614CodArea`			varchar (5), 
	`T614CodHabitacion`			varchar (5), 
	`T614Consecutivo`			varchar (5), 
	`T614IniciaFact`			varchar (1), 
	`T614Fecha`			varchar (10), 
	`T614FormaPago`			varchar (5), 
	`T614Tercero`			varchar (15), 
	`T614Detalle`			varchar (255), 
	`T614CodTemporada`			varchar (5), 
	`T614CodConcepto`			varchar (10), 
	`T614Cuenta`			varchar (1), 
	`T614Cantidad`			varchar (5), 
	`T614Valor`			varchar (15), 
	`T614PorcIVA`			varchar (5), 
	`T614TotalDescuento`			varchar (15), 
	`T614FechaInicioFact`			varchar (10), 
	`T614HoraInicio`			varchar (10), 
	`T614CodTipoCancela`			varchar (5), 
	`T614Motivo`			text
);

-- CREATE INDEXES ...
ALTER TABLE `T614CANCELAFACTURA` ADD PRIMARY KEY (`T614CodEmpresa`, `T614NumCancelaFact`, `T614CodPiso`, `T614CodArea`, `T614CodHabitacion`, `T614Consecutivo`);

CREATE TABLE `T615TIPOCANCELA`
 (
	`T615Codigo`			varchar (5), 
	`T615Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T615TIPOCANCELA` ADD PRIMARY KEY (`T615Codigo`);

CREATE TABLE `T617TIPOTRANSACCION`
 (
	`T617Codigo`			varchar (5), 
	`T617Nombre`			varchar (50), 
	`T617Tipo`			varchar (1), 
	`T617ConceptoContab`			varchar (5), 
	`T617OrdenImpresion`			varchar (5), 
	`T617ConceptoAbonoContab`			int, 
	`T617Consecutivo`			varchar (15), 
	`T617Activo`			varchar (1), 
	`T617Prefijo`			varchar (5), 
	`T617Proveedor`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T617TIPOTRANSACCION` ADD PRIMARY KEY (`T617Codigo`);

CREATE TABLE `T618TIPOARTICULO`
 (
	`T618Codigo`			varchar (5), 
	`T618Nombre`			varchar (30), 
	`T618VidaUtil`			varchar (5), 
	`T618Foto`			varchar (255), 
	`T618PorcDescuento`			varchar (20), 
	`T618PorcDescuento2`			varchar (5), 
	`T618PorcDescuento3`			varchar (5), 
	`T618PorcDescuento4`			varchar (5), 
	`T618Formato`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T618TIPOARTICULO` ADD PRIMARY KEY (`T618Codigo`);

CREATE TABLE `T619ALMACEN`
 (
	`T619CodEmpresa`			varchar (5), 
	`T619CodTemporada`			varchar (5), 
	`T619CodConcepto`			varchar (20), 
	`T619CodTipoArticulo`			varchar (5), 
	`T619StockMinimo`			varchar (10), 
	`T619StockMaximo`			varchar (10), 
	`T619Linea`			varchar (5), 
	`T619Modelo`			varchar (5), 
	`T619Color`			varchar (5), 
	`T619Talla`			varchar (5), 
	`T619Referencia`			varchar (50), 
	`T619Ubicacion`			varchar (100), 
	`T619CodTercero`			varchar (20), 
	`T619FechaCompra`			varchar (10), 
	`T619VidaUtil`			varchar (10), 
	`T619ValorCompra`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T619ALMACEN` ADD PRIMARY KEY (`T619CodEmpresa`, `T619CodTemporada`, `T619CodConcepto`);

CREATE TABLE `T61TIPOLABORAL`
 (
	`T61Codigo`			varchar (5) NOT NULL, 
	`T61Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T61TIPOLABORAL` ADD PRIMARY KEY (`T61Codigo`);

CREATE TABLE `T620CONCEPTOCONTAB`
 (
	`T620CodEmpresa`			varchar (5), 
	`T620Agno`			varchar (4), 
	`T620CodGrupo`			varchar (5), 
	`T620CodProceso`			varchar (5), 
	`T620TipoTransaccion`			varchar (5), 
	`T620CodTipoDocContab`			varchar (5), 
	`T620CtaFormaCredito`			varchar (255), 
	`T620CtaFormaContado`			varchar (255), 
	`T620CodCentro`			varchar (255), 
	`T620Nit`			varchar (255), 
	`T620Detalle`			varchar (255), 
	`T620CtaDebito`			varchar (255), 
	`T620CtaCredito`			varchar (255), 
	`T620NomCtaFormaContado`			varchar (255), 
	`T620NomCtaFormaCredito`			varchar (255), 
	`T620NomCentro`			varchar (255), 
	`T620NomNit`			varchar (255), 
	`T620NomCtaDebito`			varchar (255), 
	`T620NomCtaCredito`			varchar (255), 
	`T620CodTipoDoc`			varchar (5), 
	`T620PorcIVA1`			varchar (20), 
	`T620PorcIVA2`			varchar (20), 
	`T620PorcIVA3`			varchar (20), 
	`T620PorcIVA4`			varchar (20), 
	`T620Cuenta1`			varchar (20), 
	`T620Cuenta2`			varchar (20), 
	`T620Cuenta3`			varchar (20), 
	`T620Cuenta4`			varchar (20), 
	`T620CuentaImp1`			varchar (20), 
	`T620CuentaImp2`			varchar (20), 
	`T620CuentaImp3`			varchar (20), 
	`T620CuentaImp4`			varchar (20), 
	`T620ReteRenta`			varchar (20), 
	`T620ReteIVA`			varchar (20), 
	`T620ReteICA`			varchar (20), 
	`T620Caja`			varchar (20), 
	`T620Banco`			varchar (20), 
	`T620Credito`			varchar (20), 
	`T620ReteRentaSimpli`			varchar (20), 
	`T620ReteIVASimpli`			varchar (20), 
	`T620CostoDeb`			varchar (20), 
	`T620CostoCred`			varchar (20), 
	`T620CostoDeb1`			varchar (20), 
	`T620CostoCred1`			varchar (20), 
	`T620CostoDeb2`			varchar (20), 
	`T620CostoCred2`			varchar (20), 
	`T620CostoDeb3`			varchar (20), 
	`T620CostoCred3`			varchar (20), 
	`T620OtroDescuento`			varchar (20), 
	`T620PorcOtroDesc`			varchar (10), 
	`T620PorcOtroDesc1`			varchar (10), 
	`T620OtroDescuento1`			varchar (20), 
	`T620PorcOtroDesc2`			varchar (10), 
	`T620OtroDescuento2`			varchar (20), 
	`T620OtroDescuento3`			varchar (20), 
	`T620OtroDescuento4`			varchar (20), 
	`T620OtroDescuento5`			varchar (20), 
	`T620AUIAdmon`			varchar (20), 
	`T620AUIUtilidad`			varchar (20), 
	`T620AUIImprevisto`			varchar (20), 
	`T620AUIIVA`			varchar (20), 
	`T620PorcRenta`			varchar (20), 
	`T620PorcRenta1`			varchar (20), 
	`T620ReteRenta1`			varchar (20), 
	`T620PorcRenta2`			varchar (20), 
	`T620ReteRenta2`			varchar (20), 
	`T620PorcRenta3`			varchar (20), 
	`T620ReteRenta3`			varchar (20), 
	`T620CtaDescuento`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T620CONCEPTOCONTAB` ADD PRIMARY KEY (`T620CodEmpresa`, `T620Agno`, `T620CodGrupo`, `T620CodProceso`, `T620TipoTransaccion`, `T620CodTipoDocContab`);

CREATE TABLE `T621GRUPOCONTAB`
 (
	`T621Codigo`			varchar (5), 
	`T621Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T621GRUPOCONTAB` ADD PRIMARY KEY (`T621Codigo`);

CREATE TABLE `T622CONCEPTOCONTAB`
 (
	`T622Codigo`			varchar (5), 
	`T622Nombre`			varchar (30), 
	`T622TipoDocContab`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T622CONCEPTOCONTAB` ADD PRIMARY KEY (`T622Codigo`);

CREATE TABLE `T624SUBCONCEPTOCONTAB`
 (
	`T624Codigo`			varchar (5), 
	`T624Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T624SUBCONCEPTOCONTAB` ADD PRIMARY KEY (`T624Codigo`);

CREATE TABLE `T625VENDEDOR`
 (
	`T625Codigo`			varchar (5), 
	`T625Nombre`			varchar (30), 
	`T625Documento`			varchar (20), 
	`T625Activo`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T625VENDEDOR` ADD PRIMARY KEY (`T625Codigo`);

CREATE TABLE `T626ABONO`
 (
	`T626CodEmpresa`			varchar (5), 
	`T626NumAbono`			varchar (5), 
	`T626Prefijo`			varchar (5), 
	`T626NumFactura`			varchar (10), 
	`T626Fecha`			varchar (10), 
	`T626Valor`			varchar (15), 
	`T626CodBanco`			varchar (20), 
	`T626NumDoc`			varchar (5), 
	`T626CodTercero`			varchar (15), 
	`T626Observacion`			varchar (255), 
	`T626TotalDescuentos`			varchar (15), 
	`T626AgnoFactura`			varchar (4), 
	`T626ValorDeudaAnt`			varchar (15), 
	`T626ValorPagadoAnt`			varchar (15), 
	`T626ValorSaloAnt`			varchar (15), 
	`T626Digita`			varchar (20), 
	`T626FechaVence`			varchar (10), 
	`T626Vendedor`			varchar (20), 
	`T626FormaPago`			varchar (30), 
	`T626Retencion`			varchar (15), 
	`T626Multa`			varchar (20), 
	`T626TipoAbono`			varchar (5), 
	`T626Folio`			varchar (20), 
	`T626RetencionICA`			varchar (20), 
	`T626RetencionIVA`			varchar (20), 
	`T626PrefijoAbono`			varchar (5), 
	`T626Cobrador`			varchar (20), 
	`T626Hora`			varchar (5), 
	`T626RetencionOtro`			varchar (20), 
	`T626PorcRetencion`			varchar (20), 
	`T626Referencia`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T626ABONO` ADD PRIMARY KEY (`T626CodEmpresa`, `T626NumAbono`, `T626Prefijo`, `T626NumFactura`, `T626PrefijoAbono`);
ALTER TABLE `T626ABONO` ADD INDEX `T626CodBanco` (`T626CodBanco`);

CREATE TABLE `T627BANCO`
 (
	`T627Codigo`			varchar (20) NOT NULL, 
	`T627Nombre`			varchar (30), 
	`T627Activo`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T627BANCO` ADD PRIMARY KEY (`T627Codigo`);

CREATE TABLE `T628ABONOCOMPRA`
 (
	`T628CodEmpresa`			varchar (5), 
	`T628NumAbono`			varchar (5), 
	`T628NumEntrada`			varchar (10), 
	`T628TipoTransaccion`			varchar (5), 
	`T628Fecha`			varchar (10), 
	`T628Valor`			varchar (15), 
	`T628CodBanco`			varchar (20), 
	`T628NumDoc`			varchar (5), 
	`T628CodTercero`			varchar (15), 
	`T628Observacion`			varchar (255), 
	`T628TotalDescuentos`			varchar (15), 
	`T628AgnoFactura`			varchar (4), 
	`T628ValorDeudaAnt`			varchar (15), 
	`T628ValorPagadoAnt`			varchar (15), 
	`T628ValorSaloAnt`			varchar (15), 
	`T628Digita`			varchar (20), 
	`T628FechaVence`			varchar (10), 
	`T628Vendedor`			varchar (20), 
	`T628FormaPago`			varchar (30), 
	`T628NumFactura`			varchar (20), 
	`T628Retencion`			varchar (15), 
	`T628TipoAbono`			varchar (5), 
	`T628RetencionICA`			varchar (20), 
	`T628RetencionIVA`			varchar (20), 
	`T628PrefijoAbono`			varchar (5), 
	`T628PorcRetencion`			varchar (20), 
	`T628Referencia`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T628ABONOCOMPRA` ADD PRIMARY KEY (`T628CodEmpresa`, `T628NumAbono`, `T628NumEntrada`, `T628TipoTransaccion`, `T628PrefijoAbono`);
ALTER TABLE `T628ABONOCOMPRA` ADD INDEX `T628CodBanco` (`T628CodBanco`);
ALTER TABLE `T628ABONOCOMPRA` ADD INDEX `T628Fecha` (`T628Fecha`);

CREATE TABLE `T629PREFIJO`
 (
	`T629Codigo`			varchar (20), 
	`T629Nombre`			varchar (30), 
	`T629Activo`			varchar (1), 
	`T629FactElectro`			varchar (1), 
	`T629Tipo`			varchar (5), 
	`T629FactContin`			varchar (1), 
	`T629PosElectro`			varchar (1), 
	`T629Proveedor`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T629PREFIJO` ADD PRIMARY KEY (`T629Codigo`);

CREATE TABLE `T630LISTAVALORES`
 (
	`T630CodEmpresa`			varchar (5), 
	`T630CodTemporada`			varchar (5), 
	`T630CodConcepto`			varchar (20), 
	`T630Codigo`			varchar (5), 
	`T630Valor`			varchar (15), 
	`T630ValorIVA`			varchar (15), 
	`T630CodTipoIVA`			varchar (5), 
	`T630PorcInc`			varchar (15), 
	`T630PorcDec`			varchar (15), 
	`T630PorcRentab`			varchar (20), 
	`T630ValorIPCO`			varchar (10)
);

-- CREATE INDEXES ...
ALTER TABLE `T630LISTAVALORES` ADD PRIMARY KEY (`T630CodEmpresa`, `T630CodTemporada`, `T630CodConcepto`, `T630Codigo`);
ALTER TABLE `T630LISTAVALORES` ADD INDEX `T630CodConcepto` (`T630CodConcepto`);
ALTER TABLE `T630LISTAVALORES` ADD INDEX `T630Codigo` (`T630Codigo`);

CREATE TABLE `T632CONFIGURACLIENTE`
 (
	`T632CodEmpresa`			varchar (5), 
	`T632CodTercero`			varchar (15), 
	`T632CodConcepto`			varchar (20), 
	`T632Cantidad`			varchar (5), 
	`T632Valor`			varchar (15), 
	`T632ValorIVA`			varchar (15), 
	`T632SubCodConcepto`			varchar (5), 
	`T632Descuento`			varchar (15), 
	`T632Prefijo`			varchar (5), 
	`T632Vendedor`			varchar (15), 
	`T632CodFormaPago`			varchar (5), 
	`T632Activo`			varchar (2), 
	`T632DiaDescuento1`			varchar (20), 
	`T632ValorDescuento1`			varchar (20), 
	`T632DiaDescuento2`			varchar (20), 
	`T632ValorDescuento2`			varchar (20), 
	`T632DiaDescuento3`			varchar (20), 
	`T632ValorDescuento3`			varchar (20), 
	`T632Coeficiente`			varchar (5), 
	`T632TipoCoeficiente`			varchar (5), 
	`T632PorcDescuento1`			varchar (10), 
	`T632PorcDescuento2`			varchar (10), 
	`T632PorcDescuento3`			varchar (10), 
	`T632CodPeriodo`			varchar (5), 
	`T632DiaMulta1`			varchar (20), 
	`T632ValorMulta1`			varchar (20), 
	`T632PorcMulta1`			varchar (20), 
	`T632DiaMulta2`			varchar (20), 
	`T632ValorMulta2`			varchar (20), 
	`T632PorcMulta2`			varchar (20), 
	`T632DiaMulta3`			varchar (20), 
	`T632ValorMulta3`			varchar (20), 
	`T632PorcMulta3`			varchar (20), 
	`T632ValorMulta`			varchar (20), 
	`T632LiqInteres`			varchar (1), 
	`T632Ciclo`			varchar (5), 
	`T632Orden`			varchar (10), 
	`T632FechaIni`			varchar (10), 
	`T632FechaFin`			varchar (10), 
	`T632Cuotas`			varchar (3), 
	`T632ValorTotal`			varchar (20), 
	`T632ValorTotalIVA`			varchar (20), 
	`T632Concepto`			varchar (255), 
	`T632Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T632CONFIGURACLIENTE` ADD PRIMARY KEY (`T632CodEmpresa`, `T632CodTercero`, `T632CodConcepto`);

CREATE TABLE `T633TRASLADO`
 (
	`T633CodEmpresa`			varchar (5), 
	`T633Agno`			varchar (4), 
	`T633Numero`			varchar (5), 
	`T633Fecha`			varchar (10), 
	`T633ValorTotal`			varchar (15), 
	`T633Anular`			varchar (1), 
	`T633Concepto`			varchar (255), 
	`T633NumEntrada`			varchar (20), 
	`T633NumSalida`			varchar (20), 
	`T633Digita`			varchar (20), 
	`T634NumEnvio`			varchar (15), 
	`T634NumConfirmacion`			varchar (15), 
	`T633CodTercero`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T633TRASLADO` ADD PRIMARY KEY (`T633CodEmpresa`, `T633Agno`, `T633Numero`);

CREATE TABLE `T634TRASLADOMOV`
 (
	`T634CodEmpresa`			varchar (5), 
	`T634Agno`			varchar (4), 
	`T634NumeroDoc`			varchar (5), 
	`T634Consecutivo`			varchar (5), 
	`T634CodArticuloE`			varchar (20), 
	`T634CantidadE`			varchar (10), 
	`T634ValorArticuloE`			varchar (15), 
	`T634ValorIVAE`			varchar (15), 
	`T634SubCodConceptoE`			varchar (5), 
	`T634CodCentroE`			varchar (20), 
	`T634CodArticuloS`			varchar (20), 
	`T634CantidadS`			varchar (10), 
	`T634ValorArticuloS`			varchar (20), 
	`T634ValorIVAS`			varchar (20), 
	`T634SubCodConceptoS`			varchar (20), 
	`T634CodCentroS`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T634TRASLADOMOV` ADD PRIMARY KEY (`T634CodEmpresa`, `T634Agno`, `T634NumeroDoc`, `T634Consecutivo`);

CREATE TABLE `T635ORDENPEDIDO`
 (
	`T635CodEmpresa`			varchar (5), 
	`T635Agno`			varchar (4), 
	`T635NumeroDoc`			varchar (5), 
	`T635Fecha`			varchar (10), 
	`T635CodProveedor`			varchar (15), 
	`T635ValorBase`			varchar (15), 
	`T635ValorIVA`			varchar (15), 
	`T635ValorDescuento`			varchar (15), 
	`T635ValorTtFactura`			varchar (15), 
	`T635FormaPago`			varchar (5), 
	`T635Concepto`			text, 
	`T635TipoTransaccion`			varchar (5), 
	`T635NumEntrada`			varchar (10), 
	`T635PorcRenta`			varchar (10), 
	`T635ReteRenta`			varchar (20), 
	`T635PorcICA`			varchar (10), 
	`T635ReteICA`			varchar (20), 
	`T635PorcIVA`			varchar (10), 
	`T635ReteIVA`			varchar (20), 
	`T635PorcOtrosDesc`			varchar (10), 
	`T635OtroDescuento`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T635ORDENPEDIDO` ADD PRIMARY KEY (`T635CodEmpresa`, `T635Agno`, `T635NumeroDoc`);

CREATE TABLE `T636ORDENPEDIDOMOV`
 (
	`T636CodEmpresa`			varchar (5), 
	`T636Agno`			varchar (4), 
	`T636NumeroDoc`			varchar (5), 
	`T636CodArticulo`			varchar (20), 
	`T636Consecutivo`			varchar (5), 
	`T636Cantidad`			varchar (10), 
	`T636ValorArticulo`			varchar (15), 
	`T636ValorDescuento`			varchar (15), 
	`T636ValorIVA`			varchar (15), 
	`T636SubCodConcepto`			varchar (5), 
	`T636CodCentro`			varchar (20), 
	`T636PorcIVA`			varchar (15), 
	`T636FechaIni`			varchar (10), 
	`T636FechaFin`			varchar (10), 
	`T636CodMetro2`			varchar (20), 
	`T636NumMetro2`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T636ORDENPEDIDOMOV` ADD PRIMARY KEY (`T636CodEmpresa`, `T636Agno`, `T636NumeroDoc`, `T636CodArticulo`, `T636Consecutivo`);

CREATE TABLE `T638COTIZACION`
 (
	`T638CodEmpresa`			varchar (5), 
	`T638Prefijo`			varchar (5), 
	`T638NumFactura`			varchar (10), 
	`T638Fecha`			varchar (10), 
	`T638CodTercero`			varchar (15), 
	`T638Total`			varchar (15), 
	`T638TotalIVA`			varchar (15), 
	`T638TotalDescuento`			varchar (15), 
	`T638CodFormaPago`			varchar (5), 
	`T638Detalle`			varchar (100), 
	`T638Cancelado`			varchar (1), 
	`T638FechaIni`			varchar (10), 
	`T638HoraIni`			varchar (10), 
	`T638FechaFin`			varchar (10), 
	`T638HoraFin`			varchar (10), 
	`T638TiempoFactura`			varchar (10), 
	`T638Piso`			varchar (5), 
	`T638Area`			varchar (5), 
	`T638Habitacion`			varchar (5), 
	`T638FechaVence`			varchar (10), 
	`T638Vendedor`			varchar (15), 
	`T638Digita`			varchar (20), 
	`T638PorcRetencion`			varchar (15), 
	`T638Retencion`			varchar (15)
);

-- CREATE INDEXES ...
ALTER TABLE `T638COTIZACION` ADD PRIMARY KEY (`T638CodEmpresa`, `T638Prefijo`, `T638NumFactura`, `T638Digita`);

CREATE TABLE `T639CONTIZADETALLE`
 (
	`T639CodEmpresa`			varchar (5), 
	`T639Prefijo`			varchar (5), 
	`T639NumFactura`			varchar (10), 
	`T639Consecutivo`			varchar (5), 
	`T639Cantidad`			varchar (5), 
	`T639CodConcepto`			varchar (20), 
	`T639Valor`			varchar (15), 
	`T639ValorIVA`			varchar (15), 
	`T639SubCodConcepto`			varchar (5), 
	`T639Descuento`			varchar (15), 
	`T639CodCentro`			varchar (20), 
	`T639Digita`			varchar (20), 
	`T639PorcIVA`			varchar (15), 
	`T639Observacion`			text, 
	`T639FechaVence`			varchar (10), 
	`T639Lote`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T639CONTIZADETALLE` ADD PRIMARY KEY (`T639CodEmpresa`, `T639Prefijo`, `T639NumFactura`, `T639Consecutivo`, `T639Digita`);

CREATE TABLE `T640CONTROLHORARIO`
 (
	`T640CodEmpresa`			varchar (5), 
	`T640Nit`			varchar (15), 
	`T640Fecha`			varchar (10), 
	`T640Hora`			varchar (10), 
	`T640Evento`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T640CONTROLHORARIO` ADD PRIMARY KEY (`T640CodEmpresa`, `T640Nit`, `T640Fecha`, `T640Hora`);

CREATE TABLE `T641TIPOIVA`
 (
	`T641Codigo`			varchar (20), 
	`T641Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T641TIPOIVA` ADD PRIMARY KEY (`T641Codigo`);

CREATE TABLE `T642LICENCIAS`
 (
	`T642Consecutivo`			varchar (10), 
	`T642CodSoftware`			varchar (20), 
	`T642NumeroLicencia`			varchar (30), 
	`T642TipoLicencia`			varchar (5), 
	`T642CodCliente`			varchar (20), 
	`T642FechaExpide`			varchar (10), 
	`T642FechaInstala`			varchar (10), 
	`T642TiempoSoporte`			varchar (5), 
	`T642Valor`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T642LICENCIAS` ADD PRIMARY KEY (`T642Consecutivo`);

CREATE TABLE `T642LINEAPRODUCTO`
 (
	`T642Codigo`			varchar (20), 
	`T642Nombre`			varchar (30), 
	`T642PorcTara`			varchar (10), 
	`T642Broca`			varchar (10), 
	`T642Humedad`			varchar (10), 
	`T642FR`			varchar (10)
);

-- CREATE INDEXES ...

CREATE TABLE `T643SOFTWARE`
 (
	`T643Codigo`			varchar (20), 
	`T643Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T643SOFTWARE` ADD PRIMARY KEY (`T643Codigo`);

CREATE TABLE `T644COLORPRODUCTO`
 (
	`T644Codigo`			varchar (20), 
	`T644Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T645TALLAPRODUCTO`
 (
	`T645Codigo`			varchar (20), 
	`T645Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T646ORDENTRABAJO`
 (
	`T646CodEmpresa`			varchar (5), 
	`T646OrdenTrabajo`			varchar (10), 
	`T646Fecha`			varchar (10), 
	`T646CodTercero`			varchar (15), 
	`T646CodFormaPago`			varchar (5), 
	`T646Responsable`			varchar (255), 
	`T646Proyecto`			varchar (255), 
	`T646Total`			varchar (15), 
	`T646TotalAnticipo`			varchar (15), 
	`T646Saldo`			varchar (15), 
	`T646Detalle`			varchar (255), 
	`T646Cancelado`			varchar (1), 
	`T646Elaboro`			varchar (15), 
	`T646MatSuficiente`			varchar (1), 
	`T646Validacion`			varchar (1), 
	`T646CantPoroso`			varchar (5), 
	`T646CantDesportillado`			varchar (5), 
	`T646CantConforme`			varchar (5), 
	`T646IdentificaMuestra`			varchar (1), 
	`T646ComoIdentifica`			varchar (100), 
	`T646FormaTransporte`			varchar (255), 
	`T646Facturar`			varchar (1), 
	`T646InformeEntregado`			varchar (1), 
	`T646TipoSolicitud`			varchar (5), 
	`T646NumSolicitud`			varchar (15), 
	`T646FechaInfEntregado`			varchar (10), 
	`T646FechaEntrega`			varchar (10), 
	`T646NumFactura`			varchar (15), 
	`T646Anular`			varchar (1), 
	`T646Cargo`			varchar (5), 
	`T646NumInforme`			varchar (15), 
	`T646Impresa`			varchar (1), 
	`T646Copago`			varchar (1), 
	`T646Placa`			varchar (10), 
	`T646Marca`			varchar (100), 
	`T646Linea`			varchar (50), 
	`T646Cilindraje`			varchar (20), 
	`T646Potencia`			varchar (10), 
	`T646Modelo`			varchar (5), 
	`T646Color`			varchar (20), 
	`T646Servicio`			varchar (20), 
	`T646ClaseVehiculo`			varchar (20), 
	`T646Carroceria`			varchar (20), 
	`T646NoPuertas`			varchar (2), 
	`T646Motor`			varchar (100), 
	`T646Serie`			varchar (20), 
	`T646Chasis`			varchar (30), 
	`T646KmIni`			varchar (20), 
	`T646KmFin`			varchar (20), 
	`T646Foto1`			varchar (255), 
	`T646Foto2`			varchar (255), 
	`T646Foto3`			varchar (255), 
	`T646Foto4`			varchar (255), 
	`T646Foto5`			varchar (255), 
	`T646Foto6`			varchar (255), 
	`T646TipoOrden`			varchar (5)
);

-- CREATE INDEXES ...

CREATE TABLE `T646PLANTRABAJO`
 (
	`T646CodEmpresa`			varchar (5), 
	`T646OrdenTrabajo`			varchar (10), 
	`T646Fecha`			varchar (10), 
	`T646CodTercero`			varchar (15), 
	`T646CodFormaPago`			varchar (5), 
	`T646Responsable`			varchar (255), 
	`T646Proyecto`			varchar (255), 
	`T646Total`			varchar (15), 
	`T646TotalAnticipo`			varchar (15), 
	`T646Saldo`			varchar (15), 
	`T646Detalle`			varchar (255), 
	`T646Cancelado`			varchar (1), 
	`T646Elaboro`			varchar (15), 
	`T646MatSuficiente`			varchar (1), 
	`T646Validacion`			varchar (1), 
	`T646CantPoroso`			varchar (5), 
	`T646CantDesportillado`			varchar (5), 
	`T646CantConforme`			varchar (5), 
	`T646IdentificaMuestra`			varchar (1), 
	`T646ComoIdentifica`			varchar (100), 
	`T646FormaTransporte`			varchar (255), 
	`T646Facturar`			varchar (1), 
	`T646InformeEntregado`			varchar (1), 
	`T646TipoSolicitud`			varchar (5), 
	`T646NumSolicitud`			varchar (15), 
	`T646FechaInfEntregado`			varchar (10), 
	`T646FechaEntrega`			varchar (10), 
	`T646NumFactura`			varchar (15), 
	`T646Anular`			varchar (1), 
	`T646Cargo`			varchar (5), 
	`T646NumInforme`			varchar (15), 
	`T646Impresa`			varchar (1), 
	`T646Copago`			varchar (1)
);

-- CREATE INDEXES ...

CREATE TABLE `T647ABONODETALLE`
 (
	`T647CodEmpresa`			varchar (5), 
	`T647NumAbono`			varchar (5), 
	`T647Prefijo`			varchar (5), 
	`T647NumFactura`			varchar (10), 
	`T647CodConcepto`			varchar (10), 
	`T647Valor`			varchar (15), 
	`T647Descuento`			varchar (15), 
	`T647ValorPagado`			varchar (15), 
	`T647Saldo`			varchar (15), 
	`T647Mes`			varchar (20), 
	`T647Multa`			varchar (20), 
	`T647PrefijoAbono`			varchar (5), 
	`T647Retencion`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T647ABONODETALLE` ADD PRIMARY KEY (`T647CodEmpresa`, `T647NumAbono`, `T647Prefijo`, `T647NumFactura`, `T647CodConcepto`, `T647PrefijoAbono`);

CREATE TABLE `T647ORDENDETALLE`
 (
	`T647CodEmpresa`			varchar (5), 
	`T647OrdenTrabajo`			varchar (10), 
	`T647Consecutivo`			varchar (5), 
	`T647CodConcepto`			varchar (20), 
	`T647Cantidad`			varchar (5), 
	`T647ListaValor`			varchar (5), 
	`T647Valor`			varchar (15), 
	`T647Descuento`			varchar (15), 
	`T647Cantidad1`			varchar (10), 
	`T647Observacion`			varchar (250), 
	`T647Vendedor`			varchar (20), 
	`T647FechaIng`			varchar (10), 
	`T647FechaSale`			varchar (10), 
	`T647Detalle`			varchar (255), 
	`T647ValorIVA`			varchar (20), 
	`T647PorcenIVA`			varchar (20), 
	`T647TipoOrden`			varchar (5), 
	`T647Observa2`			varchar (100), 
	`T647Observa3`			varchar (100), 
	`T647Observa4`			varchar (100)
);

-- CREATE INDEXES ...

CREATE TABLE `T647PLANDETALLE`
 (
	`T647CodEmpresa`			varchar (5), 
	`T647OrdenTrabajo`			varchar (10), 
	`T647Consecutivo`			varchar (5), 
	`T647CodConcepto`			varchar (20), 
	`T647Cantidad`			varchar (5), 
	`T647ListaValor`			varchar (5), 
	`T647Valor`			varchar (15), 
	`T647Descuento`			varchar (15), 
	`T647Cantidad1`			varchar (10), 
	`T647Observacion`			varchar (250)
);

-- CREATE INDEXES ...

CREATE TABLE `T649ORDENOTROS`
 (
	`T649CodEmpresa`			varchar (5), 
	`T649OrdenTrabajo`			varchar (10), 
	`T649Consecutivo`			varchar (5), 
	`T649FechaToma`			varchar (10), 
	`T649Elemento`			varchar (255), 
	`T649Diseno`			varchar (50), 
	`T649CantEdad7`			varchar (5), 
	`T649CantEdad14`			varchar (5), 
	`T649CantEdad28`			varchar (5), 
	`T649CantEdadOtros`			varchar (50), 
	`T649EnsayoRealiza`			varchar (255), 
	`T649TipoElemento`			varchar (5), 
	`T649TipoDiseno`			varchar (5), 
	`T649TipoOrden`			varchar (5)
);

-- CREATE INDEXES ...

CREATE TABLE `T651TIPOVALORESCOEFICIENTE`
 (
	`T651Codigo`			varchar (20), 
	`T651Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T652ORDENTIPODISENO`
 (
	`T652Codigo`			varchar (20), 
	`T652Nombre`			varchar (100)
);

-- CREATE INDEXES ...

CREATE TABLE `T653ORDENTIPOELEMENTO`
 (
	`T653Codigo`			varchar (20), 
	`T653Nombre`			varchar (100)
);

-- CREATE INDEXES ...

CREATE TABLE `T654RECOGERCAJA`
 (
	`T654CodEmpresa`			varchar (5) NOT NULL, 
	`T654Numero`			varchar (20) NOT NULL, 
	`T654Fecha`			varchar (10), 
	`T654Hora`			varchar (8), 
	`T654Vendedor`			varchar (5), 
	`T654Valor`			varchar (20), 
	`T654Usuario`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T654RECOGERCAJA` ADD PRIMARY KEY (`T654CodEmpresa`, `T654Numero`);

CREATE TABLE `T655CONCEPTORECETA`
 (
	`T655CodEmpresa`			varchar (5) NOT NULL, 
	`T655CodConcepto`			varchar (20), 
	`T655ConceptoReceta`			varchar (20), 
	`T655Cantidad`			varchar (20), 
	`T655Valor`			varchar (20), 
	`T655Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T655CONCEPTORECETA` ADD PRIMARY KEY (`T655CodEmpresa`, `T655CodConcepto`, `T655ConceptoReceta`);

CREATE TABLE `T656CONDUCTOR`
 (
	`T656Codigo`			varchar (5) NOT NULL, 
	`T656Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T656CONDUCTOR` ADD PRIMARY KEY (`T656Codigo`);

CREATE TABLE `T657TIPOGLOSA`
 (
	`T657Codigo`			varchar (5) NOT NULL, 
	`T657Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T657TIPOGLOSA` ADD PRIMARY KEY (`T657Codigo`);

CREATE TABLE `T659AUDITCIERRE`
 (
	`T659Usuario`			varchar (20) NOT NULL, 
	`T659FechaHora`			varchar (20) NOT NULL, 
	`T659Venta`			varchar (20) NOT NULL, 
	`T659Base`			varchar (20) NOT NULL
);

-- CREATE INDEXES ...

CREATE TABLE `T660TIQUETEMOLINO`
 (
	`T660NumTiquete`			varchar (10) NOT NULL, 
	`T660Placa`			varchar (10), 
	`T660PesoBruto`			varchar (10), 
	`T660PesoTara`			varchar (10), 
	`T660PorcHumedad`			varchar (10), 
	`T660PorcImpureza`			varchar (10), 
	`T660Neto25_5`			varchar (20), 
	`T660Precio`			varchar (20), 
	`T660FechaEntrada`			varchar (20), 
	`T660FechaSalida`			varchar (20), 
	`T660CodProveedor`			varchar (20), 
	`T660Conductor`			varchar (50), 
	`T660Procedencia`			varchar (20), 
	`T660CodConcepto`			varchar (20), 
	`T660Detalle`			varchar (255), 
	`T660Observacion`			varchar (255), 
	`T660NumLiquida`			varchar (20), 
	`T660TipoEntrada`			varchar (20), 
	`T660Variedad`			varchar (100), 
	`T660GranoPartido`			varchar (100), 
	`T660ValorFlete`			varchar (20), 
	`T660ValorDescargue`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T660TIQUETEMOLINO` ADD PRIMARY KEY (`T660NumTiquete`);

CREATE TABLE `T661TIQUETELABORATO`
 (
	`T661NumTiquete`			varchar (10) NOT NULL, 
	`T661Fecha`			varchar (20), 
	`T661PorcHumedad`			varchar (10), 
	`T661PorcImpureza`			varchar (10), 
	`T661PE`			varchar (10), 
	`T661TempGrano`			varchar (10), 
	`T661NumEstufa`			varchar (10), 
	`T661PesoIni`			varchar (20), 
	`T661PesoIni2`			varchar (20), 
	`T661ValorM`			varchar (10), 
	`T661MuestraHora1`			varchar (10), 
	`T661MuestraFecha1`			varchar (10), 
	`T661MuestraHumedad1`			varchar (10), 
	`T661MuestraHora2`			varchar (10), 
	`T661MuestraFecha2`			varchar (10), 
	`T661MuestraHumedad2`			varchar (10), 
	`T661MuestraHora3`			varchar (10), 
	`T661MuestraFecha3`			varchar (10), 
	`T661MuestraHumedad3`			varchar (10), 
	`T661Integral`			varchar (10), 
	`T661Cascarilla`			varchar (10), 
	`T661Blanco`			varchar (10), 
	`T661ExcelsoIP`			varchar (10), 
	`T661Partido`			varchar (10), 
	`T661Harina`			varchar (10), 
	`T661Yeso`			varchar (10), 
	`T661GranoDanado`			varchar (10), 
	`T661Infestacion`			varchar (10), 
	`T661CodEvaluador`			varchar (20), 
	`T661Observacion`			varchar (255), 
	`T661Ambamarino`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T661TIQUETELABORATO` ADD PRIMARY KEY (`T661NumTiquete`);

CREATE TABLE `T662LIQUIDA`
 (
	`T662Numero`			varchar (20) NOT NULL, 
	`T662Fecha`			varchar (10), 
	`T662FechaPago`			varchar (10), 
	`T662CodCliente`			varchar (20), 
	`T662Impureza`			varchar (20), 
	`T662Humedad`			varchar (20), 
	`T662IP`			varchar (20), 
	`T662Yeso`			varchar (20), 
	`T662PuntoIP`			varchar (20), 
	`T662PuntoYeso`			varchar (20), 
	`T662KiloBruto`			varchar (20), 
	`T662DescKilo`			varchar (20), 
	`T662ValorSubTotal`			varchar (20), 
	`T662ValorTotal`			varchar (20), 
	`T662DescFomento`			varchar (20), 
	`T662PorcDescFomento`			varchar (20), 
	`T662DescBolsa`			varchar (20), 
	`T662PorcDescBolsa`			varchar (20), 
	`T662DescRete`			varchar (20), 
	`T662PorcDescRete`			varchar (20), 
	`T662DescDescargue`			varchar (20), 
	`T662PorcDescDescargue`			varchar (20), 
	`T662DescFlete`			varchar (20), 
	`T662PorcDescFlete`			varchar (20), 
	`T662DescAnticipo`			varchar (20), 
	`T662PorcDescAnticipo`			varchar (20), 
	`T662DescOtro`			varchar (20), 
	`T662PorcDescOtro`			varchar (20), 
	`T662Digita`			varchar (20), 
	`T662Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T662LIQUIDA` ADD PRIMARY KEY (`T662Numero`);

CREATE TABLE `T663LIQUIDADET`
 (
	`T663Numero`			varchar (20) NOT NULL, 
	`T663Consecutivo`			varchar (20) NOT NULL, 
	`T663Tiquete`			varchar (20), 
	`T663Fecha`			varchar (10), 
	`T663KiloBruto`			varchar (20), 
	`T663PorcHumedad`			varchar (20), 
	`T663PorcImpureza`			varchar (20), 
	`T663PorcIP`			varchar (20), 
	`T663PorcYeso`			varchar (20), 
	`T663Descuento`			varchar (20), 
	`T663KilosAPagar`			varchar (20), 
	`T663ValorKiloIni`			varchar (20), 
	`T663DescIPYeso`			varchar (20), 
	`T663ValorKiloFin`			varchar (20), 
	`T663ValorViaje`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T663LIQUIDADET` ADD PRIMARY KEY (`T663Numero`, `T663Consecutivo`);

CREATE TABLE `T665COBRADOR`
 (
	`T665Codigo`			varchar (20) NOT NULL, 
	`T665Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T665COBRADOR` ADD PRIMARY KEY (`T665Codigo`);

CREATE TABLE `T667DEPRECIACION`
 (
	`T667CodEmpresa`			varchar (5) NOT NULL, 
	`T667Mes`			varchar (5) NOT NULL, 
	`T667CodArticulo`			varchar (20) NOT NULL, 
	`T667FechaCompra`			varchar (10), 
	`T667ValorCompra`			varchar (20), 
	`T667ValorDeprecia`			varchar (20), 
	`T667Agno`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T667DEPRECIACION` ADD PRIMARY KEY (`T667CodEmpresa`, `T667Agno`, `T667Mes`, `T667CodArticulo`);

CREATE TABLE `T668CPTOHISTORIAL`
 (
	`T668CodConcepto`			varchar (20) NOT NULL, 
	`T668Numero`			varchar (20) NOT NULL, 
	`T668TipoHistorial`			varchar (5) NOT NULL, 
	`T668Fecha`			varchar (10) NOT NULL, 
	`T668Observacion`			varchar (255), 
	`T668Digita`			varchar (20), 
	`T668Mostrar`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T668CPTOHISTORIAL` ADD PRIMARY KEY (`T668CodConcepto`, `T668Numero`);

CREATE TABLE `T669TIPOHISTORIAL`
 (
	`T669Codigo`			varchar (5) NOT NULL, 
	`T669Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T669TIPOHISTORIAL` ADD PRIMARY KEY (`T669Codigo`);

CREATE TABLE `T670PREVIOTIQ`
 (
	`T670Numero`			varchar (10) NOT NULL, 
	`T670Fecha`			varchar (10), 
	`T670Variedad`			varchar (100), 
	`T670Placa`			varchar (10), 
	`T670NumBultos`			varchar (10), 
	`T670PorcHumedadSuc`			varchar (10), 
	`T670PorcHumedadLim`			varchar (10), 
	`T670PorcImpureza`			varchar (10), 
	`T670TempGrano`			varchar (10), 
	`T670Observacion`			varchar (255), 
	`T670CodConcepto`			varchar (20), 
	`T670Conforme`			varchar (2)
);

-- CREATE INDEXES ...

CREATE TABLE `T671PQR`
 (
	`T671Numero`			varchar (10) NOT NULL, 
	`T671Fecha`			varchar (10), 
	`T671CodTercero`			varchar (20), 
	`T671TipoSoicitud`			varchar (20), 
	`T671CodArea`			varchar (10), 
	`T671Observacion`			varchar (255), 
	`T671Recibe`			varchar (100), 
	`T671Usuario`			varchar (20), 
	`T671CodEstado`			varchar (10)
);

-- CREATE INDEXES ...
ALTER TABLE `T671PQR` ADD PRIMARY KEY (`T671Numero`);

CREATE TABLE `T672SEGUIMIENPQR`
 (
	`T672NumPQR`			varchar (10) NOT NULL, 
	`T672Consecutivo`			varchar (10) NOT NULL, 
	`T672Fecha`			varchar (10), 
	`T672TipoSeguim`			varchar (5), 
	`T672Observacion`			varchar (255), 
	`T672Recibe`			varchar (100), 
	`T672Usuario`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T672SEGUIMIENPQR` ADD PRIMARY KEY (`T672NumPQR`, `T672Consecutivo`);

CREATE TABLE `T677FINANCIAR`
 (
	`T677CodEmpresa`			varchar (5) NOT NULL, 
	`T677Prefijo`			varchar (5) NOT NULL, 
	`T677NumFactura`			varchar (20) NOT NULL, 
	`T677Digita`			varchar (20) NOT NULL, 
	`T677Tipo`			varchar (20), 
	`T677Valor`			varchar (20), 
	`T677CuotaInicial`			varchar (20), 
	`T677Factor`			varchar (10), 
	`T677NumCuotas`			varchar (10), 
	`T677Cuota`			varchar (10), 
	`T677Capital`			varchar (20), 
	`T677Interes`			varchar (20), 
	`T677Mora`			varchar (20), 
	`T677PagadoCap`			varchar (20), 
	`T677PagadoInt`			varchar (20), 
	`T677PagadoMora`			varchar (20), 
	`T677Detalle`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T677FINANCIAR` ADD PRIMARY KEY (`T677CodEmpresa`, `T677Prefijo`, `T677NumFactura`, `T677Cuota`);

CREATE TABLE `T678CREDITO`
 (
	`T678CodEmpresa`			varchar (5) NOT NULL, 
	`T678Codigo`			varchar (20) NOT NULL, 
	`T678CodTercero`			varchar (20), 
	`T678TipoLinea`			varchar (5), 
	`T678PorcInteres`			varchar (20), 
	`T678PorcMora`			varchar (20), 
	`T678CapitalIni`			varchar (20), 
	`T678NumCuotas`			varchar (10), 
	`T678Detalle`			varchar (255), 
	`T678Fecha`			varchar (10), 
	`T678FechaCuota1`			varchar (10), 
	`T678PorcPoliza`			varchar (5), 
	`T678Desembolso`			varchar (20), 
	`T604FechaDesemb`			varchar (10)
);

-- CREATE INDEXES ...
ALTER TABLE `T678CREDITO` ADD PRIMARY KEY (`T678CodEmpresa`, `T678TipoLinea`, `T678Codigo`);

CREATE TABLE `T679CREDITODET`
 (
	`T679CodEmpresa`			varchar (5) NOT NULL, 
	`T679Codigo`			varchar (20) NOT NULL, 
	`T679NumCuota`			varchar (10) NOT NULL, 
	`T679Factura`			varchar (20), 
	`T679Capital`			varchar (20), 
	`T679Interes`			varchar (20), 
	`T679Mora`			varchar (20), 
	`T679Detalle`			varchar (255), 
	`T679Fecha`			varchar (10), 
	`T679TipoLinea`			varchar (5), 
	`T679Poliza`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T679CREDITODET` ADD PRIMARY KEY (`T679CodEmpresa`, `T679TipoLinea`, `T679Codigo`, `T679NumCuota`);

CREATE TABLE `T680TIPOCREDITO`
 (
	`T680Codigo`			varchar (5) NOT NULL, 
	`T680Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T680TIPOCREDITO` ADD PRIMARY KEY (`T680Codigo`);

CREATE TABLE `T681CONCEPTOVINCULA`
 (
	`T681CodEmpresa`			varchar (5) NOT NULL, 
	`T681CodConcepto`			varchar (20), 
	`T681CptoVinculado`			varchar (20), 
	`T681Cantidad`			varchar (20), 
	`T681Valor`			varchar (20), 
	`T681Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T681CONCEPTOVINCULA` ADD PRIMARY KEY (`T681CodEmpresa`, `T681CodConcepto`, `T681CptoVinculado`);

CREATE TABLE `T682SEGUIMIEQUIPO`
 (
	`T682CodEmpresa`			varchar (5) NOT NULL, 
	`T682Fecha`			varchar (10) NOT NULL, 
	`T682Consecutivo`			varchar (20) NOT NULL, 
	`T682CodOperador`			varchar (20), 
	`T682CodConcepto`			varchar (20), 
	`T682OdoIni`			varchar (20), 
	`T682OdoFin`			varchar (20), 
	`T682Estado`			varchar (5), 
	`T682Lugar`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T682SEGUIMIEQUIPO` ADD PRIMARY KEY (`T682CodEmpresa`, `T682Fecha`, `T682Consecutivo`);

CREATE TABLE `T684ORDENINFOTECNICA`
 (
	`T684CodEmpresa`			varchar (5) NOT NULL, 
	`T684Numero`			varchar (10) NOT NULL, 
	`T684Consecutivo`			varchar (10) NOT NULL, 
	`T684Fecha`			varchar (10), 
	`T684CodTecnico`			varchar (20), 
	`T684HoraIni`			varchar (10), 
	`T684HoraFin`			varchar (10), 
	`T684CantHH`			varchar (20), 
	`T684ValorHH`			varchar (20), 
	`T684ValorTotal`			varchar (20), 
	`T684Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T684ORDENINFOTECNICA` ADD PRIMARY KEY (`T684CodEmpresa`, `T684Numero`, `T684Consecutivo`);

CREATE TABLE `T685ORDENCAUSAFALLA`
 (
	`T685CodEmpresa`			varchar (5) NOT NULL, 
	`T685Numero`			varchar (10) NOT NULL, 
	`T685Consecutivo`			varchar (10) NOT NULL, 
	`T685TipoCausa`			varchar (10), 
	`T685Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T685ORDENCAUSAFALLA` ADD PRIMARY KEY (`T685CodEmpresa`, `T685Numero`, `T685Consecutivo`);

CREATE TABLE `T686ORDENMEDIDAS`
 (
	`T686CodEmpresa`			varchar (5) NOT NULL, 
	`T686Numero`			varchar (10) NOT NULL, 
	`T686Consecutivo`			varchar (10) NOT NULL, 
	`T686TipoMedida`			varchar (10), 
	`T686Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T686ORDENMEDIDAS` ADD PRIMARY KEY (`T686CodEmpresa`, `T686Numero`, `T686Consecutivo`);

CREATE TABLE `T687ORDENELEMENTOS`
 (
	`T687CodEmpresa`			varchar (5) NOT NULL, 
	`T687Numero`			varchar (10) NOT NULL, 
	`T687Consecutivo`			varchar (10) NOT NULL, 
	`T687NumFactura`			varchar (20), 
	`T687Cantidad`			varchar (20), 
	`T687CodUnidad`			varchar (20), 
	`T687Descripcion`			varchar (255), 
	`T687ValorUnit`			varchar (20), 
	`T687ValorTotal`			varchar (20), 
	`T687Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T687ORDENELEMENTOS` ADD PRIMARY KEY (`T687CodEmpresa`, `T687Numero`, `T687Consecutivo`);

CREATE TABLE `T688TIPOLABOR`
 (
	`T688CodEmpresa`			varchar (5) NOT NULL, 
	`T688Codigo`			varchar (10) NOT NULL, 
	`T688Nombre`			varchar (200), 
	`T688Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T688TIPOLABOR` ADD PRIMARY KEY (`T688CodEmpresa`, `T688Codigo`);

CREATE TABLE `T689TIPOMANTENIMIENTO`
 (
	`T689CodEmpresa`			varchar (5) NOT NULL, 
	`T689Codigo`			varchar (10) NOT NULL, 
	`T689Nombre`			varchar (200), 
	`T689Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T689TIPOMANTENIMIENTO` ADD PRIMARY KEY (`T689CodEmpresa`, `T689Codigo`);

CREATE TABLE `T690TIPOPARADA`
 (
	`T690CodEmpresa`			varchar (5) NOT NULL, 
	`T690Codigo`			varchar (10) NOT NULL, 
	`T690Nombre`			varchar (200), 
	`T690Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T690TIPOPARADA` ADD PRIMARY KEY (`T690CodEmpresa`, `T690Codigo`);

CREATE TABLE `T692TIPOMEDIDA`
 (
	`T692CodEmpresa`			varchar (5) NOT NULL, 
	`T692Codigo`			varchar (10) NOT NULL, 
	`T692Nombre`			varchar (200), 
	`T692Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T692TIPOMEDIDA` ADD PRIMARY KEY (`T692CodEmpresa`, `T692Codigo`);

CREATE TABLE `T693SOLICITACOSTO`
 (
	`T693CodEmpresa`			varchar (5) NOT NULL, 
	`T693Agno`			varchar (4) NOT NULL, 
	`T693NumeroDoc`			varchar (5) NOT NULL, 
	`T693Fecha`			varchar (10), 
	`T693CodProveedor`			varchar (15), 
	`T693ValorBase`			varchar (15), 
	`T693ValorIVA`			varchar (15), 
	`T693ValorDescuento`			varchar (15), 
	`T693ValorTtFactura`			varchar (15), 
	`T693FormaPago`			varchar (5), 
	`T693Concepto`			varchar (255), 
	`T693TipoTransaccion`			varchar (5), 
	`T693NumEntrada`			varchar (10), 
	`T693PorcRenta`			varchar (10), 
	`T693ReteRenta`			varchar (20), 
	`T693PorcICA`			varchar (10), 
	`T693ReteICA`			varchar (20), 
	`T693PorcIVA`			varchar (10), 
	`T693ReteIVA`			varchar (20), 
	`T693PorcOtrosDesc`			varchar (10), 
	`T693OtroDescuento`			varchar (20), 
	`T693CodProveedor1`			varchar (15), 
	`T693CodProveedor2`			varchar (15), 
	`T693CodProveedor3`			varchar (15), 
	`T693CodProveedor4`			varchar (15)
);

-- CREATE INDEXES ...
ALTER TABLE `T693SOLICITACOSTO` ADD PRIMARY KEY (`T693CodEmpresa`, `T693Agno`, `T693NumeroDoc`);

CREATE TABLE `T694SOLICITACOSTOMOV`
 (
	`T694CodEmpresa`			varchar (5) NOT NULL, 
	`T694Agno`			varchar (4) NOT NULL, 
	`T694NumeroDoc`			varchar (5) NOT NULL, 
	`T694CodArticulo`			varchar (20) NOT NULL, 
	`T694Consecutivo`			varchar (5) NOT NULL, 
	`T694Cantidad`			varchar (10), 
	`T694ValorArticulo`			varchar (15), 
	`T694ValorDescuento`			varchar (15), 
	`T694ValorIVA`			varchar (15), 
	`T694SubCodConcepto`			varchar (5), 
	`T694CodCentro`			varchar (20), 
	`T694PorcIVA`			varchar (15), 
	`T694FechaIni`			varchar (10), 
	`T694FechaFin`			varchar (10), 
	`T694CodMetro2`			varchar (20), 
	`T694NumMetro2`			varchar (20), 
	`T694ValorArticulo1`			varchar (20), 
	`T694ValorArticulo2`			varchar (20), 
	`T694ValorArticulo3`			varchar (20), 
	`T694ValorArticulo4`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T694SOLICITACOSTOMOV` ADD PRIMARY KEY (`T694CodEmpresa`, `T694Agno`, `T694NumeroDoc`, `T694CodArticulo`, `T694Consecutivo`);

CREATE TABLE `T695TIPOIVA`
 (
	`T695Codigo`			varchar (5) NOT NULL, 
	`T695Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T695TIPOIVA` ADD PRIMARY KEY (`T695Codigo`);

CREATE TABLE `T696CIERREFACTURA`
 (
	`T696CodEmpresa`			varchar (5) NOT NULL, 
	`T696Vendedor`			varchar (5) NOT NULL, 
	`T696Fecha`			varchar (10) NOT NULL, 
	`T696Base`			varchar (20), 
	`T696Venta`			varchar (20), 
	`T696Detalle`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T696CIERREFACTURA` ADD PRIMARY KEY (`T696CodEmpresa`, `T696Vendedor`, `T696Fecha`);

CREATE TABLE `T698PAGO`
 (
	`T698IdDispositivo`			varchar (20) NOT NULL, 
	`T698CodInterno`			varchar (20) NOT NULL, 
	`T698FechaHora`			varchar (20), 
	`T698Documento`			varchar (20), 
	`T698Nombre`			varchar (255), 
	`T698Telefono`			varchar (20), 
	`T698Foto`			varchar (255), 
	`T698Detalle`			varchar (255), 
	`T698Nombre1`			varchar (20), 
	`T698Apellido`			varchar (20), 
	`T698Apellido1`			varchar (20), 
	`T698HostingEmail`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T698PAGO` ADD PRIMARY KEY (`T698IdDispositivo`, `T698CodInterno`);

CREATE TABLE `T699PAGODETALLE`
 (
	`T699IdDispositivo`			varchar (20) NOT NULL, 
	`T699CodInterno`			varchar (20) NOT NULL, 
	`T699Consecutivo`			varchar (20) NOT NULL, 
	`T699FechaHora`			varchar (20) NOT NULL, 
	`T699CodEmpresaVende`			varchar (20) NOT NULL, 
	`T699NombreEmpresa`			varchar (255) NOT NULL, 
	`T699Prefijo`			varchar (5) NOT NULL, 
	`T699NumFactura`			varchar (20) NOT NULL, 
	`T699ValorRecarga`			varchar (20), 
	`T699ValorVenta`			varchar (20), 
	`T699Usuario`			varchar (255), 
	`T699Equipo`			varchar (255), 
	`T699Detalle`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T699PAGODETALLE` ADD PRIMARY KEY (`T699IdDispositivo`, `T699CodInterno`, `T699Consecutivo`);

CREATE TABLE `T700RECIBO`
 (
	`T700CodEmpresa`			varchar (5), 
	`T700NumRecibo`			varchar (5), 
	`T700Prefijo`			varchar (5), 
	`T700NumFactura`			varchar (10), 
	`T700CodTercero`			varchar (15), 
	`T700Fecha`			varchar (10), 
	`T700Valor`			varchar (15), 
	`T700Automatico`			varchar (2), 
	`T700Pagado`			varchar (2), 
	`T700NumAbono`			varchar (20), 
	`T700Activo`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T700RECIBO` ADD PRIMARY KEY (`T700CodEmpresa`, `T700NumRecibo`, `T700Prefijo`, `T700NumFactura`);

CREATE TABLE `T701RECIBODETALLE`
 (
	`T701CodEmpresa`			varchar (5), 
	`T701NumRecibo`			varchar (5), 
	`T701CodConcepto`			varchar (15), 
	`T701ValorSaldoAnt`			varchar (15), 
	`T701ValorPagarSaldoAnt`			varchar (15), 
	`T701ValorSaldoAct`			varchar (15), 
	`T701ValorPagarSaldoAct`			varchar (15)
);

-- CREATE INDEXES ...

CREATE TABLE `T702INVENTARIO`
 (
	`T702CodEmpresa`			varchar (5) NOT NULL, 
	`T702Fecha`			varchar (10) NOT NULL, 
	`T702CentroCosto`			varchar (20) NOT NULL, 
	`T702CodConcepto`			varchar (20) NOT NULL, 
	`T702TotalAnt`			varchar (20), 
	`T702TotalAct`			varchar (20), 
	`T702TipoDocE`			varchar (5), 
	`T702TipoDocS`			varchar (5), 
	`T702NumDocE`			varchar (20), 
	`T702NumDocS`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T702INVENTARIO` ADD PRIMARY KEY (`T702CodEmpresa`, `T702Fecha`, `T702CentroCosto`, `T702CodConcepto`);

CREATE TABLE `T703FACTURADISP`
 (
	`T703CodEmpresa`			varchar (5) NOT NULL, 
	`T703Prefijo`			varchar (5) NOT NULL, 
	`T703NumFactura`			varchar (20) NOT NULL, 
	`T703Digita`			varchar (20) NOT NULL, 
	`T703IdDispositivo`			varchar (20) NOT NULL, 
	`T703CodInterno`			varchar (20) NOT NULL, 
	`T703Valor`			varchar (20), 
	`T703Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T703FACTURADISP` ADD PRIMARY KEY (`T703CodEmpresa`, `T703Prefijo`, `T703NumFactura`, `T703Digita`, `T703IdDispositivo`, `T703CodInterno`);

CREATE TABLE `T704RANGOFACTURA`
 (
	`T704CodEmpresa`			varchar (5) NOT NULL, 
	`T704CodPrefijo`			varchar (5) NOT NULL, 
	`T704Resolucion`			varchar (100), 
	`T704FechaIni`			varchar (10), 
	`T704FechaFin`			varchar (10), 
	`T704NumeroIni`			varchar (20), 
	`T704NumeroFin`			varchar (20), 
	`T704Observacion`			varchar (255), 
	`T704Avisar`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T704RANGOFACTURA` ADD PRIMARY KEY (`T704CodEmpresa`, `T704CodPrefijo`, `T704Resolucion`);

CREATE TABLE `T711TRIBUTO`
 (
	`T711Codigo`			varchar (20) NOT NULL, 
	`T711Nombre`			varchar (20) NOT NULL
);

-- CREATE INDEXES ...
ALTER TABLE `T711TRIBUTO` ADD PRIMARY KEY (`T711Codigo`);

CREATE TABLE `T712OBLIGACION`
 (
	`T712Codigo`			varchar (20) NOT NULL, 
	`T712Nombre`			varchar (20) NOT NULL
);

-- CREATE INDEXES ...
ALTER TABLE `T712OBLIGACION` ADD PRIMARY KEY (`T712Codigo`);

CREATE TABLE `T713LIQUIDACION`
 (
	`T713CodEmpresa`			varchar (5) NOT NULL, 
	`T713Numero`			varchar (20) NOT NULL, 
	`T713Fecha`			varchar (10), 
	`T713Tipo`			varchar (20), 
	`T713Valor`			varchar (20), 
	`T713Usuario`			varchar (20), 
	`T713FechaIni`			varchar (10), 
	`T713FechaFin`			varchar (10), 
	`T713Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T713LIQUIDACION` ADD PRIMARY KEY (`T713CodEmpresa`, `T713Numero`);

CREATE TABLE `T714LIQFACTURA`
 (
	`T714CodEmpresa`			varchar (5) NOT NULL, 
	`T714NumLiquida`			varchar (20) NOT NULL, 
	`T714CodPrefijo`			varchar (5) NOT NULL, 
	`T714NomPrefijo`			varchar (20), 
	`T714NumFactura`			varchar (20) NOT NULL, 
	`T714TotalFactura`			varchar (20), 
	`T714UtilParcial`			varchar (20), 
	`T714Flete`			varchar (20), 
	`T714PorcVendedor`			varchar (5), 
	`T714ValVendedor`			varchar (20), 
	`T714Utilactura`			varchar (20), 
	`T714PorcComParcial`			varchar (5), 
	`T714ComParcial`			varchar (20), 
	`T714UtilDRG`			varchar (20), 
	`T714PorcUtilDRG`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T714LIQFACTURA` ADD PRIMARY KEY (`T714CodEmpresa`, `T714NumLiquida`, `T714CodPrefijo`, `T714NumFactura`);

CREATE TABLE `T715LIQFACTDETALLE`
 (
	`T715CodEmpresa`			varchar (5) NOT NULL, 
	`T715NumLiquida`			varchar (20) NOT NULL, 
	`T715CodPrefijo`			varchar (5) NOT NULL, 
	`T715NumFactura`			varchar (20) NOT NULL, 
	`T715Consecutivo`			varchar (20) NOT NULL, 
	`T715CodConcepto`			varchar (20), 
	`T715Cantidad`			varchar (20), 
	`T715ValorUnit`			varchar (20), 
	`T715ValorTotal`			varchar (20), 
	`T715Impuestos`			varchar (20), 
	`T715ValorCompra`			varchar (20), 
	`T715UtilParcial`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T715LIQFACTDETALLE` ADD PRIMARY KEY (`T715CodEmpresa`, `T715NumLiquida`, `T715CodPrefijo`, `T715NumFactura`, `T715Consecutivo`);

CREATE TABLE `T79VERSION`
 (
	`T79UltVersion`			int
);

-- CREATE INDEXES ...

CREATE TABLE `T800TIPOHABITACION`
 (
	`T800Codigo`			varchar (5) NOT NULL, 
	`T800Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T800TIPOHABITACION` ADD PRIMARY KEY (`T800Codigo`);

CREATE TABLE `T801CLASEHABITACION`
 (
	`T801Codigo`			varchar (5) NOT NULL, 
	`T801Nombre`			varchar (50), 
	`T801CantPersonas`			varchar (3)
);

-- CREATE INDEXES ...
ALTER TABLE `T801CLASEHABITACION` ADD PRIMARY KEY (`T801Codigo`);

CREATE TABLE `T802TARIFA`
 (
	`T802Codigo`			varchar (5) NOT NULL, 
	`T802Nombre`			varchar (50), 
	`T802CodEstado`			varchar (5), 
	`T802Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T802TARIFA` ADD PRIMARY KEY (`T802Codigo`);

CREATE TABLE `T803TARIFARANGO`
 (
	`T803CodTarifa`			varchar (5) NOT NULL, 
	`T803Codigo`			varchar (5) NOT NULL, 
	`T803CodTipoHabitacion`			varchar (5), 
	`T803CodClaseHabitacion`			varchar (5), 
	`T803FechaIni`			varchar (10), 
	`T803FechaFin`			varchar (10), 
	`T803Valor`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T803TARIFARANGO` ADD PRIMARY KEY (`T803CodTarifa`, `T803Codigo`);

CREATE TABLE `T804PLAN`
 (
	`T804Codigo`			varchar (5) NOT NULL, 
	`T804Nombre`			varchar (50), 
	`T804CodTarifa`			varchar (5), 
	`T804ValorAdicional`			varchar (20), 
	`T804ValorNino`			varchar (20), 
	`T804CodEstado`			varchar (5), 
	`T804Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T804PLAN` ADD PRIMARY KEY (`T804Codigo`);

CREATE TABLE `T805PLANCARGO`
 (
	`T805CodPlan`			varchar (5) NOT NULL, 
	`T805CodCargo`			varchar (20) NOT NULL, 
	`T805CodTipoCuenta`			varchar (5), 
	`T805CodTipoCobro`			varchar (5), 
	`T805CobrarXPersona`			varchar (1), 
	`T805Valor`			varchar (20), 
	`T805ValorNino`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T805PLANCARGO` ADD PRIMARY KEY (`T805CodPlan`, `T805CodCargo`);

CREATE TABLE `T807ESTADO`
 (
	`T807Codigo`			varchar (5) NOT NULL, 
	`T807Nombre`			varchar (255), 
	`T807Imagen`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T807ESTADO` ADD PRIMARY KEY (`T807Codigo`);

CREATE TABLE `T808REGISTRO`
 (
	`T808Numero`			varchar (20) NOT NULL, 
	`T808CodPlan`			varchar (5), 
	`T808NumReserva`			varchar (20), 
	`T808CodTipoHabitacion`			varchar (5), 
	`T808CodClaseHabitacion`			varchar (5), 
	`T808CodHabitacion`			varchar (5), 
	`T808Valor`			varchar (20), 
	`T808NumAdulto`			varchar (3), 
	`T808NumNino`			varchar (3), 
	`T808NumAdicional`			varchar (3), 
	`T808FechaLlegada`			varchar (10), 
	`T808FechaSalida`			varchar (10), 
	`T808Observacion`			varchar (255)
);

-- CREATE INDEXES ...

CREATE TABLE `T809REGISTROTERCERO`
 (
	`T809NumRegistro`			varchar (20) NOT NULL, 
	`T809CodTercero`			varchar (20), 
	`T809CodClaseTercero`			varchar (5), 
	`T809NumFolio`			varchar (20), 
	`T809FechaLlegada`			varchar (10), 
	`T809FechaSalida`			varchar (10), 
	`T809CodMotivoViaje`			varchar (5), 
	`T809CodDptoOrigen`			varchar (2), 
	`T809CodCiudadOrigen`			varchar (3), 
	`T809CodDptoDest`			varchar (2), 
	`T809CodCiudadDest`			varchar (3), 
	`T809Empresa`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T809REGISTROTERCERO` ADD PRIMARY KEY (`T809NumRegistro`, `T809CodTercero`);

CREATE TABLE `T810TIPOCUENTA`
 (
	`T810Codigo`			varchar (5) NOT NULL, 
	`T810Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T810TIPOCUENTA` ADD PRIMARY KEY (`T810Codigo`);

CREATE TABLE `T811TIPOCOBRO`
 (
	`T811Codigo`			varchar (5) NOT NULL, 
	`T811Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T811TIPOCOBRO` ADD PRIMARY KEY (`T811Codigo`);

CREATE TABLE `T812CLASETERCERO`
 (
	`T812Codigo`			varchar (5) NOT NULL, 
	`T812Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T812CLASETERCERO` ADD PRIMARY KEY (`T812Codigo`);

CREATE TABLE `T814CARGO`
 (
	`T814Codigo`			varchar (5) NOT NULL, 
	`T814Nombre`			varchar (100), 
	`T814CodGrupoContab`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T814CARGO` ADD PRIMARY KEY (`T814Codigo`);

CREATE TABLE `T815AMBIENTE`
 (
	`T815Codigo`			varchar (5) NOT NULL, 
	`T815Nombre`			varchar (255), 
	`T815CodCargo`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T815AMBIENTE` ADD PRIMARY KEY (`T815Codigo`);

CREATE TABLE `T816ZONA`
 (
	`T816CodAmbiente`			varchar (5) NOT NULL, 
	`T816Codigo`			varchar (5) NOT NULL, 
	`T816Nombre`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T816ZONA` ADD PRIMARY KEY (`T816CodAmbiente`, `T816Codigo`);

CREATE TABLE `T817MESA`
 (
	`T817CodAmbiente`			varchar (5) NOT NULL, 
	`T817CodZona`			varchar (5) NOT NULL, 
	`T817Codigo`			varchar (5) NOT NULL, 
	`T817Nombre`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T817MESA` ADD PRIMARY KEY (`T817CodAmbiente`, `T817CodZona`, `T817Codigo`);

CREATE TABLE `T818CONCEPTO`
 (
	`T818Codigo`			varchar (20) NOT NULL, 
	`T818Nombre`			varchar (255), 
	`T818CodTipo`			varchar (5), 
	`T818Activo`			varchar (1), 
	`T818ModificaValor`			varchar (1), 
	`T818ModificaDesc`			varchar (1), 
	`T818CodUnidadMedida`			varchar (5), 
	`T818ValorVenta`			varchar (20), 
	`T818PorcIVA`			varchar (20), 
	`T818ValorCosto`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T818CONCEPTO` ADD PRIMARY KEY (`T818Codigo`);

CREATE TABLE `T819CONCEPTOAMBIENTE`
 (
	`T819CodConcepto`			varchar (20) NOT NULL, 
	`T819CodAmbiente`			varchar (5) NOT NULL
);

-- CREATE INDEXES ...
ALTER TABLE `T819CONCEPTOAMBIENTE` ADD PRIMARY KEY (`T819CodConcepto`, `T819CodAmbiente`);

CREATE TABLE `T821CUENTADETALLE`
 (
	`T821NumCuenta`			varchar (20) NOT NULL, 
	`T821Consecutivo`			varchar (20) NOT NULL, 
	`T821CodConcepto`			varchar (20), 
	`T821Cantidad`			varchar (20), 
	`T821ValorUnitario`			varchar (20), 
	`T821ValorDescuento`			varchar (20), 
	`T821ValorIva`			varchar (20), 
	`T821PorcIVA`			varchar (20), 
	`T821ValorTotal`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T821CUENTADETALLE` ADD PRIMARY KEY (`T821NumCuenta`, `T821Consecutivo`);

CREATE TABLE `T822RESERVA`
 (
	`T822Numero`			varchar (20) NOT NULL, 
	`T822Estado`			varchar (5), 
	`T822CodTercero`			varchar (20), 
	`T822CodPlan`			varchar (5), 
	`T822Fecha`			varchar (20), 
	`T822FechaLlegada`			varchar (10), 
	`T822FechaSalida`			varchar (10), 
	`T822HoraLlegada`			varchar (10), 
	`T822FormaPago`			varchar (5), 
	`T822Observacion`			varchar (255), 
	`T822Digita`			varchar (20), 
	`T822Empresa`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T822RESERVA` ADD PRIMARY KEY (`T822Numero`);

CREATE TABLE `T823RESERVAHABITACION`
 (
	`T823Numero`			varchar (20) NOT NULL, 
	`T823Consecutivo`			varchar (5) NOT NULL, 
	`T823CodTipoHabitacion`			varchar (5), 
	`T823CodClaseHabitacion`			varchar (5), 
	`T823CodHabitacion`			varchar (5), 
	`T823Valor`			varchar (20), 
	`T823NumAdulto`			varchar (20), 
	`T823NumNino`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T823RESERVAHABITACION` ADD PRIMARY KEY (`T823Numero`, `T823Consecutivo`);

CREATE TABLE `T824FOLIO`
 (
	`T824NumFolio`			varchar (20) NOT NULL, 
	`T824Fecha`			varchar (10), 
	`T824NumRegistro`			varchar (20), 
	`T824CodHabitacion`			varchar (5), 
	`T824CodTercero`			varchar (20), 
	`T824Total`			varchar (20), 
	`T824TotalIVA`			varchar (20), 
	`T824TotalDescuento`			varchar (20), 
	`T824Detalle`			varchar (255), 
	`T824Anulado`			varchar (1), 
	`T824Digita`			varchar (20), 
	`T824Estado`			varchar (5), 
	`T824NumFactura`			varchar (20), 
	`T824CodFormaPago`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T824FOLIO` ADD PRIMARY KEY (`T824NumFolio`);

CREATE TABLE `T825FOLIODETALLE`
 (
	`T825NumFolio`			varchar (20) NOT NULL, 
	`T825Consecutivo`			varchar (20) NOT NULL, 
	`T825Cantidad`			varchar (15), 
	`T825CodConcepto`			varchar (20), 
	`T825Valor`			varchar (20), 
	`T825ValorIVA`			varchar (20), 
	`T825Descuento`			varchar (20), 
	`T825CodCentro`			varchar (20), 
	`T825Digita`			varchar (20), 
	`T825CodAmbiente`			varchar (5), 
	`T825CodZona`			varchar (5), 
	`T825CodMesa`			varchar (5), 
	`T825NumCuenta`			varchar (20), 
	`T825PorcIVA`			varchar (15), 
	`T825ValorTotal`			varchar (20), 
	`T825Fecha`			varchar (10)
);

-- CREATE INDEXES ...
ALTER TABLE `T825FOLIODETALLE` ADD PRIMARY KEY (`T825NumFolio`, `T825Consecutivo`);

CREATE TABLE `TOTALES_ABONODETALLE`
 (
	`T647CodEmpresa`			varchar (5), 
	`T647NumAbono`			varchar (5), 
	`T647Prefijo`			varchar (5), 
	`T647NumFactura`			varchar (10), 
	`Total`			float
);

-- CREATE INDEXES ...

CREATE TABLE `TOTALESMANIFIESTO`
 (
	`Tercero`			varchar (20) NOT NULL
);

-- CREATE INDEXES ...

CREATE TABLE `TOTALESMANIFIESTO2`
 (
	`Tercero`			varchar (20), 
	`Factura`			varchar (20), 
	`Fecha`			varchar (20)
);

-- CREATE INDEXES ...

CREATE TABLE `TOTALESPAGOxCPTO`
 (
	`T647CodEmpresa`			varchar (5), 
	`T647Prefijo`			varchar (5), 
	`T647NumFactura`			varchar (10), 
	`T604Digita`			varchar (20), 
	`T647CodConcepto`			varchar (10), 
	`Valor`			float
);

-- CREATE INDEXES ...


-- CREATE INDEXES ...


-- CREATE INDEXES ...

CREATE TABLE `CACUERDOPAGO`
 (
	`Cuota`			varchar (10) NOT NULL, 
	`Fecha`			varchar (10) NOT NULL, 
	`Valor`			varchar (20) NOT NULL, 
	`Pagado`			varchar (1) NOT NULL, 
	`FechaPago`			varchar (10) NOT NULL, 
	`Revisada`			varchar (1), 
	`Sistema`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `CACUERDOPAGO` ADD PRIMARY KEY (`Cuota`);

CREATE TABLE `CMODULOS`
 (
	`Codigo`			varchar (5), 
	`Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `CMODULOS` ADD PRIMARY KEY (`Codigo`);

CREATE TABLE `CRPTTEM`
 (
	`Id`			varchar (50), 
	`Text1`			varchar (255), 
	`Text2`			varchar (255), 
	`Text3`			varchar (255), 
	`Text4`			varchar (255), 
	`Text5`			varchar (255), 
	`Text6`			varchar (255), 
	`Text7`			varchar (255), 
	`Text8`			varchar (255), 
	`Text9`			varchar (255), 
	`Text10`			varchar (255), 
	`Text11`			varchar (255), 
	`Text12`			varchar (255), 
	`Text13`			varchar (255), 
	`Text14`			varchar (255), 
	`Text15`			varchar (255), 
	`Text16`			varchar (255), 
	`Text17`			varchar (255), 
	`Text18`			varchar (255), 
	`Moneda1`			float, 
	`Moneda2`			float, 
	`Moneda3`			float, 
	`Moneda4`			float, 
	`Moneda5`			float, 
	`Moneda6`			float, 
	`Numero1`			int, 
	`Numero2`			int, 
	`Numero3`			int, 
	`Numero4`			int, 
	`Fecha1`			datetime, 
	`Fecha2`			datetime, 
	`Fecha3`			datetime, 
	`Fecha4`			datetime, 
	`Memo1`			text, 
	`Memo2`			text, 
	`Memo3`			text, 
	`Memo4`			text, 
	`Object1`			blob
);

-- CREATE INDEXES ...
ALTER TABLE `CRPTTEM` ADD INDEX `Id` (`Id`);

CREATE TABLE `T106MOVIMIENTO`
 (
	`T106CodEmpresa`			varchar (5) NOT NULL, 
	`T106Agno`			varchar (4) NOT NULL, 
	`T106CodTipoDoc`			varchar (5) NOT NULL, 
	`T106NumeroDoc`			varchar (20) NOT NULL, 
	`T106CodCta`			varchar (20) NOT NULL, 
	`T106ConsecCta`			varchar (5) NOT NULL, 
	`T106Fecha`			varchar (10), 
	`T106CodCentro`			varchar (6), 
	`T106Nit`			varchar (15), 
	`T106Referencia`			varchar (20), 
	`T106Detalle`			varchar (100), 
	`T106ValorDebito`			varchar (15), 
	`T106ValorCredito`			varchar (15), 
	`T106CodSubTipoDoc`			varchar (20), 
	`T106SubNumeroDoc`			varchar (20), 
	`T106FechaConciliado`			varchar (10), 
	`Anterior`			varchar (255), 
	`Nuevo`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T106MOVIMIENTO` ADD PRIMARY KEY (`T106CodEmpresa`, `T106Agno`, `T106CodTipoDoc`, `T106NumeroDoc`, `T106CodCta`, `T106ConsecCta`);
ALTER TABLE `T106MOVIMIENTO` ADD INDEX `T106CodTipoDoc` (`T106CodTipoDoc`);

CREATE TABLE `T111PLANCUENTA`
 (
	`T111CodPlan`			varchar (5), 
	`T111CodCta`			varchar (20), 
	`T111CodAlterno`			varchar (20), 
	`T111Naturaleza`			varchar (1), 
	`T111Nombre`			varchar (255), 
	`T111Movimiento`			varchar (1), 
	`T111CentroCosto`			varchar (1), 
	`T111Tercero`			varchar (1), 
	`T111CodTipoMoneda`			varchar (5), 
	`T111CodCtaAjuMoneda`			varchar (20), 
	`T111Dinamica`			varchar (255), 
	`T111Grupos`			varchar (255)
);

-- CREATE INDEXES ...

CREATE TABLE `T119FACTURA`
 (
	`T119CodEmpresa`			varchar (5), 
	`T119NumFactura`			varchar (5), 
	`T119Fecha`			varchar (10), 
	`T119CodTercero`			varchar (15), 
	`T119ValorTotal`			varchar (15), 
	`T119PorcRetefuente`			varchar (20), 
	`T119Retefuente`			varchar (20), 
	`T119PorcIVA`			varchar (20), 
	`T119IVA`			varchar (20)
);

-- CREATE INDEXES ...

CREATE TABLE `T124DESCUENTO`
 (
	`T124CodEmpresa`			varchar (5), 
	`T124Agno`			varchar (4), 
	`T124Codigo`			varchar (5), 
	`T124Nombre`			varchar (50), 
	`T124Valor`			varchar (255), 
	`T124DescAsumido`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T124DESCUENTO` ADD PRIMARY KEY (`T124CodEmpresa`, `T124Agno`, `T124Codigo`);

CREATE TABLE `T130PAGOCAUSACION`
 (
	`T130CodEmpresa`			varchar (5), 
	`T130Agno`			varchar (4), 
	`T130Numero`			varchar (10), 
	`T130AgnoCausacion`			varchar (15), 
	`T130NumCausacion`			varchar (10), 
	`T130Prefijo`			varchar (5), 
	`T130ValorDescuento`			varchar (15), 
	`T130PrefijoCausa`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T130PAGOCAUSACION` ADD PRIMARY KEY (`T130CodEmpresa`, `T130Agno`, `T130Numero`, `T130AgnoCausacion`, `T130NumCausacion`, `T130Prefijo`);

CREATE TABLE `T137CONCEPTONOMINA`
 (
	`T137CodEmpresa`			varchar (5), 
	`T137Codigo`			varchar (5), 
	`T137Nombre`			varchar (50), 
	`T137Tipo`			varchar (1), 
	`T137Valor`			varchar (15), 
	`T137Formula`			varchar (200), 
	`T137Devengado`			varchar (1), 
	`T137Deducido`			varchar (1), 
	`T137NitBeneficiario`			varchar (15), 
	`T137LiquidaPeriodico`			varchar (1), 
	`T137Otro`			varchar (1), 
	`T137Imprimir`			varchar (1), 
	`T137LiquidaNavidad`			varchar (2), 
	`T137LiquidaVacaciones`			varchar (2), 
	`T137LiquidaDefinitiva`			varchar (2), 
	`T137LiquidaServicios`			varchar (2), 
	`T137DiaLiquidacion`			varchar (2), 
	`T137UnicaFecha`			varchar (10), 
	`T137Reporte`			varchar (10), 
	`T137Ugpp`			varchar (2), 
	`T137Planilla`			varchar (2), 
	`T137CertIngresos`			varchar (2), 
	`T137NominaElec`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T137CONCEPTONOMINA` ADD PRIMARY KEY (`T137CodEmpresa`, `T137Codigo`);

CREATE TABLE `T142CTAEXOGENANIIF`
 (
	`T142CodEmpresa`			varchar (5) NOT NULL, 
	`T142Agno`			varchar (4) NOT NULL, 
	`T142CodCta`			varchar (20) NOT NULL, 
	`T142CodFormato`			varchar (5) NOT NULL, 
	`T142CodGrupo`			varchar (5) NOT NULL, 
	`T142Valor`			varchar (255) NOT NULL, 
	`T142Informacion`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T142CTAEXOGENANIIF` ADD PRIMARY KEY (`T142CodEmpresa`, `T142Agno`, `T142CodCta`, `T142CodFormato`, `T142CodGrupo`, `T142Valor`);

CREATE TABLE `T144TERCEROHISTORIAL`
 (
	`T144Nit`			varchar (20) NOT NULL, 
	`T144Numero`			varchar (20) NOT NULL, 
	`T144TipoHistorial`			varchar (5), 
	`T144Fecha`			varchar (10), 
	`T144Observacion`			varchar (255), 
	`T144Digita`			varchar (20), 
	`T144Mostrar`			varchar (5), 
	`T144Adjunto`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T144TERCEROHISTORIAL` ADD PRIMARY KEY (`T144Nit`, `T144Numero`);

CREATE TABLE `T151CUADROTURNO`
 (
	`T151CodEmpresa`			varchar (5) NOT NULL, 
	`T151Nit`			varchar (20) NOT NULL, 
	`T151Mes`			varchar (10) NOT NULL, 
	`T151Dia1`			varchar (1), 
	`T151Dia2`			varchar (1), 
	`T151Dia3`			varchar (1), 
	`T151Dia4`			varchar (1), 
	`T151Dia5`			varchar (1), 
	`T151Dia6`			varchar (1), 
	`T151Dia7`			varchar (1), 
	`T151Dia8`			varchar (1), 
	`T151Dia9`			varchar (1), 
	`T151Dia10`			varchar (1), 
	`T151Dia11`			varchar (1), 
	`T151Dia12`			varchar (1), 
	`T151Dia13`			varchar (1), 
	`T151Dia14`			varchar (1), 
	`T151Dia15`			varchar (1), 
	`T151Dia16`			varchar (1), 
	`T151Dia17`			varchar (1), 
	`T151Dia18`			varchar (1), 
	`T151Dia19`			varchar (1), 
	`T151Dia20`			varchar (1), 
	`T151Dia21`			varchar (1), 
	`T151Dia22`			varchar (1), 
	`T151Dia23`			varchar (1), 
	`T151Dia24`			varchar (1), 
	`T151Dia25`			varchar (1), 
	`T151Dia26`			varchar (1), 
	`T151Dia27`			varchar (1), 
	`T151Dia28`			varchar (1), 
	`T151Dia29`			varchar (1), 
	`T151Dia30`			varchar (1), 
	`T151Dia31`			varchar (1), 
	`T151Detalle`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T151CUADROTURNO` ADD PRIMARY KEY (`T151CodEmpresa`, `T151Nit`, `T151Mes`);

CREATE TABLE `T16TIPOSOCIEDAD`
 (
	`T16Codigo`			varchar (5), 
	`T16Nombre`			varchar (50)
);

-- CREATE INDEXES ...

CREATE TABLE `T223REMESA`
 (
	`T223NumOrden`			varchar (20) NOT NULL, 
	`T223Fecha`			varchar (10), 
	`T223CodOficina`			varchar (5), 
	`T223TerceroRemite`			varchar (20), 
	`T223DptoRemite`			varchar (5), 
	`T223CiudadRemite`			varchar (5), 
	`T223DirecRemite`			varchar (255), 
	`T223TelefonoRemite`			varchar (100), 
	`T223TerceroDestino`			varchar (20), 
	`T223DptoDestino`			varchar (5), 
	`T223CiudadDestino`			varchar (5), 
	`T223DirecDestino`			varchar (255), 
	`T223TelefonoDestino`			varchar (100), 
	`T223ValorDeclarado`			varchar (20), 
	`T223Contado`			varchar (1), 
	`T223AplicaSeguro`			varchar (1), 
	`T223ContraEntrega`			varchar (1), 
	`T223ProdTransporta`			varchar (100), 
	`T223CodNaturaleza`			varchar (5), 
	`T223CodProducto`			varchar (20), 
	`T223Cantidad`			varchar (10), 
	`T223Empaque`			varchar (10), 
	`T223Peso`			varchar (10), 
	`T223Volumen`			varchar (10), 
	`T223CodCentro`			varchar (20), 
	`T223Observacion`			varchar (255), 
	`T223Hora`			varchar (10), 
	`T223Prefijo`			varchar (10), 
	`T223CantidadD`			varchar (20), 
	`T223CantidadD1`			varchar (20), 
	`T223CantidadD2`			varchar (20)
);

-- CREATE INDEXES ...

CREATE TABLE `T23METODOAJUSTE`
 (
	`T23Codigo`			varchar (5), 
	`T23Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T30CONCEPTOCONCILIA`
 (
	`T30CodEmpresa`			varchar (5), 
	`T30Codigo`			varchar (5), 
	`T30Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T41GRUPOCONCEPTO`
 (
	`T41CodEmpresa`			varchar (5), 
	`T41Codigo`			varchar (5), 
	`T41Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T41GRUPOCONCEPTO` ADD PRIMARY KEY (`T41CodEmpresa`, `T41Codigo`);

CREATE TABLE `T49CALENDARIOTRIBUTARIO`
 (
	`T49Agno`			varchar (4), 
	`T49TipoCalendario`			varchar (5), 
	`T49TipoDigitos`			varchar (5), 
	`T49Digito`			varchar (5), 
	`T49Periodo`			varchar (5), 
	`T49Fecha`			varchar (10), 
	`Campo7`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T49CALENDARIOTRIBUTARIO` ADD PRIMARY KEY (`T49Agno`, `T49TipoCalendario`, `T49TipoDigitos`, `T49Digito`, `T49Periodo`);

CREATE TABLE `T54GRUPOEXOGENA`
 (
	`T54CodFormato`			varchar (255), 
	`T54Codigo`			varchar (5), 
	`T54Nombre`			varchar (50), 
	`T54CuantiaMinima`			varchar (15), 
	`T54Agno`			varchar (4), 
	`T54Detalle`			varchar (200)
);

-- CREATE INDEXES ...
ALTER TABLE `T54GRUPOEXOGENA` ADD PRIMARY KEY (`T54Agno`, `T54CodFormato`, `T54Codigo`);

CREATE TABLE `T601AREASHOTEL`
 (
	`T601CodEmpresa`			varchar (5), 
	`T601CodPisoHotel`			varchar (5), 
	`T601Codigo`			varchar (5), 
	`T601Nombre`			varchar (30)
);

-- CREATE INDEXES ...
ALTER TABLE `T601AREASHOTEL` ADD PRIMARY KEY (`T601CodEmpresa`, `T601CodPisoHotel`, `T601Codigo`);

CREATE TABLE `T606FACTURAENTREGA`
 (
	`T606CodEmpresa`			varchar (5) NOT NULL, 
	`T606Numero`			varchar (20) NOT NULL, 
	`T606Prefijo`			varchar (5) NOT NULL, 
	`T606NumFactura`			varchar (10) NOT NULL, 
	`T606Consecutivo`			varchar (5), 
	`T606Digita`			varchar (20), 
	`T606CodConcepto`			varchar (20), 
	`T606CantidadIni`			varchar (15), 
	`T606CantidadEnt`			varchar (15), 
	`T606Fecha`			varchar (15), 
	`T606Usuario`			varchar (20), 
	`T606CantEntregados`			varchar (15), 
	`T606CantSaldo`			varchar (15), 
	`T606Impresa`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T606FACTURAENTREGA` ADD PRIMARY KEY (`T606CodEmpresa`, `T606Numero`, `T606Prefijo`, `T606NumFactura`, `T606Consecutivo`, `T606Digita`);

CREATE TABLE `T612MOVIMIENTO_1`
 (
	`T612CodEmpresa`			varchar (5) NOT NULL, 
	`T612Agno`			varchar (4) NOT NULL, 
	`T612TipoTransaccion`			varchar (5) NOT NULL, 
	`T612NumeroDoc`			varchar (20) NOT NULL, 
	`T612CodArticulo`			varchar (20) NOT NULL, 
	`T612Cantidad`			varchar (10), 
	`T612ValorArticulo`			varchar (15), 
	`T612ValorDescuento`			varchar (15), 
	`T612ValorIVA`			varchar (15), 
	`T612SubCodConcepto`			varchar (5), 
	`T612Consecutivo`			varchar (5), 
	`T612CodCentro`			varchar (20), 
	`T612PorcIVA`			varchar (15), 
	`T612Digita`			varchar (20), 
	`T612ValorVenta`			varchar (15), 
	`T612CodMetro2`			varchar (20), 
	`T612NumMetro2`			varchar (20), 
	`T612ValorFlete`			varchar (20), 
	`T612ValorVentaAct`			varchar (20), 
	`T612FechaVence`			varchar (10), 
	`T612Lote`			varchar (20), 
	`T612ValorBaseCafe`			varchar (20), 
	`T612BonificaCafe`			varchar (20), 
	`T612PorcTara`			varchar (10), 
	`T612PorcFR`			varchar (10), 
	`T612PorcHumedad`			varchar (10), 
	`T612PorcKgBruto`			varchar (10), 
	`T612BrocaBase`			varchar (10), 
	`T612Broca`			varchar (10), 
	`T612HumedBase`			varchar (10), 
	`T612BaseFR`			varchar (10), 
	`T612PorcIVA2`			varchar (5), 
	`T612ValorIVA2`			varchar (20)
);

-- CREATE INDEXES ...

CREATE TABLE `T616TIPOFORMAPAGO`
 (
	`T616Codigo`			varchar (5), 
	`T616Nombre`			varchar (50), 
	`T616DiasInc`			varchar (3), 
	`T616Cartera`			varchar (1), 
	`T616CodCuenta`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T616TIPOFORMAPAGO` ADD PRIMARY KEY (`T616Codigo`);

CREATE TABLE `T623CONCEPTOxGRUPO`
 (
	`T623CodEmpresa`			varchar (5), 
	`T623CodConcepto`			varchar (20), 
	`T623CodGrupo`			varchar (5)
);

-- CREATE INDEXES ...
ALTER TABLE `T623CONCEPTOxGRUPO` ADD PRIMARY KEY (`T623CodEmpresa`, `T623CodConcepto`, `T623CodGrupo`);

CREATE TABLE `T631PERIODO`
 (
	`T631CodEmpresa`			varchar (5), 
	`T631Codigo`			varchar (5), 
	`T631Nombre`			varchar (50), 
	`T631FechaIni`			varchar (10), 
	`T631FechaFin`			varchar (10), 
	`T631FechaCorte`			varchar (10), 
	`T631FechaSusp`			varchar (10)
);

-- CREATE INDEXES ...
ALTER TABLE `T631PERIODO` ADD PRIMARY KEY (`T631CodEmpresa`, `T631Codigo`);

CREATE TABLE `T637TOTALES`
 (
	`T637CodEmpresa`			varchar (5), 
	`T637CodConcepto`			varchar (20), 
	`T637CodCentro`			varchar (20), 
	`T637CantEntrada`			varchar (15), 
	`T637TotalEntrada`			varchar (15), 
	`T637CantSalida`			varchar (15), 
	`T637TotalSalida`			varchar (15)
);

-- CREATE INDEXES ...
ALTER TABLE `T637TOTALES` ADD PRIMARY KEY (`T637CodEmpresa`, `T637CodConcepto`, `T637CodCentro`);

CREATE TABLE `T643MODELOPRODUCTO`
 (
	`T643Codigo`			varchar (20), 
	`T643Nombre`			varchar (30)
);

-- CREATE INDEXES ...

CREATE TABLE `T648ORDENENTRADA`
 (
	`T648CodEmpresa`			varchar (5), 
	`T648OrdenTrabajo`			varchar (10), 
	`T648Consecutivo`			varchar (5), 
	`T648Descripcion`			varchar (100), 
	`T648Cantidad`			varchar (5), 
	`T648Fuente`			varchar (50), 
	`T648FechaInf`			varchar (10), 
	`T648Ensayos`			varchar (100), 
	`T648TipoOrden`			varchar (5)
);

-- CREATE INDEXES ...

CREATE TABLE `T650TIPOCOEFPERIODO`
 (
	`T650CodEmpresa`			varchar (5), 
	`T650CodPeriodo`			varchar (5), 
	`T650CodTipoCoeficiente`			varchar (5), 
	`T650Valor`			varchar (15)
);

-- CREATE INDEXES ...

CREATE TABLE `T658GLOSA`
 (
	`T658Prefijo`			varchar (5) NOT NULL, 
	`T658NumFactura`			varchar (20) NOT NULL, 
	`T658Consecutivo`			varchar (20) NOT NULL, 
	`T658Fecha`			varchar (10), 
	`T658CodTipoGlosa`			varchar (5), 
	`T658Detalle`			varchar (255), 
	`T658ValorAcepta`			varchar (20), 
	`T658ValorRechaza`			varchar (20), 
	`T658Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T658GLOSA` ADD PRIMARY KEY (`T658Prefijo`, `T658NumFactura`, `T658Consecutivo`);

CREATE TABLE `T664CERTIFICADOS`
 (
	`T664NumeroCertificado`			varchar (20), 
	`T664Infractor`			varchar (20), 
	`T664ReciboPago`			varchar (20), 
	`T664Comparendo`			varchar (255), 
	`T664FechaComparendo`			varchar (10), 
	`T664Resolucion`			varchar (255), 
	`T664FechaProgCurso`			varchar (10), 
	`T664HoraProgCurso`			varchar (10), 
	`T664FechaRealizacurso`			varchar (10), 
	`T664HoraRealizaCurso`			varchar (10), 
	`T664HoraFinCurso`			varchar (10), 
	`T664Instructor`			varchar (20), 
	`T664TipoSancion`			varchar (1), 
	`T664CodDpto`			varchar (2), 
	`T664CodCiudad`			varchar (3), 
	`T664NumFallo`			varchar (15), 
	`T664FechaFallo`			varchar (10), 
	`T664EmpresaFallo`			varchar (100), 
	`T664TipoComparendo`			varchar (50), 
	`T664Infraccion`			varchar (50), 
	`T664Valor`			varchar (20), 
	`T664ValorAdicional`			varchar (20), 
	`T664ValorOtros`			varchar (20), 
	`T664ValorTotal`			varchar (20), 
	`T664ValorDescuento`			varchar (20), 
	`T664ValorCIA`			varchar (20), 
	`T664PorceDescuento`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T664CERTIFICADOS` ADD PRIMARY KEY (`T664NumeroCertificado`);

CREATE TABLE `T673TIPOSEGUIMIE`
 (
	`T673Codigo`			varchar (10) NOT NULL, 
	`T673Nombre`			varchar (50)
);

-- CREATE INDEXES ...
ALTER TABLE `T673TIPOSEGUIMIE` ADD PRIMARY KEY (`T673Codigo`);

CREATE TABLE `T683ORDENMANTENIM`
 (
	`T683CodEmpresa`			varchar (5) NOT NULL, 
	`T683Numero`			varchar (10) NOT NULL, 
	`T683CodArea`			varchar (10), 
	`T683CodConcepto`			varchar (20), 
	`T683TipoOrden`			varchar (10), 
	`T683NumOrdenExt`			varchar (20), 
	`T683Fecha`			varchar (10), 
	`T683Hora`			varchar (10), 
	`T683CodSolicita`			varchar (20), 
	`T683CodTecnico1`			varchar (20), 
	`T683CodTecnico2`			varchar (20), 
	`T683CodTecnico3`			varchar (20), 
	`T683CodTipoLabor`			varchar (10), 
	`T683CodTipoMant`			varchar (10), 
	`T683CodTipoParada`			varchar (10), 
	`T683CodCentro`			varchar (20), 
	`T683Observacion`			varchar (255), 
	`T683Estado`			varchar (20), 
	`T683ValorManoInt`			varchar (20), 
	`T683ValorMaterial`			varchar (20), 
	`T683ValorTotal`			varchar (20), 
	`T683Horometro`			varchar (20), 
	`T683ObservacionTecnico`			varchar (255), 
	`T683FechaEntrega`			varchar (10), 
	`T683CodCliente`			varchar (20), 
	`T683CodTipoServicio`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T683ORDENMANTENIM` ADD PRIMARY KEY (`T683CodEmpresa`, `T683Numero`);

CREATE TABLE `T691TIPOCAUSA`
 (
	`T691CodEmpresa`			varchar (5) NOT NULL, 
	`T691Codigo`			varchar (10) NOT NULL, 
	`T691Nombre`			varchar (200), 
	`T691Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T691TIPOCAUSA` ADD PRIMARY KEY (`T691CodEmpresa`, `T691Codigo`);

CREATE TABLE `T697PREFIJOFOTO`
 (
	`T697Codigo`			varchar (5) NOT NULL, 
	`T697Ruta`			varchar (255) NOT NULL, 
	`T697Observacion`			varchar (255)
);

-- CREATE INDEXES ...
ALTER TABLE `T697PREFIJOFOTO` ADD PRIMARY KEY (`T697Codigo`);

CREATE TABLE `T709BONO`
 (
	`T709CodEmpresa`			varchar (5) NOT NULL, 
	`T709Numero`			varchar (5) NOT NULL, 
	`T709Fecha`			varchar (10), 
	`T709Hora`			varchar (10), 
	`T709Tipo`			varchar (20), 
	`T709Valor`			varchar (20), 
	`T709Usuario`			varchar (20), 
	`T709CodCliente`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T709BONO` ADD PRIMARY KEY (`T709CodEmpresa`, `T709Numero`);

CREATE TABLE `T78ARCHIVOSMAESTROS`
 (
	`T78Codigo`			varchar (3), 
	`T78Nombre`			varchar (30), 
	`T78DesArchivosMaestros`			varchar (80), 
	`T78Empresa`			varchar (1)
);

-- CREATE INDEXES ...

CREATE TABLE `T806HABITACION`
 (
	`T806Codigo`			varchar (5) NOT NULL, 
	`T806Nombre`			varchar (100) NOT NULL, 
	`T806Descripcion`			varchar (255), 
	`T806Foto`			varchar (255), 
	`T806CodTipoHabitacion`			varchar (5), 
	`T806CodEstado`			varchar (5), 
	`T806NumRegistro`			varchar (20)
);

-- CREATE INDEXES ...
ALTER TABLE `T806HABITACION` ADD PRIMARY KEY (`T806Codigo`);

CREATE TABLE `T813MOTIVOVIAJE`
 (
	`T813Codigo`			varchar (5) NOT NULL, 
	`T813Nombre`			varchar (100)
);

-- CREATE INDEXES ...
ALTER TABLE `T813MOTIVOVIAJE` ADD PRIMARY KEY (`T813Codigo`);

CREATE TABLE `T820CUENTA`
 (
	`T820NumCuenta`			varchar (20) NOT NULL, 
	`T820FechaHora`			varchar (20) NOT NULL, 
	`T820CodHabitacion`			varchar (5), 
	`T820NumFolio`			varchar (20), 
	`T820CodTercero`			varchar (20), 
	`T820CodFormaPago`			varchar (5), 
	`T820CodVendedor`			varchar (5), 
	`T820Detalle`			varchar (255), 
	`T820CodAmbiente`			varchar (5), 
	`T820CodZona`			varchar (5), 
	`T820CodMesa`			varchar (5), 
	`T820Estado`			varchar (5), 
	`T820Usuario`			varchar (20), 
	`T820NumFactura`			varchar (20), 
	`T820CargarA`			varchar (1)
);

-- CREATE INDEXES ...
ALTER TABLE `T820CUENTA` ADD PRIMARY KEY (`T820NumCuenta`);


-- CREATE INDEXES ...

CREATE TABLE `T605TOTALES`
 (
	`T605CodEmpresa`			varchar (5), 
	`T605Prefijo`			varchar (5), 
	`T605NumFactura`			varchar (10), 
	`T605Digita`			varchar (20), 
	`Total`			float, 
	`TotalIVA`			float, 
	`TotalDescuento`			float
);

-- CREATE INDEXES ...

CREATE TABLE `TOTALESDEUDA_CLIENTE`
 (
	`T12Nit`			varchar (15), 
	`Dias`			int
);

-- CREATE INDEXES ...

CREATE TABLE `TOTALES_CONSECUTIVO`
 (
	`T617Codigo`			varchar (5), 
	`Consec`			float
);

-- CREATE INDEXES ...

CREATE TABLE `TOTALES_UPD`
 (
	`Ent`			varchar (255), 
	`T603Codigo`			varchar (20), 
	`T24CodCentro`			varchar (6), 
	`CantE`			float, 
	`ValorE`			float, 
	`CantS`			float, 
	`ValorS`			float
);

-- CREATE INDEXES ...

CREATE TABLE `TOTALESULTVALORCOMPRA`
 (
	`T612CodArticulo`			varchar (20), 
	`ValorCompra`			float, 
	`ValorCompra1`			float, 
	`T611Fecha`			varchar (10)
);

-- CREATE INDEXES ...

CREATE TABLE `TOTALES_CLIENTE`
 (
	`T12Nit`			varchar (20), 
	`SaldoFinal`			float
);

-- CREATE INDEXES ...

CREATE TABLE `TOTALESPAGO`
 (
	`T626CodEmpresa`			varchar (5), 
	`T626Prefijo`			varchar (5), 
	`T626NumFactura`			varchar (10), 
	`Digita`			varchar (20), 
	`T604CodTercero`			varchar (15), 
	`Valor`			float
);

-- CREATE INDEXES ...


-- CREATE Relationships ...

-- Scratch tables of the legacy database, kept so no data is left out
CREATE TABLE `copia contador`
 (
	`Cuota`			varchar (10) NOT NULL, 
	`Fecha`			varchar (10) NOT NULL, 
	`Valor`			varchar (20) NOT NULL, 
	`Pagado`			varchar (1) NOT NULL, 
	`FechaPago`			varchar (10) NOT NULL, 
	`Revisada`			varchar (1)
);

CREATE TABLE `Errores de pegado`
 (
	`F1`			varchar (255), 
	`F2`			varchar (255), 
	`F3`			varchar (255), 
	`F4`			varchar (255), 
	`F5`			varchar (255), 
	`F6`			varchar (255), 
	`F7`			varchar (255), 
	`F8`			varchar (255), 
	`F9`			varchar (255), 
	`F10`			varchar (255), 
	`F11`			varchar (255), 
	`F12`			varchar (255), 
	`F13`			varchar (255), 
	`F14`			varchar (255), 
	`F15`			varchar (255), 
	`F16`			varchar (255), 
	`F17`			varchar (255), 
	`F18`			varchar (255), 
	`F19`			varchar (255), 
	`F20`			varchar (255), 
	`F21`			varchar (255), 
	`F22`			varchar (255), 
	`F23`			varchar (255)
);

CREATE TABLE `ZZZ`
 (
	`T629Nombre`			varchar (30), 
	`T604NumFactura`			varchar (10), 
	`T604Fecha`			varchar (10), 
	`T604CodTercero`			varchar (15), 
	`T12Nombre`			varchar (255), 
	`T12Nombre2`			varchar (255), 
	`T12Apellido`			varchar (255), 
	`T12Apellido2`			varchar (255), 
	`T12RazonSocial`			varchar (255), 
	`SumadeT604Total`			float, 
	`T604CodFormaPago`			varchar (5), 
	`T616Nombre`			varchar (50), 
	`T604Vendedor`			varchar (15), 
	`T625Nombre`			varchar (30), 
	`T604FechaVence`			varchar (10), 
	`Valor`			float, 
	`T12CodDpto`			varchar (255), 
	`T19Nombre`			varchar (255), 
	`T12CodCiudad`			varchar (255), 
	`T20Nombre`			varchar (255), 
	`Expr1020`			varchar (1), 
	`F1`			int, 
	`F2`			int, 
	`DiasVence`			int, 
	`T629Codigo`			varchar (20), 
	`T604Cancelado`			varchar (1), 
	`ValorDevoluc`			float, 
	`Deuda`			float, 
	`Descuento`			float, 
	`Retencion`			float, 
	`T604Detalle`			varchar (100), 
	`Multa`			float, 
	`T57Nombre`			varchar (255)
);

CREATE TABLE `ZZZP`
 (
	`T617Nombre`			varchar (50), 
	`T611NumeroDoc`			varchar (20), 
	`T611Fecha`			varchar (10), 
	`T611CodProveedor`			varchar (15), 
	`T12Nombre`			varchar (50), 
	`T12Nombre2`			varchar (20), 
	`T12Apellido`			varchar (50), 
	`T12Apellido2`			varchar (20), 
	`T12RazonSocial`			varchar (80), 
	`ValorFactura`			float, 
	`T611FormaPago`			varchar (5), 
	`T616Nombre`			varchar (50), 
	`VEndedor`			varchar (20), 
	`VEndedor1`			varchar (255), 
	`T611FechaVence`			varchar (10), 
	`ValorAbono`			float, 
	`Expr1016`			varchar (1), 
	`T611TipoTransaccion`			varchar (5), 
	`T611Prefijo`			varchar (5), 
	`T611NumFactura`			varchar (20), 
	`T611Anular`			varchar (1), 
	`Descuento`			float, 
	`Retencion`			float, 
	`ValorDevoluc`			float, 
	`F1`			int, 
	`F2`			int, 
	`DiasVence`			int
);

CREATE TABLE `Tabla1`
 (
	`EMPRESA`			varchar (255), 
	`AGNO`			varchar (255), 
	`TD`			varchar (255), 
	`DOC`			varchar (255), 
	`VALOR`			varchar (255)
);

