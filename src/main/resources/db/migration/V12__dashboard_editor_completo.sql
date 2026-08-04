-- =====================================================================
-- V12 — El tablero del editor devuelve lo que la ficha necesita mostrar.
--
-- v_editor_dashboard solo traía cifras y el nombre de la campaña como `campana`.
-- Faltaban tres cosas y una de ellas bloqueaba el flujo entero:
--
-- 1) `a.id` (el id de la ASIGNACIÓN). Sin él, el botón "Confirmar mi
--    participación" llamaba a /assignments/undefined/confirm. Un editor no
--    podía confirmar, y sin confirmar no arranca nada.
-- 2) Los datos descriptivos de la campaña (portada, artista, título,
--    descripción y pautas): la ficha del editor los muestra todos.
-- 3) Las plataformas objetivo y el material fuente, que es justo lo que el
--    editor necesita para trabajar.
--
-- Las listas se devuelven como cadenas separadas por coma; el cliente las parte.
-- =====================================================================

CREATE OR REPLACE VIEW v_editor_dashboard AS
SELECT a.id            AS assignment_id,
       a.user_id       AS editor_id,
       a.campaign_id,
       cam.nombre      AS campana,
       cam.nombre,                                   -- alias directo para el cliente
       s.codigo        AS estado_campana,
       a.cap_dinamico, a.asignacion_base, a.extras, a.confirmado,
       -- datos que la ficha del editor muestra
       cam.artista_cancion, cam.url_audio, cam.imagen_url,
       cam.titulo, cam.descripcion, cam.pautas_contenido,
       cam.fecha_inicio, cam.fecha_cierre,
       (SELECT GROUP_CONCAT(p.codigo)
          FROM campaign_platform cp JOIN cat_platform p ON p.id = cp.platform_id
         WHERE cp.campaign_id = cam.id)              AS plataformas,
       (SELECT GROUP_CONCAT(mm.url SEPARATOR '|')
          FROM campaign_material mm
         WHERE mm.campaign_id = cam.id)              AS materiales,
       -- Cuentas que el editor eligió para ESTA campaña. Sin esto la ficha
       -- deja el botón "Subir clip" deshabilitado para siempre.
       (SELECT GROUP_CONCAT(CONCAT(pl.codigo, '~', ea.url) SEPARATOR '|')
          FROM assignment_account aa
          JOIN editor_account ea ON ea.id = aa.editor_account_id
          JOIN cat_platform pl   ON pl.id = ea.platform_id
         WHERE aa.assignment_id = a.id)              AS cuentas,
       (SELECT COUNT(*) FROM strike st
         WHERE st.user_id = a.user_id AND st.activo = TRUE) AS strikes,
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
         cam.artista_cancion, cam.url_audio, cam.imagen_url,
         cam.titulo, cam.descripcion, cam.pautas_contenido,
         cam.fecha_inicio, cam.fecha_cierre;
