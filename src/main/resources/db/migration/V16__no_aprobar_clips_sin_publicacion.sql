-- =====================================================================
-- V16 — No se puede aprobar un clip que no tiene ninguna publicación.
--
-- Crear el clip y registrar su publicación son dos llamadas separadas (el
-- backend las expone así). Si la segunda falla —como pasó mientras faltaba
-- clip_publication.created_at— queda un clip huérfano: sin link, sin cuenta,
-- sin forma de scrapearlo.
--
-- Aprobado, ese clip cobra su pago base por un video que no existe en ninguna
-- red, y nunca acumulará vistas. El candado va en el QA porque es el punto
-- donde el clip empieza a costar dinero.
--
-- Rechazar o poner en revisión sigue permitido: hay que poder sacar de la cola
-- los clips huérfanos que ya existen.
-- =====================================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_clip_qa$$

CREATE PROCEDURE sp_clip_qa(
    IN p_clip_id BIGINT, IN p_estado_codigo VARCHAR(30),
    IN p_motivo VARCHAR(500), IN p_admin_id BIGINT)
BEGIN
    DECLARE v_estado TINYINT;
    DECLARE v_campaign BIGINT;
    DECLARE v_num_videos INT;
    DECLARE v_aprobados INT;
    DECLARE v_ya_aprobado TINYINT;
    DECLARE v_publicaciones INT;

    SELECT id INTO v_estado FROM cat_qa_state WHERE codigo = p_estado_codigo;
    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estado de QA inválido';
    END IF;

    IF p_estado_codigo = 'APROBADO' THEN
        -- Sin publicación no hay video que pagar ni que medir.
        SELECT COUNT(*) INTO v_publicaciones
          FROM clip_publication WHERE clip_id = p_clip_id;
        IF v_publicaciones = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
              'Este clip no tiene ninguna publicación registrada: no se puede aprobar. Pide al editor que lo suba de nuevo con su link.';
        END IF;

        SELECT c.campaign_id INTO v_campaign FROM clip c WHERE c.id = p_clip_id;

        SELECT (q.codigo = 'APROBADO') INTO v_ya_aprobado
          FROM clip c JOIN cat_qa_state q ON q.id = c.qa_state_id
         WHERE c.id = p_clip_id;

        IF v_ya_aprobado = 0 THEN
            SELECT num_videos INTO v_num_videos
              FROM campaign WHERE id = v_campaign FOR UPDATE;

            SELECT COUNT(*) INTO v_aprobados
              FROM clip c JOIN cat_qa_state q ON q.id = c.qa_state_id
             WHERE c.campaign_id = v_campaign AND q.codigo = 'APROBADO';

            IF v_aprobados >= v_num_videos THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
                  'La campaña ya alcanzó su total de videos presupuestados; no se pueden aprobar más clips';
            END IF;
        END IF;
    END IF;

    UPDATE clip SET qa_state_id = v_estado, motivo = p_motivo WHERE id = p_clip_id;

    INSERT INTO audit_log (user_id, accion, detalle)
    VALUES (p_admin_id, 'CLIP_QA', CONCAT('Clip ', p_clip_id, ' -> ', p_estado_codigo));
END$$

DELIMITER ;
