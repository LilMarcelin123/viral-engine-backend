-- =====================================================================
-- V9 — La vista de campañas devuelve también los datos descriptivos.
--
-- Motivo: v_campaign_report_admin solo exponía cifras (presupuesto, bolsas,
-- métricas). La ficha de campaña necesita además la portada, el artista y el
-- cliente, así que la tarjeta mostraba siempre el ícono genérico y
-- "Sin artista · Sin cliente" aunque el alta sí guardara esos campos.
--
-- Solo se agregan columnas: nada de lo que ya consumía la app cambia de nombre
-- ni de posición.
-- =====================================================================

CREATE OR REPLACE VIEW v_campaign_report_admin AS
SELECT cam.id AS campaign_id, cam.nombre, s.codigo AS estado,
       -- datos descriptivos (nuevos en V9)
       cam.artista_cancion, cam.url_audio, cam.imagen_url,
       cam.titulo, cam.descripcion, cam.pautas_contenido,
       cam.fecha_inicio, cam.fecha_cierre, cam.client_id,
       -- cifras
       cam.num_videos, cam.presupuesto, cam.pagado,
       (cam.presupuesto - cam.pagado) AS restante,
       ROUND(cam.num_videos * cc.base_por_clip, 2) AS pool_base,
       ROUND((cam.presupuesto - cam.num_videos * cc.base_por_clip) * cc.pct_a, 2) AS sub_bolsa_a,
       ROUND((cam.presupuesto - cam.num_videos * cc.base_por_clip) * cc.pct_b, 2) AS sub_bolsa_b,
       IFNULL(cc.premio_1_monto_fijo,
              ROUND((cam.presupuesto - cam.num_videos * cc.base_por_clip) * cc.pct_c, 2)) AS sub_bolsa_c,
       COUNT(DISTINCT c.id) AS clips,
       COUNT(DISTINCT CASE WHEN q.codigo='APROBADO' THEN c.id END) AS clips_aprobados,
       COUNT(DISTINCT c.editor_id) AS editores,
       COALESCE(SUM(m.vistas_totales),0) AS vistas,
       COALESCE(SUM(m.likes_totales),0) AS likes
FROM campaign cam
JOIN cat_campaign_state s ON s.id = cam.campaign_state_id
LEFT JOIN campaign_config cc ON cc.campaign_id = cam.id
LEFT JOIN clip c           ON c.campaign_id = cam.id
LEFT JOIN cat_qa_state q   ON q.id = c.qa_state_id
LEFT JOIN v_clip_metrics m ON m.clip_id = c.id
GROUP BY cam.id, cam.nombre, s.codigo,
         cam.artista_cancion, cam.url_audio, cam.imagen_url,
         cam.titulo, cam.descripcion, cam.pautas_contenido,
         cam.fecha_inicio, cam.fecha_cierre, cam.client_id,
         cam.num_videos, cam.presupuesto, cam.pagado,
         cc.base_por_clip, cc.pct_a, cc.pct_b, cc.pct_c, cc.premio_1_monto_fijo;
