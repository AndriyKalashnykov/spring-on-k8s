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

package com.vmware.demos.springonk8s.api.rest.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Sets baseline security response headers on every response. Closes the two ZAP baseline WARN-NEW
 * findings reported by the {@code dast} CI job:
 *
 * <ul>
 *   <li>{@code 10049 Storable and Cacheable Content} — pages must declare a Cache-Control policy.
 *       For an API + actuator + Swagger UI demo, {@code no-store} is appropriate (responses reflect
 *       live state and are cheap to recompute).
 *   <li>{@code 90004 Cross-Origin-Resource-Policy Header Missing or Invalid} — sets {@code
 *       same-origin} so external pages cannot embed our responses.
 * </ul>
 */
@Component
public class SecurityHeadersFilter extends OncePerRequestFilter {

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain chain)
      throws ServletException, IOException {
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("Cross-Origin-Resource-Policy", "same-origin");
    chain.doFilter(request, response);
  }
}
