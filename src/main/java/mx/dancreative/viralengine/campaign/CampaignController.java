package mx.dancreative.viralengine.campaign;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import mx.dancreative.viralengine.security.CurrentUser;
import mx.dancreative.viralengine.wallet.WalletService;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/campaigns")
@PreAuthorize("hasRole('ADMIN')")
public class CampaignController {

    public record CreateRequest(
            @NotBlank String nombre, String artistaCancion, String urlAudio,
            LocalDate fechaInicio, LocalDate fechaCierre,
            @Size(max = 100) String titulo, @Size(max = 1500) String descripcion,
            String pautas, String imagenUrl,
            @NotNull @Min(1) Integer numVideos,
            @NotNull @DecimalMin("0.01") java.math.BigDecimal presupuesto,
            Long clientId,
            List<String> plataformas,          // codigos: TIKTOK, INSTAGRAM, ...
            List<Map<String, String>> materiales // [{tipo: LINK|ARCHIVO, url: ...}]
    ) {}

    private final JdbcTemplate jdbc;
    public CampaignController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @PostMapping
    @Transactional
    public Map<String, Object> crear(@Valid @RequestBody CreateRequest req) {
        try {
            Long id = jdbc.execute((java.sql.Connection con) -> {
                try (var cs = con.prepareCall("{CALL sp_campaign_crear(?,?,?,?,?,?,?,?,?,?,?,?,?,?)}")) {
                    cs.setString(1, req.nombre());
                    cs.setString(2, req.artistaCancion());
                    cs.setString(3, req.urlAudio());
                    cs.setObject(4, req.fechaInicio());
                    cs.setObject(5, req.fechaCierre());
                    cs.setString(6, req.titulo());
                    cs.setString(7, req.descripcion());
                    cs.setString(8, req.pautas());
                    cs.setString(9, req.imagenUrl());
                    cs.setInt(10, req.numVideos());
                    cs.setBigDecimal(11, req.presupuesto());
                    if (req.clientId() == null) cs.setNull(12, Types.BIGINT); else cs.setLong(12, req.clientId());
                    cs.setLong(13, CurrentUser.id());
                    cs.registerOutParameter(14, Types.BIGINT);
                    cs.execute();
                    return cs.getLong(14);
                }
            });
            if (req.plataformas() != null)
                for (String cod : req.plataformas())
                    jdbc.update("""
                        INSERT IGNORE INTO campaign_platform (campaign_id, platform_id)
                        SELECT ?, id FROM cat_platform WHERE codigo = ?""", id, cod);
            if (req.materiales() != null)
                for (var m : req.materiales())
                    jdbc.update("""
                        INSERT INTO campaign_material (campaign_id, material_type_id, url)
                        SELECT ?, id, ? FROM cat_material_type WHERE codigo = ?""",
                        id, m.get("url"), m.getOrDefault("tipo", "LINK"));
            return jdbc.queryForMap("SELECT * FROM v_campaign_report_admin WHERE campaign_id = ?", id);
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    @PostMapping("/{id}/activate")
    public void activar(@PathVariable long id) {
        try { jdbc.update("CALL sp_campaign_activar(?, ?)", id, CurrentUser.id()); }
        catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    @PostMapping("/{id}/close")
    public void cerrar(@PathVariable long id) {
        try { jdbc.update("CALL sp_campaign_finalizar(?, 'CERRADA', ?)", id, CurrentUser.id()); }
        catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    @PostMapping("/{id}/cancel")
    public void cancelar(@PathVariable long id) {
        try { jdbc.update("CALL sp_campaign_finalizar(?, 'CANCELADA', ?)", id, CurrentUser.id()); }
        catch (DataAccessException e) { throw WalletService.traducir(e); }
    }

    /** Edición de campañas ya creadas (cambios finales del cliente). */
    @PatchMapping("/{id}")
    public void editar(@PathVariable long id, @RequestBody Map<String, Object> campos) {
        // Lista blanca: el nombre de columna se concatena, así que NADA fuera de aquí
        // puede llegar al SQL. client_id permite reasignar la campaña a otro cliente.
        var permitidos = List.of("nombre","artista_cancion","url_audio","fecha_inicio","fecha_cierre",
                                 "imagen_url","titulo","descripcion","pautas_contenido",
                                 "num_videos","presupuesto","client_id");
        campos.forEach((k, v) -> {
            if (permitidos.contains(k))
                jdbc.update("UPDATE campaign SET " + k + " = ? WHERE id = ?", v, id);
        });
    }

    @GetMapping
    public List<Map<String, Object>> listar() {
        return jdbc.queryForList("SELECT * FROM v_campaign_report_admin ORDER BY campaign_id DESC");
    }

    @GetMapping("/{id}")
    public Map<String, Object> detalle(@PathVariable long id) {
        return jdbc.queryForMap("SELECT * FROM v_campaign_report_admin WHERE campaign_id = ?", id);
    }

    /** Videos de la campaña con editor, tags, likes y vistas; filtro por editor. */
    @GetMapping("/{id}/videos")
    public List<Map<String, Object>> videos(@PathVariable long id,
                                            @RequestParam(required = false) Long editor) {
        return jdbc.queryForList("""
            SELECT * FROM v_campaign_videos
             WHERE campaign_id = ? AND (? IS NULL OR editor_id = ?)
             ORDER BY vistas_totales DESC""", id, editor, editor);
    }
}
