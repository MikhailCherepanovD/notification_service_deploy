
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS route_monitoring CASCADE;
DROP TABLE IF EXISTS ticket_data CASCADE;
DROP TABLE IF EXISTS route CASCADE;
DROP TABLE IF EXISTS location CASCADE;
DROP TABLE IF EXISTS type_of_route CASCADE;

CREATE TABLE users(
	users_id SERIAL PRIMARY KEY,
	login varchar(50),
	password varchar(100),
	user_name varchar(50),
	email varchar(50),
	telegram varchar(50)
);

CREATE TABLE route_monitoring(
	route_monitoring_id SERIAL PRIMARY KEY,
	users_id INT,
	route_id INT,
	frequency_monitoring INT, -- интервал будет записываться в часах
	start_time_monitoring TIMESTAMP,
	finish_time_monitoring TIMESTAMP,
	transfers_are_allowed BOOLEAN
);

CREATE TABLE ticket_data(
	ticket_data_id SERIAL PRIMARY KEY,
	route_monitoring_id INT,
	time_of_checking TIMESTAMP,
	price INT,
	ticket_data JSON
);

CREATE TABLE route(
	route_id SERIAL PRIMARY KEY,
	type_of_route_id INT,
	start_location_id INT,
	finish_location_id INT
);


CREATE TABLE location(
	location_id SERIAL PRIMARY KEY,
	city_name varchar(50),
	IATA_code varchar(50)
);

CREATE TABLE type_of_route(
	type_of_route_id SERIAL PRIMARY KEY,
	type_name varchar(50)
);



ALTER TABLE route_monitoring
    ADD FOREIGN KEY (users_id) REFERENCES users(users_id)
		ON UPDATE CASCADE ON DELETE CASCADE,
    ADD FOREIGN KEY (route_id) REFERENCES route(route_id)
		ON UPDATE CASCADE ON DELETE CASCADE;
		
ALTER TABLE route
    ADD FOREIGN KEY (type_of_route_id) REFERENCES type_of_route(type_of_route_id)
		ON UPDATE CASCADE ON DELETE CASCADE,
    ADD FOREIGN KEY (start_location_id) REFERENCES location(location_id)
		ON UPDATE CASCADE ON DELETE CASCADE,
    ADD FOREIGN KEY (finish_location_id) REFERENCES location(location_id)
		ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ticket_data
    ADD FOREIGN KEY (route_monitoring_id) REFERENCES route_monitoring(route_monitoring_id)
		ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE users
ADD CONSTRAINT unique_login1 UNIQUE (login);



CREATE INDEX users___users_id_idx ON users(users_id);

CREATE INDEX route_monitoring___route_monitoring_id_idx ON route_monitoring (route_monitoring_id);
CREATE INDEX route_monitoring___users_id_idx ON route_monitoring (users_id);
CREATE INDEX route_monitoring___route_id_idx ON route_monitoring (route_id);


CREATE INDEX ticket_data___ticket_data_id_idx ON ticket_data(ticket_data_id);
CREATE INDEX ticket_data___time_of_checking_idx ON ticket_data(time_of_checking);

CREATE INDEX route___route_id_idx ON route(route_id);
CREATE INDEX route___start_location_id_idx ON route(start_location_id);
CREATE INDEX route___finish_location_id_idx ON route(finish_location_id);

CREATE INDEX location___location_id_idx ON location(location_id);
































DROP FUNCTION IF EXISTS insert_data_journey;
DROP FUNCTION IF EXISTS update_or_insert_users;
DROP FUNCTION IF EXISTS get_all_routes_by_user;
DROP FUNCTION IF EXISTS get_route;
DROP FUNCTION IF EXISTS get_recent_ticket_data;
DROP FUNCTION IF EXISTS get_cheapest_ticket_data;
DROP FUNCTION IF EXISTS get_statistic_ticket_data;

CREATE OR REPLACE FUNCTION update_or_insert_users( --0 - конфликт на логинах, 1 - значение вставлено, 2 - значение обновлено
    p_users_id INT,
    p_login TEXT,
    p_password TEXT,
    p_user_name TEXT,
    p_email TEXT,
    p_telegram TEXT
) RETURNS INT AS $$
DECLARE
    returned_value INT;
BEGIN
	BEGIN
	  	IF NOT EXISTS(
			SELECT 1 FROM users WHERE users.users_id=p_users_id
		)
		THEN 
			INSERT INTO users (users_id, login, password, user_name, email, telegram)
			VALUES (p_users_id, p_login, p_password, p_user_name, p_email, p_telegram);
			returned_value = 1;
		ELSE
			UPDATE users SET 
				login = p_login,
				password = p_password,
				user_name = p_user_name,
				email = p_email,
				telegram=p_telegram
			WHERE users_id=p_users_id;
			returned_value=2;
		END IF;
	EXCEPTION
        WHEN unique_violation THEN
			returned_value=0;
	END;
	RETURN returned_value;
