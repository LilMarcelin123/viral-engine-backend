package mx.dancreative.viralengine.assignment;

import mx.dancreative.viralengine.security.CurrentUser;
import mx.dancreative.viralengine.wallet.WalletService;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.sql.Types;
import java.util.List;
import java.util.Map;

@RestController
public class AssignmentController {

    private final JdbcTemplate jdbc;
    public AssignmentController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    private void exigirPropia(long assignmentId) {
        Long owner = jdbc.queryForObject(
            "SELECT user_id FROM editor_assignment WHERE id = ?", Long.class, assignmentId);
        if (owner == null || !owner.equals(CurrentUser.id()))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "La asignación no es tuya");
    }

    @PostMapping("/campaigns/{id}/assignments")
    @PreAuthorize("hasRole('ADMIN')")
    public Map<String, Object> crear(@PathVariable long id, @RequestBody Map<String, Long> body) {
        try {
            Long aid = jdbc.execute((java.sql.Connection con) -> {
                try (var cs = con.prepareCall("{CALL sp_assignment_crear(?,?,?)}")) {
                    cs.setLong(1, id);
                    cs.setLong(2, body.get("userId"));
                    cs.registerOutParameter(3, Types.BIGINT);
                    cs.execute();
                    return cs.getLong(3);
                }
            });
            return jdbc.queryForMap("SELECT * FROM editor_assignment WHERE id = ?", aid);
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    @PostMapping("/assignments/{id}/confirm")
    @PreAuthorize("hasRole('EDITOR')")
    public void confirmar(@PathVariable long id) {
        exigirPropia(id);
        try { jdbc.update("CALL sp_assignment_confirmar(?)", id); }
        catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    /** Selecciona/deselecciona una cuenta del registro global para esta campaña. */
    @PutMapping("/assignments/{id}/accounts")
    @PreAuthorize("hasRole('EDITOR')")
    public void setCuenta(@PathVariable long id, @RequestBody Map<String, Object> body) {
        exigirPropia(id);
        try {
            jdbc.update("CALL sp_assignment_set_cuenta(?, ?, ?)",
                id, ((Number) body.get("accountId")).longValue(), (Boolean) body.get("agregar"));
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    @PostMapping("/assignments/{id}/release")
    @PreAuthorize("hasRole('ADMIN')")
    public void liberar(@PathVariable long id, @RequestBody Map<String, Object> body) {
        try {
            jdbc.update("CALL sp_reasignacion_liberar(?, ?, ?, ?)",
                id, body.getOrDefault("motivo", "MANUAL"),
                ((Number) body.get("cantidad")).intValue(), CurrentUser.id());
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    @PostMapping("/assignments/{id}/claim")
    @PreAuthorize("hasRole('EDITOR')")
    public void reclamar(@PathVariable long id, @RequestBody Map<String, Object> body) {
        exigirPropia(id);
        try {
            jdbc.update("CALL sp_reasignacion_reclamar(?, ?)",
                id, ((Number) body.get("cantidad")).intValue());
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    @GetMapping("/campaigns/{id}/reassignment")
    public Map<String, Object> disponibles(@PathVariable long id) {
        return jdbc.queryForMap("SELECT * FROM v_reassignment_available WHERE campaign_id = ?", id);
    }

    @GetMapping("/campaigns/{id}/assignments")
    @PreAuthorize("hasRole('ADMIN')")
    public List<Map<String, Object>> porCampania(@PathVariable long id) {
        return jdbc.queryForList("""
            SELECT a.*, u.nombre AS editor,
                   (SELECT COUNT(*) FROM strike s WHERE s.user_id = a.user_id AND s.activo = TRUE) AS strikes
              FROM editor_assignment a JOIN users u ON u.id = a.user_id
             WHERE a.campaign_id = ?""", id);
    }
}
