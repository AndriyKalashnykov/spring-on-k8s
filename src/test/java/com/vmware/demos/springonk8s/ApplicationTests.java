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

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpStatus;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public class ApplicationTests {
    @LocalServerPort
    private int port;

    private RestClient getRestClient() {
        return RestClient.builder().baseUrl("http://localhost:" + port).build();
    }

    @Test
    public void contextLoads() {
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
        var status = client.get().uri("/actuator/health").exchange((request, response) -> response.getStatusCode());
        assertThat(status).isEqualTo(HttpStatus.OK);
    }
}