END;
$$ LANGUAGE plpgsql;



DROP FUNCTION IF exists insert_data_journey;
CREATE OR REPLACE FUNCTION insert_data_journey( --0 - нет такого пользователя, 1 - значение вставлено, 2 - значение обновлено, 3 - ошибка базы данных
    p_users_id INT,
	
    p_frequency_monitoring INT,
    p_start_time_monitoring TIMESTAMP,
    p_finish_time_monitoring TIMESTAMP,
    p_transfers_are_allowed BOOLEAN,
	
    p_type_of_route_name TEXT,
	
	p_start_city_name TEXT,
	p_start_iata_code TEXT,
	p_finish_city_name TEXT,
	p_finish_iata_code TEXT,
	
	p_time_of_checking TIMESTAMP,
	p_price INT,
	p_ticket_data JSON,
	p_route_monitoring_id INT DEFAULT NULL
)RETURNS TABLE(returning_route_monitoring_id INT, status INT) AS $$
DECLARE
    v_type_of_route_id INT;
	v_start_location_id INT;
	v_finish_location_id INT;
	v_route_id INT;
	v_route_monitoring_id INT;
BEGIN
	IF NOT EXISTS(
		SELECT * FROM users WHERE users_id=p_users_id
	)THEN
		returning_route_monitoring_id:=NULL;
		status:=0;
		RETURN NEXT;
		RETURN;
	END IF;
	BEGIN
		SELECT type_of_route_id INTO v_type_of_route_id FROM type_of_route WHERE type_name = p_type_of_route_name;
		IF v_type_of_route_id IS NULL THEN
			INSERT INTO type_of_route(type_name)
			VALUES (p_type_of_route_name)
			RETURNING type_of_route_id INTO v_type_of_route_id;
		END IF;
	
		SELECT location_id INTO v_start_location_id FROM location 
		WHERE city_name = p_start_city_name AND IATA_code = p_start_iata_code;
		IF v_start_location_id IS NULL THEN
			INSERT INTO location(city_name,IATA_code)
			VALUES (p_start_city_name,p_start_iata_code)
			RETURNING location_id INTO v_start_location_id;
		END IF;
	
		SELECT location_id INTO v_finish_location_id FROM location 
		WHERE city_name = p_finish_city_name AND IATA_code = p_finish_iata_code;
		IF v_finish_location_id IS NULL THEN
			INSERT INTO location(city_name,IATA_code)
			VALUES (p_finish_city_name,p_finish_iata_code)
			RETURNING location_id INTO v_finish_location_id;
		END IF;
	
		SELECT route_id INTO v_route_id FROM route 
		WHERE type_of_route_id = v_type_of_route_id
		AND start_location_id = v_start_location_id AND finish_location_id = v_finish_location_id;
		IF v_route_id IS NULL THEN
			INSERT INTO route(type_of_route_id,start_location_id,finish_location_id)
			VALUES (v_type_of_route_id,v_start_location_id,v_finish_location_id)
			RETURNING route_id INTO v_route_id;
		END IF;

		IF p_route_monitoring_id IS NULL 
		THEN
			INSERT INTO route_monitoring(
				users_id,
				route_id,
				frequency_monitoring,
				start_time_monitoring,
				finish_time_monitoring,
				transfers_are_allowed)
			VALUES(
				p_users_id,
				v_route_id,
				p_frequency_monitoring,
				p_start_time_monitoring,
				p_finish_time_monitoring,
				p_transfers_are_allowed)
			RETURNING route_monitoring_id INTO v_route_monitoring_id;
			returning_route_monitoring_id:=v_route_monitoring_id;
			status:=1;
		ELSIF NOT EXISTS (SELECT * FROM route_monitoring WHERE route_monitoring_id = p_route_monitoring_id) THEN
			INSERT INTO route_monitoring(
				route_monitoring_id,
				users_id,
				route_id,
				frequency_monitoring,
				start_time_monitoring,
				finish_time_monitoring,
				transfers_are_allowed)
			VALUES(
				p_route_monitoring_id,
				p_users_id,
				v_route_id,
				p_frequency_monitoring,
				p_start_time_monitoring,
				p_finish_time_monitoring,
				p_transfers_are_allowed)
			RETURNING route_monitoring_id INTO v_route_monitoring_id;
			returning_route_monitoring_id:=v_route_monitoring_id;
			status:=1;
		ELSE
			UPDATE 
				route_monitoring
			SET 
				route_id = v_route_id,
				frequency_monitoring = p_frequency_monitoring,
				start_time_monitoring = p_start_time_monitoring,
				finish_time_monitoring = p_finish_time_monitoring,
				transfers_are_allowed = p_transfers_are_allowed
			WHERE route_monitoring_id = p_route_monitoring_id;
			returning_route_monitoring_id:=p_route_monitoring_id;
			status:=2;
			v_route_monitoring_id:=p_route_monitoring_id;
		END IF;
		
		INSERT INTO ticket_data(route_monitoring_id, time_of_checking, price, ticket_data)
		VALUES (v_route_monitoring_id,p_time_of_checking, p_price, p_ticket_data);
		
		RETURN NEXT;
		RETURN;
	EXCEPTION
    	WHEN OTHERS THEN
			returning_route_monitoring_id:=NULL;
			status:=3;
			RETURN NEXT;
			RETURN;
	END;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS get_all_routes_by_user;
