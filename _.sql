declare @date_from char(8) = N'20260901';
declare @date_to char(8) = N'20260930';
with
sales_source as (
    select
        [システム番号] as system_id,
        [出荷先] as store_code,
        [処理日付] as processing_date,
        [伝票番号] as slip_number,
        [取引区分] as transaction_type,
        [備考] as remarks,
        [売上額] as sales_amount,
        [作成ＰＧＭ] as creation_program
    from
        dbo.APV_RT_SALES
),

sales_rows as (
    select
        [システム番号] as system_id,
        [システム行番号] as system_row_number,
        [出荷セクション] as section_code,
        [販売担当者] as staff_code
    from
        dbo.APV_RT_SALES_R
),

sections as (
    select
        [セクション] as section_code,
        [セクション名] as section_name
    from
        dbo.APV_RM_SECTION_M
),

staff as (
    select
        [担当者] as staff_code,
        [担当者名] as staff_name
    from
        dbo.APV_RM_STAFF_M
),

imported_source as (
    select
        [自店コード] as store_code,
        [伝票日付] as slip_date,
        [伝票番号] as slip_number,
        [顧客番号] as order_number,
        [決済番号] as payment_number,
        [支払金額] as payment_amount,
        [作成ＰＧＭ] as creation_program
    from
        dbo.APV_RT_SALES_PAYMENT
),

sales as (
    select
        source.store_code,
        source.processing_date,
        source.transaction_type,
        source.creation_program,
        case source.creation_program
            when N'TFO300E' then source.remarks
            else source.slip_number
        end as slip_number,
        case source.creation_program
            when N'TFO300E' then N'スマレジ'
            else sections.section_name
        end as section_name,
        replace(staff.staff_name, N'　', N'') as staff_name
    from
        sales_source as source
    inner join sales_rows as detail
        on
            source.system_id = detail.system_id
            and detail.system_row_number = 1
    left join sections
        on detail.section_code = sections.section_code
    left join staff
        on detail.staff_code = staff.staff_code
    where
        source.sales_amount <> 0
        and source.processing_date >= @date_from
        and source.processing_date <= @date_to
        and source.remarks not in (N'66307', N'66317')
        and source.creation_program <> N'TFT220E'
),

imported_sales as (
    select
        source.slip_date,
        source.slip_number,
        source.store_code,
        N'取込売上' as section_name,
        N'レゾン' as staff_name,
        N'銀行振込' as payment_method,
        source.payment_number,
        source.order_number,
        source.payment_amount
    from
        imported_source as source
    where
        source.creation_program = N'TFT220E'
        and source.slip_date >= @date_from
        and source.slip_date <= @date_to
)

select *
from
    imported_sales;
