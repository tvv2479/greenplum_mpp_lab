
-- Анализ динамики продаж и ранжирование категорий по регионам 
-- с использованием распределенных таблиц и реплицированного справочника.

explain analyze
with regional_sales as (
-- Сбор первичных агрегатов с локальных сегментов (Local Aggregation)
select f.region_code,
       d.category_name,
       f.sale_date,
       sum(f.total_amount) as daily_category_revenue,
       count(distinct f.customer_id) as active_customers
  from fact_order_items f
  join dim_stores s on f.store_id = s.store_id -- Соединение с реплицированным справочником
  join dim_categories d on f.category_id = d.category_id -- Соединение с распределенной таблицей категорий
 where f.sale_date >= '2026-01-01'
 group by f.region_code, d.category_name, f.sale_date
       )
       -- Применение оконной функции по глобально перераспределенным данным
       select region_code,
              category_name,
              daily_category_revenue,
              active_customers,
              -- Окно вычисляет скользящее суммирование или ранг внутри региона
              rank() over (partition by region_code order by daily_category_revenue desc) as revenue_rank
         from regional_sales;