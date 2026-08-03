-- =====================================================================
-- VIRAL ENGINE — V4: Integración con APIFY para el scrapeo
--
-- IMPORTANTE: el API token de Apify NUNCA va en la base de datos.
-- Va en variables de entorno (APIFY_TOKEN) del backend.
-- Aquí solo se guarda QUÉ actor usar por plataforma y el historial/costo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Qué actor de Apify scrapea cada plataforma (dinámico, sin hardcode)
-- ---------------------------------------------------------------------
ALTER TABLE cat_platform
    ADD COLUMN apify_actor_id  VARCHAR(120) NULL COMMENT 'Actor de Apify que scrapea esta plataforma',
    ADD COLUMN apify_input_key VARCHAR(60)  NULL COMMENT 'Nombre del campo de entrada con las URLs (ej. postURLs, directUrls)';

-- Ajusta estos valores a los actores que realmente uses en tu cuenta de Apify
UPDATE cat_platform SET apify_actor_id = 'clockworks~tiktok-scraper',   apify_input_key = 'postURLs'   WHERE codigo = 'TIKTOK';
UPDATE cat_platform SET apify_actor_id = 'apify~instagram-scraper',     apify_input_key = 'directUrls' WHERE codigo = 'INSTAGRAM';
UPDATE cat_platform SET apify_actor_id = 'streamers~youtube-scraper',   apify_input_key = 'startUrls'  WHERE codigo = 'YOUTUBE';

-- ---------------------------------------------------------------------
-- 2. Trazabilidad y costo de cada corrida de Apify
-- ---------------------------------------------------------------------
ALTER TABLE scrape_run
    ADD COLUMN platform_id     TINYINT       NULL COMMENT 'Plataforma scrapeada en esta corrida',
    ADD COLUMN apify_actor_id  VARCHAR(120)  NULL,
    ADD COLUMN apify_run_id    VARCHAR(80)   NULL COMMENT 'ID de la corrida en Apify (para auditar allá)',
    ADD COLUMN apify_dataset_id VARCHAR(80)  NULL,
    ADD COLUMN items_solicitados INT         NOT NULL DEFAULT 0,
    ADD COLUMN items_recibidos   INT         NOT NULL DEFAULT 0,
    ADD COLUMN compute_units    DECIMAL(12,4) NULL COMMENT 'CU consumidas (costo Apify)',
    ADD COLUMN costo_usd        DECIMAL(12,4) NULL,
    ADD CONSTRAINT fk_sr_platform FOREIGN KEY (platform_id) REFERENCES cat_platform (id);

CREATE INDEX idx_sr_apify_run ON scrape_run (apify_run_id);

-- ---------------------------------------------------------------------
-- 3. Historial de métricas por publicación
-- Cada scrapeo deja una foto de vistas/likes. Sirve para:
--   * auditar por qué un clip pagó lo que pagó (las vistas mueven dinero)
--   * graficar la evolución del clip
--   * detectar saltos anómalos (vistas infladas, TyC §5)
-- ---------------------------------------------------------------------
CREATE TABLE publication_metric_history (
    id             BIGINT      NOT NULL AUTO_INCREMENT,
    publication_id BIGINT      NOT NULL,
    scrape_run_id  BIGINT      NULL,
    vistas         BIGINT      NOT NULL DEFAULT 0,
    likes          BIGINT      NOT NULL DEFAULT 0,
    delta_vistas   BIGINT      NULL COMMENT 'Diferencia contra la lectura anterior',
    captured_at    DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_pmh_pub (publication_id, captured_at),
    KEY idx_pmh_run (scrape_run_id),
    CONSTRAINT fk_pmh_pub FOREIGN KEY (publication_id) REFERENCES clip_publication (id) ON DELETE CASCADE,
    CONSTRAINT fk_pmh_run FOREIGN KEY (scrape_run_id)  REFERENCES scrape_run (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- 4. Vistas de apoyo
-- ---------------------------------------------------------------------

-- Publicaciones que SÍ deben scrapearse: campaña activa y clip no congelado
CREATE OR REPLACE VIEW v_publicaciones_a_scrapear AS
SELECT p.id           AS publication_id,
       p.link,
       p.platform_id,
       pl.codigo      AS plataforma,
       pl.apify_actor_id,
       pl.apify_input_key,
       c.id           AS clip_id,
       c.campaign_id,
       c.fecha_congelado
FROM clip_publication p
JOIN clip c              ON c.id = p.clip_id
JOIN cat_platform pl     ON pl.id = p.platform_id
JOIN campaign cam        ON cam.id = c.campaign_id
JOIN cat_campaign_state s ON s.id = cam.campaign_state_id
WHERE s.computa_garantia = TRUE                      -- campaña activa
  AND (c.fecha_congelado IS NULL OR c.fecha_congelado > NOW(6));

-- Costo acumulado de scrapeo por campaña
CREATE OR REPLACE VIEW v_costo_scrapeo AS
SELECT campaign_id,
       COUNT(*)                     AS corridas,
       COALESCE(SUM(compute_units),0) AS compute_units,
       COALESCE(SUM(costo_usd),0)     AS costo_usd,
       MAX(finalizado_at)           AS ultima_corrida
FROM scrape_run
GROUP BY campaign_id;

-- ---------------------------------------------------------------------
-- 5. Procedimiento: aplicar el resultado de una corrida de Apify
-- El backend inserta las lecturas y este SP actualiza métricas,
-- guarda el histórico con su delta y congela los clips que cumplieron.
-- ---------------------------------------------------------------------
DELIMITER $$

CREATE PROCEDURE sp_scrape_aplicar_lectura(
    IN p_publication_id BIGINT,
    IN p_scrape_run_id  BIGINT,
    IN p_vistas         BIGINT,
    IN p_likes          BIGINT)
BEGIN
    DECLARE v_prev BIGINT DEFAULT 0;
    DECLARE v_clip BIGINT;
    DECLARE v_dias SMALLINT;

    START TRANSACTION;
        SELECT vistas, clip_id INTO v_prev, v_clip
          FROM clip_publication WHERE id = p_publication_id FOR UPDATE;

        UPDATE clip_publication
           SET vistas = p_vistas, likes = p_likes, updated_at = NOW(6)
         WHERE id = p_publication_id;

        INSERT INTO publication_metric_history (publication_id, scrape_run_id, vistas, likes, delta_vistas)
        VALUES (p_publication_id, p_scrape_run_id, p_vistas, p_likes, p_vistas - COALESCE(v_prev,0));

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
