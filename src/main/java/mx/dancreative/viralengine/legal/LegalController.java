package mx.dancreative.viralengine.legal;

import jakarta.servlet.http.HttpServletRequest;
import mx.dancreative.viralengine.security.CurrentUser;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Documentos legales y su aceptación.
 * Requisito de "Cambios finales": aviso de privacidad + aceptación del contrato.
 */
@RestController
@RequestMapping("/legal")
public class LegalController {

    private final JdbcTemplate jdbc;
    public LegalController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    /** Documentos vigentes que le tocan al usuario, con su estado de aceptación. */
    @GetMapping("/pending")
    public List<Map<String, Object>> pendientes() {
        return jdbc.queryForList("""
            SELECT p.legal_document_id, p.tipo, p.version, p.titulo, p.aceptado,
                   d.contenido
              FROM v_legal_pendiente p
              JOIN legal_document d ON d.id = p.legal_document_id
             WHERE p.user_id = ?
             ORDER BY FIELD(p.tipo,'PRIVACIDAD','TYC_EDITOR','TYC_CLIENTE')""",
            CurrentUser.id());
    }

    /** Acepta todos los documentos pendientes. Deja constancia de IP y navegador. */
    @PostMapping("/accept")
    public Map<String, Object> aceptar(@RequestBody(required = false) Map<String, Object> body,
                                       HttpServletRequest req) {
        Long uid = CurrentUser.id();
        String ip = req.getHeader("X-Forwarded-For");
        if (ip == null || ip.isBlank()) ip = req.getRemoteAddr();
        String ua = req.getHeader("User-Agent");
        if (ua != null && ua.length() > 255) ua = ua.substring(0, 255);

        jdbc.update("""
            INSERT IGNORE INTO legal_acceptance (user_id, legal_document_id, ip, user_agent)
            SELECT ?, legal_document_id, ?, ?
              FROM v_legal_pendiente
             WHERE user_id = ? AND aceptado = FALSE""", uid, ip, ua, uid);

        // se guarda también en users para consultas rápidas
        jdbc.update("""
            UPDATE users u
               SET u.tyc_aceptado_at = COALESCE(u.tyc_aceptado_at, NOW(6)),
                   u.privacidad_aceptada_at = COALESCE(u.privacidad_aceptada_at, NOW(6)),
                   u.tyc_version = (SELECT MAX(d.version) FROM legal_document d
                                     JOIN cat_legal_type t ON t.id = d.legal_type_id
                                    WHERE d.vigente = TRUE AND t.codigo <> 'PRIVACIDAD')
             WHERE u.id = ?""", uid);

        jdbc.update("INSERT INTO audit_log (user_id, accion, detalle) VALUES (?, 'LEGAL_ACCEPT', ?)",
                    uid, "Aceptó términos y aviso de privacidad desde " + ip);

        return Map.of("ok", true);
    }

    /** Consulta pública de un documento (para mostrarlo fuera de sesión si hace falta). */
    @GetMapping("/{tipo}")
    public Map<String, Object> documento(@PathVariable String tipo) {
        return jdbc.queryForMap("""
            SELECT d.id, t.codigo AS tipo, d.version, d.titulo, d.contenido, d.publicado_at
              FROM legal_document d
              JOIN cat_legal_type t ON t.id = d.legal_type_id
             WHERE t.codigo = ? AND d.vigente = TRUE
             ORDER BY d.publicado_at DESC LIMIT 1""", tipo.toUpperCase());
    }
}
