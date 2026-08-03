package mx.dancreative.viralengine.notify;

import jakarta.mail.internet.MimeMessage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

/**
 * Notificaciones a editores y clientes.
 *
 * Diseño en dos pasos: primero se ENCOLAN en la tabla notification
 * (nunca se envía dentro de la transacción de negocio, para que un fallo
 * de correo no tumbe la creación de una campaña), y luego un proceso
 * periódico las envía y marca el resultado.
 *
 * Correo: SMTP (Gmail con contraseña de aplicación).
 * WhatsApp: canal preparado; queda PENDIENTE hasta conectar proveedor.
 */
@Service
public class NotificationService {

    private static final Logger log = LoggerFactory.getLogger(NotificationService.class);

    private final JdbcTemplate jdbc;
    private final JavaMailSender mail;
    private final String from;
    private final boolean envioActivo;
    private final String appUrl;

    public NotificationService(JdbcTemplate jdbc,
                               JavaMailSender mail,
                               @Value("${app.mail.from:}") String from,
                               @Value("${app.mail.enabled:false}") boolean envioActivo,
                               @Value("${app.front-url:http://localhost:5173}") String appUrl) {
        this.jdbc = jdbc; this.mail = mail;
        this.from = from; this.envioActivo = envioActivo; this.appUrl = appUrl;
    }

    // ---------- ENCOLADO ----------

    /** Avisa a todos los editores activos que se abrió una campaña. */
    public int notificarNuevaCampania(long campaignId) {
        Map<String, Object> c = jdbc.queryForMap(
            "SELECT nombre, artista_cancion, num_videos FROM campaign WHERE id = ?", campaignId);

        String asunto = "Nueva campaña disponible: " + c.get("nombre");
        String cuerpo = """
            <p>Hola,</p>
            <p>Se abrió una nueva campaña en <b>Viral Engine</b>:</p>
            <ul>
              <li><b>Campaña:</b> %s</li>
              <li><b>Artista / canción:</b> %s</li>
              <li><b>Videos:</b> %s</li>
            </ul>
            <p>Tienes <b>24 horas</b> para confirmar tu participación. Si no confirmas,
               tus videos pasan a la bolsa de reasignación.</p>
            <p><a href="%s">Entrar a la plataforma</a></p>
            """.formatted(c.get("nombre"), c.get("artista_cancion"), c.get("num_videos"), appUrl);

        return encolarAEditores("NUEVA_CAMPANA", campaignId, asunto, cuerpo);
    }

    /** Avisa a un editor que se le aplicó un strike, con el motivo. */
    public void notificarStrike(long userId, long campaignId, String motivo) {
        String cuerpo = """
            <p>Hola,</p>
            <p>Se registró un <b>strike</b> en tu cuenta por el siguiente motivo:</p>
            <blockquote>%s</blockquote>
            <p>El clip afectado queda excluido del cálculo de bonos, pero conserva su
               pago base si ya había sido aprobado.</p>
            <p>Recuerda que al acumular 3 strikes se cierra el acceso a la plataforma.</p>
            <p><a href="%s">Revisar en la plataforma</a></p>
            """.formatted(motivo == null ? "Sin motivo especificado" : motivo, appUrl);

        encolar(userId, "STRIKE", campaignId, "Se registró un strike en tu cuenta", cuerpo);
    }

    /** Avisa al cliente que su reporte final está listo. */
    public void notificarReporteFinal(long campaignId) {
        List<Map<String, Object>> destinos = jdbc.queryForList("""
            SELECT u.id, c.nombre FROM campaign c
              JOIN users u ON u.id = c.client_id
             WHERE c.id = ? AND u.activo = TRUE""", campaignId);

        for (Map<String, Object> d : destinos) {
            String cuerpo = """
                <p>Hola,</p>
                <p>La campaña <b>%s</b> ha concluido y su reporte final ya está disponible
                   en la plataforma.</p>
                <p><a href="%s/campaign-report">Ver reporte</a></p>
                """.formatted(d.get("nombre"), appUrl);
            encolar(((Number) d.get("id")).longValue(), "REPORTE_FINAL", campaignId,
                    "Reporte final: " + d.get("nombre"), cuerpo);
        }
    }

