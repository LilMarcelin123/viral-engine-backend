package mx.dancreative.viralengine.scrape;

import com.fasterxml.jackson.databind.JsonNode;
import mx.dancreative.viralengine.security.CurrentUser;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.util.*;

/**
 * Orquesta el scrapeo. Se dispara SIEMPRE a mano: no hay tarea programada ni
 * botón en la aplicación, porque cada corrida de Apify cuesta dinero y quien
 * decide cuándo pagarla es el administrador.
 *
 * El flujo es en dos tiempos porque Apify tarda minutos:
 *   1. iniciar()   — lanza una corrida por plataforma y devuelve los ids
 *   2. recolectar() — revisa las corridas abiertas y aplica lo que ya terminó
 */
@Service
public class ScrapeService {

    private static final Logger log = LoggerFactory.getLogger(ScrapeService.class);

    private final JdbcTemplate jdbc;
    private final ApifyClient apify;

    public ScrapeService(JdbcTemplate jdbc, ApifyClient apify) {
        this.jdbc = jdbc; this.apify = apify;
    }

    // ---------------------------------------------------------------
    // 1. Iniciar
    // ---------------------------------------------------------------

    /**
     * Lanza una corrida por cada plataforma con publicaciones pendientes.
     * @param campaignId null = todas las campañas activas
     */
    public List<Map<String, Object>> iniciar(Long campaignId) {
        List<Map<String, Object>> pendientes = jdbc.queryForList("""
            SELECT platform_id, plataforma, apify_actor_id, apify_input_key,
                   GROUP_CONCAT(link SEPARATOR '\\n') AS links,
                   COUNT(*) AS n
              FROM v_publicaciones_a_scrapear
             WHERE (? IS NULL OR campaign_id = ?)
             GROUP BY platform_id, plataforma, apify_actor_id, apify_input_key""",
            campaignId, campaignId);

        if (pendientes.isEmpty())
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "No hay publicaciones que scrapear: revisa que la campaña esté activa y tenga clips publicados.");

        List<Map<String, Object>> corridas = new ArrayList<>();

