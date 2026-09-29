{#
  GOLD · Dimension hora del dia. Grano: una hora (0-23).
  PK: time_key (= hora). Permite analizar la demanda por franja horaria.
#}
with hours as (
    select row_number() over (order by seq4()) - 1 as hour_of_day
    from table(generator(rowcount => 24))
)

select
    hour_of_day                                                     as time_key,
    hour_of_day,
    lpad(hour_of_day, 2, '0') || ':00-' || lpad(hour_of_day, 2, '0') || ':59' as hour_label,
    case
        when hour_of_day between 0 and 5   then 'Madrugada'
        when hour_of_day between 6 and 11  then 'Manana'
        when hour_of_day between 12 and 18 then 'Tarde'
        else 'Noche'
    end                                                             as day_part,
    -- Franja del recargo "rush hour" de la TLC (lun-vie 16:00-20:00)
    hour_of_day between 16 and 19                                   as is_rush_hour_window
from hours
