-- =====================================================================
-- V13 — Las publicaciones de cada clip, listas para consumir.
--
-- Ningún endpoint devolvía clip_publication, pero la interfaz la usa en seis
-- lugares. El caso que importa: en la cola de moderación el admin no veía el
-- LINK del video que estaba aprobando o rechazando, así que el QA se hacía a
-- ciegas. También la afectaban el filtro por cuenta en el reporte de campaña
-- y la biblioteca de contenido.
--
-- Se devuelve una sola cadena por clip con el formato
--   PLATAFORMA~link~cuenta~vistas~likes
-- separando publicaciones con "|". El cliente la parte.
-- Se evita el N+1 de consultar publicaciones por cada renglón.
-- =====================================================================

CREATE OR REPLACE VIEW v_clip_publicaciones AS
SELECT p.clip_id,
       GROUP_CONCAT(
         CONCAT_WS('~',
           pl.codigo,
           p.link,
           COALESCE(ea.url, ''),
           p.vistas,
           p.likes)
         ORDER BY p.id SEPARATOR '|')  AS publicaciones
  FROM clip_publication p
  JOIN cat_platform pl        ON pl.id = p.platform_id
  LEFT JOIN editor_account ea ON ea.id = p.editor_account_id
 GROUP BY p.clip_id;
