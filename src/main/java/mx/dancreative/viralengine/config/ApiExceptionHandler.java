package mx.dancreative.viralengine.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.util.Map;

/**
 * Devuelve el mensaje real SOLO para errores de negocio (ResponseStatusException,
 * que es donde traducimos los SIGNAL de MySQL). Cualquier otra excepción se
 * registra en el log pero al cliente solo le llega un texto genérico, para no
 * filtrar rutas de archivos, consultas SQL ni detalles internos.
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<Map<String, Object>> negocio(ResponseStatusException e) {
        return ResponseEntity.status(e.getStatusCode()).body(Map.of(
            "timestamp", Instant.now().toString(),
            "status", e.getStatusCode().value(),
            "message", e.getReason() == null ? "Solicitud inválida" : e.getReason()
        ));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> inesperado(Exception e) {
        log.error("Error no controlado", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of(
            "timestamp", Instant.now().toString(),
            "status", 500,
            "message", "Ocurrió un error inesperado. Inténtalo de nuevo."
        ));
    }
}
