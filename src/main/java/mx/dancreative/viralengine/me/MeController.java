package mx.dancreative.viralengine.me;

import mx.dancreative.viralengine.security.CurrentUser;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/me")
@PreAuthorize("hasRole('EDITOR')")
public class MeController {

    private final JdbcTemplate jdbc;
    public MeController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    /** Dashboard: solo campañas ACTIVAS (las cerradas no se muestran al editor). */
    @GetMapping("/dashboard")
    public List<Map<String, Object>> dashboard() {
        return jdbc.queryForList("""
            SELECT * FROM v_editor_dashboard
             WHERE editor_id = ? AND estado_campana = 'ACTIVA'""", CurrentUser.id());
    }

    /** Sus clips con estado de QA y vistas. */
    @GetMapping("/clips")
    public List<Map<String, Object>> clips(@RequestParam(required = false) Long campaign) {
        return jdbc.queryForList("""
            SELECT c.id, c.campaign_id, c.titulo, q.codigo AS estado, c.motivo,
                   c.excluido_bonos, m.vistas_totales, m.likes_totales, c.fecha_congelado,
                   pb.publicaciones
              FROM clip c
              JOIN cat_qa_state q ON q.id = c.qa_state_id
              LEFT JOIN v_clip_metrics m ON m.clip_id = c.id
              LEFT JOIN v_clip_publicaciones pb ON pb.clip_id = c.id
             WHERE c.editor_id = ? AND (? IS NULL OR c.campaign_id = ?)
             ORDER BY c.created_at DESC""", CurrentUser.id(), campaign, campaign);
    }

    /** Sus pagos: los ve aunque la campaña esté cerrada. */
    @GetMapping("/payments")
    public List<Map<String, Object>> pagos() {
        return jdbc.queryForList("""
            SELECT p.campaign_id, c.nombre AS campana, p.pago_base, p.bono_escalon,
                   p.bono_acumulado, p.premio_1, p.total, s.codigo AS estado,
                   p.fecha_pago, p.quincena
              FROM payment p
              JOIN campaign c ON c.id = p.campaign_id
              JOIN cat_payment_state s ON s.id = p.payment_state_id
             WHERE p.editor_id = ? ORDER BY p.id DESC""", CurrentUser.id());
    }

    /** Sus strikes con motivo. */
    @GetMapping("/strikes")
    public List<Map<String, Object>> strikes() {
        return jdbc.queryForList("""
            SELECT s.id, s.motivo, s.activo, s.created_at, c.nombre AS campana
              FROM strike s LEFT JOIN campaign c ON c.id = s.campaign_id
             WHERE s.user_id = ? ORDER BY s.created_at DESC""", CurrentUser.id());
    }

    /**
     * Datos propios del usuario: nombre, teléfono y correo PayPal (medio de pago
     * para la dispersión manual). Solo se actualiza lo que venga en el cuerpo,
     * así que mandar un campo suelto no borra los demás.
     */
    // Anula el hasRole('EDITOR') de la clase: cualquiera edita SUS propios datos
    // (la pantalla de Ajustes la usan admin, editor y cliente por igual).
    @PreAuthorize("isAuthenticated()")
    @PutMapping({"/paypal", "/perfil"})
    public void perfil(@RequestBody Map<String, String> body) {
        if (body.containsKey("nombre"))
            jdbc.update("UPDATE users SET nombre = ? WHERE id = ?",
                body.get("nombre"), CurrentUser.id());
        if (body.containsKey("telefono"))
            jdbc.update("UPDATE users SET telefono = ? WHERE id = ?",
                body.get("telefono"), CurrentUser.id());
        if (body.containsKey("correoPaypal"))
            jdbc.update("UPDATE users SET correo_paypal = ? WHERE id = ?",
                body.get("correoPaypal"), CurrentUser.id());
    }
}
