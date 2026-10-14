
-- =========================================================================
-- GREENPLUM ARCHITECTURE LAB: Advanced DDL & Storage Engineering
-- =========================================================================

-- Очистка старых объектов (если пересоздаем схему)
drop table if exists fact_order_items cascade;
drop table if exists dim_stores cascade;

-- -------------------------------------------------------------------------
-- 1. СТРАТЕГИЯ ШАРДИНГА И ХРАНЕНИЯ ДЛЯ ТАБЛИЦЫ ФАКТОВ
-- -------------------------------------------------------------------------
-- Цель: 
--  - Избежать Data Skew (перекоса) с помощью составного ключа распределения.
--  - Ускорить сканирование OLAP-запросов за счет колоночного AO-формата (Append-Optimized).
--  - Оптимизировать дисковое пространство через сжатие ZSTD.
--  - Организовать эффективный Partition Pruning по дате и региону.

create table fact_order_items (
    order_id        bigint,
    item_id         int,
    store_id        int,
    customer_id     bigint,
    sale_date       date not null,
    region_code     varchar(10) not null,
    quantity        int,
    unit_price      numeric(10, 2),
    total_amount    numeric(12, 2),
    is_returned     boolean default false
)
-- 1. Составной ключ шардинга (Distribution Key)
-- Распределяем данные по сегментам на основе хеша двух колонок.
-- Это снижает риск Data Skew, если по одной колонке есть перекос.
distributed by (store_id, customer_id)
-- 2. Многоуровневое (композитное) партиционирование:
-- Уровень 1: Помесячное секционирование по дате продажи.
-- Уровень 2: Вложенное подразделение (SUBPARTITION) по регионам внутри каждого месяца.
-- Позволяет Greenplum отсекать целые сегменты и файлы при фильтрации (Partition Pruning).
partition by range (sale_date)
subpartition by list (region_code)
             (
              -- Секция за Январь 2026 с подсекциями по регионам
              partition p2026_01 start (date '2026-01-01') inclusive
                                 end (date '2026-02-01') exclusive
                        (
                         subpartition sub_eu values ('EU'),
                         subpartition sub_us values ('US'),
                         subpartition sub_apac values ('APAC'),
                         subpartition sub_default default subpartition
                        ),
              -- Секция за Февраль 2026
              partition p2026_02 start (date '2026-02-01') inclusive
                                 end (date '2026-03-01') exclusive
                        (
                         subpartition sub_eu values ('EU'),
                         subpartition sub_us values ('US'),
                         subpartition sub_apac values ('APAC'),
                         subpartition sub_default default subpartition
                        )
             )
             -- 3. Настройки физического хранения (Append-Optimized Columnar + ZSTD Compression)
             with (
                   appendonly = true,         -- Таблица оптимизирована для быстрой дозаписи (нет Page-level блокировок Postgres)
                   orientation = column,      -- Колоночное хранение (читаются только запрошенные колонки)
                   compresstype = zstd,       -- Алгоритм сжатия (баланс скорости и степени сжатия)
                   compresslevel = 6          -- Уровень сжатия от 1 до 19
                  );





-- -------------------------------------------------------------------------
-- 2. ТАБЛИЦА ИЗМЕРЕНИЙ (Справочник магазинов)
-- -------------------------------------------------------------------------
-- Для маленьких таблиц измерений, которые часто участвуют в JOIN с фактами,
-- часто применяют репликацию на все сегменты, чтобы избежать Redistribute Motion.

create table dim_stores (
    store_id        int,
    store_name      varchar(100),
    city            varchar(50),
    country         varchar(50),
    manager_name    varchar(100)
)
distributed replicated; -- Копия таблицы хранится на КАЖДОМ сегменте кластера!