CREATE OR REPLACE FUNCTION get_all_routes_by_user(
    p_user_id INT
)
RETURNS TABLE(
    route_monitoring_id INT,
    frequency_monitoring INT,
    start_time_monitoring TIMESTAMP,
    finish_time_monitoring TIMESTAMP,
    transfers_are_allowed BOOLEAN,
    start_city TEXT,
    start_iata TEXT,
    finish_city TEXT,
    finish_iata TEXT
) 
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rm.route_monitoring_id,
        rm.frequency_monitoring,
        rm.start_time_monitoring,
        rm.finish_time_monitoring,
        rm.transfers_are_allowed,
        ls.city_name::text AS start_city,
        ls.IATA_code::text AS start_iata,
        lf.city_name::text AS finish_city,
        lf.IATA_code::text AS finish_iata
    FROM route_monitoring rm
    JOIN route r ON rm.route_id = r.route_id 
    JOIN "location" ls ON r.start_location_id = ls.location_id
    JOIN "location" lf ON r.finish_location_id = lf.location_id 
    WHERE rm.users_id = p_user_id;
END;
$$;


DROP FUNCTION IF EXISTS get_route;
CREATE OR REPLACE FUNCTION get_route(
    p_user_id INT,
	p_route_monitoring_id INT
)
RETURNS TABLE(
    route_monitoring_id INT,
    frequency_monitoring INT,
    start_time_monitoring TIMESTAMP,
    finish_time_monitoring TIMESTAMP,
    transfers_are_allowed BOOLEAN,
    start_city TEXT,
    start_iata TEXT,
    finish_city TEXT,
    finish_iata TEXT
) 
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rm.route_monitoring_id,
        rm.frequency_monitoring,
        rm.start_time_monitoring,
        rm.finish_time_monitoring,
	rm.transfers_are_allowed,
        ls.city_name::text AS start_city,
        ls.IATA_code::text AS start_iata,
        lf.city_name::text AS finish_city,
        lf.IATA_code::text AS finish_iata
    FROM route_monitoring rm
    JOIN route r ON rm.route_id = r.route_id 
    JOIN "location" ls ON r.start_location_id = ls.location_id
    JOIN "location" lf ON r.finish_location_id = lf.location_id 
    WHERE rm.users_id = p_user_id AND rm.route_monitoring_id = p_route_monitoring_id;
END;
$$;

DROP FUNCTION IF EXISTS get_recent_ticket_data;
CREATE OR REPLACE FUNCTION get_recent_ticket_data(
	p_route_monitoring_id INT,
   	p_current_time TIMESTAMP,
	p_hash_interval_minutes INT
)RETURNS JSON AS $$
DECLARE
	v_time_diff INT;
	v_last_ticket_data JSON;
	v_last_time_cheching TIMESTAMP;
BEGIN
	SELECT time_of_checking, ticket_data
	INTO v_last_time_cheching,v_last_ticket_data
	FROM ticket_data 
	WHERE route_monitoring_id = p_route_monitoring_id
	ORDER BY time_of_checking DESC LIMIT 1;
	
	IF v_last_ticket_data IS NULL THEN
		return NULL;
	END IF;
	v_time_diff := EXTRACT(EPOCH FROM (p_current_time - v_last_time_cheching))/60;
	IF v_time_diff>p_hash_interval_minutes THEN
		v_last_ticket_data:=NULL;
	END IF;
	RETURN v_last_ticket_data;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS get_cheapest_ticket_data;
CREATE OR REPLACE FUNCTION get_cheapest_ticket_data(
	p_route_monitoring_id INT
)RETURNS JSON AS $$
DECLARE
	returned_value JSON;
BEGIN
	SELECT t.ticket_data INTO returned_value
	FROM ticket_data t
	WHERE route_monitoring_id = p_route_monitoring_id
	ORDER BY price DESC LIMIT 1;
	RETURN returned_value;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS get_statistic_ticket_data;
