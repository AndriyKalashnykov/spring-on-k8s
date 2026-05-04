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

  @LocalServerPort private int port;

  @BeforeAll
  static void writeOverride() throws IOException {
    Files.createDirectories(CONFIGTREE_DIR);
    Files.writeString(CONFIGTREE_DIR.resolve("app.message"), OVERRIDE);
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
}
