declare @date_from_compact char(8) = '20260901';
declare @date_to_exclusive_compact char(8) = '20261001';
declare @date_from_hyphen char(10) = '2026-09-01';
declare @date_to_exclusive_hyphen char(10) = '2026-10-01';

with
ne_source as (
    select
        _.[店舗コード],
        _.[伝票番号],
        _.[受注番号],
        _.[発送方法区分],
        _.[支払区分],
        _.[発送伝票番号],
        _.[クレジット承認番号],
        _.[オプション２],
        _.[オプション９],
        v.[ポイント数],
        v.[オプション３],
        v.[総合計] - v.[オプション３] as [正味金額]
    from dbo.APV_RF_NE_SALES as _
    cross apply (
        values
        (
            cast(cast(_.[総合計] as decimal(10, 2)) as int),
            cast(cast(_.[ポイント数] as decimal(10, 2)) as int),
            coalesce(try_cast(_.[オプション３] as int), 0)
        )
    ) as v ([総合計], [ポイント数], [オプション３])
    where
        _.[法人] = '000'
        and _.[処理フラグ] = 0
),

ne_payment as (
    select
        _.[店舗コード],
        _.[伝票番号],
        _.[受注番号],
        _.[オプション９],
        v.[支払方法],
        v.[支払番号],
        v.[支払金額]
    from ne_source as _
    cross apply (
        values
        (
            case
                when _.[店舗コード] in ('1', '20') and _.[支払区分] = '0' then 'MS クレジットカード'
                when _.[店舗コード] in ('1', '20') and _.[支払区分] in ('32', '35', '36') then 'MS コンビニ'
                when _.[店舗コード] = '1' and _.[支払区分] in ('72', '76') then 'SB PayPay'
                when _.[店舗コード] = '20' and _.[支払区分] in ('72', '76') then 'MS PayPay'
                when _.[店舗コード] = '2' and _.[支払区分] = '0' then 'デジマート'
                when _.[店舗コード] in ('3', '4') and _.[支払区分] in ('0', '15', '32', '35', '36') then '楽天ペイ'
                when _.[店舗コード] in ('5', '6', '17') and _.[支払区分] in ('0', '32', '35', '36', '63', '68', '72', '76') then 'Yahoo'
                when _.[店舗コード] = '7' and _.[支払区分] = '48' then 'Amazon'
                when _.[店舗コード] = '10' then 'Amazon'
                when _.[支払区分] = '1' and _.[発送方法区分] in ('13', '15', '17', '18') then '佐川コレクト'
                when _.[支払区分] = '1' and _.[発送方法区分] in ('20', '21', '28') then 'ヤマトコレクト'
                when _.[支払区分] = '1' and _.[発送方法区分] = '30' then 'ゆうパックコレクト'
                when _.[支払区分] = '15' then '銀行振込'
                when _.[支払区分] = '30' then 'JACCSショッピングクレジット'
                when _.[支払区分] = '31' then 'ORICOショッピングクレジット'
                when _.[支払区分] = '42' then 'Shopifyペイメント'
                when _.[支払区分] = '43' then 'KOMOJU'
                when _.[支払区分] = '48' then 'Amazon Pay'
                when _.[支払区分] = '53' then 'PAYGENT VISA/MASTER'
                when _.[支払区分] = '54' then 'PAYGENT コンビニ'
                when _.[支払区分] = '56' then 'PAYGENT ATM'
                when _.[支払区分] = '57' then 'PAYGENT JCB'
                when _.[支払区分] = '60' then 'PayPal'
                when _.[支払区分] = '67' then 'Payo_er'
                when _.[支払区分] = '70' then 'MS バーチャル口座'
                when _.[支払区分] = '85' then 'ポイント全額支払い'
                when _.[支払区分] = '95' then '売掛'
                when _.[支払区分] = '96' then 'その他'
                when _.[支払区分] = '99' then '支払済'
            end,
            case _.[支払区分]
                when '1' then _.[発送伝票番号]
                else _.[クレジット承認番号]
            end,
            _.[正味金額]
        ),
        (
            case
                when _.[店舗コード] in ('1', '20') then 'IMCポイント'
                when _.[店舗コード] in ('3', '4') then '楽天ポイント'
                when _.[店舗コード] in ('5', '6') then 'Yahooポイント'
            end,
            null,
            _.[ポイント数]
        ),
        (
            '銀行振込',
            _.[オプション２],
            _.[オプション３]
        )
    ) as v ([支払方法], [支払番号], [支払金額])
    where v.[支払金額] <> 0
),

section as (
    select
        _.[店舗コード],
        _.[セクション]
    from (
        values
        ('1', '自社'),
        ('2', 'デジマート'),
        ('3', '楽天WEBSHOP'),
        ('4', '楽天17SHOPS'),
        ('5', 'Yahoo!WEBSHOP'),
        ('6', 'Yahoo!17SHOPS'),
        ('7', 'Amazon'),
        ('10', 'Amazon FBA'),
        ('12', 'eBay'),
        ('13', 'Reverb'),
        ('14', '海外バイヤー'),
        ('17', 'ヤフオク'),
        ('18', '自社海外'),
        ('20', '自社')
    ) as _ ([店舗コード], [セクション])
),

staff as (
    select
        _.[担当者],
        replace(_.[担当者名], '　', '') as [担当者名]
    from dbo.APV_RM_STAFF_M as _
),

