-- =====================================================================
-- PRUEBA DE REGRESIÓN — Reglas de dinero de Viral Engine
--
-- Verifica las cuatro reglas que cuestan dinero si se rompen y que no avisan
-- cuando lo hacen. Todas se han roto alguna vez en este proyecto.
--
--   1. No se pueden aprobar más clips de los presupuestados   (V7 / V16)
--   2. No se puede aprobar un clip sin publicación            (V16)
--   3. El premio al clip #1 exige vistas > 0                  (V18)
--   4. A + B + C == bolsa, sin exceder el presupuesto         (V10)
--
-- CÓMO CORRERLA
--   mysql -h HOST -P PUERTO -u USUARIO -p BASE < prueba_reglas_de_dinero.sql
--
-- CUÁNDO
--   Después de cualquier cambio a sp_clip_qa, sp_calcular_pagos o
--   sp_campaign_crear. La regla 1 en particular vive dentro de sp_clip_qa: si
--   alguien reescribe ese procedimiento sin acordarse del tope, se pierde y no
--   hay forma de enterarse hasta que una campaña apruebe de más.
--
-- ADVERTENCIA
--   Los procedimientos hacen COMMIT internamente, así que esto ESCRIBE datos
--   reales y luego los borra. Córrela contra una base de pruebas, no contra
--   producción. Todo lo que crea lleva el prefijo ZZZ_PRUEBA para que sea
--   identificable si algo falla a la mitad y hay que limpiar a mano.
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_zzz_prueba_reglas;

DELIMITER $$

