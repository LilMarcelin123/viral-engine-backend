-- =====================================================================
-- V17 — Los 3 strikes remueven al editor DE LA CAMPAÑA, no de la cuenta.
--
-- Cómo estaba: sp_strike_aplicar contaba los strikes del editor a nivel global
-- (fn_strikes_activos, sin campaña) y al llegar al límite ponía
-- users.user_state_id = REMOVIDO. Eso bloquea el LOGIN: el editor no podía
-- entrar a la aplicación, ni siquiera para ver sus otras campañas o sus pagos.
--
-- Además dos strikes en campañas distintas se sumaban entre sí, así que un
-- editor podía quedar fuera de todo por incidencias no relacionadas.
--
-- Cómo debe ser: los strikes se cuentan POR CAMPAÑA y al tercero el editor
-- sale de ESA campaña. Conserva su cuenta, su acceso, sus pagos ya aprobados
-- y sus demás campañas. Es lo que la propia interfaz ya decía:
-- "Saliste de esta campaña por 3 strikes: conservas tu pago base de lo ya
--  aprobado, pero pierdes los bonos."
--
-- Los videos que tenía apartados se liberan al pool de reasignación con el
-- motivo STRIKE_REMOCION, que para eso existe.
-- =====================================================================

ALTER TABLE editor_assignment
    ADD COLUMN removido        BOOLEAN      NOT NULL DEFAULT FALSE,
    ADD COLUMN removido_at     DATETIME(6)  NULL,
    ADD COLUMN motivo_remocion VARCHAR(500) NULL;

-- Deshace el efecto de la regla anterior: nadie debe estar bloqueado a nivel
-- cuenta por strikes. La remoción correcta se recalcula por campaña abajo.
UPDATE users
   SET user_state_id = (SELECT id FROM cat_user_state WHERE codigo='ACTIVO')
 WHERE user_state_id = (SELECT id FROM cat_user_state WHERE codigo='REMOVIDO');

DELIMITER $$

-- Strikes activos de un editor EN UNA CAMPAÑA.
DROP FUNCTION IF EXISTS fn_strikes_campana$$
CREATE FUNCTION fn_strikes_campana(p_user_id BIGINT, p_campaign_id BIGINT) RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v INT;
    SELECT COUNT(*) INTO v FROM strike
     WHERE user_id = p_user_id AND campaign_id = p_campaign_id AND activo = TRUE;
    RETURN COALESCE(v,0);
END$$

DROP PROCEDURE IF EXISTS sp_strike_aplicar$$
CREATE PROCEDURE sp_strike_aplicar(
    IN p_user_id BIGINT, IN p_campaign_id BIGINT, IN p_clip_id BIGINT,
    IN p_motivo VARCHAR(500), IN p_admin_id BIGINT)
BEGIN
    DECLARE v_activos INT;
    DECLARE v_limite INT;
    DECLARE v_assignment BIGINT;
    DECLARE v_pendientes INT;
    DECLARE v_reason TINYINT;

    START TRANSACTION;
        INSERT INTO strike (user_id, campaign_id, clip_id, motivo, aplicado_por)
        VALUES (p_user_id, p_campaign_id, p_clip_id, p_motivo, p_admin_id);

        -- El clip queda excluido de bonos pero conserva su pago base (TyC §5)
        IF p_clip_id IS NOT NULL THEN
            UPDATE clip SET excluido_bonos = TRUE WHERE id = p_clip_id;
        END IF;

        SELECT strikes_para_remocion INTO v_limite FROM app_config WHERE id = 1;
        SET v_activos = fn_strikes_campana(p_user_id, p_campaign_id);

        IF v_activos >= v_limite AND p_campaign_id IS NOT NULL THEN
            SELECT id, GREATEST(asignacion_base + extras
                                - (SELECT COUNT(*) FROM clip c
                                    JOIN cat_qa_state q ON q.id = c.qa_state_id
                                   WHERE c.campaign_id = p_campaign_id
                                     AND c.editor_id = p_user_id
                                     AND q.codigo = 'APROBADO'), 0)
              INTO v_assignment, v_pendientes
              FROM editor_assignment
             WHERE campaign_id = p_campaign_id AND user_id = p_user_id
               AND removido = FALSE
             FOR UPDATE;

            IF v_assignment IS NOT NULL THEN
                UPDATE editor_assignment
                   SET removido = TRUE, removido_at = NOW(6),
                       motivo_remocion = CONCAT(v_limite, ' strikes en la campaña')
                 WHERE id = v_assignment;

                -- Los videos que ya no va a entregar vuelven al pool.
                IF v_pendientes > 0 THEN
                    SELECT id INTO v_reason FROM cat_reassignment_reason
                     WHERE codigo = 'STRIKE_REMOCION';

                    UPDATE editor_assignment
                       SET extras = 0,
                           asignacion_base = GREATEST(asignacion_base + extras - v_pendientes, 0)
                     WHERE id = v_assignment;

                    INSERT INTO reassignment_entry
                        (campaign_id, origen_assignment_id, reason_id, cantidad, creado_por)
                    VALUES (p_campaign_id, v_assignment, v_reason, v_pendientes, p_admin_id);
                END IF;
            END IF;
        END IF;
    COMMIT;
