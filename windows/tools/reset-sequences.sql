-- Run by Restore Database.bat after pg_restore: moves every identity/serial sequence past its
-- table's MAX(Id), so new rows never collide with restored ones. Same as Backend/scripts/db-restore.sh.
\set ON_ERROR_STOP on

DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT c.table_name, c.column_name,
               pg_get_serial_sequence(format('%I.%I', c.table_schema, c.table_name), c.column_name) AS seq
        FROM information_schema.columns c
        WHERE c.table_schema = 'public'
          AND pg_get_serial_sequence(format('%I.%I', c.table_schema, c.table_name), c.column_name) IS NOT NULL
    LOOP
        EXECUTE format(
            'SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM %I), 1), EXISTS (SELECT 1 FROM %I))',
            r.seq, r.column_name, r.table_name, r.table_name);
    END LOOP;
END $$;