CREATE PROCEDURE sp_zzz_prueba_reglas()
BEGIN
    DECLARE v_admin      BIGINT;
    DECLARE v_editor     BIGINT;
    DECLARE v_campaign   BIGINT;
    DECLARE v_cuenta     BIGINT;
    DECLARE v_clip1      BIGINT;
    DECLARE v_clip2      BIGINT;
    DECLARE v_clip3      BIGINT;
    DECLARE v_fallo      TINYINT DEFAULT 0;
    DECLARE v_premio     DECIMAL(12,2);
    DECLARE v_a          DECIMAL(12,2);
    DECLARE v_b          DECIMAL(12,2);
    DECLARE v_c          DECIMAL(12,2);
    DECLARE v_bolsa      DECIMAL(12,2);
    DECLARE v_errores    INT DEFAULT 0;

    -- Handler para las pruebas que ESPERAN un error: marca la bandera
    -- en vez de abortar el procedimiento.
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_fallo = 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_resultados;
    CREATE TEMPORARY TABLE tmp_resultados (
        n INT, regla VARCHAR(120), esperado VARCHAR(80),
        obtenido VARCHAR(80), resultado VARCHAR(10));

    -- ---------------------------------------------------------------
    -- Preparación
    -- ---------------------------------------------------------------
    INSERT INTO users (nombre, email, password_hash, user_type_id, user_state_id)
    SELECT 'ZZZ_PRUEBA Admin', 'zzz_prueba_admin@local', 'x',
           (SELECT id FROM cat_user_type  WHERE codigo='ADMIN'),
           (SELECT id FROM cat_user_state WHERE codigo='ACTIVO');
    SET v_admin = LAST_INSERT_ID();

    INSERT INTO users (nombre, email, password_hash, user_type_id, user_state_id)
    SELECT 'ZZZ_PRUEBA Editor', 'zzz_prueba_editor@local', 'x',
           (SELECT id FROM cat_user_type  WHERE codigo='EDITOR'),
           (SELECT id FROM cat_user_state WHERE codigo='ACTIVO');
    SET v_editor = LAST_INSERT_ID();

    INSERT INTO editor_account (user_id, platform_id, handle, url)
    SELECT v_editor, id, 'zzzpruebacandado', 'https://www.tiktok.com/@zzzpruebacandado'
      FROM cat_platform WHERE codigo='TIKTOK';
    SET v_cuenta = LAST_INSERT_ID();

    -- Campaña de 2 videos y $1,000:
    --   pool_base = 2 x 10 = 20   |   bolsa = 980
    --   C = 300  |  resto 680  ->  A = 480.00  B = 200.00
    CALL sp_campaign_crear('ZZZ_PRUEBA Candado', NULL, NULL, NULL, NULL,
                           NULL, NULL, NULL, NULL,
                           2, 1000.00, NULL, v_admin, @cid);
    SET v_campaign = @cid;

    INSERT INTO editor_assignment (campaign_id, user_id) VALUES (v_campaign, v_editor);

    -- Tres clips con publicación, para poder aprobarlos
    INSERT INTO clip (campaign_id, editor_id, titulo, fecha_publicado, qa_state_id)
    SELECT v_campaign, v_editor, 'ZZZ_PRUEBA clip 1', NOW(6), id
      FROM cat_qa_state WHERE codigo='SUBIDO';
    SET v_clip1 = LAST_INSERT_ID();

    INSERT INTO clip (campaign_id, editor_id, titulo, fecha_publicado, qa_state_id)
    SELECT v_campaign, v_editor, 'ZZZ_PRUEBA clip 2', NOW(6), id
      FROM cat_qa_state WHERE codigo='SUBIDO';
    SET v_clip2 = LAST_INSERT_ID();

    INSERT INTO clip (campaign_id, editor_id, titulo, fecha_publicado, qa_state_id)
    SELECT v_campaign, v_editor, 'ZZZ_PRUEBA clip 3', NOW(6), id
      FROM cat_qa_state WHERE codigo='SUBIDO';
    SET v_clip3 = LAST_INSERT_ID();

    -- Publicaciones directas (sin el SP) para no chocar con los topes diarios
    INSERT INTO clip_publication (clip_id, editor_account_id, platform_id, link)
    SELECT v_clip1, v_cuenta, id, 'https://www.tiktok.com/@zzzpruebacandado/video/1'
      FROM cat_platform WHERE codigo='TIKTOK';
    INSERT INTO clip_publication (clip_id, editor_account_id, platform_id, link)
    SELECT v_clip2, v_cuenta, id, 'https://www.tiktok.com/@zzzpruebacandado/video/2'
      FROM cat_platform WHERE codigo='TIKTOK';
    -- El clip 3 se queda A PROPÓSITO sin publicación (prueba 2)

    -- ---------------------------------------------------------------
    -- Prueba 2 primero: aprobar un clip SIN publicación debe fallar
    -- ---------------------------------------------------------------
    SET v_fallo = 0;
    CALL sp_clip_qa(v_clip3, 'APROBADO', 'prueba', v_admin);
    INSERT INTO tmp_resultados VALUES
      (2, 'Aprobar clip sin publicacion', 'rechaza',
       IF(v_fallo=1,'rechaza','ACEPTO'), IF(v_fallo=1,'PASA','FALLA'));
    IF v_fallo = 0 THEN SET v_errores = v_errores + 1; END IF;

    -- Se le agrega publicación para poder usarlo en la prueba del tope
    INSERT INTO clip_publication (clip_id, editor_account_id, platform_id, link)
    SELECT v_clip3, v_cuenta, id, 'https://www.tiktok.com/@zzzpruebacandado/video/3'
      FROM cat_platform WHERE codigo='TIKTOK';

    -- ---------------------------------------------------------------
    -- Prueba 1: el tope de videos presupuestados
    -- ---------------------------------------------------------------
    SET v_fallo = 0;
    CALL sp_clip_qa(v_clip1, 'APROBADO', '', v_admin);
    CALL sp_clip_qa(v_clip2, 'APROBADO', '', v_admin);
    INSERT INTO tmp_resultados VALUES
      (0, 'Aprobar los 2 clips presupuestados', 'acepta',
       IF(v_fallo=0,'acepta','RECHAZO'), IF(v_fallo=0,'PASA','FALLA'));
    IF v_fallo = 1 THEN SET v_errores = v_errores + 1; END IF;

    SET v_fallo = 0;
    CALL sp_clip_qa(v_clip3, 'APROBADO', '', v_admin);   -- el tercero de dos
    INSERT INTO tmp_resultados VALUES
      (1, 'Aprobar un clip de mas (tope de la campana)', 'rechaza',
       IF(v_fallo=1,'rechaza','ACEPTO'), IF(v_fallo=1,'PASA','FALLA'));
    IF v_fallo = 0 THEN SET v_errores = v_errores + 1; END IF;

    -- ---------------------------------------------------------------
    -- Pruebas 3 y 4: el reparto
    -- ---------------------------------------------------------------
    SET v_fallo = 0;
    CALL sp_calcular_pagos(v_campaign, v_admin);

    SELECT COALESCE(SUM(premio_1),0) INTO v_premio
      FROM payment WHERE campaign_id = v_campaign;
    INSERT INTO tmp_resultados VALUES
      (3, 'Premio al clip #1 con 0 vistas', '0.00',
       CAST(v_premio AS CHAR), IF(v_premio = 0,'PASA','FALLA'));
    IF v_premio <> 0 THEN SET v_errores = v_errores + 1; END IF;

    SELECT sub_bolsa_a, sub_bolsa_b, bolsa_bonos
      INTO v_a, v_b, v_bolsa
      FROM payout_run WHERE campaign_id = v_campaign
     ORDER BY id DESC LIMIT 1;
    -- sub_bolsa_c en payout_run guarda lo REPARTIDO (0 si no hubo ganador), así
    -- que el premio APARTADO se relee de la configuración de la campaña. No se
    -- escribe 300 a mano: si el cliente cambia el premio, la prueba debe seguir
    -- siendo válida en vez de fallar por un número viejo.
    SELECT LEAST(COALESCE(premio_1_monto_fijo, ROUND(v_bolsa * pct_c, 2)), v_bolsa)
      INTO v_c FROM campaign_config WHERE campaign_id = v_campaign;
    INSERT INTO tmp_resultados VALUES
      (4, 'A + B + C == bolsa', CAST(v_bolsa AS CHAR),
       CAST(v_a + v_b + v_c AS CHAR),
       IF(v_a + v_b + v_c = v_bolsa,'PASA','FALLA'));
    IF v_a + v_b + v_c <> v_bolsa THEN SET v_errores = v_errores + 1; END IF;

    -- ---------------------------------------------------------------
    -- Limpieza
    -- ---------------------------------------------------------------
    DELETE FROM payment            WHERE campaign_id = v_campaign;
    DELETE FROM payout_run         WHERE campaign_id = v_campaign;
    DELETE FROM clip_publication   WHERE clip_id IN (v_clip1, v_clip2, v_clip3);
    DELETE FROM clip               WHERE campaign_id = v_campaign;
    DELETE FROM assignment_account WHERE editor_account_id = v_cuenta;
    DELETE FROM editor_assignment  WHERE campaign_id = v_campaign;
    DELETE FROM campaign_bonus_tier WHERE campaign_id = v_campaign;
    DELETE FROM campaign_config    WHERE campaign_id = v_campaign;
    DELETE FROM campaign           WHERE id = v_campaign;
    DELETE FROM editor_account     WHERE id = v_cuenta;
    DELETE FROM audit_log          WHERE user_id IN (v_admin, v_editor);
    DELETE FROM users              WHERE id IN (v_admin, v_editor);

    -- ---------------------------------------------------------------
    -- Resultado
    -- ---------------------------------------------------------------
    SELECT n AS `#`, regla, esperado, obtenido, resultado
      FROM tmp_resultados ORDER BY n;

    SELECT IF(v_errores = 0,
              'TODAS LAS REGLAS PASAN',
              CONCAT('*** ', v_errores, ' REGLA(S) ROTA(S) — revisar arriba ***')) AS veredicto;

    DROP TEMPORARY TABLE IF EXISTS tmp_resultados;
END$$

DELIMITER ;

CALL sp_zzz_prueba_reglas();

DROP PROCEDURE IF EXISTS sp_zzz_prueba_reglas;
