SET NOCOUNT ON;

DECLARE @DateFrom char(8) = '20260601';
DECLARE @DateTo   char(8) = '20260831';

DROP TABLE IF EXISTS #Sales;
DROP TABLE IF EXISTS #TargetTransaction;
DROP TABLE IF EXISTS #Pos;
DROP TABLE IF EXISTS #PosOtherPayment;

SELECT
    Sales.[処理日付],
    Sales.[売上先],
    Sales.[売上セクション],
    Sales.[出荷備考],
    Sales.[販売担当者],
    SUM(Sales.[売価金額] + Sales.[売価消費税]) AS [売価]
INTO
    #Sales
FROM
    dbo.APV_RT_SALES_R AS Sales
WHERE
    Sales.[処理日付] >= @DateFrom
    AND Sales.[処理日付] <= @DateTo
GROUP BY
    Sales.[処理日付],
    Sales.[売上先],
    Sales.[売上セクション],
    Sales.[出荷備考],
    Sales.[販売担当者]
HAVING
    SUM(Sales.[売価金額] + Sales.[売価消費税]) <> 0;

CREATE NONCLUSTERED
INDEX SalesByShippingNote ON #Sales ([出荷備考]);

SELECT DISTINCT
    Sales.[出荷備考] AS [取引ＩＤ]
INTO
    #TargetTransaction
FROM
    #Sales AS Sales
WHERE
    Sales.[出荷備考] IS NOT NULL;

CREATE UNIQUE CLUSTERED
INDEX TargetTransactionByTransactionId ON #TargetTransaction ([取引ＩＤ]);

SELECT
    Pos.[取引ＩＤ],
    COALESCE(TRY_CAST(Pos.[ポイント値引き] AS int), 0) AS [ポイント値引き],
    COALESCE(TRY_CAST(Pos.[合計] AS int), 0) AS [合計],
    COALESCE(TRY_CAST(Pos.[内現金支払金額] AS int), 0) AS [内現金支払金額],
    COALESCE(TRY_CAST(Pos.[内クレジット支払金額] AS int), 0) AS [内クレジット支払金額],
    Pos.[伝票番号],
    Pos.[取扱カード会社],
    Pos.[メモ],
    Pos.[レシート番号]
INTO
    #Pos
FROM
    dbo.APV_RF_SPOS_SALES AS Pos
    INNER JOIN #TargetTransaction AS Target ON Target.[取引ＩＤ] = Pos.[取引ＩＤ]
WHERE
    Pos.[取引区分] = N'1';

CREATE CLUSTERED
INDEX PosByTransactionId ON #Pos ([取引ＩＤ]);

SELECT
    Payment.[取引ＩＤ],
    Payment.[その他支払方法ＩＤ],
    Payment.[支払方法名],
    COALESCE(TRY_CAST(Payment.[預かり金その他] AS int), 0) AS [預かり金その他]
INTO
    #PosOtherPayment
FROM
    dbo.APV_RF_SPOS_SALES_PAYMENT AS Payment
    INNER JOIN #TargetTransaction AS Target ON Target.[取引ＩＤ] = Payment.[取引ＩＤ];

CREATE CLUSTERED
INDEX PosOtherPaymentByTransactionId ON #PosOtherPayment ([取引ＩＤ]);

