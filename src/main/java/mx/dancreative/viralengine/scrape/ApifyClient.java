package mx.dancreative.viralengine.scrape;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Map;

/**
 * Cliente mínimo de la API de Apify.
 *
 * El token NUNCA toca la base de datos ni el repositorio: vive en la variable
 * de entorno APIFY_TOKEN del backend.
 *
 * Solo se usan tres llamadas:
 *   - lanzar una corrida de un actor
 *   - consultar su estado
 *   - traer los resultados del dataset
 */
@Component
public class ApifyClient {

    private static final String BASE = "https://api.apify.com/v2";

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(20)).build();
    private final ObjectMapper json = new ObjectMapper();
    private final String token;

    public ApifyClient(@Value("${app.apify.token:}") String token) {
        this.token = token;
    }

    public boolean configurado() { return token != null && !token.isBlank(); }

    private void exigirToken() {
        if (!configurado())
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Falta la variable APIFY_TOKEN en el servidor: el scrapeo está deshabilitado.");
    }

    /** Datos de una corrida recién lanzada o consultada. */
    public record Corrida(String runId, String datasetId, String estado,
                          Double computeUnits, Double costoUsd) {}

    /**
     * Lanza el actor con la lista de URLs. `inputKey` sale del catálogo
     * (postURLs, directUrls, startUrls...) porque cada actor lo llama distinto.
     */
    public Corrida lanzar(String actorId, String inputKey, List<String> urls) {
        exigirToken();
        try {
            Map<String, Object> input = Map.of(
                inputKey, urls,
                "resultsLimit", urls.size()
            );
            HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(BASE + "/acts/" + actorId + "/runs?token=" + token))
                .header("Content-Type", "application/json")
                .timeout(Duration.ofSeconds(60))
                .POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(input)))
                .build();

            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() >= 300)
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                    "Apify rechazó la corrida (HTTP " + res.statusCode() + ")");

            JsonNode d = json.readTree(res.body()).path("data");
            return new Corrida(d.path("id").asText(null),
                               d.path("defaultDatasetId").asText(null),
                               d.path("status").asText("READY"),
                               null, null);
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "No se pudo contactar a Apify: " + e.getMessage());
        }
    }

    /** Estado actual de una corrida. RUNNING, SUCCEEDED, FAILED, ABORTED... */
    public Corrida consultar(String runId) {
        exigirToken();
        try {
            HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(BASE + "/actor-runs/" + runId + "?token=" + token))
                .timeout(Duration.ofSeconds(30)).GET().build();

            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() >= 300)
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                    "Apify no devolvió la corrida (HTTP " + res.statusCode() + ")");

            JsonNode d = json.readTree(res.body()).path("data");
            JsonNode stats = d.path("stats");
            Double cu = stats.hasNonNull("computeUnits") ? stats.get("computeUnits").asDouble() : null;
            JsonNode usage = d.path("usageTotalUsd");
            Double usd = usage.isNumber() ? usage.asDouble() : null;

            return new Corrida(d.path("id").asText(null),
                               d.path("defaultDatasetId").asText(null),
                               d.path("status").asText("UNKNOWN"),
                               cu, usd);
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "No se pudo consultar la corrida en Apify: " + e.getMessage());
        }
    }

    /** Resultados del dataset de una corrida terminada. */
    public JsonNode resultados(String datasetId) {
        exigirToken();
        try {
            HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(BASE + "/datasets/" + datasetId + "/items?clean=true&token=" + token))
                .timeout(Duration.ofMinutes(2)).GET().build();

            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() >= 300)
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                    "Apify no devolvió el dataset (HTTP " + res.statusCode() + ")");

            return json.readTree(res.body());
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "No se pudieron traer los resultados de Apify: " + e.getMessage());
        }
    }
}
