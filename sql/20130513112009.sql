\set ON_ERROR_STOP ON
select require_sql_revision(20130511141439);
begin transaction;

create sequence packages_seq;

grant select,update on packages_seq to "${CRON_USER}";

create table packages(
    id bigint not null default nextval('packages_seq'),
    constraint pk_packages primary key(id),
    suite text not null,
    package text not null,
    architecture text not null,
    version text not null,
    constraint un_packages unique(suite, package, architecture, version),
    stale boolean
);

grant select on packages to "${WEB_USER}";
grant select,update,insert,delete on packages to "${CRON_USER}";

create table package_properties(
    pkg_id bigint not null,
    constraint fk_package_properties_package
        foreign key(pkg_id) references packages(id),
    name text not null,
    constraint pk_pkg_props primary key(pkg_id, name),
    value text not null,
    stale boolean
);

grant select on package_properties to "${WEB_USER}";
grant select,update,insert,delete on package_properties to "${CRON_USER}";

select set_sql_revision(20130513112009);
commit transaction;