ne_sales as (
    select
        _.[処理日付] as [日付],
        _.[伝票番号],
        s.[セクション],
        n.[受注番号] as [識別番号],
        _.[出荷先] as [店舗],
        coalesce(t.[担当者名], 'FBA担当者') as [担当者],
        n.[支払方法],
        n.[支払番号],
        case _.[取引区分]
            when 1100 then n.[支払金額]
            else -n.[支払金額]
        end as [支払金額]
    from dbo.APV_RT_SALES as _
    left join ne_payment as n on _.[伝票番号] = n.[伝票番号]
    left join section as s on n.[店舗コード] = s.[店舗コード]
    left join staff as t on n.[オプション９] = t.[担当者]
    where
        _.[売上額] <> 0
        and _.[処理日付] >= @date_from_compact
        and _.[処理日付] < @date_to_exclusive_compact
        and _.[作成ＰＧＭ] in ('NNB200E', 'REC_NEUR')
),

school_sales as (
    select
        _.[伝票日付] as [日付],
        _.[伝票番号],
        '取込売上' as [セクション],
        _.[顧客番号] as [識別番号],
        _.[自店コード] as [店舗],
        'レゾン' as [担当者],
        '銀行振込' as [支払方法],
        _.[決済番号] as [支払番号],
        cast(_.[支払金額] as int) as [支払金額]
    from dbo.APV_RT_SALES_PAYMENT as _
    where
        _.[伝票日付] >= @date_from_compact
        and _.[伝票日付] < @date_to_exclusive_compact
),

pos_source as (
    select
        _.[送受信管理番号],
        _.[送受信管理行番号],
        _.[取引ＩＤ],
        _.[販売員コード],
        _.[伝票番号],
        _.[取扱カード会社],
        _.[メモ],
        _.[レシート番号],
        cast(_.[合計] as int) as [合計],
        cast(_.[内現金支払金額] as int) as [内現金支払金額],
        cast(_.[内クレジット支払金額] as int) as [内クレジット支払金額],
        cast(_.[使用ポイント] as int) as [使用ポイント]
    from dbo.APV_RF_SPOS_SALES as _
    where
        _.[取引区分] = '1'
        and _.[取引日時] >= @date_from_hyphen
        and _.[取引日時] < @date_to_exclusive_hyphen
),

pos_payment as (
    select
        _.[取引ＩＤ],
        _.[レシート番号],
        _.[販売員コード],
        p.[支払方法],
        p.[支払番号],
        p.[支払金額]
    from pos_source as _
    cross apply (
        select
            v.[支払方法],
            v.[支払番号],
            v.[支払金額]
        from (
            values
            (
                '現金',
                null,
                _.[内現金支払金額]
            ),
            (
                case _.[取扱カード会社]
                    when ' ' then 'クレジット手入力'
                    when 'Transportation system IC' then '交通系IC'
                    else _.[取扱カード会社]
                end,
                right('00000' + _.[伝票番号], 5),
                _.[内クレジット支払金額]
            ),
            (
                'IMCポイント',
                null,
                _.[使用ポイント]
            ),
            (
                '前受金',
                null,
                _.[合計]
                - _.[内現金支払金額]
                - _.[内クレジット支払金額]
                - coalesce((
                    select sum(cast(o.[預かり金その他] as int))
                    from dbo.APV_RF_SPOS_SALES_PAYMENT as o
                    where
                        o.[送受信管理番号] = _.[送受信管理番号]
                        and o.[送受信管理行番号] = _.[送受信管理行番号]
                ), 0)
            )
        ) as v ([支払方法], [支払番号], [支払金額])
        union all
        select
            case o.[その他支払方法ＩＤ]
                when '18' then 'IMCポイント'
                else o.[支払方法名]
            end as [支払方法],
            case o.[その他支払方法ＩＤ]
                when '18' then null
                else _.[メモ]
            end as [支払番号],
            cast(o.[預かり金その他] as int) as [支払金額]
        from dbo.APV_RF_SPOS_SALES_PAYMENT as o
        where
            o.[送受信管理番号] = _.[送受信管理番号]
            and o.[送受信管理行番号] = _.[送受信管理行番号]
    ) as p
    where p.[支払金額] <> 0
),

pos_sales as (
    select
        _.[処理日付] as [日付],
        _.[備考] as [伝票番号],
        'スマレジ' as [セクション],
        p.[レシート番号] as [識別番号],
        _.[出荷先] as [店舗],
        t.[担当者名] as [担当者],
        p.[支払方法],
        p.[支払番号],
        p.[支払金額]
    from dbo.APV_RT_SALES as _
    left join pos_payment as p on _.[備考] = p.[取引ＩＤ]
    left join staff as t on p.[販売員コード] = t.[担当者]
    where
        _.[売上額] <> 0
        and _.[処理日付] >= @date_from_compact
        and _.[処理日付] < @date_to_exclusive_compact
        and _.[作成ＰＧＭ] = 'TFO300E'
)

select
    cast(_.[日付] as datetime) as [日付],
    cast(_.[伝票番号] as int) as [伝票番号],
    _.[セクション],
    _.[識別番号],
    cast(_.[店舗] as int) as [店舗],
    _.[担当者],
    _.[支払方法],
    _.[支払番号],
    _.[支払金額]
from (
    select * from ne_sales
    union all
    select * from school_sales
    union all
    select * from pos_sales
) as _;
