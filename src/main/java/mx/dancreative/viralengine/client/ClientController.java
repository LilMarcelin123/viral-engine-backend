package mx.dancreative.viralengine.client;

import mx.dancreative.viralengine.security.CurrentUser;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/client")
@PreAuthorize("hasRole('CLIENTE')")
public class ClientController {

    private final JdbcTemplate jdbc;
    public ClientController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    private void exigirSuya(long campaignId) {
        Long owner = jdbc.queryForObject(
            "SELECT client_id FROM campaign WHERE id = ?", Long.class, campaignId);
        if (owner == null || !owner.equals(CurrentUser.id()))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "La campaña no está asignada a tu cuenta");
    }

    /** Sus campañas — vista SIN ningún dato de dinero. Incluye cerradas. */
    @GetMapping("/campaigns")
    public List<Map<String, Object>> campanias() {
        return jdbc.queryForList("""
            SELECT * FROM v_campaign_report_client WHERE client_id = ?
             ORDER BY campaign_id DESC""", CurrentUser.id());
    }

    @GetMapping("/campaigns/{id}")
    public Map<String, Object> reporte(@PathVariable long id) {
        exigirSuya(id);
        return jdbc.queryForMap("SELECT * FROM v_campaign_report_client WHERE campaign_id = ?", id);
    }

    /** Videos de su campaña: editor, tags, likes, vistas; filtro por editor. */
    @GetMapping("/campaigns/{id}/videos")
    public List<Map<String, Object>> videos(@PathVariable long id,
                                            @RequestParam(required = false) Long editor) {
        exigirSuya(id);
        return jdbc.queryForList("""
            SELECT clip_id, titulo, editor, estado_qa, fecha_publicado,
                   vistas_totales, likes_totales, tags
              FROM v_campaign_videos
             WHERE campaign_id = ? AND (? IS NULL OR editor_id = ?)
             ORDER BY vistas_totales DESC""", id, editor, editor);
    }
}
