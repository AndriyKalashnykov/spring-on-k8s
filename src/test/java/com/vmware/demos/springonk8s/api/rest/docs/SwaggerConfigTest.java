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

package com.vmware.demos.springonk8s.api.rest.docs;

import static org.assertj.core.api.Assertions.assertThat;

import io.swagger.v3.oas.models.OpenAPI;
import org.junit.jupiter.api.Test;

class SwaggerConfigTest {

  @Test
  void apiBeanExposesConfiguredInfo() {
    OpenAPI openApi = new SwaggerConfig().api();
    assertThat(openApi).isNotNull();
    assertThat(openApi.getInfo()).isNotNull();
    assertThat(openApi.getInfo().getTitle()).isEqualTo("REST + Swagger UI");
    assertThat(openApi.getInfo().getDescription()).isEqualTo("REST + Swagger UI sample app");
    assertThat(openApi.getInfo().getVersion()).isEqualTo("1.0");
    assertThat(openApi.getInfo().getLicense()).isNotNull();
    assertThat(openApi.getInfo().getLicense().getName()).isEqualTo("Apache 2.0");
  }
}
