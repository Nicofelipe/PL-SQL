--FECHA DE PROCESO
VARIABLE B_MES NUMBER;
EXEC :B_MES := 6;
VARIABLE B_ANNHO NUMBER;
EXEC :B_ANNHO := 2021;
DECLARE

--FECHA DE PROCESO
/*V_MES NUMBER(2) := 6;
V_ANNHO NUMBER(4) := 2021;*/

--MAXIMO DE ASIGNACION
V_MAX_ASIGNACION NUMBER(6) := 250000;

--CALCULOS
V_MOVIL_EXTRA NUMBER(8) := 0;
V_INCENTIVO NUMBER(2) := 0;
V_INCENTIVO_TOTAL NUMBER(8) := 0;
V_ASIGNACION NUMBER(4,2) := 0;
V_ASIGNACION_TOTAL NUMBER(8) := 0;
V_TOTAL_ASIG NUMBER(8) := 0;


--EXCEPTION DEFINIDA POR EL USUARIO
EXEC_MAX_ASIG EXCEPTION;

-- REGISTRO PARA ALMACENAR LAS FUNCIONES DE GRUPO
TYPE tip_group_emp IS RECORD(
NRO_ASESORIAS NUMBER(3),
MONTO_HONORARIOS NUMBER(8)
);

REG_GROUP tip_group_emp;

-- VARRAY
TYPE TIPO_VARRAY_MOV_EXTRA IS VARRAY(5)
OF VARCHAR2(1);

V_VARRAY_MOV_EXTRA TIPO_VARRAY_MOV_EXTRA;

--CURSOR 
CURSOR CUR_REG_RESUMEN_MES IS SELECT 
                                    P.NOMBRE_PROFESION AS NOM ,
                                    NVL(ROUND(SUM(DM.nro_asesorias)),0) AS NRO_AS,
                                    NVL(ROUND(SUM(DM.monto_honorarios)),0) AS NR_HON,
                                    NVL(ROUND(SUM(DM.monto_movil_extra)),0) AS NR_ME,
                                    NVL(ROUND(SUM(DM.monto_asig_tipocont)),0) AS NR_AT,
                                    NVL(ROUND(SUM(DM.monto_asig_profesion)),0) AS NR_AP,
                                    NVL(ROUND(SUM(DM.monto_total_asignaciones)),0) AS NRO_MTA
                                FROM PROFESION P LEFT JOIN DETALLE_ASIGNACION_MES DM
                                ON P.NOMBRE_PROFESION = DM.PROFESION
                                GROUP BY anno_proceso,mes_proceso,P.NOMBRE_PROFESION
                                ORDER BY 1;
--REGISTRO DEL CURSOR                                
V_REG_RESUMEN_MES CUR_REG_RESUMEN_MES%ROWTYPE;

BEGIN

EXECUTE IMMEDIATE('TRUNCATE TABLE DETALLE_ASIGNACION_MES');
EXECUTE IMMEDIATE('TRUNCATE TABLE RESUMEN_MES_PROFESION');
EXECUTE IMMEDIATE('TRUNCATE TABLE ERRORES_PROCESO');
EXECUTE IMMEDIATE('DROP SEQUENCE SQ_ERRORES');
EXECUTE IMMEDIATE('CREATE SEQUENCE SQ_ERRORES');

--OTORGANDOLE VALORES AL VARRAY
V_VARRAY_MOV_EXTRA := TIPO_VARRAY_MOV_EXTRA(2,4,5,7,9);

