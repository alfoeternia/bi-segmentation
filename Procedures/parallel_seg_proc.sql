CREATE OR REPLACE PROCEDURE parallel_seg_proc
IS
    v_task_name   VARCHAR2(30) := DBMS_PARALLEL_EXECUTE.GENERATE_TASK_NAME();
    v_plsql_block VARCHAR2(32767);
BEGIN
    DELETE parallel_exec_test_table
     WHERE test_name = v_task_name;

    DBMS_PARALLEL_EXECUTE.create_task(task_name => v_task_name);

    DBMS_PARALLEL_EXECUTE.create_chunks_by_sql(
        task_name   => v_task_name,
        sql_stmt    => 'select min(OBJECTID), max(OBJECTID) from HPMS_SECTION group by ROUTE_ID',
        by_rowid    => FALSE
    );


    v_plsql_block :=
        q'[
begin 
   parallel_seg_chunk('v_task_name',:start_id,:end_id);
end;
]';
    DBMS_PARALLEL_EXECUTE.run_task(
        task_name        => v_task_name,
        sql_stmt         => v_plsql_block,
        language_flag    => DBMS_SQL.native,
        parallel_level   => 5
    );

    DBMS_OUTPUT.put_line(
           TO_CHAR(SYSTIMESTAMP, 'yyyy-mm-dd hh24:mi:ss.ff')
        || '  '
        || DBMS_PARALLEL_EXECUTE.task_status(v_task_name)
    );
    
    
  DBMS_PARALLEL_EXECUTE.DROP_TASK(v_task_name);
END;
/