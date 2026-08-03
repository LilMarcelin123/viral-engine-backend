package mx.dancreative.viralengine.account;

import mx.dancreative.viralengine.security.CurrentUser;
import mx.dancreative.viralengine.wallet.WalletService;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/me/accounts")
@PreAuthorize("hasRole('EDITOR')")
public class EditorAccountController {

    private final JdbcTemplate jdbc;
    public EditorAccountController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @GetMapping
    public List<Map<String, Object>> mias() {
        return jdbc.queryForList("""
            SELECT a.id, p.codigo AS plataforma, a.handle, a.url, a.activo
              FROM editor_account a JOIN cat_platform p ON p.id = a.platform_id
             WHERE a.user_id = ? ORDER BY p.codigo, a.handle""", CurrentUser.id());
    }

    /** Alta con validación de límites (3/plataforma, 9 total) y de URL por red — todo en el SP. */
    @PostMapping
    public void alta(@RequestBody Map<String, String> body) {
        Integer platformId = jdbc.queryForObject(
            "SELECT id FROM cat_platform WHERE codigo = ? AND activo = TRUE",
            Integer.class, body.get("plataforma"));
        try {
            jdbc.update("CALL sp_editor_account_alta(?, ?, ?, ?)",
                CurrentUser.id(), platformId, body.get("handle"), body.get("url"));
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    @DeleteMapping("/{id}")
    public void baja(@PathVariable long id) {
        int n = jdbc.update(
            "UPDATE editor_account SET activo = FALSE WHERE id = ? AND user_id = ?",
            id, CurrentUser.id());
        if (n == 0) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "La cuenta no es tuya");
    }
}
