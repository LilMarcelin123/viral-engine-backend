package mx.dancreative.viralengine.storage;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.nio.file.*;
import java.time.LocalDate;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

/**
 * Guarda archivos en disco. En Railway se monta un Volume en la ruta
 * app.storage.path (por ejemplo /data), que SÍ sobrevive a los deploys.
 * En local usa ./uploads.
 */
@Service
public class StorageService {

    private static final List<String> IMG = List.of("jpg","jpeg","png","webp","gif");
    private static final List<String> VID = List.of("mp4","mov","avi");

    private static final long MAX_IMG = 5L  * 1024 * 1024;        // 5 MB
    private static final long MAX_VID = 500L * 1024 * 1024;       // 500 MB

    private final Path root;
    private final String publicUrl;

    public StorageService(@Value("${app.storage.path:./uploads}") String path,
                          @Value("${app.storage.public-url:}") String publicUrl) {
        this.root = Paths.get(path).toAbsolutePath().normalize();
        this.publicUrl = publicUrl;
    }

    @PostConstruct
    void init() throws IOException {
        Files.createDirectories(root);
    }

    /** tipo: "image" o "video". Devuelve la URL pública del archivo. */
    public String guardar(MultipartFile file, String tipo) {
        if (file == null || file.isEmpty())
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Archivo vacío");

        String original = Path.of(file.getOriginalFilename() == null ? "archivo" : file.getOriginalFilename())
                              .getFileName().toString();          // evita rutas tipo ../../
        String ext = original.contains(".")
                ? original.substring(original.lastIndexOf('.') + 1).toLowerCase(Locale.ROOT) : "";

        boolean esVideo = "video".equalsIgnoreCase(tipo);
        List<String> permitidas = esVideo ? VID : IMG;
        long max = esVideo ? MAX_VID : MAX_IMG;

        if (!permitidas.contains(ext))
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                "Formato no permitido. Se aceptan: " + String.join(", ", permitidas));
        if (file.getSize() > max)
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                "El archivo excede el máximo de " + (max / 1024 / 1024) + " MB");

        // carpetas por fecha para no acumular miles de archivos en una sola
        String carpeta = (esVideo ? "videos/" : "img/") + LocalDate.now();
        String nombre  = UUID.randomUUID() + "." + ext;

        try {
            Path destino = root.resolve(carpeta).resolve(nombre).normalize();
            if (!destino.startsWith(root))
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Ruta inválida");
            Files.createDirectories(destino.getParent());
            file.transferTo(destino);
        } catch (IOException e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                "No se pudo guardar el archivo: " + e.getMessage());
        }

        String ruta = "/files/" + carpeta + "/" + nombre;
        return publicUrl.isBlank() ? ruta : publicUrl + ruta;
    }
}