END$$

DROP PROCEDURE IF EXISTS sp_strike_quitar$$
CREATE PROCEDURE sp_strike_quitar(
    IN p_strike_id BIGINT, IN p_admin_id BIGINT, IN p_motivo VARCHAR(500))
BEGIN
    DECLARE v_user BIGINT;
    DECLARE v_campaign BIGINT;
    DECLARE v_activos INT;
    DECLARE v_limite INT;

    START TRANSACTION;
        SELECT user_id, campaign_id INTO v_user, v_campaign
          FROM strike WHERE id = p_strike_id FOR UPDATE;

        UPDATE strike
           SET activo = FALSE, removido_por = p_admin_id,
               removido_at = NOW(6), motivo_remocion = p_motivo
         WHERE id = p_strike_id;

        SELECT strikes_para_remocion INTO v_limite FROM app_config WHERE id = 1;
        SET v_activos = fn_strikes_campana(v_user, v_campaign);

        -- Si baja del límite, vuelve a la campaña. Los videos liberados NO se
        -- recuperan automáticamente: pudieron reclamarlos otros editores.
        IF v_activos < v_limite AND v_campaign IS NOT NULL THEN
            UPDATE editor_assignment
               SET removido = FALSE, removido_at = NULL, motivo_remocion = NULL
             WHERE campaign_id = v_campaign AND user_id = v_user AND removido = TRUE;
        END IF;
    COMMIT;
END$$

DELIMITER ;

-- El tablero del editor tiene que saber si quedó fuera de la campaña y
-- cuántos strikes lleva EN ELLA.
CREATE OR REPLACE VIEW v_editor_dashboard AS
SELECT a.id            AS assignment_id,
       a.user_id       AS editor_id,
       a.campaign_id,
       cam.nombre      AS campana,
       cam.nombre,
       s.codigo        AS estado_campana,
       a.cap_dinamico, a.asignacion_base, a.extras, a.confirmado,
       a.removido, a.motivo_remocion,
       fn_strikes_campana(a.user_id, a.campaign_id) AS strikes,
       cam.artista_cancion, cam.url_audio, cam.imagen_url,
       cam.titulo, cam.descripcion, cam.pautas_contenido,
       cam.fecha_inicio, cam.fecha_cierre,
       (SELECT GROUP_CONCAT(p.codigo)
          FROM campaign_platform cp JOIN cat_platform p ON p.id = cp.platform_id
         WHERE cp.campaign_id = cam.id)              AS plataformas,
       (SELECT GROUP_CONCAT(mm.url SEPARATOR '|')
          FROM campaign_material mm
         WHERE mm.campaign_id = cam.id)              AS materiales,
       (SELECT GROUP_CONCAT(CONCAT(pl.codigo, '~', ea.url) SEPARATOR '|')
          FROM assignment_account aa
          JOIN editor_account ea ON ea.id = aa.editor_account_id
          JOIN cat_platform pl   ON pl.id = ea.platform_id
         WHERE aa.assignment_id = a.id)              AS cuentas,
       COUNT(DISTINCT c.id) AS clips_subidos,
       COUNT(DISTINCT CASE WHEN q.codigo='APROBADO' THEN c.id END) AS clips_aprobados,
       COALESCE(SUM(m.vistas_totales),0) AS vistas,
       COALESCE((SELECT p.total FROM payment p
                  WHERE p.campaign_id = a.campaign_id AND p.editor_id = a.user_id),0) AS total_pago,
       (SELECT ps.codigo FROM payment p JOIN cat_payment_state ps ON ps.id = p.payment_state_id
         WHERE p.campaign_id = a.campaign_id AND p.editor_id = a.user_id) AS estado_pago
FROM editor_assignment a
JOIN campaign cam         ON cam.id = a.campaign_id
JOIN cat_campaign_state s ON s.id = cam.campaign_state_id
LEFT JOIN clip c          ON c.campaign_id = a.campaign_id AND c.editor_id = a.user_id
LEFT JOIN cat_qa_state q  ON q.id = c.qa_state_id
LEFT JOIN v_clip_metrics m ON m.clip_id = c.id
GROUP BY a.id, a.user_id, a.campaign_id, cam.id, cam.nombre, s.codigo,
         a.cap_dinamico, a.asignacion_base, a.extras, a.confirmado,
         a.removido, a.motivo_remocion,
         cam.artista_cancion, cam.url_audio, cam.imagen_url,
         cam.titulo, cam.descripcion, cam.pautas_contenido,
         cam.fecha_inicio, cam.fecha_cierre;
