-- =====================================================================
-- VIRAL ENGINE — V5: Funciones de validación, procedimientos operativos
-- y vistas de reportes. Todos los límites se leen de app_config.
-- =====================================================================

DELIMITER $$

-- =====================================================================
-- FUNCIONES DE APOYO
-- =====================================================================

-- Quincena en formato YYYY-MM-Q1 / YYYY-MM-Q2
CREATE FUNCTION fn_quincena(p_fecha DATE) RETURNS CHAR(10)
DETERMINISTIC
BEGIN
    RETURN CONCAT(DATE_FORMAT(p_fecha,'%Y-%m'), IF(DAY(p_fecha) <= 15, '-Q1', '-Q2'));
END$$

-- Cuentas registradas del editor en una plataforma
CREATE FUNCTION fn_cuentas_editor(p_user_id BIGINT, p_platform_id TINYINT) RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v INT;
    SELECT COUNT(*) INTO v FROM editor_account
     WHERE user_id = p_user_id AND activo = TRUE
       AND (p_platform_id IS NULL OR platform_id = p_platform_id);
    RETURN COALESCE(v,0);
END$$

-- Publicaciones subidas HOY por una cuenta
CREATE FUNCTION fn_publicaciones_hoy_cuenta(p_account_id BIGINT) RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v INT;
    SELECT COUNT(*) INTO v FROM clip_publication
     WHERE editor_account_id = p_account_id AND DATE(created_at) = CURDATE();
    RETURN COALESCE(v,0);
END$$

-- Publicaciones subidas HOY por el editor (todas sus cuentas)
CREATE FUNCTION fn_publicaciones_hoy_editor(p_user_id BIGINT) RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v INT;
    SELECT COUNT(*) INTO v
      FROM clip_publication p JOIN clip c ON c.id = p.clip_id
     WHERE c.editor_id = p_user_id AND DATE(p.created_at) = CURDATE();
    RETURN COALESCE(v,0);
END$$

-- Cap dinámico = MIN(% de la campaña, cuentas seleccionadas x factor x días)
CREATE FUNCTION fn_cap_dinamico(p_campaign_id BIGINT, p_assignment_id BIGINT) RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_num_videos INT;
    DECLARE v_pct DECIMAL(5,4);
    DECLARE v_factor DECIMAL(5,2);
    DECLARE v_dias INT;
    DECLARE v_cuentas INT;

    SELECT c.num_videos, cc.pct_cap_campana, cc.clips_cuenta_dia,
           GREATEST(DATEDIFF(c.fecha_cierre, c.fecha_inicio), 1)
      INTO v_num_videos, v_pct, v_factor, v_dias
      FROM campaign c JOIN campaign_config cc ON cc.campaign_id = c.id
     WHERE c.id = p_campaign_id;

    SELECT COUNT(*) INTO v_cuentas FROM assignment_account WHERE assignment_id = p_assignment_id;
    IF v_cuentas = 0 THEN SET v_cuentas = 1; END IF;

    RETURN LEAST(FLOOR(v_num_videos * v_pct), FLOOR(v_cuentas * v_factor * v_dias));
END$$

-- =====================================================================
-- ALTA DE CAMPAÑA (con snapshot de configuración y tabulador)
-- =====================================================================

CREATE PROCEDURE sp_campaign_crear(
    IN p_nombre VARCHAR(200), IN p_artista VARCHAR(255), IN p_url_audio VARCHAR(500),
    IN p_fecha_inicio DATE,   IN p_fecha_cierre DATE,
    IN p_titulo VARCHAR(100), IN p_descripcion VARCHAR(1500),
    IN p_pautas TEXT,         IN p_imagen VARCHAR(500),
    IN p_num_videos INT,      IN p_client_id BIGINT, IN p_user_id BIGINT,
    OUT p_campaign_id BIGINT)
