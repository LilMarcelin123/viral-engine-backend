package mx.dancreative.viralengine.storage;

import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.http.*;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.beans.factory.annotation.Value;

import java.io.IOException;
import java.nio.file.*;
import java.util.Map;

@RestController
public class FileController {

    private final StorageService storage;
    private final Path root;

    public FileController(StorageService storage,
                          @Value("${app.storage.path:./uploads}") String path) {
        this.storage = storage;
        this.root = Paths.get(path).toAbsolutePath().normalize();
    }

    /** Subida. tipo=image (miniaturas) | video (material fuente). */
    @PostMapping("/files/upload")
    @PreAuthorize("hasAnyRole('ADMIN','EDITOR')")
    public Map<String, String> subir(@RequestParam("file") MultipartFile file,
                                     @RequestParam(defaultValue = "image") String tipo) {
        String url = storage.guardar(file, tipo);
        return Map.of("url", url, "file_url", url, "name", file.getOriginalFilename());
    }

    /** Descarga/serve del archivo. */
    @GetMapping("/files/**")
    public ResponseEntity<Resource> servir(@RequestHeader HttpHeaders headers,
                                           jakarta.servlet.http.HttpServletRequest req) {
        String rel = req.getRequestURI().substring("/files/".length());
        try {
            Path archivo = root.resolve(rel).normalize();
            if (!archivo.startsWith(root) || !Files.exists(archivo))
                throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Archivo no encontrado");

            Resource r = new UrlResource(archivo.toUri());
            String ct = Files.probeContentType(archivo);
            return ResponseEntity.ok()
                    .contentType(ct != null ? MediaType.parseMediaType(ct) : MediaType.APPLICATION_OCTET_STREAM)
                    .cacheControl(CacheControl.maxAge(java.time.Duration.ofDays(30)).cachePublic())
                    .body(r);
        } catch (IOException e) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Archivo no encontrado");
        }
    }
}
