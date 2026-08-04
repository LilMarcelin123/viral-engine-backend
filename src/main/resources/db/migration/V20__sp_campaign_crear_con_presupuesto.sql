-- =====================================================================
-- V20 — sp_campaign_crear con presupuesto (reempaque de la antigua V8).
--
-- Misma razón que V19: V8 nunca entró al repositorio. En una base limpia
-- quedaría la versión de V5, que recibe 13 parámetros; el backend llama con
-- 14 (incluye p_presupuesto), así que CREAR CUALQUIER CAMPAÑA fallaría.
--
-- OJO — DIFERENCIA DELIBERADA CON LA V8 ORIGINAL:
-- La V8 también redefinía v_campaign_report_admin con la fórmula vieja
-- (60/25/15 sobre la bolsa, sin descontar el premio primero). Esa vista NO se
-- incluye aquí: la manda la V10, y copiarla revertiría el reparto y volvería a
-- comprometer más dinero del que hay en presupuestos chicos.
--
-- El DROP PROCEDURE IF EXISTS hace que sea idempotente.
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_campaign_crear;

DELIMITER $$

CREATE PROCEDURE sp_campaign_crear(
    IN p_nombre VARCHAR(200), IN p_artista VARCHAR(255), IN p_url_audio VARCHAR(500),
    IN p_fecha_inicio DATE,   IN p_fecha_cierre DATE,
    IN p_titulo VARCHAR(100), IN p_descripcion VARCHAR(1500),
    IN p_pautas TEXT,         IN p_imagen VARCHAR(500),
    IN p_num_videos INT,
    IN p_presupuesto DECIMAL(12,2),
    IN p_client_id BIGINT,    IN p_user_id BIGINT,
    OUT p_campaign_id BIGINT)
BEGIN
    DECLARE v_base_clip DECIMAL(12,2);
    DECLARE v_pool_base DECIMAL(12,2);
    DECLARE v_draft TINYINT;

    IF p_num_videos IS NULL OR p_num_videos <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El número de videos debe ser mayor a cero';
    END IF;

    IF p_presupuesto IS NULL OR p_presupuesto <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El presupuesto debe ser mayor a cero';
    END IF;

    SELECT base_por_clip INTO v_base_clip FROM app_config WHERE id = 1;
    SET v_pool_base = p_num_videos * v_base_clip;

    IF p_presupuesto < v_pool_base THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            'El presupuesto no alcanza para cubrir el pago base de los videos capturados';
    END IF;

    START TRANSACTION;
        SELECT id INTO v_draft FROM cat_campaign_state WHERE codigo = 'DRAFT';

        INSERT INTO campaign (nombre, artista_cancion, url_audio, fecha_inicio, fecha_cierre,
                              imagen_url, titulo, descripcion, pautas_contenido,
                              num_videos, presupuesto, client_id, campaign_state_id)
        VALUES (p_nombre, p_artista, p_url_audio, p_fecha_inicio, p_fecha_cierre,
                p_imagen, p_titulo, p_descripcion, p_pautas,
                p_num_videos, p_presupuesto, p_client_id, v_draft);

        SET p_campaign_id = LAST_INSERT_ID();

        INSERT INTO campaign_config (campaign_id, precio_por_video, base_por_clip,
                                     pct_a, pct_b, pct_c, premio_1_monto_fijo,
                                     dias_congelado, pct_cap_campana, clips_cuenta_dia)
        SELECT p_campaign_id, precio_por_video, base_por_clip, pct_a, pct_b, pct_c,
               premio_1_monto_fijo, dias_congelado, pct_cap_campana, clips_por_cuenta_dia_cap
          FROM app_config WHERE id = 1;

        INSERT INTO campaign_bonus_tier (campaign_id, tier_type_id, vistas_min, bono)
        SELECT p_campaign_id, tier_type_id, vistas_min, bono FROM bonus_tier;

        INSERT INTO audit_log (user_id, accion, detalle)
        VALUES (p_user_id, 'CAMPAIGN_CREATE',
                CONCAT('Campaña ', p_campaign_id, ' - ', p_nombre,
                       ' | videos: ', p_num_videos, ' | presupuesto: ', p_presupuesto));
    COMMIT;
END$$

DELIMITER ;
