-- =====================================================================
-- VIRAL ENGINE — V2: Vistas, funciones y procedimientos almacenados
-- Toda la lógica de dinero es transaccional y bloquea la billetera.
-- Nada de valores hardcodeados: todo se lee de app_config / catálogos.
-- =====================================================================

-- =====================================================================
-- VISTAS (derivados: no se almacenan, se calculan)
-- =====================================================================

CREATE OR REPLACE VIEW v_clip_metrics AS
SELECT c.id           AS clip_id,
       c.campaign_id,
       c.editor_id,
       COALESCE(SUM(p.vistas),0) AS vistas_totales,
       COALESCE(SUM(p.likes),0)  AS likes_totales,
       COUNT(p.id)               AS publicaciones
FROM clip c
LEFT JOIN clip_publication p ON p.clip_id = c.id
GROUP BY c.id, c.campaign_id, c.editor_id;

-- Garantía = suma de (presupuesto - pagado) de campañas cuyo estado computa
CREATE OR REPLACE VIEW v_wallet_summary AS
SELECT w.saldo_total,
       w.total_depositado,
       COALESCE((SELECT SUM(c.presupuesto - c.pagado)
                 FROM campaign c
                 JOIN cat_campaign_state s ON s.id = c.campaign_state_id
                 WHERE s.computa_garantia = TRUE), 0) AS en_garantia,
       w.saldo_total - COALESCE((SELECT SUM(c.presupuesto - c.pagado)
                 FROM campaign c
                 JOIN cat_campaign_state s ON s.id = c.campaign_state_id
                 WHERE s.computa_garantia = TRUE), 0) AS monto_libre
FROM business_wallet w WHERE w.id = 1;

CREATE OR REPLACE VIEW v_editor_strikes AS
SELECT u.id AS user_id,
       COALESCE(SUM(CASE WHEN s.activo THEN 1 ELSE 0 END),0) AS strikes_activos
FROM users u LEFT JOIN strike s ON s.user_id = u.id
GROUP BY u.id;

-- Tasa de aprobación del editor (para el umbral de extras)
CREATE OR REPLACE VIEW v_editor_qa_rate AS
SELECT c.editor_id,
       SUM(q.codigo = 'APROBADO')                              AS aprobados,
       SUM(q.codigo IN ('APROBADO','NO_APROBADO'))             AS evaluados,
       CASE WHEN SUM(q.codigo IN ('APROBADO','NO_APROBADO')) = 0 THEN NULL
            ELSE SUM(q.codigo = 'APROBADO') / SUM(q.codigo IN ('APROBADO','NO_APROBADO'))
       END AS tasa_aprobacion
FROM clip c JOIN cat_qa_state q ON q.id = c.qa_state_id
GROUP BY c.editor_id;

-- Ranking de editores (métricas base; el score mixto se pondera en app_config)
CREATE OR REPLACE VIEW v_editor_ranking AS
SELECT u.id AS editor_id, u.nombre,
       COALESCE(SUM(m.vistas_totales),0)                    AS vistas_totales,
       COUNT(DISTINCT CASE WHEN q.codigo='APROBADO' THEN c.id END) AS clips_aprobados,
       COALESCE((SELECT SUM(p.total) FROM payment p WHERE p.editor_id = u.id),0) AS ganancias
FROM users u
JOIN cat_user_type t ON t.id = u.user_type_id AND t.codigo = 'EDITOR'
LEFT JOIN clip c          ON c.editor_id = u.id
LEFT JOIN cat_qa_state q  ON q.id = c.qa_state_id
LEFT JOIN v_clip_metrics m ON m.clip_id = c.id
GROUP BY u.id, u.nombre;

-- =====================================================================
-- FUNCIONES
-- =====================================================================
DELIMITER $$

CREATE FUNCTION fn_monto_libre() RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v DECIMAL(12,2);
    SELECT monto_libre INTO v FROM v_wallet_summary;
    RETURN COALESCE(v,0);
END$$

CREATE FUNCTION fn_strikes_activos(p_user_id BIGINT) RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v INT;
    SELECT COUNT(*) INTO v FROM strike WHERE user_id = p_user_id AND activo = TRUE;
    RETURN COALESCE(v,0);