BEGIN
    DECLARE v_precio DECIMAL(12,2);
    DECLARE v_draft TINYINT;

    IF p_num_videos IS NULL OR p_num_videos <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El número de videos debe ser mayor a cero';
    END IF;

    START TRANSACTION;
        SELECT precio_por_video INTO v_precio FROM app_config WHERE id = 1;
        SELECT id INTO v_draft FROM cat_campaign_state WHERE codigo = 'DRAFT';

        INSERT INTO campaign (nombre, artista_cancion, url_audio, fecha_inicio, fecha_cierre,
                              imagen_url, titulo, descripcion, pautas_contenido,
                              num_videos, presupuesto, client_id, campaign_state_id)
        VALUES (p_nombre, p_artista, p_url_audio, p_fecha_inicio, p_fecha_cierre,
                p_imagen, p_titulo, p_descripcion, p_pautas,
                p_num_videos, p_num_videos * v_precio, p_client_id, v_draft);

        SET p_campaign_id = LAST_INSERT_ID();

        -- Snapshot de la configuración vigente
        INSERT INTO campaign_config (campaign_id, precio_por_video, base_por_clip,
                                     pct_a, pct_b, pct_c, premio_1_monto_fijo,
                                     dias_congelado, pct_cap_campana, clips_cuenta_dia)
        SELECT p_campaign_id, precio_por_video, base_por_clip, pct_a, pct_b, pct_c,
               premio_1_monto_fijo, dias_congelado, pct_cap_campana, clips_por_cuenta_dia_cap
          FROM app_config WHERE id = 1;

        -- Snapshot del tabulador vigente
        INSERT INTO campaign_bonus_tier (campaign_id, tier_type_id, vistas_min, bono)
        SELECT p_campaign_id, tier_type_id, vistas_min, bono FROM bonus_tier;

        INSERT INTO audit_log (user_id, accion, detalle)
        VALUES (p_user_id, 'CAMPAIGN_CREATE', CONCAT('Campaña ', p_campaign_id, ' - ', p_nombre));
    COMMIT;
END$$

-- =====================================================================
-- ASIGNACIONES
-- =====================================================================

CREATE PROCEDURE sp_assignment_crear(
    IN p_campaign_id BIGINT, IN p_user_id BIGINT, OUT p_assignment_id BIGINT)
BEGIN
    INSERT INTO editor_assignment (campaign_id, user_id) VALUES (p_campaign_id, p_user_id);
    SET p_assignment_id = LAST_INSERT_ID();
    UPDATE editor_assignment SET cap_dinamico = fn_cap_dinamico(p_campaign_id, p_assignment_id)
     WHERE id = p_assignment_id;
END$$

-- Confirma participación (valida ventana de N horas de app_config)
CREATE PROCEDURE sp_assignment_confirmar(IN p_assignment_id BIGINT)
BEGIN
    DECLARE v_horas SMALLINT;
    DECLARE v_creada DATETIME(6);

    SELECT horas_confirmacion INTO v_horas FROM app_config WHERE id = 1;
    -- La ventana corre desde que se creó la ASIGNACIÓN, no la campaña
    SELECT a.created_at INTO v_creada
      FROM editor_assignment a
     WHERE a.id = p_assignment_id;

    IF TIMESTAMPDIFF(HOUR, v_creada, NOW(6)) > v_horas THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Venció la ventana de confirmación';
    END IF;

    UPDATE editor_assignment SET confirmado = TRUE, confirmado_at = NOW(6)
     WHERE id = p_assignment_id;
END$$

-- Reemplaza las cuentas seleccionadas para la campaña y recalcula el cap
CREATE PROCEDURE sp_assignment_set_cuenta(
    IN p_assignment_id BIGINT, IN p_editor_account_id BIGINT, IN p_agregar BOOLEAN)
BEGIN
    DECLARE v_campaign BIGINT;
    DECLARE v_user BIGINT;
    DECLARE v_owner BIGINT;

    SELECT campaign_id, user_id INTO v_campaign, v_user
      FROM editor_assignment WHERE id = p_assignment_id;
    SELECT user_id INTO v_owner FROM editor_account WHERE id = p_editor_account_id;

    IF v_owner <> v_user THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cuenta no pertenece a este editor';
    END IF;

    START TRANSACTION;
        IF p_agregar THEN
            INSERT IGNORE INTO assignment_account (assignment_id, editor_account_id)
            VALUES (p_assignment_id, p_editor_account_id);
        ELSE
            DELETE FROM assignment_account
             WHERE assignment_id = p_assignment_id AND editor_account_id = p_editor_account_id;
        END IF;

        UPDATE editor_assignment SET cap_dinamico = fn_cap_dinamico(v_campaign, p_assignment_id)
         WHERE id = p_assignment_id;
    COMMIT;