        for (Map<String, Object> p : pendientes) {
            String actor = (String) p.get("apify_actor_id");
            String inputKey = (String) p.get("apify_input_key");
            String plataforma = (String) p.get("plataforma");

            if (actor == null || actor.isBlank() || inputKey == null || inputKey.isBlank()) {
                corridas.add(Map.of("plataforma", plataforma, "estado", "SIN_ACTOR",
                    "detalle", "cat_platform no tiene actor configurado para " + plataforma));
                continue;
            }

            List<String> urls = List.of(((String) p.get("links")).split("\n"));

            Long runDbId = crearRegistro(campaignId, (Number) p.get("platform_id"), actor, urls.size());

            try {
                ApifyClient.Corrida c = apify.lanzar(actor, inputKey, urls);
                jdbc.update("""
                    UPDATE scrape_run
                       SET apify_run_id = ?, apify_dataset_id = ?
                     WHERE id = ?""", c.runId(), c.datasetId(), runDbId);

                corridas.add(new LinkedHashMap<>(Map.of(
                    "scrape_run_id", runDbId,
                    "plataforma", plataforma,
                    "publicaciones", urls.size(),
                    "apify_run_id", String.valueOf(c.runId()),
                    "estado", "EJECUTANDO")));

            } catch (RuntimeException e) {
                marcarError(runDbId, e.getMessage());
                corridas.add(new LinkedHashMap<>(Map.of(
                    "scrape_run_id", runDbId,
                    "plataforma", plataforma,
                    "estado", "ERROR",
                    "detalle", String.valueOf(e.getMessage()))));
            }
        }
        return corridas;
    }

    private Long crearRegistro(Long campaignId, Number platformId, String actor, int solicitados) {
        jdbc.update("""
            INSERT INTO scrape_run (campaign_id, scrape_state_id, ejecutado_por,
                                    platform_id, apify_actor_id, items_solicitados)
            SELECT ?, id, ?, ?, ?, ? FROM cat_scrape_state WHERE codigo = 'EJECUTANDO'""",
            campaignId, CurrentUser.id(), platformId, actor, solicitados);
        return jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    private void marcarError(Long runId, String mensaje) {
        jdbc.update("""
            UPDATE scrape_run
               SET scrape_state_id = (SELECT id FROM cat_scrape_state WHERE codigo='ERROR'),
                   error = LEFT(?, 500), finalizado_at = NOW(6)
             WHERE id = ?""", mensaje, runId);
    }

    // ---------------------------------------------------------------
    // 2. Recolectar
    // ---------------------------------------------------------------

    /** Revisa las corridas abiertas; aplica las que ya terminaron en Apify. */
    public List<Map<String, Object>> recolectar() {
        List<Map<String, Object>> abiertas = jdbc.queryForList("""
            SELECT sr.id, sr.apify_run_id, sr.apify_dataset_id, sr.platform_id,
                   pl.codigo AS plataforma,
                   pl.apify_campo_vistas, pl.apify_campo_likes,
                   pl.apify_campo_autor,  pl.apify_campo_url
              FROM scrape_run sr
              JOIN cat_scrape_state st ON st.id = sr.scrape_state_id
              LEFT JOIN cat_platform pl ON pl.id = sr.platform_id
             WHERE st.codigo = 'EJECUTANDO' AND sr.apify_run_id IS NOT NULL""");

        List<Map<String, Object>> salida = new ArrayList<>();

        for (Map<String, Object> r : abiertas) {
            Long runDbId = ((Number) r.get("id")).longValue();
            String apifyRunId = (String) r.get("apify_run_id");

            ApifyClient.Corrida c;
            try {
                c = apify.consultar(apifyRunId);
            } catch (RuntimeException e) {
                salida.add(Map.of("scrape_run_id", runDbId, "estado", "SIN_RESPUESTA",
                                  "detalle", String.valueOf(e.getMessage())));
                continue;
            }

            switch (c.estado()) {
                case "SUCCEEDED" -> salida.add(aplicar(runDbId, r, c));
                case "FAILED", "ABORTED", "TIMED-OUT" -> {
                    marcarError(runDbId, "Apify terminó en estado " + c.estado());
                    salida.add(Map.of("scrape_run_id", runDbId, "estado", c.estado()));
                }
                default -> salida.add(Map.of("scrape_run_id", runDbId,
                                             "estado", "EJECUTANDO",
                                             "detalle", "Apify sigue trabajando"));
            }
        }

        if (salida.isEmpty())
            return List.of(Map.of("estado", "NADA_PENDIENTE",
                                  "detalle", "No hay corridas abiertas"));
        return salida;
    }

    private Map<String, Object> aplicar(Long runDbId, Map<String, Object> r, ApifyClient.Corrida c) {
        String datasetId = c.datasetId() != null ? c.datasetId() : (String) r.get("apify_dataset_id");
        JsonNode items;
        try {
            items = apify.resultados(datasetId);
        } catch (RuntimeException e) {
            marcarError(runDbId, e.getMessage());
            return Map.of("scrape_run_id", runDbId, "estado", "ERROR",
                          "detalle", String.valueOf(e.getMessage()));
        }

        // Índice link -> publication_id para casar cada resultado con su publicación
        Map<String, Long> porLink = new HashMap<>();
        for (Map<String, Object> p : jdbc.queryForList(
                "SELECT id, link FROM clip_publication WHERE platform_id = ?", r.get("platform_id"))) {
            porLink.put(normalizarUrl((String) p.get("link")), ((Number) p.get("id")).longValue());
        }

        int aplicados = 0, sinCasar = 0;

        for (JsonNode item : items) {
            String url = primerTexto(item, (String) r.get("apify_campo_url"));
            Long pubId = url == null ? null : porLink.get(normalizarUrl(url));

            if (pubId == null) { sinCasar++; continue; }

            long vistas = primerNumero(item, (String) r.get("apify_campo_vistas"));
            long likes  = primerNumero(item, (String) r.get("apify_campo_likes"));
            String autor = primerTexto(item, (String) r.get("apify_campo_autor"));

            try {
                jdbc.update("CALL sp_scrape_aplicar_lectura(?, ?, ?, ?, ?)",
                            pubId, runDbId, vistas, likes, autor);
                aplicados++;
            } catch (RuntimeException e) {
                log.warn("No se pudo aplicar la lectura de la publicación {}: {}", pubId, e.getMessage());
            }
        }

        jdbc.update("""
            UPDATE scrape_run
               SET scrape_state_id = (SELECT id FROM cat_scrape_state WHERE codigo='OK'),
                   finalizado_at = NOW(6),
                   publicaciones_actualizadas = ?,
                   compute_units = ?, costo_usd = ?
             WHERE id = ?""", aplicados, c.computeUnits(), c.costoUsd(), runDbId);

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("scrape_run_id", runDbId);
        res.put("plataforma", r.get("plataforma"));
        res.put("estado", "OK");
        res.put("aplicados", aplicados);
        res.put("sin_casar", sinCasar);
        res.put("costo_usd", c.costoUsd());
        return res;
    }

    // ---------------------------------------------------------------
    // Utilidades de lectura del JSON
    // ---------------------------------------------------------------

    /**
     * El catálogo guarda varias rutas alternativas separadas por coma porque los
     * actores cambian de campo entre versiones. Se usa la primera que exista.
     * Soporta notación de punto: authorMeta.name
     */
    private JsonNode buscar(JsonNode item, String rutas) {
        if (rutas == null || rutas.isBlank()) return null;
        for (String ruta : rutas.split(",")) {
            JsonNode n = item;
            for (String parte : ruta.trim().split("\\.")) {
                if (n == null) break;
                n = n.get(parte);
            }
            if (n != null && !n.isNull()) return n;
        }
        return null;
    }

    private String primerTexto(JsonNode item, String rutas) {
        JsonNode n = buscar(item, rutas);
        return n == null ? null : n.asText(null);
    }

    private long primerNumero(JsonNode item, String rutas) {
        JsonNode n = buscar(item, rutas);
        return n == null ? 0L : n.asLong(0L);
    }

    /** Para casar URLs: sin protocolo, sin www, sin query, sin diagonal final. */
    private String normalizarUrl(String url) {
        if (url == null) return "";
        String u = url.trim().toLowerCase();
        u = u.replaceFirst("^https?://", "").replaceFirst("^www\\.", "");
        int q = u.indexOf('?');
        if (q >= 0) u = u.substring(0, q);
        return u.replaceAll("/+$", "");
    }
}
