CREATE TABLE IF NOT EXISTS `lation_towing` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `player_identifier` VARCHAR(60) NOT NULL,
    `vehicles_towed` INT DEFAULT 0,
    `emergency_jobs` INT DEFAULT 0,
    `civilian_jobs` INT DEFAULT 0,
    `total_earned` INT DEFAULT 0,
    `distance_driven` FLOAT DEFAULT 0,
    `repairs_performed` INT DEFAULT 0,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )