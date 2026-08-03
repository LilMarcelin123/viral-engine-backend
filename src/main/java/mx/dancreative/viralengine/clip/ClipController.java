package mx.dancreative.viralengine.clip;

import mx.dancreative.viralengine.security.CurrentUser;
import mx.dancreative.viralengine.wallet.WalletService;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.sql.Statement;
import java.util.List;
import java.util.Map;

@RestController
public class ClipController {

    private final JdbcTemplate jdbc;
    public ClipController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    private void exigirPropio(long clipId) {
        Long owner = jdbc.queryForObject("SELECT editor_id FROM clip WHERE id = ?", Long.class, clipId);
        if (owner == null || !owner.equals(CurrentUser.id()))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "El clip no es tuyo");
    }

    /** Alta del clip (estado SUBIDO) + tags. */
    @PostMapping("/clips")
    @PreAuthorize("hasRole('EDITOR')")
    @Transactional
    public Map<String, Object> crear(@RequestBody Map<String, Object> body) {
        long campaignId = ((Number) body.get("campaignId")).longValue();

        // El editor solo puede subir clips a campañas donde está asignado.
        Integer asignado = jdbc.queryForObject("""
            SELECT COUNT(*) FROM editor_assignment
             WHERE campaign_id = ? AND user_id = ?""",
            Integer.class, campaignId, CurrentUser.id());
        if (asignado == null || asignado == 0)
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                "No estás asignado a esta campaña");
        var kh = new GeneratedKeyHolder();
        jdbc.update(con -> {
            var ps = con.prepareStatement("""
                INSERT INTO clip (campaign_id, editor_id, titulo, fecha_publicado, qa_state_id)
                SELECT ?, ?, ?, NOW(6), id FROM cat_qa_state WHERE codigo = 'SUBIDO'""",
                Statement.RETURN_GENERATED_KEYS);
            ps.setLong(1, campaignId);
            ps.setLong(2, CurrentUser.id());
            ps.setString(3, (String) body.get("titulo"));
            return ps;
        }, kh);
        long clipId = kh.getKey().longValue();

        @SuppressWarnings("unchecked")
        List<String> tags = (List<String>) body.get("tags");
        if (tags != null) for (String t : tags) {
            jdbc.update("INSERT IGNORE INTO tag (nombre) VALUES (?)", t);
            jdbc.update("""
                INSERT IGNORE INTO clip_tag (clip_id, tag_id)
                SELECT ?, id FROM tag WHERE nombre = ?""", clipId, t);
        }
        return Map.of("id", clipId);
    }

    /** Publicación en una cuenta: el SP valida límites diarios, cap y URL por red. */
    @PostMapping("/clips/{id}/publications")
    @PreAuthorize("hasRole('EDITOR')")
    public void publicar(@PathVariable long id, @RequestBody Map<String, Object> body) {
        exigirPropio(id);
        try {
            jdbc.update("CALL sp_clip_publicacion_alta(?, ?, ?)",
                id, ((Number) body.get("accountId")).longValue(), (String) body.get("link"));
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    /** QA (admin): APROBADO / NO_APROBADO / EN_REVISION + motivo. */
    @PatchMapping("/clips/{id}/qa")
    @PreAuthorize("hasRole('ADMIN')")
    public void qa(@PathVariable long id, @RequestBody Map<String, String> body) {
        try {
            jdbc.update("CALL sp_clip_qa(?, ?, ?, ?)",
                id, body.get("estado"), body.get("motivo"), CurrentUser.id());
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    /** Strike (admin): excluye el clip de bonos, acumula al editor; 3 => removido. */
    @PostMapping("/clips/{id}/strike")
    @PreAuthorize("hasRole('ADMIN')")
    public void strike(@PathVariable long id, @RequestBody Map<String, String> body) {
        Map<String, Object> clip = jdbc.queryForMap(
            "SELECT editor_id, campaign_id FROM clip WHERE id = ?", id);
        try {
            jdbc.update("CALL sp_strike_aplicar(?, ?, ?, ?, ?)",
                clip.get("editor_id"), clip.get("campaign_id"), id,
                body.get("motivo"), CurrentUser.id());
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    /** Quitar strike (admin) — botón de los cambios finales. */
    @DeleteMapping("/strikes/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public void quitarStrike(@PathVariable long id, @RequestBody Map<String, String> body) {
        try {
            jdbc.update("CALL sp_strike_quitar(?, ?, ?)",
                id, CurrentUser.id(), body.getOrDefault("motivo", "Corrección del admin"));
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    /** Cola de moderación (admin). */
    @GetMapping("/moderation")
    @PreAuthorize("hasRole('ADMIN')")
    public List<Map<String, Object>> cola() {
        return jdbc.queryForList("""
            SELECT c.id, c.campaign_id, cam.nombre AS campana, u.nombre AS editor,
                   c.titulo, q.codigo AS estado, c.created_at,
                   (SELECT COUNT(*) FROM strike s WHERE s.user_id = c.editor_id AND s.activo = TRUE) AS strikes_editor
              FROM clip c
              JOIN campaign cam   ON cam.id = c.campaign_id
              JOIN users u        ON u.id = c.editor_id
              JOIN cat_qa_state q ON q.id = c.qa_state_id
             WHERE q.codigo IN ('SUBIDO','EN_REVISION')
             ORDER BY c.created_at""");
    }

    /** Pantalla "Editores" (admin): cuentas, strikes, pagado y pendiente. */
    @GetMapping("/editors")
    @PreAuthorize("hasRole('ADMIN')")
    public List<Map<String, Object>> editores() {
        return jdbc.queryForList("""
            SELECT u.id, u.nombre, u.email, st.codigo AS estado,
                   (SELECT COUNT(*) FROM editor_account a WHERE a.user_id = u.id AND a.activo) AS cuentas,
                   (SELECT COUNT(*) FROM strike s WHERE s.user_id = u.id AND s.activo) AS strikes,
                   COALESCE((SELECT SUM(p.total) FROM payment p
                              JOIN cat_payment_state ps ON ps.id = p.payment_state_id
                             WHERE p.editor_id = u.id AND ps.codigo = 'PAGADO'), 0) AS total_pagado,
                   COALESCE((SELECT SUM(p.total) FROM payment p
                              JOIN cat_payment_state ps ON ps.id = p.payment_state_id
                             WHERE p.editor_id = u.id AND ps.codigo = 'PENDIENTE'), 0) AS total_pendiente
              FROM users u
              JOIN cat_user_type t  ON t.id = u.user_type_id AND t.codigo = 'EDITOR'
              JOIN cat_user_state st ON st.id = u.user_state_id
             ORDER BY u.nombre""");
    }
}