FOR V_REG_MES IN (SELECT
                    PRO.numrun_prof AS RUT,
                    PRO.dvrun_prof AS DVRUN,
                    TO_CHAR(PRO.numrun_prof,'09G999G999') AS RUNCONFORMATO,
                    INITCAP(PRO.nombre||' '||PRO.appaterno) AS NOMBRE,
                    PR.cod_profesion AS CODPROFESION,
                    PR.nombre_profesion AS PROFESION,
                    CO.nom_comuna AS COMUNA,
                    PRO.sueldo AS SUELDO,
                    PRO.cod_tpcontrato AS CODTIPOCONTRATO
                FROM PROFESIONAL PRO JOIN PROFESION PR
                ON PRO.cod_profesion = PR.cod_profesion
                JOIN COMUNA CO
                ON PRO.cod_comuna = CO.cod_comuna
                JOIN ASESORIA ASE
                ON ASE.numrun_prof = PRO.numrun_prof
                AND EXTRACT(MONTH FROM ASE.inicio_asesoria) = :B_MES
                AND EXTRACT(YEAR FROM ASE.inicio_asesoria) = :B_ANNHO/*EXTRACT(YEAR FROM SYSDATE)-2*/
                GROUP BY PRO.numrun_prof,PRO.dvrun_prof,PRO.nombre,PRO.appaterno,
                         PR.nombre_profesion,CO.nom_comuna,PRO.cod_tpcontrato,
                         PR.cod_profesion,PRO.sueldo
                ORDER BY PR.nombre_profesion,PRO.appaterno) LOOP
               
    -- CALCULANDO CON FUNCIONES DE GRUPO A PARTE
                SELECT
                    COUNT(numrun_prof),
                    SUM(HONORARIO)
                    INTO REG_GROUP
                FROM ASESORIA
                WHERE numrun_prof = V_REG_MES.RUT
                AND EXTRACT(MONTH FROM inicio_asesoria) = :B_MES
                AND EXTRACT(YEAR FROM inicio_asesoria) = :B_ANNHO
                GROUP BY numrun_prof;

    --MOFIDICADO PARA QUE SEA COMO LA IMAGEN REFERENCIAL DE LA PRUEBA
    
    IF(/*REG_GROUP.MONTO_HONORARIOS < 350000 AND*/ V_REG_MES.COMUNA = 'Santiago' )THEN
        V_MOVIL_EXTRA := ROUND(REG_GROUP.MONTO_HONORARIOS*(V_VARRAY_MOV_EXTRA(1)/100));
        ELSIF(V_REG_MES.COMUNA = 'Ñuñoa' )THEN
            V_MOVIL_EXTRA := ROUND(REG_GROUP.MONTO_HONORARIOS*(V_VARRAY_MOV_EXTRA(2)/100));
            ELSIF(/*(REG_GROUP.MONTO_HONORARIOS >= 350000 AND REG_GROUP.MONTO_HONORARIOS < 400000) AND*/ V_REG_MES.COMUNA = 'La Reina')THEN
                V_MOVIL_EXTRA := ROUND(REG_GROUP.MONTO_HONORARIOS*(V_VARRAY_MOV_EXTRA(3)/100));
                ELSIF(/*(REG_GROUP.MONTO_HONORARIOS >= 400000 AND REG_GROUP.MONTO_HONORARIOS < 680000) AND */V_REG_MES.COMUNA = 'Macul')THEN
                    V_MOVIL_EXTRA := ROUND(REG_GROUP.MONTO_HONORARIOS*(V_VARRAY_MOV_EXTRA(5)/100));
                    ELSIF(/*(REG_GROUP.MONTO_HONORARIOS >= 680000 AND REG_GROUP.MONTO_HONORARIOS < 800000 )AND*/ V_REG_MES.COMUNA = 'La Florida')THEN
                        V_MOVIL_EXTRA := ROUND(REG_GROUP.MONTO_HONORARIOS*(V_VARRAY_MOV_EXTRA(4)/100));
    ELSE V_MOVIL_EXTRA := 0;
    END IF;

    -- CALCULANDO INCENTIVO POR TIPO DE CONTRATO
    SELECT
       incentivo 
    INTO V_INCENTIVO
    FROM TIPO_CONTRATO
    WHERE cod_tpcontrato = V_REG_MES.CODTIPOCONTRATO ;
    
    
    --BLOQUE ANIDADO
    BEGIN
        
        -- CALCULANDO ASIGNACION POR CODIGO DE PROFESION
        SELECT
            asignacion
        INTO V_ASIGNACION
        FROM PORCENTAJE_PROFESION
        WHERE cod_profesion = V_REG_MES.CODPROFESION;
        
        -- INSERTANDO ERROR NOT FOUND
        EXCEPTION WHEN NO_DATA_FOUND THEN
            INSERT INTO ERRORES_PROCESO
                VALUES (SQ_ERRORES.NEXTVAL,'ORA-01403: No se ha encontrado ningún dato',
                'Error al obtener porcentaje de asignacion para el run Nro.'||V_REG_MES.RUNCONFORMATO);
            V_ASIGNACION := 0;
    -- FIN BLOQUE ANIDADO
    END; 
    
    
    -- CALCULANDO VALORES
    V_ASIGNACION_TOTAL := ROUND(REG_GROUP.MONTO_HONORARIOS*(V_ASIGNACION/100));-- ESTA DEBERIA SER CON SUELDO SEGUN LA GUIA
    V_INCENTIVO_TOTAL := ROUND(REG_GROUP.MONTO_HONORARIOS/*V_REG_MES.SUELDO*/*(V_INCENTIVO/100)); --ESTE ES POR EL SUELDO
    V_TOTAL_ASIG := ROUND(V_ASIGNACION_TOTAL+V_INCENTIVO_TOTAL+V_MOVIL_EXTRA);
    
    -- CREANDO UNA EXCEPTION DEFINIDA POR EL CLIENTE
    --INICIO BLOQUE ANIDADO
    BEGIN
    IF V_TOTAL_ASIG > V_MAX_ASIGNACION THEN
        RAISE EXEC_MAX_ASIG;
    END IF;
    
    EXCEPTION WHEN EXEC_MAX_ASIG THEN
    
    -- INSERTANDO ERRORES 
    INSERT INTO ERRORES_PROCESO
                VALUES (SQ_ERRORES.NEXTVAL,'Error. profesional supera el monto límite de asignaciones. Run Nro.'||
                V_REG_MES.RUNCONFORMATO,'Se reemplazó el monto total de las agisnaciones calculadas de '||V_TOTAL_ASIG||
                ' por el monto límite de '||V_MAX_ASIGNACION);

    V_TOTAL_ASIG := V_MAX_ASIGNACION;
