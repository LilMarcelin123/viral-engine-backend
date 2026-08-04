-- =====================================================================
-- V18 — El Premio al clip #1 exige que el ganador tenga vistas.
--
-- El procedimiento elegía al ganador con:
--     ORDER BY vistas_totales DESC, clip_id ASC LIMIT 1
-- Con todos los clips en 0 vistas el desempate cae en clip_id, así que
-- ganaba el clip MÁS VIEJO y se pagaban $300 sin que nadie hubiera generado
-- una sola vista. Se detectó en producción: un editor con 1 clip aprobado y
-- 0 vistas tenía $310 por cobrar ($10 de base + $300 de premio).
--
-- El caso es fácil de alcanzar porque el scraping todavía no existe: hasta que
-- corra, TODOS los clips tienen 0 vistas.
--
-- Regla nueva: si el mejor clip no tiene vistas, no hay premio. Los $300
-- simplemente no se reparten y quedan disponibles en el presupuesto.
-- El resto del cálculo (base, sub-bolsas A y B, prorrateo) no cambia.
-- =====================================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_calcular_pagos$$

CREATE PROCEDURE sp_calcular_pagos(IN p_campaign_id BIGINT, IN p_user_id BIGINT)
BEGIN
    DECLARE v_num_videos INT;
    DECLARE v_presupuesto, v_base_clip, v_pct_a, v_pct_b, v_pct_c DECIMAL(12,4);
    DECLARE v_premio_fijo DECIMAL(12,2);
    DECLARE v_pool_base, v_bolsa, v_resto, v_sub_a, v_sub_b, v_sub_c DECIMAL(12,2);
    DECLARE v_nominal_a, v_nominal_b DECIMAL(12,2);
    DECLARE v_factor_a, v_factor_b DECIMAL(9,6);
    DECLARE v_top_clip BIGINT;
    DECLARE v_top_editor BIGINT;
    DECLARE v_top_vistas BIGINT;
    DECLARE v_pendiente TINYINT;

    SELECT c.num_videos, c.presupuesto, cc.base_por_clip, cc.pct_a, cc.pct_b, cc.pct_c, cc.premio_1_monto_fijo
      INTO v_num_videos, v_presupuesto, v_base_clip, v_pct_a, v_pct_b, v_pct_c, v_premio_fijo
      FROM campaign c JOIN campaign_config cc ON cc.campaign_id = c.id
     WHERE c.id = p_campaign_id;

    SET v_pool_base = v_num_videos * v_base_clip;
    SET v_bolsa     = v_presupuesto - v_pool_base;

    -- El premio se aparta primero (V10)
    SET v_sub_c = IF(v_premio_fijo IS NULL,
                     ROUND(v_bolsa * v_pct_c, 2),
                     LEAST(v_premio_fijo, GREATEST(v_bolsa, 0)));
    SET v_resto = GREATEST(v_bolsa - v_sub_c, 0);
    SET v_sub_a = ROUND(v_resto * v_pct_a / NULLIF(v_pct_a + v_pct_b, 0), 2);
    SET v_sub_b = v_resto - v_sub_a;

    DROP TEMPORARY TABLE IF EXISTS tmp_clips;
    CREATE TEMPORARY TABLE tmp_clips AS
    SELECT c.id AS clip_id, c.editor_id, m.vistas_totales,
           fn_bono_escalon(p_campaign_id,'CLIP', m.vistas_totales) AS bono_nominal
      FROM clip c
      JOIN cat_qa_state q     ON q.id = c.qa_state_id AND q.participa_bonos = TRUE
      JOIN v_clip_metrics m   ON m.clip_id = c.id
     WHERE c.campaign_id = p_campaign_id AND c.excluido_bonos = FALSE;

    SELECT COALESCE(SUM(bono_nominal),0) INTO v_nominal_a FROM tmp_clips;
    SET v_factor_a = IF(v_nominal_a > v_sub_a AND v_nominal_a > 0, v_sub_a / v_nominal_a, 1.000000);

    DROP TEMPORARY TABLE IF EXISTS tmp_editores;
    CREATE TEMPORARY TABLE tmp_editores AS
    SELECT editor_id, SUM(vistas_totales) AS vistas_acum,
           fn_bono_escalon(p_campaign_id,'EDITOR', SUM(vistas_totales)) AS bono_nominal
      FROM tmp_clips GROUP BY editor_id;

    SELECT COALESCE(SUM(bono_nominal),0) INTO v_nominal_b FROM tmp_editores;
    SET v_factor_b = IF(v_nominal_b > v_sub_b AND v_nominal_b > 0, v_sub_b / v_nominal_b, 1.000000);

    -- Sub-bolsa C: clip #1 por vistas.
    -- V18: sin vistas no hay ganador. Antes el desempate por clip_id premiaba
    -- al clip más viejo aunque nadie hubiera generado una sola vista.
    SET v_top_clip = NULL;
    SET v_top_editor = NULL;
    SELECT clip_id, editor_id, vistas_totales
      INTO v_top_clip, v_top_editor, v_top_vistas
      FROM tmp_clips
     WHERE vistas_totales > 0
     ORDER BY vistas_totales DESC, clip_id ASC LIMIT 1;

    SELECT id INTO v_pendiente FROM cat_payment_state WHERE codigo='PENDIENTE';

    START TRANSACTION;
        UPDATE payment
           SET bono_escalon = 0, bono_acumulado = 0, premio_1 = 0
         WHERE campaign_id = p_campaign_id AND payment_state_id = v_pendiente;

        INSERT INTO payment (campaign_id, editor_id, pago_base, bono_escalon, bono_acumulado, premio_1, payment_state_id)
        SELECT p_campaign_id, c.editor_id,
               COUNT(*) * v_base_clip, 0, 0, 0, v_pendiente
          FROM clip c JOIN cat_qa_state q ON q.id = c.qa_state_id AND q.paga_base = TRUE
         WHERE c.campaign_id = p_campaign_id
         GROUP BY c.editor_id
            ON DUPLICATE KEY UPDATE
               pago_base = IF(payment_state_id = v_pendiente, VALUES(pago_base), pago_base);

        UPDATE payment p
          JOIN (SELECT editor_id, ROUND(SUM(bono_nominal) * v_factor_a, 2) AS bono
                  FROM tmp_clips GROUP BY editor_id) x ON x.editor_id = p.editor_id
           SET p.bono_escalon = x.bono
         WHERE p.campaign_id = p_campaign_id AND p.payment_state_id = v_pendiente;

        UPDATE payment p
          JOIN (SELECT editor_id, ROUND(bono_nominal * v_factor_b, 2) AS bono
                  FROM tmp_editores) y ON y.editor_id = p.editor_id
           SET p.bono_acumulado = y.bono
         WHERE p.campaign_id = p_campaign_id AND p.payment_state_id = v_pendiente;

        IF v_top_editor IS NOT NULL THEN
            UPDATE payment SET premio_1 = v_sub_c
             WHERE campaign_id = p_campaign_id AND editor_id = v_top_editor
               AND payment_state_id = v_pendiente;
        END IF;

        INSERT INTO payout_run (campaign_id, ejecutado_por, pool_base, bolsa_bonos,
                                sub_bolsa_a, sub_bolsa_b, sub_bolsa_c,
                                nominal_a, factor_a, nominal_b, factor_b, total_calculado)
        SELECT p_campaign_id, p_user_id, v_pool_base, v_bolsa, v_sub_a, v_sub_b,
               IF(v_top_editor IS NULL, 0, v_sub_c),
               v_nominal_a, v_factor_a, v_nominal_b, v_factor_b,
               COALESCE(SUM(total),0)
          FROM payment WHERE campaign_id = p_campaign_id;
    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_clips;
    DROP TEMPORARY TABLE IF EXISTS tmp_editores;
END$$

DELIMITER ;
