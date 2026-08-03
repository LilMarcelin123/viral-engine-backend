package mx.dancreative.viralengine.report;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Reportes del admin (requisito de "Cambios finales"):
 * generales, por tags y por campaña.
 */
@RestController
@RequestMapping("/reports")
@PreAuthorize("hasRole('ADMIN')")
public class ReportController {

    private final JdbcTemplate jdbc;
    public ReportController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    /** Resumen general de la plataforma. */
    @GetMapping("/general")
    public Map<String, Object> general() {
        Map<String, Object> r = jdbc.queryForMap("""
            SELECT
              (SELECT COUNT(*) FROM campaign) AS campanias,
              (SELECT COUNT(*) FROM campaign c
                 JOIN cat_campaign_state s ON s.id = c.campaign_state_id
                WHERE s.computa_garantia = TRUE) AS campanias_activas,
              (SELECT COUNT(*) FROM clip) AS clips,
              (SELECT COUNT(*) FROM clip c
                 JOIN cat_qa_state q ON q.id = c.qa_state_id
                WHERE q.codigo = 'APROBADO') AS clips_aprobados,
              (SELECT COALESCE(SUM(vistas),0) FROM clip_publication) AS vistas,
              (SELECT COALESCE(SUM(likes),0)  FROM clip_publication) AS likes,
              (SELECT COUNT(*) FROM users u
                 JOIN cat_user_type t ON t.id = u.user_type_id
                WHERE t.codigo = 'EDITOR') AS editores,
              (SELECT COALESCE(SUM(p.total),0) FROM payment p
                 JOIN cat_payment_state s ON s.id = p.payment_state_id
                WHERE s.codigo = 'PAGADO') AS total_pagado,
              (SELECT COALESCE(SUM(p.total),0) FROM payment p
                 JOIN cat_payment_state s ON s.id = p.payment_state_id
                WHERE s.codigo = 'PENDIENTE') AS total_pendiente""");
        return r;
    }

    /**
     * Reporte por tags: métricas agregadas de todos los clips que llevan
     * cada tag, opcionalmente filtrado por campaña.
     */
    @GetMapping("/tags")
    public List<Map<String, Object>> porTags(@RequestParam(required = false) Long campaign) {
        return jdbc.queryForList("""
            SELECT t.nombre AS tag,
                   COUNT(DISTINCT c.id)                                        AS clips,
                   COUNT(DISTINCT CASE WHEN q.codigo='APROBADO' THEN c.id END) AS clips_aprobados,
                   COUNT(DISTINCT c.editor_id)                                 AS editores,
                   COUNT(DISTINCT c.campaign_id)                               AS campanias,
                   COALESCE(SUM(m.vistas_totales),0)                           AS vistas,
                   COALESCE(SUM(m.likes_totales),0)                            AS likes,
                   ROUND(COALESCE(AVG(m.vistas_totales),0))                    AS vistas_promedio
              FROM tag t
              JOIN clip_tag ct ON ct.tag_id = t.id
              JOIN clip c      ON c.id = ct.clip_id
              JOIN cat_qa_state q ON q.id = c.qa_state_id
              LEFT JOIN v_clip_metrics m ON m.clip_id = c.id
             WHERE (? IS NULL OR c.campaign_id = ?)
             GROUP BY t.id, t.nombre
             ORDER BY vistas DESC""", campaign, campaign);
    }

    /** Detalle de los clips de un tag (para el drill-down). */
    @GetMapping("/tags/{tag}/clips")
    public List<Map<String, Object>> clipsDeTag(@PathVariable String tag,
                                                @RequestParam(required = false) Long campaign) {
        return jdbc.queryForList("""
            SELECT v.* FROM v_campaign_videos v
              JOIN clip_tag ct ON ct.clip_id = v.clip_id
              JOIN tag t       ON t.id = ct.tag_id
             WHERE t.nombre = ?
               AND (? IS NULL OR v.campaign_id = ?)
             ORDER BY v.vistas_totales DESC""", tag, campaign, campaign);
    }
}
