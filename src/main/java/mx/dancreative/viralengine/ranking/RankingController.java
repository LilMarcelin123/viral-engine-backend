package mx.dancreative.viralengine.ranking;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

@RestController
@PreAuthorize("hasRole('ADMIN')")
public class RankingController {

    private final JdbcTemplate jdbc;
    public RankingController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    /** metric: vistas | ganancias | clips | score (pesos editables en app_config). */
    @GetMapping("/ranking/editors")
    public List<Map<String, Object>> ranking(@RequestParam(defaultValue = "vistas") String metric) {
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT * FROM v_editor_ranking");

        double maxV = rows.stream().mapToDouble(r -> num(r, "vistas_totales")).max().orElse(1);
        double maxG = rows.stream().mapToDouble(r -> num(r, "ganancias")).max().orElse(1);
        double maxC = rows.stream().mapToDouble(r -> num(r, "clips_aprobados")).max().orElse(1);

        Map<String, Object> w = jdbc.queryForMap(
            "SELECT score_w_vistas, score_w_ganancias, score_w_clips FROM app_config WHERE id = 1");
        double wv = num(w, "score_w_vistas"), wg = num(w, "score_w_ganancias"), wc = num(w, "score_w_clips");

        for (var r : rows) {
            double score = wv * (num(r, "vistas_totales") / Math.max(maxV, 1))
                         + wg * (num(r, "ganancias")      / Math.max(maxG, 1))
                         + wc * (num(r, "clips_aprobados")/ Math.max(maxC, 1));
            r.put("score", Math.round(score * 1000.0) / 1000.0);
        }

        Comparator<Map<String, Object>> cmp = switch (metric) {
            case "ganancias" -> Comparator.comparingDouble(r -> -num(r, "ganancias"));
            case "clips"     -> Comparator.comparingDouble(r -> -num(r, "clips_aprobados"));
            case "score"     -> Comparator.comparingDouble(r -> -num(r, "score"));
            default          -> Comparator.comparingDouble(r -> -num(r, "vistas_totales"));
        };
        rows.sort(cmp);
        int pos = 1;
        for (var r : rows) r.put("posicion", pos++);
        return rows;
    }

    private static double num(Map<String, Object> r, String k) {
        Object v = r.get(k);
        if (v == null) return 0;
        if (v instanceof BigDecimal b) return b.doubleValue();
        return ((Number) v).doubleValue();
    }
}