WITH
    OtherPaymentSummary AS (
        SELECT
            Payment.[取引ＩＤ],
            SUM(Payment.[預かり金その他]) AS [預かり金その他合計]
        FROM
            #PosOtherPayment AS Payment
        GROUP BY
            Payment.[取引ＩＤ]
    ),
    StandardPayment AS (
        SELECT
            Pos.[取引ＩＤ],
            Payment.[支払方法],
            Payment.[支払番号],
            CAST(Pos.[レシート番号] AS nvarchar(100)) AS [受注番号],
            Payment.[支払金額]
        FROM
            #Pos AS Pos
            LEFT JOIN OtherPaymentSummary AS Summary ON Summary.[取引ＩＤ] = Pos.[取引ＩＤ]
            CROSS APPLY (
                VALUES
                    (
                        CAST(N'IMCポイント' AS nvarchar(100)),
                        CAST(NULL AS nvarchar(100)),
                        Pos.[ポイント値引き]
                    ),
                    (
                        CAST(N'現金' AS nvarchar(100)),
                        CAST(NULL AS nvarchar(100)),
                        Pos.[内現金支払金額]
                    ),
                    (
                        CAST(
                            CASE Pos.[取扱カード会社]
                                WHEN N' ' THEN N'クレジット手入力'
                                WHEN N'Transportation system IC' THEN N'交通系IC'
                                ELSE Pos.[取扱カード会社]
                            END AS nvarchar(100)
                        ),
                        CAST(
                            RIGHT(N'00000' + CAST(Pos.[伝票番号] AS nvarchar(100)), 5) AS nvarchar(100)
                        ),
                        Pos.[内クレジット支払金額]
                    ),
                    (
                        CAST(N'前受金' AS nvarchar(100)),
                        CAST(NULL AS nvarchar(100)),
                        Pos.[合計] - Pos.[内現金支払金額] - Pos.[内クレジット支払金額] - COALESCE(Summary.[預かり金その他合計], 0)
                    )
            ) AS Payment ([支払方法], [支払番号], [支払金額])
        WHERE
            Payment.[支払金額] <> 0
    ),
    OtherPayment AS (
        SELECT
            Pos.[取引ＩＤ],
            CAST(
                CASE Other.[その他支払方法ＩＤ]
                    WHEN N'18' THEN N'IMCポイント'
                    ELSE Other.[支払方法名]
                END AS nvarchar(100)
            ) AS [支払方法],
            CAST(
                CASE Other.[その他支払方法ＩＤ]
                    WHEN N'18' THEN NULL
                    ELSE Pos.[メモ]
                END AS nvarchar(100)
            ) AS [支払番号],
            CAST(Pos.[レシート番号] AS nvarchar(100)) AS [受注番号],
            Other.[預かり金その他] AS [支払金額]
        FROM
            #Pos AS Pos
            INNER JOIN #PosOtherPayment AS Other ON Other.[取引ＩＤ] = Pos.[取引ＩＤ]
        WHERE
            Other.[預かり金その他] <> 0
    ),
    Payment AS (
        SELECT
            Standard.[取引ＩＤ],
            Standard.[支払方法],
            Standard.[支払番号],
            Standard.[受注番号],
            Standard.[支払金額]
        FROM
            StandardPayment AS Standard
        UNION ALL
        SELECT
            Other.[取引ＩＤ],
            Other.[支払方法],
            Other.[支払番号],
            Other.[受注番号],
            Other.[支払金額]
        FROM
            OtherPayment AS Other
    )
SELECT
    CAST(Sales.[処理日付] AS datetime) AS [日付],
    CAST(Sales.[売上先] AS int) AS [店舗],
    CAST(Section.[セクション名] AS nvarchar(100)) AS [セクション],
    CAST(Sales.[出荷備考] AS int) AS [伝票番号],
    CAST(REPLACE(Staff.[担当者名], N'　', N'') AS nvarchar(100)) AS [担当者],
    CAST(Sales.[売価] AS int) AS [合計金額],
    CAST(Payment.[支払方法] AS nvarchar(100)) AS [支払方法],
    CAST(Payment.[支払番号] AS nvarchar(100)) AS [支払番号],
    CAST(Payment.[受注番号] AS nvarchar(100)) AS [受注番号],
    CAST(Payment.[支払金額] AS int) AS [支払金額]
FROM
    #Sales AS Sales
    LEFT JOIN dbo.APV_RM_SECTION_M AS Section ON Section.[セクション] = Sales.[売上セクション]
    LEFT JOIN dbo.APV_RM_STAFF_M AS Staff ON Staff.[担当者] = Sales.[販売担当者]
    LEFT JOIN Payment ON Payment.[取引ＩＤ] = Sales.[出荷備考];
