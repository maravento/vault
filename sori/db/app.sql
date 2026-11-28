-- SORI control tables: clients and users. Each client has its own database.
-- FILE: db/app.sql

CREATE TABLE IF NOT EXISTS sori_clients (
    id     INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    slug   VARCHAR(30)  NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    active TINYINT(1)   NOT NULL DEFAULT 1,
    created TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sori_users (
    id         INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    client_id INT UNSIGNED NULL,
    username    VARCHAR(30)  NOT NULL UNIQUE,
    name     VARCHAR(100) NOT NULL,
    hash       VARCHAR(255) NOT NULL,
    role        VARCHAR(20)  NOT NULL DEFAULT 'user',
    active     TINYINT(1)   NOT NULL DEFAULT 1,
    created     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_users_client FOREIGN KEY (client_id)
        REFERENCES sori_clients (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sori_attempts (
    ip      VARCHAR(45) NOT NULL,
    attempted_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_ip_momento (ip, attempted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