    private int encolarAEditores(String tipo, Long campaignId, String asunto, String cuerpo) {
        List<Map<String, Object>> editores = jdbc.queryForList("""
            SELECT u.id FROM users u
              JOIN cat_user_type t  ON t.id  = u.user_type_id AND t.codigo = 'EDITOR'
              JOIN cat_user_state s ON s.id  = u.user_state_id AND s.codigo = 'ACTIVO'""");
        for (Map<String, Object> e : editores)
            encolar(((Number) e.get("id")).longValue(), tipo, campaignId, asunto, cuerpo);
        return editores.size();
    }

    /** Crea el registro en cola para cada canal disponible del usuario. */
    private void encolar(long userId, String tipo, Long campaignId, String asunto, String cuerpo) {
        Map<String, Object> u = jdbc.queryForMap(
            "SELECT email, telefono FROM users WHERE id = ?", userId);

        String email = (String) u.get("email");
        if (email != null && !email.isBlank())
            insertar(userId, "EMAIL", tipo, campaignId, email, asunto, cuerpo);

        String tel = (String) u.get("telefono");
        if (tel != null && !tel.isBlank())
            insertar(userId, "WHATSAPP", tipo, campaignId, tel, asunto, cuerpo);
    }

    private void insertar(long userId, String canal, String tipo, Long campaignId,
                          String destino, String asunto, String cuerpo) {
        jdbc.update("""
            INSERT INTO notification (user_id, notification_channel_id, notification_type_id,
                                      notification_state_id, destino, campaign_id, mensaje)
            SELECT ?,
                   (SELECT id FROM cat_notification_channel WHERE codigo = ?),
                   (SELECT id FROM cat_notification_type    WHERE codigo = ?),
                   (SELECT id FROM cat_notification_state   WHERE codigo = 'PENDIENTE'),
                   ?, ?, ?""",
            userId, canal, tipo, destino, campaignId, asunto + "|||" + cuerpo);
    }

    // ---------- ENVÍO ----------

    /** Procesa la cola cada minuto. Solo envía correo; WhatsApp queda pendiente. */
    @Scheduled(fixedDelayString = "${app.mail.poll-ms:60000}")
    public void procesarCola() {
        if (!envioActivo) return;

        List<Map<String, Object>> pendientes = jdbc.queryForList("""
            SELECT n.id, n.destino, n.mensaje, ch.codigo AS canal
              FROM notification n
              JOIN cat_notification_channel ch ON ch.id = n.notification_channel_id
              JOIN cat_notification_state   st ON st.id = n.notification_state_id
             WHERE st.codigo = 'PENDIENTE' AND ch.codigo = 'EMAIL'
             ORDER BY n.created_at LIMIT 50""");

        for (Map<String, Object> n : pendientes) {
            long id = ((Number) n.get("id")).longValue();
            try {
                String[] partes = String.valueOf(n.get("mensaje")).split("\\|\\|\\|", 2);
                enviarCorreo((String) n.get("destino"), partes[0],
                             partes.length > 1 ? partes[1] : "");
                marcar(id, "ENVIADO", null);
            } catch (Exception e) {
                log.warn("Falló el envío de la notificación {}: {}", id, e.getMessage());
                marcar(id, "ERROR", e.getMessage());
            }
        }
    }

    private void enviarCorreo(String para, String asunto, String htmlBody) throws Exception {
        MimeMessage msg = mail.createMimeMessage();
        MimeMessageHelper h = new MimeMessageHelper(msg, "UTF-8");
        h.setFrom(from);
        h.setTo(para);
        h.setSubject(asunto);
        h.setText(htmlBody, true);
        mail.send(msg);
    }

    private void marcar(long id, String estado, String error) {
        jdbc.update("""
            UPDATE notification
               SET notification_state_id = (SELECT id FROM cat_notification_state WHERE codigo = ?),
                   enviado_at = IF(? = 'ENVIADO', NOW(6), enviado_at),
                   error = ?
             WHERE id = ?""", estado, estado,
            error == null ? null : (error.length() > 500 ? error.substring(0, 500) : error), id);
    }
}