CREATE OR REPLACE FUNCTION get_statistic_ticket_data(
	p_route_monitoring_id INT,
	p_current_time TIMESTAMP
)RETURNS TABLE(
	ret_time_of_checking TIMESTAMP,
	ret_ticket_data JSON
) AS $$
DECLARE
	v_frequency_monitoring INT;
	v_first_time_of_checking TIMESTAMP;
	v_current_time_loop TIMESTAMP;
	v_interval_loop_step INTERVAL;
BEGIN
	SELECT frequency_monitoring
	INTO v_frequency_monitoring
	FROM route_monitoring WHERE route_monitoring_id = p_route_monitoring_id;

	IF v_frequency_monitoring IS NULL THEN
		RETURN QUERY SELECT NULL::TIMESTAMP, NULL::JSON; 
	END IF;
	
	SELECT time_of_checking
	INTO v_first_time_of_checking
	FROM ticket_data
	WHERE route_monitoring_id = p_route_monitoring_id
	ORDER BY time_of_checking ASC LIMIT 1;

	IF v_first_time_of_checking IS NULL THEN
		RETURN QUERY SELECT NULL::TIMESTAMP, NULL::JSON; 
	END IF;

	v_current_time_loop:=p_current_time;
	v_interval_loop_step:=(v_frequency_monitoring * INTERVAL '1 minute');
	WHILE v_current_time_loop >= (v_first_time_of_checking - (v_frequency_monitoring * INTERVAL '1 minute')) LOOP
		--RAISE NOTICE 'Current time: %', v_current_time_loop;
		RETURN QUERY
		SELECT time_of_checking, ticket_data
		FROM ticket_data
		WHERE route_monitoring_id = p_route_monitoring_id
		AND time_of_checking<= v_current_time_loop + (v_interval_loop_step/2)
		AND time_of_checking >= v_current_time_loop - (v_interval_loop_step/2)
		ORDER BY time_of_checking ASC LIMIT 1;
		
		v_current_time_loop:= v_current_time_loop - v_interval_loop_step;
	END LOOP;
	
END;
$$ LANGUAGE plpgsql;




























DROP VIEW IF EXISTS  notification_sending_view;
DROP TABLE IF EXISTS table_route_checking;
DROP TRIGGER IF EXISTS new_route_trigger ON route_monitoring;
DROP FUNCTION IF EXISTS trigger_function;
DROP PROCEDURE IF EXISTS update_time_of_next_checking;

CREATE OR REPLACE VIEW notification_sending_view AS
	SELECT u.users_id, u.user_name, u.telegram, u.email,  rm.route_monitoring_id, rm.frequency_monitoring
	FROM route_monitoring rm 
	JOIN users u ON u.users_id = rm.users_id;
	
	


CREATE TABLE table_route_checking(
	table_route_checking_id SERIAL PRIMARY KEY,
	route_id INT,
	time_of_next_checking TIMESTAMP,
	first_checking BOOLEAN
);



CREATE FUNCTION trigger_function()
RETURNS trigger AS $$
DECLARE
	v_time_of_next_checking TIMESTAMP;
BEGIN 
	IF TG_OP = 'INSERT' THEN
		INSERT INTO table_route_checking(route_id,time_of_next_checking,first_checking)
		VALUES(NEW.route_monitoring_id,CURRENT_TIMESTAMP,True);
		RETURN NEW;
	ELSIF TG_OP = 'DELETE' THEN
		DELETE FROM table_route_checking WHERE route_id = OLD.route_monitoring_id;
		RETURN NULL;
	ELSIF TG_OP = 'UPDATE' THEN
        -- Обновляем информацию о маршруте
        UPDATE table_route_checking
        SET time_of_next_checking = CURRENT_TIMESTAMP
        WHERE route_id = NEW.route_monitoring_id;
        RETURN NEW;  -- Для UPDATE возвращаем NEW
    END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER new_route_trigger AFTER INSERT OR DELETE OR UPDATE ON route_monitoring
	FOR EACH ROW 
	EXECUTE FUNCTION trigger_function();
	
	


CREATE OR REPLACE PROCEDURE update_time_of_next_checking(
	p_route_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
	v_frequency_monitoring INT;
	v_increasing_value INTERVAL;
BEGIN
	SELECT frequency_monitoring
	INTO v_frequency_monitoring
	FROM route_monitoring WHERE route_monitoring_id = p_route_id;
	v_increasing_value:=(v_frequency_monitoring * INTERVAL '1 minute');
	UPDATE table_route_checking SET time_of_next_checking = time_of_next_checking + v_increasing_value WHERE route_id = p_route_id;
END;
$$;










