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

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.availability.ApplicationAvailability;
import org.springframework.boot.availability.AvailabilityChangeEvent;
import org.springframework.boot.availability.LivenessState;
import org.springframework.boot.availability.ReadinessState;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.ApplicationContext;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.RestClient;

/**
 * Asserts that the liveness and readiness probes report independent state. A regression where the
 * two probe groups collapse onto the same source (or where a readiness flip incorrectly toggles
 * liveness) would silently break Kubernetes traffic-shedding semantics — the pod would either
 * accept traffic when it shouldn't or get killed when it should just be drained.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public class AvailabilityIT {

  @LocalServerPort private int port;

  @Autowired private ApplicationContext context;

  @Autowired private ApplicationAvailability availability;

  private RestClient client() {
    return RestClient.builder().baseUrl("http://localhost:" + port).build();
  }

  @Test
  public void readinessFlipDoesNotAffectLiveness() {
    AvailabilityChangeEvent.publish(context, ReadinessState.REFUSING_TRAFFIC);
    try {
      assertThat(availability.getReadinessState()).isEqualTo(ReadinessState.REFUSING_TRAFFIC);
      assertThat(availability.getLivenessState()).isEqualTo(LivenessState.CORRECT);

      // /actuator/health/readiness reports OUT_OF_SERVICE → 503.
      try {
        client().get().uri("/actuator/health/readiness").retrieve().toBodilessEntity();
      } catch (HttpServerErrorException.ServiceUnavailable expected) {
        assertThat(expected.getResponseBodyAsString()).contains("OUT_OF_SERVICE");
      }

      // Liveness must remain UP — a state flip on readiness is a drain signal, not a kill signal.
      String liveness =
          client().get().uri("/actuator/health/liveness").retrieve().body(String.class);
      assertThat(liveness).contains("\"status\":\"UP\"");
    } finally {
      AvailabilityChangeEvent.publish(context, ReadinessState.ACCEPTING_TRAFFIC);
    }
  }
}