-- FIN BLOQUE ANIDADO
    END;
    
    --INSERTANDO TODOS LOS EMPLEADOS SEGUN LOS CALCULOS NECESARIOS
    INSERT INTO DETALLE_ASIGNACION_MES VALUES(:B_MES,:B_ANNHO,V_REG_MES.RUT,V_REG_MES.NOMBRE,
                                              V_REG_MES.PROFESION,REG_GROUP.NRO_ASESORIAS,
                                              REG_GROUP.MONTO_HONORARIOS,V_MOVIL_EXTRA,V_INCENTIVO_TOTAL,
                                              V_ASIGNACION_TOTAL,V_TOTAL_ASIG);  
  
 END LOOP;  --FIN DEL CURSOR PARA INSERTAR DATOS EN TABLA DETALLE_ASIGNACION_MES Y ERRORES_PROCESO
    
 COMMIT;
 
 --INICIANDO BLOQUE PARA CALCULAR EL RESUMEN DE MES
    BEGIN
        OPEN CUR_REG_RESUMEN_MES;
        
        LOOP
        FETCH CUR_REG_RESUMEN_MES INTO V_REG_RESUMEN_MES;
        EXIT WHEN CUR_REG_RESUMEN_MES%NOTFOUND;
     
                 INSERT INTO RESUMEN_MES_PROFESION (ANNO_MES_PROCESO,PROFESION,TOTAL_ASESORIAS,
                                                    MONTO_TOTAL_HONORARIOS,MONTO_TOTAL_MOVIL_EXTRA,
                                                    MONTO_TOTAL_ASIG_TIPOCONT,MONTO_TOTAL_ASIG_PROF,
                                                    MONTO_TOTAL_ASIGNACIONES) 
                VALUES (:B_ANNHO||LPAD(:B_MES, 2, '0'),V_REG_RESUMEN_MES.NOM,V_REG_RESUMEN_MES.NRO_AS,
                                         V_REG_RESUMEN_MES.NR_HON,V_REG_RESUMEN_MES.NR_ME,V_REG_RESUMEN_MES.NR_AT,
                                         V_REG_RESUMEN_MES.NR_AP,V_REG_RESUMEN_MES.NRO_MTA);
        
        END LOOP;       
    END;
-- FIN DEL BLOQUE
 
 COMMIT;
END;


/
--CREANDO SECUENCIA
CREATE SEQUENCE SQ_ERRORES;

-----------------------------------------------DETALLE_ASIGNACION_MES
--CONSULTANDO TABLA
SELECT * FROM DETALLE_ASIGNACION_MES;
--TRUNCANDO TABLA
TRUNCATE TABLE DETALLE_ASIGNACION_MES;

-----------------------------------------------RESUMEN_MES_PROFESION
--CONSULTANDO TABLA 
SELECT * FROM RESUMEN_MES_PROFESION;
-- TRUNCANDO TABLA
TRUNCATE TABLE RESUMEN_MES_PROFESION;

-----------------------------------------------ERRORES_PROCESO
--CONSULTANDO TABLA
SELECT * FROM ERRORES_PROCESO;
--TRUNCANDO TABLA
TRUNCATE TABLE ERRORES_PROCESO;



SELECT * FROM PROFESIONAL WHERE NUMRUN_PROF = 18505021;
SELECT * FROM COMUNA;

SELECT * FROM ASESORIA;
SELECT * FROM EMPRESA;
SELECT * FROM PROFESIONAL;
SELECT * FROM SECTOR;
SELECT * FROM COMUNA;
SELECT * FROM PROFESION;
SELECT * FROM ESTADO_CIVIL;
SELECT * FROM AFP;
SELECT * FROM ISAPRE;
SELECT * FROM TIPO_CONTRATO;
SELECT * FROM DETALLE_ASIGNACION_MES;
SELECT * FROM RESUMEN_MES_PROFESION;
SELECT * FROM PORCENTAJE_PROFESION;
SELECT * FROM ERRORES_PROCESO;
/
