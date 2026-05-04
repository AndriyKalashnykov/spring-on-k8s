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

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.web.client.RestClient;

/**
 * Asserts that values mounted via Spring's {@code configtree:} property source override the
 * controllers' {@code @Value("${app.message:...}")} defaults — the same mechanism the K8s
 * deployment uses to inject ConfigMap values at {@code /etc/config/} via {@code
 * SPRING_CONFIG_IMPORT}.
 */
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = "spring.config.import=configtree:target/configtree-test/")
public class ConfigTreeOverrideIT {

  private static final Path CONFIGTREE_DIR = Path.of("target", "configtree-test");
  private static final String OVERRIDE = "Hello configtree!";
  // A second, controller-unrelated key materialises as a regular property but must NOT influence
  // the controllers' @Value("${app.message:...}") resolution. Catches a regression where the
  // configtree binding accidentally maps every file under the directory onto `app.message`.
  private static final String UNRELATED_KEY = "app.unrelated";
  private static final String UNRELATED_VALUE = "do-not-leak-into-app.message";

  @LocalServerPort private int port;

  // Field injection routes through Spring's PropertySources just like the controllers' own
  // @Value resolution — proves the configtree mounted both keys without importing
  // org.springframework.core.env.Environment (which would drag spring-core into test-only usage
  // and trip mvn dependency:analyze).
  @Value("${app.unrelated:NOT_SET}")
  private String unrelatedFromEnvironment;

  @Value("${app.message:DEFAULT}")
  private String appMessageFromEnvironment;

  @BeforeAll
  static void writeOverride() throws IOException {
    Files.createDirectories(CONFIGTREE_DIR);
    Files.writeString(CONFIGTREE_DIR.resolve("app.message"), OVERRIDE);
    Files.writeString(CONFIGTREE_DIR.resolve(UNRELATED_KEY), UNRELATED_VALUE);
  }

  @AfterAll
  static void cleanup() throws IOException {
    if (Files.exists(CONFIGTREE_DIR)) {
      try (var stream = Files.walk(CONFIGTREE_DIR)) {
        stream.sorted(Comparator.reverseOrder()).forEach(p -> p.toFile().delete());
      }
    }
  }

  private RestClient client() {
    return RestClient.builder().baseUrl("http://localhost:" + port).build();
  }

  @Test
  public void helloReflectsConfigtreeOverride() {
    String body = client().get().uri("/v1/hello").retrieve().body(String.class);
    assertThat(body).isEqualTo(OVERRIDE);
  }

  @Test
  public void byeReflectsConfigtreeOverride() {
    String body = client().get().uri("/v1/bye").retrieve().body(String.class);
    assertThat(body).isEqualTo(OVERRIDE);
  }

  @Test
  public void unrelatedKeyIsBoundButDoesNotShadowAppMessage() {
    // The unrelated key resolves via @Value into its own property slot…
    assertThat(unrelatedFromEnvironment).isEqualTo(UNRELATED_VALUE);
    // …and must NOT bleed into app.message. A name-collision regression where configtree
    // mapped every file onto app.message would surface here (and on the live HTTP call below)
    // as the unrelated value leaking through.
    assertThat(appMessageFromEnvironment).isEqualTo(OVERRIDE);
    String body = client().get().uri("/v1/hello").retrieve().body(String.class);
    assertThat(body).isEqualTo(OVERRIDE);
  }
}
