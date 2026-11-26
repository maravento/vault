-- SORI control tables: clients and users. Each client has its own database.
-- FILE: db/app.sql

CREATE TABLE IF NOT EXISTS sori_clientes (
    id     INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    slug   VARCHAR(30)  NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    activo TINYINT(1)   NOT NULL DEFAULT 1,
    creado TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sori_usuarios (
    id         INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    cliente_id INT UNSIGNED NULL,
    usuario    VARCHAR(30)  NOT NULL UNIQUE,
    nombre     VARCHAR(100) NOT NULL,
    hash       VARCHAR(255) NOT NULL,
    rol        VARCHAR(20)  NOT NULL DEFAULT 'usuario',
    activo     TINYINT(1)   NOT NULL DEFAULT 1,
    creado     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_usuarios_cliente FOREIGN KEY (cliente_id)
        REFERENCES sori_clientes (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sori_intentos (
    ip      VARCHAR(45) NOT NULL,
    momento TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_ip_momento (ip, momento)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
