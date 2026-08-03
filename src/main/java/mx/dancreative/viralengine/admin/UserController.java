package mx.dancreative.viralengine.admin;

import mx.dancreative.viralengine.security.CurrentUser;
import mx.dancreative.viralengine.wallet.WalletService;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@PreAuthorize("hasRole('ADMIN')")
public class UserController {

    private final JdbcTemplate jdbc;
    private final PasswordEncoder encoder;

    public UserController(JdbcTemplate jdbc, PasswordEncoder encoder) {
        this.jdbc = jdbc; this.encoder = encoder;
    }

    /** Lista de usuarios con su rol, estado y (si es cliente) sus campañas asignadas. */
    @GetMapping("/users")
    public List<Map<String, Object>> listar() {
        return jdbc.queryForList("""
            SELECT u.id, u.nombre, u.email, u.telefono, u.correo_paypal,
                   t.codigo AS role, t.codigo AS user_type,
                   st.codigo AS estado, u.created_at,
                   (SELECT COUNT(*) FROM editor_account a WHERE a.user_id = u.id AND a.activo) AS cuentas,
                   (SELECT COUNT(*) FROM strike s WHERE s.user_id = u.id AND s.activo) AS strikes,
                   (SELECT GROUP_CONCAT(c.id) FROM campaign c WHERE c.client_id = u.id) AS campanias_ids
              FROM users u
              JOIN cat_user_type t   ON t.id  = u.user_type_id
              JOIN cat_user_state st ON st.id = u.user_state_id
             ORDER BY t.codigo, u.nombre""");
    }

    /** Cambia rol, estado o datos básicos del usuario. */
    @PatchMapping("/users/{id}")
    public void actualizar(@PathVariable long id, @RequestBody Map<String, Object> body) {
        String rol = (String) (body.containsKey("user_type") ? body.get("user_type") : body.get("role"));
        if (rol != null)
            jdbc.update("""
                UPDATE users SET user_type_id = (SELECT id FROM cat_user_type WHERE codigo = ?)
                 WHERE id = ?""", rol.toUpperCase(), id);

        if (body.get("estado") != null)
            jdbc.update("""
                UPDATE users SET user_state_id = (SELECT id FROM cat_user_state WHERE codigo = ?)
                 WHERE id = ?""", ((String) body.get("estado")).toUpperCase(), id);

        if (body.get("nombre") != null)
            jdbc.update("UPDATE users SET nombre = ? WHERE id = ?", body.get("nombre"), id);
        if (body.get("telefono") != null)
            jdbc.update("UPDATE users SET telefono = ? WHERE id = ?", body.get("telefono"), id);

        jdbc.update("INSERT INTO audit_log (user_id, accion, detalle) VALUES (?, 'USER_UPDATE', ?)",
                    CurrentUser.id(), "Usuario " + id + " actualizado");
    }

    /** Asigna o desasigna una campaña a un cliente (chips de la ficha). */
    @PutMapping("/users/{id}/campaigns/{campaignId}")
    public void asignarCampania(@PathVariable long id, @PathVariable long campaignId,
                                @RequestBody Map<String, Object> body) {
        boolean asignar = Boolean.TRUE.equals(body.get("asignar"));
        jdbc.update("UPDATE campaign SET client_id = ? WHERE id = ?", asignar ? id : null, campaignId);
    }

    /**
     * Invitación: crea el usuario con una contraseña temporal.
     * (El envío del correo se implementará después; por ahora se devuelve
     *  la contraseña temporal para que el admin la comparta.)
     */
    @PostMapping("/users/invite")
    public Map<String, Object> invitar(@RequestBody Map<String, String> body) {
        String email = body.get("email");
        String rol   = body.getOrDefault("user_type", body.getOrDefault("role", "EDITOR")).toUpperCase();
        String temp  = UUID.randomUUID().toString().substring(0, 10);
        try {
            jdbc.update("""
                INSERT INTO users (nombre, email, password_hash, user_type_id, user_state_id)
                SELECT ?, ?, ?,
                       (SELECT id FROM cat_user_type  WHERE codigo = ?),
                       (SELECT id FROM cat_user_state WHERE codigo = 'ACTIVO')""",
                body.getOrDefault("nombre", email.split("@")[0]), email, encoder.encode(temp), rol);
        } catch (DataAccessException e) { throw WalletService.traducir(e); }

        jdbc.update("INSERT INTO audit_log (user_id, accion, detalle) VALUES (?, 'USER_INVITE', ?)",
                    CurrentUser.id(), "Invitación a " + email + " como " + rol);
        return Map.of("email", email, "role", rol, "password_temporal", temp);
    }

