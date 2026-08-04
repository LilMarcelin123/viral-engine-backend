package mx.dancreative.viralengine.scrape;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Scrapeo — solo administrador y solo a mano.
 *
 * No hay tarea programada ni botón en la interfaz a propósito: cada corrida de
 * Apify cuesta, y quien decide cuándo gastarla es el administrador desde la
 * terminal (ver scripts/scrape.sh).
 */
@RestController
@RequestMapping("/scrape")
@PreAuthorize("hasRole('ADMIN')")
public class ScrapeController {

    private final ScrapeService service;
    private final ApifyClient apify;
    private final JdbcTemplate jdbc;

    public ScrapeController(ScrapeService service, ApifyClient apify, JdbcTemplate jdbc) {
        this.service = service; this.apify = apify; this.jdbc = jdbc;
    }

    /** Qué se scrapearía ahora mismo, sin gastar una corrida. */
    @GetMapping("/pendientes")
    public Map<String, Object> pendientes(@RequestParam(required = false) Long campaign) {
        return Map.of(
            "apify_configurado", apify.configurado(),
            "por_plataforma", jdbc.queryForList("""
                SELECT plataforma, COUNT(*) AS publicaciones,
                       MIN(apify_actor_id) AS actor
                  FROM v_publicaciones_a_scrapear
                 WHERE (? IS NULL OR campaign_id = ?)
                 GROUP BY plataforma""", campaign, campaign));
    }

    /** Lanza una corrida por plataforma. Devuelve los ids para recolectar después. */
    @PostMapping("/iniciar")
    public List<Map<String, Object>> iniciar(@RequestParam(required = false) Long campaign) {
        return service.iniciar(campaign);
    }

    /** Aplica los resultados de las corridas que ya terminaron en Apify. */
    @PostMapping("/recolectar")
    public List<Map<String, Object>> recolectar() {
        return service.recolectar();
    }

    /** Últimas corridas con su costo. */
    @GetMapping("/corridas")
    public List<Map<String, Object>> corridas(@RequestParam(defaultValue = "20") int limit) {
        return jdbc.queryForList("""
            SELECT sr.id, sr.campaign_id, cam.nombre AS campana, pl.codigo AS plataforma,
                   st.codigo AS estado, sr.items_solicitados, sr.items_recibidos,
                   sr.publicaciones_actualizadas, sr.costo_usd, sr.compute_units,
                   sr.iniciado_at, sr.finalizado_at, sr.error, sr.apify_run_id
              FROM scrape_run sr
              JOIN cat_scrape_state st ON st.id = sr.scrape_state_id
              LEFT JOIN cat_platform pl ON pl.id = sr.platform_id
              LEFT JOIN campaign cam    ON cam.id = sr.campaign_id
             ORDER BY sr.id DESC LIMIT ?""", Math.min(limit, 100));
    }

    /** Publicaciones cuyo autor no coincide con la cuenta registrada. */
    @GetMapping("/sospechosas")
    public List<Map<String, Object>> sospechosas() {
        return jdbc.queryForList("SELECT * FROM v_publicaciones_sospechosas");
    }
}
