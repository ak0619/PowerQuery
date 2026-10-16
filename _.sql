declare @date_from_compact char(8) = '20260901';
declare @date_to_compact char(8) = '20260930';
declare @date_from_hyphen char(10) = '2026-09-01';
declare @date_to_hyphen char(10) = '2026-09-30';

with sales_header as (
    select
        sales.[売上先],
        sales.[処理日付],
        sales.[取引区分],
        sales.[出荷備考],
        sales.[作成ＰＧＭ],
        staff.[担当者名],
        sections.[セクション名]
    from
        dbo.APV_RT_SALES_R as sales
    left join dbo.APV_RM_STAFF_M as staff
        on sales.[販売担当者] = staff.[担当者]
    left join dbo.APV_RM_SECTION_M as sections
        on sales.[売上セクション] = sections.[セクション]
    where
        sales.[システム行番号] = 1
        and sales.[処理日付] between @date_from_compact and @date_to_compact
        and sales.[出荷備考] not in (N'66307', N'66317')
),

pos_other_payments as (
    select
        [送受信管理番号],
        [送受信管理行番号],
        [その他支払方法ＩＤ],
        [支払方法名],
        [預かり金その他]
    from
        dbo.APV_RF_SPOS_SALES_PAYMENT
),

pos_payments as (
    select
        regular.[取引ＩＤ],
        regular.[レシート番号],
        payments.[支払方法],
        payments.[支払番号],
        payments.[支払金額]
    from
        dbo.APV_RF_SPOS_SALES as regular
    outer apply (
        select sum(cast(other.[預かり金その他] as int)) as [預かり金その他合計]
        from
            pos_other_payments as other
        where
            other.[送受信管理番号] = regular.[送受信管理番号]
            and other.[送受信管理行番号] = regular.[送受信管理行番号]
    ) as other_totals
    cross apply (
        select
            components.[支払方法],
            components.[支払番号],
            cast(components.[支払金額] as int) as [支払金額]
        from (
            values
            (
                N'IMCポイント',
                null,
                regular.[ポイント値引き]
            ),
            (
                N'現金',
                null,
                regular.[内現金支払金額]
            ),
            (
                case regular.[取扱カード会社]
                    when N' ' then N'クレジット手入力'
                    when N'Transportation system IC' then N'交通系IC'
                    else regular.[取扱カード会社]
                end,
                right(N'00000' + regular.[伝票番号], 5),
                regular.[内クレジット支払金額]
            ),
            (
                N'前受金',
                null,
                cast(regular.[合計] as int)
                - cast(regular.[内現金支払金額] as int)
                - cast(regular.[内クレジット支払金額] as int)
                - coalesce(other_totals.[預かり金その他合計], 0)
            )
        ) as components ([支払方法], [支払番号], [支払金額])

        union all

        select
            case other.[その他支払方法ＩＤ]
                when N'18' then N'IMCポイント'
                else other.[支払方法名]
            end,
            case other.[その他支払方法ＩＤ]
                when N'18' then null
                else regular.[メモ]
            end,
            cast(other.[預かり金その他] as int)
        from
            pos_other_payments as other
        where
            other.[送受信管理番号] = regular.[送受信管理番号]
            and other.[送受信管理行番号] = regular.[送受信管理行番号]
    ) as payments
    where
        regular.[取引区分] = N'1'
        and left(regular.[取引日時], 10) between @date_from_hyphen and @date_to_hyphen
        and payments.[支払金額] <> 0
),

pos_sales as (
    select
        sales.[処理日付] as [日付],
        sales.[出荷備考] as [伝票番号],
        sales.[売上先] as [店舗],
        N'スマレジ' as [セクション],
        sales.[担当者名] as [担当者],
        payments.[支払方法],
        payments.[支払番号],
        payments.[レシート番号] as [受注番号],
        payments.[支払金額]
    from
        sales_header as sales
    left join pos_payments as payments
        on sales.[出荷備考] = payments.[取引ＩＤ]
    where
        sales.[作成ＰＧＭ] = N'TFO300E'
)

select *
from
    pos_sales;
