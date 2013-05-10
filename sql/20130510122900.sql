\set ON_ERROR_STOP ON
begin transaction;

create table db_revisions(db_revision bigint primary key);

create user "${CRON_USER}";

grant select,insert on db_revisions to ${CRON_USER};

CREATE OR REPLACE FUNCTION require_sql_revision(bigint)
RETURNS boolean AS $$
DECLARE rev bigint;
BEGIN
    SELECT INTO rev db_revision
    FROM db_revisions
    WHERE db_revision = $1;

    IF ( rev is null ) THEN
        RAISE EXCEPTION 'Wrong SQL revision';
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION set_sql_revision(bigint)
RETURNS varchar(3) AS $$
BEGIN
    INSERT INTO db_revisions(db_revision)
    VALUES($1);

    RETURN $1;
END
$$ LANGUAGE 'plpgsql';

create table debtags(id text primary key, descr text);

grant select,insert,delete on debtags to ${CRON_USER};

create user "${WEB_USER}";

grant select on debtags to "${WEB_USER}";

select set_sql_revision(20130510122900);
commit transaction;