END$$

-- =====================================================================
-- CUENTAS DEL EDITOR (valida límites y que la URL sea de esa red social)
-- =====================================================================

CREATE PROCEDURE sp_editor_account_alta(
    IN p_user_id BIGINT, IN p_platform_id TINYINT,
    IN p_handle VARCHAR(150), IN p_url VARCHAR(500))
BEGIN
    DECLARE v_max_plat SMALLINT;
    DECLARE v_max_total SMALLINT;
    DECLARE v_regex VARCHAR(255);

    SELECT max_cuentas_por_plataforma, max_cuentas_total
      INTO v_max_plat, v_max_total FROM app_config WHERE id = 1;

    IF fn_cuentas_editor(p_user_id, p_platform_id) >= v_max_plat THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alcanzaste el máximo de cuentas para esta plataforma';
    END IF;
    IF fn_cuentas_editor(p_user_id, NULL) >= v_max_total THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alcanzaste el máximo total de cuentas';
    END IF;

    -- La validación de red social sale del catálogo, no del código
    SELECT url_regex INTO v_regex FROM cat_platform WHERE id = p_platform_id;
    IF v_regex IS NOT NULL AND p_url IS NOT NULL AND p_url NOT REGEXP v_regex THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La URL no corresponde a la red social seleccionada';
    END IF;

    INSERT INTO editor_account (user_id, platform_id, handle, url)
    VALUES (p_user_id, p_platform_id, p_handle, p_url);
END$$

-- =====================================================================
-- CLIPS Y PUBLICACIONES (valida límites diarios y cap)
-- =====================================================================

CREATE PROCEDURE sp_clip_publicacion_alta(
    IN p_clip_id BIGINT, IN p_editor_account_id BIGINT, IN p_link VARCHAR(500))
BEGIN
    DECLARE v_max_cuenta SMALLINT;
    DECLARE v_max_dia SMALLINT;
    DECLARE v_editor BIGINT;
    DECLARE v_platform TINYINT;
    DECLARE v_regex VARCHAR(255);

    SELECT max_clips_por_cuenta_dia, max_clips_dia
      INTO v_max_cuenta, v_max_dia FROM app_config WHERE id = 1;

    SELECT editor_id INTO v_editor FROM clip WHERE id = p_clip_id;
    SELECT platform_id INTO v_platform FROM editor_account WHERE id = p_editor_account_id;

    IF fn_publicaciones_hoy_cuenta(p_editor_account_id) >= v_max_cuenta THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Límite diario alcanzado para esta cuenta';
    END IF;
    IF fn_publicaciones_hoy_editor(v_editor) >= v_max_dia THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Límite diario total alcanzado';
    END IF;

    SELECT url_regex INTO v_regex FROM cat_platform WHERE id = v_platform;
    IF v_regex IS NOT NULL AND p_link NOT REGEXP v_regex THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El link no corresponde a la plataforma de la cuenta';
    END IF;

    INSERT INTO clip_publication (clip_id, editor_account_id, platform_id, link)
    VALUES (p_clip_id, p_editor_account_id, v_platform, p_link);
END$$

-- Cambio de estado de QA (aprobar / rechazar)
CREATE PROCEDURE sp_clip_qa(
    IN p_clip_id BIGINT, IN p_estado_codigo VARCHAR(30),
    IN p_motivo VARCHAR(500), IN p_admin_id BIGINT)
BEGIN
    DECLARE v_estado TINYINT;
    SELECT id INTO v_estado FROM cat_qa_state WHERE codigo = p_estado_codigo;
    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estado de QA inválido';
    END IF;

    UPDATE clip SET qa_state_id = v_estado, motivo = p_motivo WHERE id = p_clip_id;

    INSERT INTO audit_log (user_id, accion, detalle)
    VALUES (p_admin_id, 'CLIP_QA', CONCAT('Clip ', p_clip_id, ' -> ', p_estado_codigo));
END$$

