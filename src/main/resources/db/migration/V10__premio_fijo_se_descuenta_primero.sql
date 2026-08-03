-- =====================================================================
-- V10 — El Premio #1 fijo se descuenta ANTES de repartir A y B.
--
-- Problema que corrige:
-- El tabulador reparte la bolsa 60/25/15 (A/B/C) y hay un CHECK que obliga a
-- que esos porcentajes sumen 1. Pero el cliente fijó el Premio #1 en $300, así
-- que C dejó de ser el 15%. El resultado era que A+B+C podía superar la bolsa:
--
--     bolsa * 0.85 + 300  >  bolsa   siempre que  bolsa < 2000
--
-- Con una bolsa de $950 el sistema comprometía $1,107.50 contra un presupuesto
-- de $1,000. No se perdía dinero (el CHECK ck_campaign_pagado habría rechazado
-- el último pago) pero el descuadre aparecía DESPUÉS de prometerle montos a los
-- editores, y la garantía en la billetera reservaba de menos.
--
-- Regla nueva:
--   1. C = premio fijo (o el pct_c si no hay premio fijo configurado)
--   2. A y B se reparten lo que sobra, conservando su proporción 60:25
--
-- El premio nunca cambia y el presupuesto nunca se excede. A y B dejan de ser
-- el 60% y 25% literales de la bolsa para ser el 60:25 del remanente.
--
-- Ejemplo (bolsa $950, premio $300):
--   resto = 650 ->  A = 650 * 0.60/0.85 = 458.82 ;  B = 191.18 ;  C = 300
--   suma exacta = 950
--
-- Si NO hay premio fijo (premio_1_monto_fijo IS NULL) el comportamiento es
-- idéntico al anterior: los tres porcentajes suman 1 y la cuenta ya cerraba.
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
    DECLARE v_pendiente TINYINT;

    SELECT c.num_videos, c.presupuesto, cc.base_por_clip, cc.pct_a, cc.pct_b, cc.pct_c, cc.premio_1_monto_fijo
      INTO v_num_videos, v_presupuesto, v_base_clip, v_pct_a, v_pct_b, v_pct_c, v_premio_fijo
      FROM campaign c JOIN campaign_config cc ON cc.campaign_id = c.id
     WHERE c.id = p_campaign_id;

    SET v_pool_base = v_num_videos * v_base_clip;
    SET v_bolsa     = v_presupuesto - v_pool_base;

    -- ---- V10: el premio se aparta primero ----
    SET v_sub_c = IF(v_premio_fijo IS NULL,
                     ROUND(v_bolsa * v_pct_c, 2),
                     LEAST(v_premio_fijo, GREATEST(v_bolsa, 0)));
    SET v_resto = GREATEST(v_bolsa - v_sub_c, 0);
    SET v_sub_a = ROUND(v_resto * v_pct_a / NULLIF(v_pct_a + v_pct_b, 0), 2);
    -- B toma el remanente exacto: así A+B+C == bolsa sin arrastre de redondeo
    SET v_sub_b = v_resto - v_sub_a;

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

-- ---------------------------------------------------------------------
-- El reparto vive en UNA sola definición reutilizable, para que la ficha de
-- campaña no pueda desincronizarse de lo que realmente paga el procedimiento.
-- ---------------------------------------------------------------------

-- Paso 1: pool base, bolsa y el premio ya apartado.
CREATE OR REPLACE VIEW v_campaign_bolsa_base AS
SELECT cam.id AS campaign_id,
       ROUND(cam.num_videos * cc.base_por_clip, 2) AS pool_base,
       GREATEST(cam.presupuesto - cam.num_videos * cc.base_por_clip, 0) AS bolsa,
       IF(cc.premio_1_monto_fijo IS NULL,
          ROUND(GREATEST(cam.presupuesto - cam.num_videos * cc.base_por_clip, 0) * cc.pct_c, 2),
          LEAST(cc.premio_1_monto_fijo,
                GREATEST(cam.presupuesto - cam.num_videos * cc.base_por_clip, 0))) AS sub_bolsa_c,
       cc.pct_a, cc.pct_b
  FROM campaign cam
  LEFT JOIN campaign_config cc ON cc.campaign_id = cam.id;

-- Paso 2: A y B se reparten el remanente en proporción pct_a : pct_b.
-- B toma la resta exacta, así A+B+C == bolsa sin arrastre de redondeo.
CREATE OR REPLACE VIEW v_campaign_subbolsas AS
SELECT campaign_id, pool_base, bolsa, sub_bolsa_c,
       ROUND((bolsa - sub_bolsa_c) * pct_a / NULLIF(pct_a + pct_b, 0), 2) AS sub_bolsa_a,
       (bolsa - sub_bolsa_c)
         - ROUND((bolsa - sub_bolsa_c) * pct_a / NULLIF(pct_a + pct_b, 0), 2) AS sub_bolsa_b
  FROM v_campaign_bolsa_base;

CREATE OR REPLACE VIEW v_campaign_report_admin AS
SELECT cam.id AS campaign_id, cam.nombre, s.codigo AS estado,
       cam.artista_cancion, cam.url_audio, cam.imagen_url,
       cam.titulo, cam.descripcion, cam.pautas_contenido,
       cam.fecha_inicio, cam.fecha_cierre, cam.client_id,
       cam.num_videos, cam.presupuesto, cam.pagado,
       (cam.presupuesto - cam.pagado) AS restante,
       sb.pool_base, sb.sub_bolsa_a, sb.sub_bolsa_b, sb.sub_bolsa_c,
       COUNT(DISTINCT c.id) AS clips,
       COUNT(DISTINCT CASE WHEN q.codigo='APROBADO' THEN c.id END) AS clips_aprobados,
       COUNT(DISTINCT c.editor_id) AS editores,
       COALESCE(SUM(m.vistas_totales),0) AS vistas,
       COALESCE(SUM(m.likes_totales),0) AS likes
FROM campaign cam
JOIN cat_campaign_state s     ON s.id = cam.campaign_state_id
LEFT JOIN v_campaign_subbolsas sb ON sb.campaign_id = cam.id
LEFT JOIN clip c              ON c.campaign_id = cam.id
LEFT JOIN cat_qa_state q      ON q.id = c.qa_state_id
LEFT JOIN v_clip_metrics m    ON m.clip_id = c.id
GROUP BY cam.id, cam.nombre, s.codigo,
         cam.artista_cancion, cam.url_audio, cam.imagen_url,
         cam.titulo, cam.descripcion, cam.pautas_contenido,
         cam.fecha_inicio, cam.fecha_cierre, cam.client_id,
         cam.num_videos, cam.presupuesto, cam.pagado,
         sb.pool_base, sb.sub_bolsa_a, sb.sub_bolsa_b, sb.sub_bolsa_c;
