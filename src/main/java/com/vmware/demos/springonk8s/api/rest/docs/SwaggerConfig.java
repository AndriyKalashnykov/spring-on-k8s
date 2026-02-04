package com.vmware.demos.springonk8s.api.rest.docs;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;


@Configuration
public class SwaggerConfig {

    @Bean
    public OpenAPI api() {
        return new OpenAPI()
                .info(apiInfo());
    }

    private Info apiInfo() {
        return new Info()
                .title("REST + Swagger UI")
                .description("REST + Swagger UI sample app")
                .termsOfService("github")
                .license(new License()
                        .name("Apache 2.0")
                        .url(""))
                .version("1.0");
    }
}
