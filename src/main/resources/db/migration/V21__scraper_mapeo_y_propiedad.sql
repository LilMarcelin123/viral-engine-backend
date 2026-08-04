-- =====================================================================
-- V21 — Scraper: mapeo de campos por actor y verificación de propiedad.
--
-- Dos cosas que faltaban para poder scrapear de verdad:
--
-- 1) CADA ACTOR DE APIFY DEVUELVE LOS CAMPOS CON OTRO NOMBRE.
--    El de TikTok manda playCount/diggCount/authorMeta.name, el de Instagram
--    videoPlayCount/likesCount/ownerUsername, el de YouTube viewCount/likes/
--    channelName. Poner eso en el código Java significaría un `switch` por
--    plataforma y tener que desplegar cada vez que se cambie de actor.
--    Va en el catálogo, como el resto de las reglas de este sistema.
--
-- 2) VERIFICACIÓN DE PROPIEDAD EN INSTAGRAM Y YOUTUBE.
--    Esas dos redes no ponen el usuario en la URL del video, así que al
--    registrar la publicación es imposible saber si el video es del editor.
--    El scraper SÍ devuelve el autor: aquí se compara contra el handle de la
--    cuenta registrada y se marca la publicación.
--
--    Decisión deliberada: si la publicación ya estaba APROBADA no se le cambia
--    el estado, solo se marca. Revertir automáticamente algo ya aprobado
--    tocaría dinero que quizá ya se prometió. Si todavía no está aprobada, se
--    manda a EN_REVISION para que el admin la vea. El sistema detecta;
--    la persona decide.
-- =====================================================================

ALTER TABLE cat_platform
    ADD COLUMN apify_campo_vistas VARCHAR(80) NULL COMMENT 'Ruta al conteo de vistas en el JSON del actor',
    ADD COLUMN apify_campo_likes  VARCHAR(80) NULL COMMENT 'Ruta a los likes',
    ADD COLUMN apify_campo_autor  VARCHAR(80) NULL COMMENT 'Ruta al usuario autor del post',
    ADD COLUMN apify_campo_url    VARCHAR(80) NULL COMMENT 'Ruta a la URL del post, para casar con el link guardado';

-- Rutas con notación de punto. Se listan alternativas separadas por coma:
-- el backend usa la primera que exista en el objeto.
UPDATE cat_platform SET
    apify_campo_vistas = 'playCount,videoPlayCount,views',
    apify_campo_likes  = 'diggCount,likes',
    apify_campo_autor  = 'authorMeta.name,authorMeta.uniqueId',
    apify_campo_url    = 'webVideoUrl,postPage,url'
 WHERE codigo = 'TIKTOK';

UPDATE cat_platform SET
    apify_campo_vistas = 'videoPlayCount,videoViewCount,playCount',
    apify_campo_likes  = 'likesCount,likes',
    apify_campo_autor  = 'ownerUsername,owner.username',
    apify_campo_url    = 'url,postUrl'
 WHERE codigo = 'INSTAGRAM';

UPDATE cat_platform SET
    apify_campo_vistas = 'viewCount,views,numberOfViews',
    apify_campo_likes  = 'likes,likeCount',
    apify_campo_autor  = 'channelUsername,channelName,channelHandle',
    apify_campo_url    = 'url,videoUrl'
 WHERE codigo = 'YOUTUBE';

-- ---------------------------------------------------------------------
-- Propiedad de la publicación
-- ---------------------------------------------------------------------
ALTER TABLE clip_publication
    ADD COLUMN autor_detectado VARCHAR(150) NULL
        COMMENT 'Usuario que el scraper reporta como autor del post',
    ADD COLUMN propiedad_ok    BOOLEAN      NULL
        COMMENT 'NULL = sin verificar, TRUE = coincide con la cuenta, FALSE = no coincide',
    ADD COLUMN verificado_at   DATETIME(6)  NULL;

DELIMITER $$

-- Normaliza un handle para comparar: minúsculas, sin @ ni espacios.
DROP FUNCTION IF EXISTS fn_norm_handle$$
CREATE FUNCTION fn_norm_handle(p_handle VARCHAR(200)) RETURNS VARCHAR(200)
DETERMINISTIC
BEGIN
    RETURN LOWER(TRIM(LEADING '@' FROM TRIM(COALESCE(p_handle, ''))));
END$$

DROP PROCEDURE IF EXISTS sp_scrape_aplicar_lectura$$