END$$

-- Escalón alcanzado según el tabulador SNAPSHOT de la campaña
CREATE FUNCTION fn_bono_escalon(p_campaign_id BIGINT, p_tipo VARCHAR(30), p_vistas BIGINT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v DECIMAL(12,2);
    SELECT COALESCE(MAX(t.bono),0) INTO v
    FROM campaign_bonus_tier t
    JOIN cat_tier_type tt ON tt.id = t.tier_type_id
    WHERE t.campaign_id = p_campaign_id AND tt.codigo = p_tipo AND p_vistas >= t.vistas_min;
    RETURN COALESCE(v,0);
END$$

-- =====================================================================
-- PROCEDIMIENTOS — BILLETERA
-- =====================================================================

-- Depósito manual (no mueve dinero real; es un registro)
CREATE PROCEDURE sp_wallet_deposito(IN p_monto DECIMAL(12,2), IN p_user_id BIGINT, IN p_nota VARCHAR(500))
BEGIN
    DECLARE v_tipo TINYINT;
    IF p_monto IS NULL OR p_monto <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El monto debe ser mayor a cero';
    END IF;
    START TRANSACTION;
        SELECT id INTO v_tipo FROM cat_movement_type WHERE codigo='DEPOSITO';
        SELECT id FROM business_wallet WHERE id=1 FOR UPDATE;   -- bloqueo de fila
        UPDATE business_wallet
           SET saldo_total = saldo_total + p_monto,
               total_depositado = total_depositado + p_monto
         WHERE id = 1;
        INSERT INTO wallet_movement (movement_type_id, monto, nota, hecho_por)
        VALUES (v_tipo, p_monto, p_nota, p_user_id);
    COMMIT;
END$$

-- =====================================================================
-- PROCEDIMIENTOS — CAMPAÑAS
-- =====================================================================

-- Activa la campaña: valida saldo libre y aparta la garantía.
CREATE PROCEDURE sp_campaign_activar(IN p_campaign_id BIGINT, IN p_user_id BIGINT)
BEGIN
    DECLARE v_presupuesto DECIMAL(12,2);
    DECLARE v_libre DECIMAL(12,2);
    DECLARE v_estado TINYINT;
    DECLARE v_tipo TINYINT;

    START TRANSACTION;
        SELECT id FROM business_wallet WHERE id=1 FOR UPDATE;
        SELECT presupuesto INTO v_presupuesto FROM campaign WHERE id = p_campaign_id FOR UPDATE;
        SET v_libre = fn_monto_libre();

        IF v_presupuesto > v_libre THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Saldo libre insuficiente para activar la campaña';
        END IF;

        SELECT id INTO v_estado FROM cat_campaign_state WHERE codigo='ACTIVA';
        SELECT id INTO v_tipo   FROM cat_movement_type  WHERE codigo='APARTADO_GARANTIA';

        UPDATE campaign SET campaign_state_id = v_estado, version = version + 1 WHERE id = p_campaign_id;
        INSERT INTO wallet_movement (movement_type_id, monto, campaign_id, nota, hecho_por)
        VALUES (v_tipo, v_presupuesto, p_campaign_id, 'Garantía apartada al activar', p_user_id);
    COMMIT;
END$$

-- Cierra o cancela: libera lo no gastado (presupuesto - pagado)
CREATE PROCEDURE sp_campaign_finalizar(IN p_campaign_id BIGINT, IN p_estado_codigo VARCHAR(30), IN p_user_id BIGINT)
BEGIN
    DECLARE v_presupuesto DECIMAL(12,2);
    DECLARE v_pagado DECIMAL(12,2);
    DECLARE v_estado TINYINT;
    DECLARE v_tipo TINYINT;

    SELECT id INTO v_estado FROM cat_campaign_state WHERE codigo = p_estado_codigo AND es_final = TRUE;
    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estado final inválido';
    END IF;

    START TRANSACTION;
        SELECT id FROM business_wallet WHERE id=1 FOR UPDATE;
        SELECT presupuesto, pagado INTO v_presupuesto, v_pagado
          FROM campaign WHERE id = p_campaign_id FOR UPDATE;

        SELECT id INTO v_tipo FROM cat_movement_type WHERE codigo='LIBERACION_GARANTIA';

        UPDATE campaign SET campaign_state_id = v_estado, version = version + 1 WHERE id = p_campaign_id;

        IF (v_presupuesto - v_pagado) > 0 THEN
            INSERT INTO wallet_movement (movement_type_id, monto, campaign_id, nota, hecho_por)
            VALUES (v_tipo, v_presupuesto - v_pagado, p_campaign_id, 'Liberación de garantía no gastada', p_user_id);
        END IF;
    COMMIT;
END$$

-- =====================================================================
-- PROCEDIMIENTOS — PAGOS
-- =====================================================================

CREATE PROCEDURE sp_payment_marcar_pagado(
    IN p_payment_id BIGINT, IN p_referencia VARCHAR(200), IN p_user_id BIGINT)
BEGIN
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_campaign BIGINT;
    DECLARE v_saldo DECIMAL(12,2);
    DECLARE v_pagado TINYINT;
    DECLARE v_tipo TINYINT;
    DECLARE v_estado_actual TINYINT;

    START TRANSACTION;
        SELECT saldo_total INTO v_saldo FROM business_wallet WHERE id=1 FOR UPDATE;
        SELECT total, campaign_id, payment_state_id
          INTO v_total, v_campaign, v_estado_actual
          FROM payment WHERE id = p_payment_id FOR UPDATE;

        SELECT id INTO v_pagado FROM cat_payment_state WHERE codigo='PAGADO';

        IF v_estado_actual = v_pagado THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El pago ya estaba marcado como pagado';
        END IF;
        IF v_total > v_saldo THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Saldo insuficiente en la billetera';
        END IF;

        SELECT id INTO v_tipo FROM cat_movement_type WHERE codigo='PAGO_EDITOR';

        UPDATE business_wallet SET saldo_total = saldo_total - v_total WHERE id = 1;
        UPDATE campaign SET pagado = pagado + v_total, version = version + 1 WHERE id = v_campaign;
        UPDATE payment
           SET payment_state_id = v_pagado, fecha_pago = NOW(6),
               referencia = p_referencia, marcado_por = p_user_id
         WHERE id = p_payment_id;

        INSERT INTO wallet_movement (movement_type_id, monto, campaign_id, nota, hecho_por)
        VALUES (v_tipo, v_total, v_campaign, CONCAT('Pago a editor. Ref: ', COALESCE(p_referencia,'')), p_user_id);
    COMMIT;
END$$

-- =====================================================================
-- PROCEDIMIENTOS — STRIKES
-- =====================================================================

CREATE PROCEDURE sp_strike_aplicar(
    IN p_user_id BIGINT, IN p_campaign_id BIGINT, IN p_clip_id BIGINT,
    IN p_motivo VARCHAR(500), IN p_admin_id BIGINT)
BEGIN
    DECLARE v_activos INT;
    DECLARE v_limite INT;
    DECLARE v_removido TINYINT;

    START TRANSACTION;
        INSERT INTO strike (user_id, campaign_id, clip_id, motivo, aplicado_por)
        VALUES (p_user_id, p_campaign_id, p_clip_id, p_motivo, p_admin_id);

        -- El clip queda excluido de bonos pero conserva su pago base (TyC §5)
        IF p_clip_id IS NOT NULL THEN
            UPDATE clip SET excluido_bonos = TRUE WHERE id = p_clip_id;
        END IF;

        SELECT strikes_para_remocion INTO v_limite FROM app_config WHERE id = 1;
        SET v_activos = fn_strikes_activos(p_user_id);

        IF v_activos >= v_limite THEN
            SELECT id INTO v_removido FROM cat_user_state WHERE codigo='REMOVIDO';
            UPDATE users SET user_state_id = v_removido WHERE id = p_user_id;
        END IF;
    COMMIT;
END$$

CREATE PROCEDURE sp_strike_quitar(
    IN p_strike_id BIGINT, IN p_admin_id BIGINT, IN p_motivo VARCHAR(500))
BEGIN
    DECLARE v_user BIGINT;
    DECLARE v_activos INT;
    DECLARE v_limite INT;
    DECLARE v_activo_state TINYINT;

    START TRANSACTION;
        SELECT user_id INTO v_user FROM strike WHERE id = p_strike_id FOR UPDATE;

        UPDATE strike
           SET activo = FALSE, removido_por = p_admin_id,
               removido_at = NOW(6), motivo_remocion = p_motivo
         WHERE id = p_strike_id;

        SELECT strikes_para_remocion INTO v_limite FROM app_config WHERE id = 1;
        SET v_activos = fn_strikes_activos(v_user);

        -- Si baja del límite, se reactiva al editor
        IF v_activos < v_limite THEN
            SELECT id INTO v_activo_state FROM cat_user_state WHERE codigo='ACTIVO';
            UPDATE users SET user_state_id = v_activo_state
             WHERE id = v_user AND user_state_id = (SELECT id FROM cat_user_state WHERE codigo='REMOVIDO');
        END IF;
    COMMIT;
END$$

-- =====================================================================
-- PROCEDIMIENTO — MOTOR DE BOLSAS (PRORRATEO, TyC §3.5)
-- Todo el que califica cobra. Si el nominal excede la sub-bolsa,
-- se aplica factor = sub_bolsa / nominal a TODOS los participantes.
-- =====================================================================

CREATE PROCEDURE sp_calcular_pagos(IN p_campaign_id BIGINT, IN p_user_id BIGINT)
BEGIN
    DECLARE v_num_videos INT;
    DECLARE v_presupuesto, v_base_clip, v_pct_a, v_pct_b, v_pct_c DECIMAL(12,4);
    DECLARE v_premio_fijo DECIMAL(12,2);
    DECLARE v_pool_base, v_bolsa, v_sub_a, v_sub_b, v_sub_c DECIMAL(12,2);
    DECLARE v_nominal_a, v_nominal_b DECIMAL(12,2);
    DECLARE v_factor_a, v_factor_b DECIMAL(9,6);
    DECLARE v_top_clip BIGINT;
    DECLARE v_top_editor BIGINT;
    DECLARE v_pendiente TINYINT;

    SELECT c.num_videos, c.presupuesto, cc.base_por_clip, cc.pct_a, cc.pct_b, cc.pct_c, cc.premio_1_monto_fijo
      INTO v_num_videos, v_presupuesto, v_base_clip, v_pct_a, v_pct_b, v_pct_c, v_premio_fijo
      FROM campaign c JOIN campaign_config cc ON cc.campaign_id = c.id
     WHERE c.id = p_campaign_id;

    SET v_pool_base = v_num_videos * v_base_clip;
    SET v_bolsa     = v_presupuesto - v_pool_base;
    SET v_sub_a     = ROUND(v_bolsa * v_pct_a, 2);
    SET v_sub_b     = ROUND(v_bolsa * v_pct_b, 2);
    SET v_sub_c     = IFNULL(v_premio_fijo, ROUND(v_bolsa * v_pct_c, 2));

    -- Clips elegibles: aprobados y no excluidos de bonos
    DROP TEMPORARY TABLE IF EXISTS tmp_clips;
    CREATE TEMPORARY TABLE tmp_clips AS
    SELECT c.id AS clip_id, c.editor_id, m.vistas_totales,
           fn_bono_escalon(p_campaign_id,'CLIP', m.vistas_totales) AS bono_nominal
      FROM clip c
      JOIN cat_qa_state q     ON q.id = c.qa_state_id AND q.participa_bonos = TRUE
      JOIN v_clip_metrics m   ON m.clip_id = c.id
     WHERE c.campaign_id = p_campaign_id AND c.excluido_bonos = FALSE;

    -- Sub-bolsa A: prorrateo
    SELECT COALESCE(SUM(bono_nominal),0) INTO v_nominal_a FROM tmp_clips;
    SET v_factor_a = IF(v_nominal_a > v_sub_a AND v_nominal_a > 0, v_sub_a / v_nominal_a, 1.000000);

    -- Sub-bolsa B: acumulado por editor
    DROP TEMPORARY TABLE IF EXISTS tmp_editores;
    CREATE TEMPORARY TABLE tmp_editores AS
    SELECT editor_id, SUM(vistas_totales) AS vistas_acum,
           fn_bono_escalon(p_campaign_id,'EDITOR', SUM(vistas_totales)) AS bono_nominal
      FROM tmp_clips GROUP BY editor_id;

    SELECT COALESCE(SUM(bono_nominal),0) INTO v_nominal_b FROM tmp_editores;
    SET v_factor_b = IF(v_nominal_b > v_sub_b AND v_nominal_b > 0, v_sub_b / v_nominal_b, 1.000000);

    -- Sub-bolsa C: clip #1 por vistas
    SELECT clip_id, editor_id INTO v_top_clip, v_top_editor
      FROM tmp_clips ORDER BY vistas_totales DESC, clip_id ASC LIMIT 1;

    SELECT id INTO v_pendiente FROM cat_payment_state WHERE codigo='PENDIENTE';

    START TRANSACTION;
        -- RECÁLCULO SEGURO: solo se tocan pagos PENDIENTES. Los ya PAGADOS
        -- se conservan intactos (nunca se recalcula dinero ya liquidado).
        UPDATE payment
           SET bono_escalon = 0, bono_acumulado = 0, premio_1 = 0
         WHERE campaign_id = p_campaign_id AND payment_state_id = v_pendiente;

        -- Base: $X por cada clip APROBADO (aunque esté excluido de bonos)
        INSERT INTO payment (campaign_id, editor_id, pago_base, bono_escalon, bono_acumulado, premio_1, payment_state_id)
        SELECT p_campaign_id, c.editor_id,
               COUNT(*) * v_base_clip, 0, 0, 0, v_pendiente
          FROM clip c JOIN cat_qa_state q ON q.id = c.qa_state_id AND q.paga_base = TRUE
         WHERE c.campaign_id = p_campaign_id
         GROUP BY c.editor_id
            ON DUPLICATE KEY UPDATE
               pago_base = IF(payment_state_id = v_pendiente, VALUES(pago_base), pago_base);

        -- Sub-bolsa A prorrateada, agregada por editor (solo PENDIENTES)
        UPDATE payment p
          JOIN (SELECT editor_id, ROUND(SUM(bono_nominal) * v_factor_a, 2) AS bono
                  FROM tmp_clips GROUP BY editor_id) x ON x.editor_id = p.editor_id
           SET p.bono_escalon = x.bono
         WHERE p.campaign_id = p_campaign_id AND p.payment_state_id = v_pendiente;

        -- Sub-bolsa B prorrateada (solo PENDIENTES)
        UPDATE payment p
          JOIN (SELECT editor_id, ROUND(bono_nominal * v_factor_b, 2) AS bono
                  FROM tmp_editores) y ON y.editor_id = p.editor_id
           SET p.bono_acumulado = y.bono
         WHERE p.campaign_id = p_campaign_id AND p.payment_state_id = v_pendiente;

        -- Premio al clip #1 (solo PENDIENTES)
        IF v_top_editor IS NOT NULL THEN
            UPDATE payment SET premio_1 = v_sub_c
             WHERE campaign_id = p_campaign_id AND editor_id = v_top_editor
               AND payment_state_id = v_pendiente;
        END IF;

        INSERT INTO payout_run (campaign_id, ejecutado_por, pool_base, bolsa_bonos,
                                sub_bolsa_a, sub_bolsa_b, sub_bolsa_c,
                                nominal_a, factor_a, nominal_b, factor_b, total_calculado)
        SELECT p_campaign_id, p_user_id, v_pool_base, v_bolsa, v_sub_a, v_sub_b, v_sub_c,
               v_nominal_a, v_factor_a, v_nominal_b, v_factor_b,
               COALESCE(SUM(total),0)
          FROM payment WHERE campaign_id = p_campaign_id;
    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_clips;
    DROP TEMPORARY TABLE IF EXISTS tmp_editores;
END$$

DELIMITER ;
