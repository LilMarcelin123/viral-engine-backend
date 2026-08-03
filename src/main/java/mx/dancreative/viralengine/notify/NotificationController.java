package mx.dancreative.viralengine.notify;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/notifications")
@PreAuthorize("hasRole('ADMIN')")
public class NotificationController {

    private final JdbcTemplate jdbc;
    private final NotificationService service;

    public NotificationController(JdbcTemplate jdbc, NotificationService service) {
        this.jdbc = jdbc; this.service = service;
    }

    /** Bitácora de notificaciones (enviadas, pendientes y con error). */
    @GetMapping
    public List<Map<String, Object>> listar(@RequestParam(defaultValue = "100") int limit) {
        return jdbc.queryForList("""
            SELECT n.id, u.nombre AS usuario, n.destino,
                   ch.codigo AS canal, t.codigo AS tipo, st.codigo AS estado,
                   SUBSTRING_INDEX(n.mensaje, '|||', 1) AS asunto,
                   c.nombre AS campana, n.error, n.enviado_at,
                   n.created_at, n.created_at AS created_date
              FROM notification n
              LEFT JOIN users u    ON u.id = n.user_id
              LEFT JOIN campaign c ON c.id = n.campaign_id
              JOIN cat_notification_channel ch ON ch.id = n.notification_channel_id
              JOIN cat_notification_type    t  ON t.id  = n.notification_type_id
              JOIN cat_notification_state   st ON st.id = n.notification_state_id
             ORDER BY n.created_at DESC LIMIT ?""", Math.min(limit, 500));
    }

    /** Dispara el aviso de nueva campaña a todos los editores activos. */
    @PostMapping("/campaign/{id}")
    public Map<String, Object> avisarCampania(@PathVariable long id) {
        int n = service.notificarNuevaCampania(id);
        return Map.of("encoladas", n);
    }

    /** Reintenta las notificaciones que fallaron. */
    @PostMapping("/retry")
    public Map<String, Object> reintentar() {
        int n = jdbc.update("""
            UPDATE notification
               SET notification_state_id = (SELECT id FROM cat_notification_state WHERE codigo='PENDIENTE'),
                   error = NULL
             WHERE notification_state_id = (SELECT id FROM cat_notification_state WHERE codigo='ERROR')""");
        return Map.of("reencoladas", n);
    }
}