CREATE PROCEDURE sp_scrape_aplicar_lectura(
    IN p_publication_id BIGINT,
    IN p_scrape_run_id  BIGINT,
    IN p_vistas         BIGINT,
    IN p_likes          BIGINT,
    IN p_autor          VARCHAR(150))
BEGIN
    DECLARE v_prev BIGINT DEFAULT 0;
    DECLARE v_clip BIGINT;
    DECLARE v_dias SMALLINT;
    DECLARE v_handle VARCHAR(150);
    DECLARE v_ok BOOLEAN DEFAULT NULL;
    DECLARE v_estado VARCHAR(30);
    DECLARE v_revision TINYINT;

    START TRANSACTION;
        SELECT p.vistas, p.clip_id, fn_norm_handle(ea.handle)
          INTO v_prev, v_clip, v_handle
          FROM clip_publication p
          LEFT JOIN editor_account ea ON ea.id = p.editor_account_id
         WHERE p.id = p_publication_id FOR UPDATE;

        -- Si el scraper no devolvió autor, se queda sin verificar (NULL).
        IF p_autor IS NOT NULL AND p_autor <> '' AND v_handle IS NOT NULL AND v_handle <> '' THEN
            SET v_ok = (fn_norm_handle(p_autor) = v_handle);
        END IF;

        UPDATE clip_publication
           SET vistas = p_vistas, likes = p_likes, updated_at = NOW(6),
               autor_detectado = p_autor,
               propiedad_ok    = COALESCE(v_ok, propiedad_ok),
               verificado_at   = IF(v_ok IS NULL, verificado_at, NOW(6))
         WHERE id = p_publication_id;

        INSERT INTO publication_metric_history (publication_id, scrape_run_id, vistas, likes, delta_vistas)
        VALUES (p_publication_id, p_scrape_run_id, p_vistas, p_likes, p_vistas - COALESCE(v_prev,0));

        -- Autor que no coincide: se manda a revisión SOLO si aún no se aprobó.
        -- Un clip ya aprobado se marca pero no se toca: revertirlo movería
        -- dinero que quizá ya se le prometió al editor.
        IF v_ok = FALSE THEN
            SELECT q.codigo INTO v_estado
              FROM clip c JOIN cat_qa_state q ON q.id = c.qa_state_id
             WHERE c.id = v_clip;

            IF v_estado IN ('SUBIDO', 'EN_REVISION') THEN
                SELECT id INTO v_revision FROM cat_qa_state WHERE codigo='EN_REVISION';
                UPDATE clip
                   SET qa_state_id = v_revision,
                       motivo = CONCAT('El scraper reporta que el autor es @', p_autor,
                                       ', no la cuenta registrada @', v_handle)
                 WHERE id = v_clip;
            END IF;
        END IF;

        -- Congelado automático a los N días de publicado (app_config)
        SELECT dias_congelado INTO v_dias FROM app_config WHERE id = 1;
        UPDATE clip
           SET fecha_congelado = DATE_ADD(fecha_publicado, INTERVAL v_dias DAY)
         WHERE id = v_clip
           AND fecha_publicado IS NOT NULL
           AND fecha_congelado IS NULL;

        UPDATE scrape_run
           SET items_recibidos = items_recibidos + 1
         WHERE id = p_scrape_run_id;
    COMMIT;
END$$

DELIMITER ;

-- Publicaciones cuyo autor no coincide con la cuenta registrada.
-- Es la cola de revisión de propiedad para el administrador.
CREATE OR REPLACE VIEW v_publicaciones_sospechosas AS
SELECT p.id AS publication_id, p.link, p.autor_detectado, p.verificado_at,
       ea.handle AS cuenta_registrada, pl.codigo AS plataforma,
       c.id AS clip_id, c.titulo, q.codigo AS estado_qa,
       c.campaign_id, cam.nombre AS campana,
       u.id AS editor_id, u.nombre AS editor
  FROM clip_publication p
  JOIN clip c              ON c.id = p.clip_id
  JOIN cat_qa_state q      ON q.id = c.qa_state_id
  JOIN campaign cam        ON cam.id = c.campaign_id
  JOIN users u             ON u.id = c.editor_id
  JOIN cat_platform pl     ON pl.id = p.platform_id
  LEFT JOIN editor_account ea ON ea.id = p.editor_account_id
 WHERE p.propiedad_ok = FALSE
 ORDER BY p.verificado_at DESC;
