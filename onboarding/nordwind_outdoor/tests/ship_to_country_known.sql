-- Assumption A3: a delivery country the dictionary's list does not name is never guessed.
-- It would load as NULL, so this test fails the run and the name is raised with the partner's owner.
-- depends_on: {{ ref('order_line') }}
select ship_to, count(*) as n
from {{ source('bronze', 'nordwind_orders_raw') }}
where nullif(trim(ship_to), '') is not null
  and lower(trim(ship_to)) not in ('de', 'germany', 'deutschland', 'at', 'austria', 'österreich', 'ch', 'switzerland', 'schweiz')
group by 1