DELIMITER ;

-- =====================================================================
-- VISTAS DE REPORTES
-- =====================================================================

-- Biblioteca / videos por campaña: incluye QUÉ EDITOR subió cada video
CREATE OR REPLACE VIEW v_campaign_videos AS
SELECT c.campaign_id,
       cam.nombre        AS campana,
       c.id              AS clip_id,
       c.titulo,
       c.editor_id,
       u.nombre          AS editor,
       q.codigo          AS estado_qa,
       c.excluido_bonos,
       c.fecha_publicado,
       m.vistas_totales,
       m.likes_totales,
       GROUP_CONCAT(DISTINCT t.nombre ORDER BY t.nombre SEPARATOR ', ') AS tags
FROM clip c
JOIN campaign cam       ON cam.id = c.campaign_id
JOIN users u            ON u.id  = c.editor_id
JOIN cat_qa_state q     ON q.id  = c.qa_state_id
LEFT JOIN v_clip_metrics m ON m.clip_id = c.id
LEFT JOIN clip_tag ct   ON ct.clip_id = c.id
LEFT JOIN tag t         ON t.id = ct.tag_id
GROUP BY c.campaign_id, cam.nombre, c.id, c.titulo, c.editor_id, u.nombre,
         q.codigo, c.excluido_bonos, c.fecha_publicado, m.vistas_totales, m.likes_totales;

-- Reporte ADMIN: incluye dinero
CREATE OR REPLACE VIEW v_campaign_report_admin AS
SELECT cam.id AS campaign_id, cam.nombre, s.codigo AS estado,
       cam.num_videos, cam.presupuesto, cam.pagado,
       (cam.presupuesto - cam.pagado)              AS restante,
       COUNT(DISTINCT c.id)                        AS clips,
       COUNT(DISTINCT CASE WHEN q.codigo='APROBADO' THEN c.id END) AS clips_aprobados,
       COUNT(DISTINCT c.editor_id)                 AS editores,
       COALESCE(SUM(m.vistas_totales),0)           AS vistas,
       COALESCE(SUM(m.likes_totales),0)            AS likes
FROM campaign cam
JOIN cat_campaign_state s ON s.id = cam.campaign_state_id
LEFT JOIN clip c          ON c.campaign_id = cam.id
LEFT JOIN cat_qa_state q  ON q.id = c.qa_state_id
LEFT JOIN v_clip_metrics m ON m.clip_id = c.id
GROUP BY cam.id, cam.nombre, s.codigo, cam.num_videos, cam.presupuesto, cam.pagado;

-- Reporte CLIENTE: SIN ningún dato de dinero (TyC / decisión de producto)
CREATE OR REPLACE VIEW v_campaign_report_client AS
SELECT cam.id AS campaign_id, cam.client_id, cam.nombre, s.codigo AS estado,
       cam.fecha_inicio, cam.fecha_cierre, cam.num_videos,
       COUNT(DISTINCT CASE WHEN q.codigo='APROBADO' THEN c.id END) AS videos_publicados,
       COUNT(DISTINCT c.editor_id)                 AS editores,
       COALESCE(SUM(m.vistas_totales),0)           AS vistas,
       COALESCE(SUM(m.likes_totales),0)            AS likes
FROM campaign cam
JOIN cat_campaign_state s ON s.id = cam.campaign_state_id
LEFT JOIN clip c          ON c.campaign_id = cam.id
LEFT JOIN cat_qa_state q  ON q.id = c.qa_state_id
LEFT JOIN v_clip_metrics m ON m.clip_id = c.id
GROUP BY cam.id, cam.client_id, cam.nombre, s.codigo,
         cam.fecha_inicio, cam.fecha_cierre, cam.num_videos;

-- Dashboard del editor
CREATE OR REPLACE VIEW v_editor_dashboard AS
SELECT a.user_id AS editor_id, a.campaign_id, cam.nombre AS campana,
       s.codigo AS estado_campana, a.cap_dinamico, a.asignacion_base, a.extras,
       a.confirmado,
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
GROUP BY a.user_id, a.campaign_id, cam.nombre, s.codigo, a.cap_dinamico,
         a.asignacion_base, a.extras, a.confirmado;
