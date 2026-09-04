SET NOCOUNT ON;

DECLARE @DateFrom char(8) = '20260601';
DECLARE @DateTo   char(8) = '20260831';

DROP TABLE IF EXISTS #Sales;
DROP TABLE IF EXISTS #TargetTransaction;
DROP TABLE IF EXISTS #Pos;
DROP TABLE IF EXISTS #PosOtherPayment;

SELECT
    S.[処理日付],
    S.[売上先],
    S.[売上セクション],
    S.[出荷備考],
    S.[販売担当者],
    SUM(S.[売価金額] + S.[売価消費税]) AS [売価]
INTO
    #Sales
FROM
    dbo.APV_RT_SALES_R AS S
WHERE
    S.[処理日付] >= @DateFrom
    AND S.[処理日付] <= @DateTo
GROUP BY
    S.[処理日付],
    S.[売上先],
    S.[売上セクション],
    S.[出荷備考],
    S.[販売担当者]
HAVING
    SUM(S.[売価金額] + S.[売価消費税]) <> 0
OPTION
    (RECOMPILE);

CREATE CLUSTERED
INDEX CX_Sales_TransactionId ON #Sales ([出荷備考]);

SELECT
    S.[出荷備考] AS [取引ＩＤ]
INTO
    #TargetTransaction
FROM
    #Sales AS S
WHERE
    S.[出荷備考] IS NOT NULL
GROUP BY
    S.[出荷備考];

CREATE UNIQUE CLUSTERED
INDEX CX_TargetTransaction_TransactionId ON #TargetTransaction ([取引ＩＤ]);

SELECT
    P.[取引ＩＤ],
    ISNULL(TRY_CAST(P.[ポイント値引き] AS int), 0) AS [ポイント値引き],
    ISNULL(TRY_CAST(P.[合計] AS int), 0) AS [合計],
    ISNULL(TRY_CAST(P.[内現金支払金額] AS int), 0) AS [内現金支払金額],
    ISNULL(TRY_CAST(P.[内クレジット支払金額] AS int), 0) AS [内クレジット支払金額],
    P.[伝票番号],
    P.[取扱カード会社],
    P.[メモ],
    P.[レシート番号]
INTO
    #Pos
FROM
    #TargetTransaction AS T
    INNER JOIN dbo.APV_RF_SPOS_SALES AS P ON P.[取引ＩＤ] = T.[取引ＩＤ]
WHERE
    P.[取引区分] = N'1';

CREATE CLUSTERED
INDEX CX_Pos_TransactionId ON #Pos ([取引ＩＤ]);

SELECT
    OP.[取引ＩＤ],
    OP.[その他支払方法ＩＤ],
    OP.[支払方法名],
    ISNULL(TRY_CAST(OP.[預かり金その他] AS int), 0) AS [預かり金その他]
INTO
    #PosOtherPayment
FROM
    #TargetTransaction AS T
    INNER JOIN dbo.APV_RF_SPOS_SALES_PAYMENT AS OP ON OP.[取引ＩＤ] = T.[取引ＩＤ];

CREATE CLUSTERED
INDEX CX_PosOtherPayment_TransactionId ON #PosOtherPayment ([取引ＩＤ]);

WITH
    OtherPaymentSummary AS (
        SELECT
            OP.[取引ＩＤ],
            SUM(OP.[預かり金その他]) AS [預かり金その他合計]
        FROM
            #PosOtherPayment AS OP
        GROUP BY
            OP.[取引ＩＤ]
    ),
    Payment AS (
        SELECT
            P.[取引ＩＤ],
            V.[支払方法],
            V.[支払番号],
            CAST(P.[レシート番号] AS nvarchar(100)) AS [受注番号],
            V.[支払金額]
        FROM
            #Pos AS P
            LEFT JOIN OtherPaymentSummary AS OPS ON OPS.[取引ＩＤ] = P.[取引ＩＤ]
            CROSS APPLY (
                VALUES
                    (
                        CAST(N'IMCポイント' AS nvarchar(100)),
                        CAST(NULL AS nvarchar(100)),
                        P.[ポイント値引き]
                    ),
                    (
                        CAST(N'現金' AS nvarchar(100)),
                        CAST(NULL AS nvarchar(100)),
                        P.[内現金支払金額]
                    ),
                    (
                        CAST(
                            CASE P.[取扱カード会社]
                                WHEN N' ' THEN N'クレジット手入力'
                                WHEN N'Transportation system IC' THEN N'交通系IC'
                                ELSE P.[取扱カード会社]
                            END AS nvarchar(100)
                        ),
                        CAST(
                            RIGHT(N'00000' + CAST(P.[伝票番号] AS nvarchar(100)), 5) AS nvarchar(100)
                        ),
                        P.[内クレジット支払金額]
                    ),
                    (
                        CAST(N'前受金' AS nvarchar(100)),
                        CAST(NULL AS nvarchar(100)),
                        P.[合計] - P.[内現金支払金額] - P.[内クレジット支払金額] - ISNULL(OPS.[預かり金その他合計], 0)
                    )
            ) AS V ([支払方法], [支払番号], [支払金額])
        WHERE
            V.[支払金額] <> 0
        UNION ALL
        SELECT
            P.[取引ＩＤ],
            CAST(
                CASE OP.[その他支払方法ＩＤ]
                    WHEN N'18' THEN N'IMCポイント'
                    ELSE OP.[支払方法名]
                END AS nvarchar(100)
            ) AS [支払方法],
            CAST(
                CASE OP.[その他支払方法ＩＤ]
                    WHEN N'18' THEN NULL
                    ELSE P.[メモ]
                END AS nvarchar(100)
            ) AS [支払番号],
            CAST(P.[レシート番号] AS nvarchar(100)) AS [受注番号],
            OP.[預かり金その他] AS [支払金額]
        FROM
            #Pos AS P
            INNER JOIN #PosOtherPayment AS OP ON OP.[取引ＩＤ] = P.[取引ＩＤ]
        WHERE
            OP.[預かり金その他] <> 0
    )
SELECT
    CAST(S.[処理日付] AS datetime) AS [日付],
    CAST(S.[売上先] AS int) AS [店舗],
    CAST(SEC.[セクション名] AS nvarchar(100)) AS [セクション],
    CAST(S.[出荷備考] AS int) AS [伝票番号],
    CAST(REPLACE(STF.[担当者名], N'　', N'') AS nvarchar(100)) AS [担当者],
    CAST(S.[売価] AS int) AS [合計金額],
    P.[支払方法],
    P.[支払番号],
    P.[受注番号],
    CAST(P.[支払金額] AS int) AS [支払金額]
FROM
    #Sales AS S
    LEFT JOIN dbo.APV_RM_SECTION_M AS SEC ON SEC.[セクション] = S.[売上セクション]
    LEFT JOIN dbo.APV_RM_STAFF_M AS STF ON STF.[担当者] = S.[販売担当者]
    LEFT JOIN Payment AS P ON P.[取引ＩＤ] = S.[出荷備考];
