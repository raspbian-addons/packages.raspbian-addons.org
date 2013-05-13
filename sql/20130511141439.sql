\set ON_ERROR_STOP ON
begin transaction;
select require_sql_revision(20130510122900);

create table descriptions(
    md5 char(32),
    lang varchar(10),
    descr text not null,
    stale boolean,
    constraint pk_descriptions primary key(md5,lang)
);


grant select,insert,delete on descriptions to ${CRON_USER};

grant select on descriptions to "${WEB_USER}";

select set_sql_revision(20130511141439);
commit transaction;
