-- =====================================================================
-- V15 — Que el link publicado sea de la cuenta seleccionada.
--
-- Problema: un editor podía subir el link de un video de CUALQUIER cuenta.
-- sp_clip_publicacion_alta solo validaba el dominio (que fuera de TikTok),
-- no la propiedad. Y la validación del navegador se saltaba sola cuando la
-- cuenta estaba registrada con un link corto (vt.tiktok.com/ZSxxxx), del que
-- no se puede extraer el @usuario.
--
-- La corrección tiene dos partes:
--
-- 1) El REGISTRO de la cuenta ahora exige una URL de PERFIL canónica, de la
--    que sí se pueda derivar el usuario. Se separa en `perfil_regex` porque
--    `url_regex` se seguirá usando para los links de VIDEO, que tienen otra
--    forma. El handle se deriva en la base, no se confía en el cliente.
--
-- 2) El ALTA DE PUBLICACIÓN exige que el link contenga el handle de la cuenta,
--    pero SOLO en las plataformas donde la URL del video lo incluye.
--
-- LIMITACIÓN IMPORTANTE, a propósito y documentada:
-- solo TikTok pone el @usuario en la URL del video
-- (tiktok.com/@usuario/video/123). Instagram (instagram.com/reel/XYZ) y
-- YouTube (youtu.be/ID, /shorts/ID) NO lo incluyen: para esas dos es
-- IMPOSIBLE verificar la propiedad desde la URL. Ahí la verificación real
-- tiene que hacerse al scrapear, comparando el autor que devuelve el scraper
-- contra la cuenta registrada. Se deja la bandera lista para no fingir que
-- está resuelto.
-- =====================================================================

ALTER TABLE cat_platform
    ADD COLUMN perfil_regex VARCHAR(255) NULL
        COMMENT 'Forma canónica de la URL de PERFIL, de la que se deriva el handle',
    ADD COLUMN valida_handle_en_link BOOLEAN NOT NULL DEFAULT FALSE
        COMMENT 'TRUE solo si la URL del video incluye el @usuario (hoy: TikTok)';

UPDATE cat_platform SET
    perfil_regex = '^https?://([a-z0-9-]+\\.)?tiktok\\.com/@[A-Za-z0-9._-]+/?$',
    valida_handle_en_link = TRUE
 WHERE codigo = 'TIKTOK';

UPDATE cat_platform SET
    perfil_regex = '^https?://([a-z0-9-]+\\.)?instagram\\.com/[A-Za-z0-9._]+/?$',
    valida_handle_en_link = FALSE
 WHERE codigo = 'INSTAGRAM';

UPDATE cat_platform SET
    perfil_regex = '^https?://([a-z0-9-]+\\.)?youtube\\.com/(@[A-Za-z0-9._-]+|channel/[A-Za-z0-9_-]+|c/[A-Za-z0-9._-]+)/?$',
    valida_handle_en_link = FALSE
 WHERE codigo = 'YOUTUBE';

DELIMITER $$

-- Deriva el usuario desde una URL de perfil canónica:
-- quita query string y diagonal final, toma el último segmento y le quita la @.
DROP FUNCTION IF EXISTS fn_handle_de_url$$
CREATE FUNCTION fn_handle_de_url(p_url VARCHAR(500)) RETURNS VARCHAR(150)
DETERMINISTIC
BEGIN
    DECLARE v VARCHAR(500);
    SET v = SUBSTRING_INDEX(p_url, '?', 1);
    SET v = TRIM(TRAILING '/' FROM v);
    SET v = SUBSTRING_INDEX(v, '/', -1);
    RETURN LOWER(TRIM(LEADING '@' FROM v));
END$$

DROP PROCEDURE IF EXISTS sp_editor_account_alta$$
CREATE PROCEDURE sp_editor_account_alta(
    IN p_user_id BIGINT, IN p_platform_id TINYINT,
    IN p_handle VARCHAR(150), IN p_url VARCHAR(500))
BEGIN
    DECLARE v_max_plat SMALLINT;
    DECLARE v_max_total SMALLINT;
    DECLARE v_regex VARCHAR(255);
    DECLARE v_handle VARCHAR(150);

    SELECT max_cuentas_por_plataforma, max_cuentas_total
      INTO v_max_plat, v_max_total FROM app_config WHERE id = 1;

    IF fn_cuentas_editor(p_user_id, p_platform_id) >= v_max_plat THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alcanzaste el máximo de cuentas para esta plataforma';
    END IF;
    IF fn_cuentas_editor(p_user_id, NULL) >= v_max_total THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alcanzaste el máximo total de cuentas';
    END IF;

    -- Debe ser la URL del PERFIL, no un link corto ni un video.
    SELECT perfil_regex INTO v_regex FROM cat_platform WHERE id = p_platform_id;
    IF v_regex IS NOT NULL AND (p_url IS NULL OR p_url NOT REGEXP v_regex) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            'Registra la URL de tu perfil (por ejemplo tiktok.com/@tuusuario). Los links cortos no sirven para verificar que la cuenta es tuya.';
    END IF;

    -- El handle se deriva aquí: no se confía en lo que mande el cliente.
    SET v_handle = fn_handle_de_url(p_url);
    IF v_handle IS NULL OR v_handle = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No pude identificar el usuario en esa URL';
    END IF;

    INSERT INTO editor_account (user_id, platform_id, handle, url)
    VALUES (p_user_id, p_platform_id, v_handle, p_url);
END$$

DROP PROCEDURE IF EXISTS sp_clip_publicacion_alta$$
CREATE PROCEDURE sp_clip_publicacion_alta(
    IN p_clip_id BIGINT, IN p_editor_account_id BIGINT, IN p_link VARCHAR(500))
BEGIN
    DECLARE v_max_cuenta SMALLINT;
    DECLARE v_max_dia SMALLINT;
    DECLARE v_editor BIGINT;
    DECLARE v_platform TINYINT;
    DECLARE v_regex VARCHAR(255);
    DECLARE v_handle VARCHAR(150);
    DECLARE v_valida_handle BOOLEAN;

    SELECT max_clips_por_cuenta_dia, max_clips_dia
      INTO v_max_cuenta, v_max_dia FROM app_config WHERE id = 1;

    SELECT editor_id INTO v_editor FROM clip WHERE id = p_clip_id;
    SELECT platform_id, handle INTO v_platform, v_handle
      FROM editor_account WHERE id = p_editor_account_id;

    IF fn_publicaciones_hoy_cuenta(p_editor_account_id) >= v_max_cuenta THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Límite diario alcanzado para esta cuenta';
    END IF;
    IF fn_publicaciones_hoy_editor(v_editor) >= v_max_dia THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Límite diario total alcanzado';
    END IF;

    SELECT url_regex, valida_handle_en_link
      INTO v_regex, v_valida_handle
      FROM cat_platform WHERE id = v_platform;

    IF v_regex IS NOT NULL AND p_link NOT REGEXP v_regex THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El link no corresponde a la plataforma de la cuenta';
    END IF;

    -- Propiedad: solo donde la URL del video trae el usuario (hoy TikTok).
    IF v_valida_handle = TRUE AND v_handle IS NOT NULL AND v_handle <> '' THEN
        IF LOWER(p_link) NOT LIKE CONCAT('%@', v_handle, '%') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
                'Ese video no es de la cuenta seleccionada. Solo puedes registrar publicaciones de tus propias cuentas.';
        END IF;
    END IF;

    INSERT INTO clip_publication (clip_id, editor_account_id, platform_id, link)
    VALUES (p_clip_id, p_editor_account_id, v_platform, p_link);
END$$

DELIMITER ;
