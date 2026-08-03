package mx.dancreative.viralengine.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Limita los intentos fallidos de inicio de sesión por clave (correo + IP).
 * En memoria: suficiente para una instancia. Si algún día se escala a varias,
 * hay que moverlo a la base de datos o a un caché compartido.
 */
@Component
public class LoginRateLimiter {

    private record Intentos(int conteo, Instant desde) {}

    private final Map<String, Intentos> mapa = new ConcurrentHashMap<>();
    private final int max;
    private final Duration ventana;

    public LoginRateLimiter(@Value("${app.login.max-intentos:5}") int max,
                            @Value("${app.login.ventana-minutos:5}") int ventanaMin) {
        this.max = max;
        this.ventana = Duration.ofMinutes(ventanaMin);
    }

    /** Lanza 429 si la clave superó el límite dentro de la ventana. */
    public void verificar(String clave) {
        Intentos i = mapa.get(clave);
        if (i == null) return;
        if (Duration.between(i.desde(), Instant.now()).compareTo(ventana) > 0) {
            mapa.remove(clave);
            return;
        }
        if (i.conteo() >= max)
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                "Demasiados intentos fallidos. Espera unos minutos antes de volver a intentar.");
    }

    public void registrarFallo(String clave) {
        mapa.compute(clave, (k, v) ->
            (v == null || Duration.between(v.desde(), Instant.now()).compareTo(ventana) > 0)
                ? new Intentos(1, Instant.now())
                : new Intentos(v.conteo() + 1, v.desde()));
    }

    public void limpiar(String clave) { mapa.remove(clave); }
}
