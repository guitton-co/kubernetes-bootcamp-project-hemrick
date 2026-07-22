-- Performance produit : popularité et fidélité de réachat, par produit / allée / département.
-- Ce dataset n'a pas de prix ni de chiffre d'affaires : la popularité (nombre de commandes)
-- et le taux de réachat sont les métriques business les plus pertinentes disponibles.

with order_products as (
    select order_id, product_id, add_to_cart_order, reordered
    from {{ source('raw_instacart', 'raw_order_products_prior') }}
    union all
    select order_id, product_id, add_to_cart_order, reordered
    from {{ source('raw_instacart', 'raw_order_products_train') }}
),

product_stats as (
    select
        product_id,
        count(*) as times_ordered,
        countif(reordered) as times_reordered,
        safe_divide(countif(reordered), count(*)) as reorder_rate,
        avg(add_to_cart_order) as avg_add_to_cart_position,
        count(distinct order_id) as distinct_orders
    from order_products
    group by product_id
)

select
    p.product_id,
    p.product_name,
    a.aisle,
    d.department,
    s.times_ordered,
    s.times_reordered,
    round(s.reorder_rate, 4) as reorder_rate,
    round(s.avg_add_to_cart_position, 2) as avg_add_to_cart_position,
    s.distinct_orders
from product_stats s
inner join {{ source('raw_instacart', 'raw_products') }} p using (product_id)
left join {{ source('raw_instacart', 'raw_aisles') }} a using (aisle_id)
left join {{ source('raw_instacart', 'raw_departments') }} d using (department_id)
order by s.times_ordered desc