    // ---------- Configuración de bonos (Settings → Pagos) ----------

    @GetMapping("/config")
    public Map<String, Object> config() {
        Map<String, Object> cfg = jdbc.queryForMap("SELECT * FROM app_config WHERE id = 1");
        cfg.put("tiers", jdbc.queryForList("""
            SELECT t.id, tt.codigo AS tipo, t.vistas_min, t.bono
              FROM bonus_tier t JOIN cat_tier_type tt ON tt.id = t.tier_type_id
             ORDER BY tt.codigo, t.vistas_min"""));
        return cfg;
    }

    @PutMapping("/config")
    public void guardarConfig(@RequestBody Map<String, Object> body) {
        var permitidos = List.of("precio_por_video","base_por_clip","pct_a","pct_b","pct_c",
            "premio_1_monto_fijo","max_cuentas_por_plataforma","max_cuentas_total",
            "max_clips_por_cuenta_dia","max_clips_dia","dias_congelado","horas_confirmacion",
            "pct_aprobacion_extras","strikes_para_remocion","pct_cap_campana",
            "clips_por_cuenta_dia_cap","score_w_vistas","score_w_ganancias","score_w_clips");
        body.forEach((k, v) -> {
            if (permitidos.contains(k))
                jdbc.update("UPDATE app_config SET " + k + " = ? WHERE id = 1", v);
        });
    }

    // ---------- Bitácora ----------

    @GetMapping("/audit")
    public List<Map<String, Object>> audit(@RequestParam(defaultValue = "100") int limit) {
        return jdbc.queryForList("""
            SELECT a.id, a.accion, a.detalle, a.created_at, a.created_at AS created_date,
                   u.nombre AS usuario, t.codigo AS rol
              FROM audit_log a
              LEFT JOIN users u        ON u.id = a.user_id
              LEFT JOIN cat_user_type t ON t.id = u.user_type_id
             ORDER BY a.created_at DESC LIMIT ?""", Math.min(limit, 500));
    }

    @PostMapping("/audit")
    public void registrar(@RequestBody Map<String, Object> body) {
        jdbc.update("INSERT INTO audit_log (user_id, accion, detalle) VALUES (?, ?, ?)",
            CurrentUser.id(),
            body.getOrDefault("accion", "ACCION"),
            body.getOrDefault("detalle", ""));
        
        
        
    }
    
    
    /** Todos los clips (admin) para cruzar por editor. */
    @GetMapping("/clips")
    public List<Map<String, Object>> clips() {
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT c.id, c.campaign_id, c.editor_id, c.titulo, c.motivo,
                   q.codigo AS estado, c.excluido_bonos, c.fecha_publicado,
                   c.created_at, c.created_at AS created_date,
                   COALESCE(m.vistas_totales,0) AS vistas_totales,
                   COALESCE(m.likes_totales,0)  AS likes_totales
              FROM clip c
              JOIN cat_qa_state q ON q.id = c.qa_state_id
              LEFT JOIN v_clip_metrics m ON m.clip_id = c.id
             ORDER BY c.created_at DESC""");

        for (Map<String, Object> c : rows) {
            c.put("publications", jdbc.queryForList("""
                SELECT p.codigo AS platform, cp.link, cp.vistas, cp.likes
                  FROM clip_publication cp
                  JOIN cat_platform p ON p.id = cp.platform_id
                 WHERE cp.clip_id = ?""", c.get("id")));
        }
        return rows;
    }
    
    
    /** Todas las asignaciones (admin), con sus cuentas anidadas. */
    @GetMapping("/assignments")
    public List<Map<String, Object>> assignments() {
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT a.id, a.campaign_id, a.user_id, a.user_id AS editor_id,
                   a.cap_dinamico, a.asignacion_base, a.extras, a.confirmado,
                   a.created_at, a.created_at AS created_date, cam.nombre AS campana
              FROM editor_assignment a
              JOIN campaign cam ON cam.id = a.campaign_id
             ORDER BY a.id DESC""");
        for (Map<String, Object> r : rows) {
            r.put("cuentas", jdbc.queryForList("""
                SELECT p.codigo AS platform, e.handle, e.url
                  FROM assignment_account aa
                  JOIN editor_account e ON e.id = aa.editor_account_id
                  JOIN cat_platform p   ON p.id = e.platform_id
                 WHERE aa.assignment_id = ?""", r.get("id")));
        }
        return rows;
    }
}
