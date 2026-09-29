-- Reconciliacion SILVER -> GOLD: la tabla de hechos tiene exactamente un
-- registro por viaje valido de Silver (su grano). Falla si devuelve filas.
select
    (select count(*) from {{ ref('slv_yellow_trips') }}) as filas_silver,
    (select count(*) from {{ ref('fct_trips') }})        as filas_fct
where (select count(*) from {{ ref('slv_yellow_trips') }})
   <> (select count(*) from {{ ref('fct_trips') }})
