/*
 * Copyright (c) 2021 VMware, Inc. or its affiliates
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.vmware.demos.springonk8s;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.http.HttpClient;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public class ApplicationIT {
  @LocalServerPort private int port;

  private RestClient getRestClient() {
    return RestClient.builder().baseUrl("http://localhost:" + port).build();
  }

  private RestClient noRedirectClient() {
    HttpClient httpClient =
        HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NEVER).build();
    return RestClient.builder()
        .baseUrl("http://localhost:" + port)
        .requestFactory(new JdkClientHttpRequestFactory(httpClient))
        .build();
  }

  @Test
  public void contextLoads() {}

  @Test
  public void testRoot() {
    RestClient client = getRestClient();
    String response = client.get().uri("/").retrieve().body(String.class);
    assertThat(response).isEqualTo("Hello world");
  }

  @Test
  public void testHello() {
    RestClient client = getRestClient();
    String response = client.get().uri("/v1/hello").retrieve().body(String.class);
    assertThat(response).isEqualTo("Hello world!");
  }

  @Test
  public void testBye() {
    RestClient client = getRestClient();
    String response = client.get().uri("/v1/bye").retrieve().body(String.class);
    assertThat(response).isEqualTo("Bye world!");
  }

  @Test
  public void testHealth() {
    RestClient client = getRestClient();
    String body = client.get().uri("/actuator/health").retrieve().body(String.class);
    assertThat(body)
        .contains("\"status\":\"UP\"")
        .contains("\"groups\"")
        .contains("\"liveness\"")
        .contains("\"readiness\"");
  }

  @Test
  public void testSwaggerUi() {
    // Springdoc redirects /swagger-ui.html to /swagger-ui/index.html (302).
    // Disable redirect-following so the test can pin both the status code and the Location target.
    var response =
        noRedirectClient().get().uri("/swagger-ui.html").retrieve().toEntity(String.class);
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FOUND);
    String location = response.getHeaders().getFirst(HttpHeaders.LOCATION);
    assertThat(location).isNotNull().contains("swagger-ui");
  }

  @Test
  public void testLiveness() {
    RestClient client = getRestClient();
    String body = client.get().uri("/actuator/health/liveness").retrieve().body(String.class);
    assertThat(body).contains("\"status\":\"UP\"");
  }

  @Test
  public void testReadiness() {
    RestClient client = getRestClient();
    String body = client.get().uri("/actuator/health/readiness").retrieve().body(String.class);
    assertThat(body).contains("\"status\":\"UP\"");
  }

  @Test
  public void testPrometheus() {
    RestClient client = getRestClient();
    var response = client.get().uri("/actuator/prometheus").retrieve().toEntity(String.class);
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).contains("jvm_memory_used_bytes");
  }

  @Test
  public void testPrometheusHttpMetrics() {
    // Prime the MVC instrumentation with one request, then scrape and assert that the
    // http_server_requests metric appears. Catches regressions where micrometer's web
    // instrumentation breaks even though jvm_* metrics still publish.
    RestClient client = getRestClient();
    client.get().uri("/v1/hello").retrieve().body(String.class);
    String body = client.get().uri("/actuator/prometheus").retrieve().body(String.class);
    assertThat(body).contains("http_server_requests_seconds");
  }

  @Test
  public void testActuatorInfo() {
    RestClient client = getRestClient();
    var response = client.get().uri("/actuator/info").retrieve().toEntity(String.class);
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
  }

  @Test
  public void testHelloProducesTextPlain() {
    // Controllers declare produces=text/plain; an Accept header that excludes text/plain must
    // be rejected with 406 (and NOT silently fall through to the catch-all).
    RestClient client = getRestClient();
    HttpClientErrorException ex =
        org.junit.jupiter.api.Assertions.assertThrows(
            HttpClientErrorException.class,
            () ->
                client
                    .get()
                    .uri("/v1/hello")
                    .accept(MediaType.APPLICATION_XML)
                    .retrieve()
                    .toBodilessEntity());
    assertThat(ex.getStatusCode()).isEqualTo(HttpStatus.NOT_ACCEPTABLE);

    // text/plain Accept must succeed and return the matching content type.
    var response =
        client
            .get()
            .uri("/v1/hello")
            .accept(MediaType.TEXT_PLAIN)
            .retrieve()
            .toEntity(String.class);
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getHeaders().getContentType()).isNotNull();
    assertThat(response.getHeaders().getContentType().isCompatibleWith(MediaType.TEXT_PLAIN))
        .isTrue();
  }

  @Test
  public void testSecurityHeadersOnApi() {
    // SecurityHeadersFilter must set Cache-Control: no-store and
    // Cross-Origin-Resource-Policy: same-origin on every response.
    var response = getRestClient().get().uri("/v1/hello").retrieve().toEntity(String.class);
    assertThat(response.getHeaders().getFirst("Cache-Control")).isEqualTo("no-store");
    assertThat(response.getHeaders().getFirst("Cross-Origin-Resource-Policy"))
        .isEqualTo("same-origin");
  }

  @Test
  public void testSecurityHeadersOnActuator() {
    // Actuator endpoints get the same headers — ZAP probes /actuator/* too.
    var response = getRestClient().get().uri("/actuator/health").retrieve().toEntity(String.class);
    assertThat(response.getHeaders().getFirst("Cache-Control")).isEqualTo("no-store");
    assertThat(response.getHeaders().getFirst("Cross-Origin-Resource-Policy"))
        .isEqualTo("same-origin");
  }

  @Test
  public void testNotFound() {
    RestClient client = getRestClient();
    HttpClientErrorException ex =
        org.junit.jupiter.api.Assertions.assertThrows(
            HttpClientErrorException.class,
            () -> client.get().uri("/does-not-exist-abc").retrieve().toBodilessEntity());
    assertThat(ex.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  public void testOpenApiDocs() throws Exception {
    RestClient client = getRestClient();
    String body = client.get().uri("/v3/api-docs").retrieve().body(String.class);
    JsonNode root = new ObjectMapper().readTree(body);
    assertThat(root.path("info").path("title").asText()).isEqualTo("REST + Swagger UI");
    assertThat(root.path("info").path("version").asText()).isEqualTo("1.0");
    assertThat(root.path("paths").has("/v1/hello")).isTrue();
    assertThat(root.path("paths").has("/v1/bye")).isTrue();
    assertThat(root.path("paths").path("/v1/hello").has("get")).isTrue();
    assertThat(root.path("paths").path("/v1/bye").has("get")).isTrue();
  }
}
