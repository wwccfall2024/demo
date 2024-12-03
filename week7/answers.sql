CREATE SCHEMA destruction;
USE destruction;

CREATE TABLE players (
    player_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
    first_name VARCHAR(30) NOT NULL,
    last_name VARCHAR(30) NOT NULL,
    email VARCHAR(50) NOT NULL
);

CREATE TABLE characters (
    character_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
    player_id INT UNSIGNED NOT NULL,
    name VARCHAR(30) NOT NULL,
    level INT UNSIGNED NOT NULL,
    FOREIGN KEY (player_id) REFERENCES players(player_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE winners (
    character_id INT UNSIGNED PRIMARY KEY NOT NULL,
    name VARCHAR(30) NOT NULL,
    FOREIGN KEY (character_id) REFERENCES characters(character_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE character_stats (
    character_id INT UNSIGNED PRIMARY KEY NOT NULL,
    health INT UNSIGNED NOT NULL,
    armor INT UNSIGNED NOT NULL,
    FOREIGN KEY (character_id) REFERENCES characters(character_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE teams (
    team_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
    name VARCHAR(30) NOT NULL
);

CREATE TABLE team_members (
    team_member_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
    team_id INT UNSIGNED NOT NULL,
    character_id INT UNSIGNED NOT NULL,
    FOREIGN KEY (team_id) REFERENCES teams(team_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (character_id) REFERENCES characters(character_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE items (
    item_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
    name VARCHAR(30) NOT NULL,
    armor INT NOT NULL,
    damage INT NOT NULL
);

CREATE TABLE inventory (
    inventory_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
    character_id INT UNSIGNED NOT NULL,
    item_id INT UNSIGNED NOT NULL,
    FOREIGN KEY (character_id) REFERENCES characters(character_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(item_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE equipped (
    equipped_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
    character_id INT UNSIGNED NOT NULL,
    item_id INT UNSIGNED NOT NULL,
    FOREIGN KEY (character_id) REFERENCES characters(character_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(item_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE VIEW character_items AS
    SELECT
        characters.character_id,
        characters.name AS character_name,
        items.name AS item_name,
        items.armor AS armor,
        items.damage AS damage
    FROM characters
    INNER JOIN inventory ON characters.character_id = inventory.character_id
    INNER JOIN items ON inventory.item_id = items.item_id
    UNION
    SELECT
        characters.character_id,
        characters.name AS character_name,
        items.name AS item_name,
        items.armor AS armor,
        items.damage AS damage
    FROM characters
    INNER JOIN equipped ON characters.character_id = equipped.character_id
    INNER JOIN items ON equipped.item_id = items.item_id
    ORDER BY character_name, item_name;

CREATE VIEW team_items AS
    SELECT
        teams.team_id AS team_id,
        teams.name AS team_name,
        items.name AS item_name,
        items.armor AS armor,
        items.damage AS damage
    FROM teams
    INNER JOIN team_members ON teams.team_id = team_members.team_id
    INNER JOIN characters ON team_members.character_id = characters.character_id
    INNER JOIN inventory ON characters.character_id = inventory.character_id
    INNER JOIN items ON inventory.item_id = items.item_id
    UNION
    SELECT
        teams.team_id AS team_id,
        teams.name AS team_name,
        items.name AS item_name,
        items.armor AS armor,
        items.damage AS damage
    FROM teams
    INNER JOIN team_members ON teams.team_id = team_members.team_id
    INNER JOIN characters ON team_members.character_id = characters.character_id
    INNER JOIN equipped ON characters.character_id = equipped.character_id
    INNER JOIN items ON equipped.item_id = items.item_id
    ORDER BY team_name, item_name;

DELIMITER ;;
CREATE FUNCTION armor_total(char_id INT UNSIGNED)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE item_armor_total INT;
    DECLARE char_armor_total INT;
    SELECT SUM(items.armor) INTO item_armor_total
    FROM equipped
    INNER JOIN items ON equipped.item_id = items.item_id
    WHERE equipped.character_id = char_id;

    SELECT armor INTO char_armor_total
    FROM character_stats
    WHERE character_id = char_id;

    RETURN item_armor_total + char_armor_total;
END;;

CREATE PROCEDURE attack(
    IN to_char_id INT UNSIGNED,
    IN equipped_id INT UNSIGNED)
BEGIN
    DECLARE item_damage INT;
    DECLARE to_char_health INT;
    DECLARE to_char_armor INT;
    DECLARE total_damage INT;

    SELECT i.damage INTO item_damage
    FROM items i
        INNER JOIN equipped e ON i.item_id = e.item_id
    WHERE e.equipped_id = equipped_id;

    SELECT health INTO to_char_health
    FROM character_stats
    WHERE character_id = to_char_id;

    SELECT armor_total(to_char_id) INTO to_char_armor;

    SET total_damage = item_damage - to_char_armor;
    IF total_damage > 0 THEN
        IF to_char_health < total_damage THEN
            DELETE FROM characters
            WHERE character_id = to_char_id;
        ELSE
            UPDATE character_stats
            SET health = to_char_health - total_damage
            WHERE character_id = to_char_id;
        END IF;
    END IF;
END;;

CREATE PROCEDURE equip(IN inven_id INT UNSIGNED)
BEGIN
    DECLARE char_id INT UNSIGNED;
    DECLARE v_item_id INT UNSIGNED;
    SELECT character_id, item_id INTO char_id, v_item_id
        FROM inventory
        WHERE inventory_id = inven_id;
    
    INSERT INTO equipped
        (character_id, item_id)
    VALUES
        (char_id, v_item_id);
    
    DELETE FROM inventory
    WHERE inventory_id = inven_id;
END;;

CREATE PROCEDURE unequip(IN equip_id INT UNSIGNED)
BEGIN
    DECLARE char_id INT UNSIGNED;
    DECLARE v_item_id INT UNSIGNED;
    SELECT character_id, item_id INTO char_id, v_item_id
        FROM equipped
        WHERE equipped_id = equip_id;
    
    INSERT INTO inventory
        (character_id, item_id)
    VALUES
        (char_id, v_item_id);
    
    DELETE FROM equipped
    WHERE equipped_id = equip_id;
END;;

CREATE PROCEDURE set_winners(IN t_id INT UNSIGNED)
BEGIN
    DECLARE id INT UNSIGNED;
    DECLARE v_name VARCHAR(30);
    DECLARE row_not_found TINYINT DEFAULT FALSE;

    DECLARE curse CURSOR FOR
        SELECT c.character_id AS c_id, c.name AS c_name
        FROM characters c
        INNER JOIN team_members tm ON c.character_id = tm.character_id
        WHERE tm.team_id = t_id;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET row_not_found = TRUE;

    DELETE FROM winners;

    OPEN curse;
    read_loop: LOOP
        FETCH curse INTO id, v_name;
        IF row_not_found THEN
            LEAVE read_loop;
        END IF;
        INSERT INTO winners
            (character_id, name)
        VALUES
            (id, v_name);
    END LOOP read_loop;
    CLOSE curse;
END;;
DELIMITER ;

