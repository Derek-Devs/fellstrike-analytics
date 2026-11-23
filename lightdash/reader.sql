-- Lightdash's own login to the warehouse: it can read the marts and nothing else (docs/analytics-design.md, 9.2).
-- docker compose runs this before Lightdash starts (the lightdash-reader service), with the password from .env in
-- the psql variable pw. Running it again changes nothing, except to set the password again.

-- Make the role if it isn't there, then set its password. format() with %L quotes the password safely, and \gexec
-- runs the statement the query returns.
select format('create role lightdash_reader login password %L', :'pw')
where not exists (select from pg_roles where rolname = 'lightdash_reader') \gexec
select format('alter role lightdash_reader login password %L', :'pw') \gexec

-- dbt makes the marts schema on its first build. Making it here first lets the grants below work on a new warehouse.
create schema if not exists marts;

select format('grant connect on database %I to lightdash_reader', current_database()) \gexec
grant usage on schema marts to lightdash_reader;
grant select on all tables in schema marts to lightdash_reader;
-- dbt drops and makes the mart tables again on every build. Default privileges give each new table the same grant.
select format('alter default privileges for role %I in schema marts grant select on tables to lightdash_reader',
              current_user) \gexec
