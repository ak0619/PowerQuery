// 接続文字列
"Provider = Microsoft.ACE.OLEDB.16.0; Data Source = C:\imprg_settings\database\財務利用者限定ＤＢ.accdb"
    meta [
        IsParameterQuery = true,
        Type = "Text",
        IsParameterQueryRequired = true
    ]

// POS_現金
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_APV_RF_SPOS_SALES"),
    列を選択 = Table.SelectColumns(ソース, {"取引ＩＤ", "取引区分", "内現金支払金額", "レシート番号"}),
    行を選択 = Table.SelectRows(列を選択, each ([取引区分] = "1") and ([内現金支払金額] <> "0")),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            店舗コード = "0",
            支払方法 = "現金",
            支払番号 = "",
            支払額 = Number.Abs(Number.From([内現金支払金額]))
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(
        レコード列を追加,
        "レコード",
        {"店舗コード", "支払方法", "支払番号", "支払額"}
    ),
    列を削除 = Table.RemoveColumns(レコード列を展開, {"取引区分", "内現金支払金額"}),
    列名を変更 = Table.RenameColumns(列を削除, {{"取引ＩＤ", "伝票番号"}, {"レシート番号", "受注番号"}}),
    列順を並替 = Table.ReorderColumns(
        列名を変更,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// POS_ポイント
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_APV_RF_SPOS_SALES"),
    列を選択 = Table.SelectColumns(ソース, {"取引ＩＤ", "取引区分", "ポイント値引き", "レシート番号"}),
    行を選択 = Table.SelectRows(
        列を選択,
        each ([取引区分] = "1") and ([ポイント値引き] <> "0")
    ),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            店舗コード = "0",
            支払方法 = "IMCポイント",
            支払番号 = "",
            支払額 = Number.Abs(Number.From([ポイント値引き]))
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(
        レコード列を追加,
        "レコード",
        {"店舗コード", "支払方法", "支払番号", "支払額"}
    ),
    列を削除 = Table.RemoveColumns(レコード列を展開, {"取引区分", "ポイント値引き"}),
    列名を変更 = Table.RenameColumns(列を削除, {{"取引ＩＤ", "伝票番号"}, {"レシート番号", "受注番号"}}),
    列順を並替 = Table.ReorderColumns(
        列名を変更,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// POS_クレジット
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_APV_RF_SPOS_SALES"),
    列を選択 = Table.SelectColumns(
        ソース,
        {"取引ＩＤ", "取引区分", "内クレジット支払金額", "伝票番号", "取扱カード会社", "レシート番号"}
    ),
    行を選択 = Table.SelectRows(
        列を選択,
        each ([取引区分] = "1") and ([内クレジット支払金額] <> "0")
    ),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            店舗コード = "0",
            支払方法 =
                if [取扱カード会社] = " " then
                    "クレジット手入力"
                else if [取扱カード会社] = "Transportation system IC" then
                    "交通系IC"
                else
                    [取扱カード会社],
            支払番号 = if [伝票番号] = " " then "" else Text.PadStart([伝票番号], 5, "0"),
            支払額 = Number.Abs(Number.From([内クレジット支払金額]))
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(
        レコード列を追加,
        "レコード",
        {"店舗コード", "支払方法", "支払番号", "支払額"}
    ),
    列を削除 = Table.RemoveColumns(
        レコード列を展開,
        {"取引区分", "内クレジット支払金額", "伝票番号", "取扱カード会社"}
    ),
    列名を変更 = Table.RenameColumns(列を削除, {{"取引ＩＤ", "伝票番号"}, {"レシート番号", "受注番号"}}),
    列順を並替 = Table.ReorderColumns(
        列名を変更,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// POS_他支払
let
    ソース = OleDb.Query(
        接続文字列,
        Text.Combine(
            {
                "   SELECT *",
                "     FROM dbo_APV_RF_SPOS_SALES_PAYMENT AS a",
                "LEFT JOIN dbo_APV_RF_SPOS_SALES AS b",
                "       ON a.送受信管理番号 = b.送受信管理番号",
                "      AND a.送受信管理行番号 = b.送受信管理行番号"
            },
            "#(lf)"
        )
    ),
    列を選択 = Table.SelectColumns(
        ソース,
        {"a.取引ＩＤ", "支払方法名", "預かり金その他", "メモ", "レシート番号"}
    ),
    行を選択 = Table.SelectRows(列を選択, each ([預かり金その他] <> "0")),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            店舗コード = "0",
            支払方法 =
                if Text.StartsWith([支払方法名], "IMCポイント") then
                    "IMCポイント"
                else
                    [支払方法名],
            支払番号 = Text.Trim(Text.Clean([メモ])),
            支払額 = Number.Abs(Number.From([預かり金その他]))
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(
        レコード列を追加,
        "レコード",
        {"店舗コード", "支払方法", "支払番号", "支払額"}
    ),
    列を削除 = Table.RemoveColumns(レコード列を展開, {"支払方法名", "預かり金その他", "メモ"}),
    列名を変更 = Table.RenameColumns(
        列を削除,
        {{"a.取引ＩＤ", "伝票番号"}, {"レシート番号", "受注番号"}}
    ),
    列順を並替 = Table.ReorderColumns(
        列名を変更,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// POS_前受金
let
    ソース = OleDb.Query(
        接続文字列,
        Text.Combine(
            {
                "   SELECT *",
                "     FROM dbo_APV_RF_SPOS_SALES AS a",
                "LEFT JOIN dbo_APV_RF_SPOS_SALES_PAYMENT AS b",
                "       ON a.送受信管理番号 = b.送受信管理番号",
                "      AND a.送受信管理行番号 = b.送受信管理行番号",
                "    WHERE b.送受信管理番号 IS NULL"
            },
            "#(lf)"
        )
    ),
    列を選択 = Table.SelectColumns(
        ソース,
        {"a.取引ＩＤ", "取引区分", "合計", "内現金支払金額", "内クレジット支払金額", "預かり金", "レシート番号"}
    ),
    行を選択 = Table.SelectRows(
        列を選択,
        each ([取引区分] = "1")
            and ([合計] <> "0")
            and ([内現金支払金額] = "0")
            and ([内クレジット支払金額] = "0")
    ),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            店舗コード = "0",
            支払方法 = "前受金",
            支払番号 = "",
            支払額 = Number.Abs(Number.From([預かり金]))
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(
        レコード列を追加,
        "レコード",
        {"店舗コード", "支払方法", "支払番号", "支払額"}
    ),
    列を削除 = Table.RemoveColumns(
        レコード列を展開,
        {"取引区分", "合計", "内現金支払金額", "内クレジット支払金額", "預かり金"}
    ),
    列名を変更 = Table.RenameColumns(
        列を削除,
        {{"a.取引ＩＤ", "伝票番号"}, {"レシート番号", "受注番号"}}
    ),
    列順を並替 = Table.ReorderColumns(
        列名を変更,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// 取込売上
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_APV_RT_SALES_PAYMENT"),
    列を選択 = Table.SelectColumns(ソース, {"伝票番号", "顧客番号", "決済番号", "支払金額"}),
    レコード列を追加 = Table.AddColumn(
        列を選択,
        "レコード",
        each [店舗コード = "-1", 支払方法 = "銀行振込"]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(レコード列を追加, "レコード", {"店舗コード", "支払方法"}),
    列名を変更 = Table.RenameColumns(
        レコード列を展開,
        {{"顧客番号", "受注番号"}, {"決済番号", "支払番号"}, {"支払金額", "支払額"}}
    ),
    列順を並替 = Table.ReorderColumns(
        列名を変更,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// NE_ポイント
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_IM_NE_SALES WHERE 法人 = '000'"),
    列を選択 = Table.SelectColumns(ソース, {"店舗コード", "伝票番号", "受注番号", "ポイント数"}),
    行を選択 = Table.SelectRows(列を選択, each ([ポイント数] <> "0.00")),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            支払方法 =
                if [店舗コード] = "20" or [店舗コード] = "1" then
                    "IMCポイント"
                else if [店舗コード] = "3" or [店舗コード] = "4" then
                    "楽天ポイント"
                else if [店舗コード] = "5" or [店舗コード] = "6" then
                    "Yahooポイント"
                else
                    "",
            支払番号 = [受注番号],
            支払額 = Number.From([ポイント数])
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(
        レコード列を追加,
        "レコード",
        {"支払方法", "支払番号", "支払額"}
    ),
    列を削除 = Table.RemoveColumns(レコード列を展開, {"ポイント数"}),
    列順を並替 = Table.ReorderColumns(
        列を削除,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// NE_銀行振込_1
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_IM_NE_SALES WHERE 法人 = '000'"),
    列を選択 = Table.SelectColumns(
        ソース,
        {"店舗コード", "伝票番号", "受注番号", "支払区分", "総合計", "クレジット承認番号", "オプション３"}
    ),
    行を選択 = Table.SelectRows(列を選択, each ([総合計] <> "0.00" and [支払区分] = "15")),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            支払方法 = if [店舗コード] = "3" or [店舗コード] = "4" then "楽天ペイ" else "銀行振込",
            支払番号 = if [クレジット承認番号] = " " then [受注番号] else [クレジット承認番号],
            支払額 = Number.From([総合計])
                - (if [オプション３] = " " then 0 else Number.From([オプション３]))
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(
        レコード列を追加,
        "レコード",
        {"支払方法", "支払番号", "支払額"}
    ),
    列を削除 = Table.RemoveColumns(レコード列を展開, {"支払区分", "総合計", "クレジット承認番号", "オプション３"}),
    列順を並替 = Table.ReorderColumns(
        列を削除,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// NE_銀行振込_2
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_IM_NE_SALES WHERE 法人 = '000'"),
    列を選択 = Table.SelectColumns(
        ソース,
        {"店舗コード", "伝票番号", "受注番号", "オプション２", "オプション３"}
    ),
    行を選択 = Table.SelectRows(列を選択, each ([オプション２] <> " ")),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [支払方法 = "銀行振込", 支払額 = Number.From([オプション３])]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(レコード列を追加, "レコード", {"支払方法", "支払額"}),
    列を削除 = Table.RemoveColumns(レコード列を展開, {"オプション３"}),
    列名を変更 = Table.RenameColumns(列を削除, {{"オプション２", "支払番号"}}),
    列順を並替 = Table.ReorderColumns(
        列名を変更,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// NE_クレジット
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_IM_NE_SALES WHERE 法人 = '000'"),
    列を選択 = Table.SelectColumns(
        ソース,
        {"店舗コード", "伝票番号", "受注番号", "支払区分", "総合計", "オプション３"}
    ),
    行を選択 = Table.SelectRows(列を選択, each ([支払区分] = "0" and [総合計] <> "0.00")),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            支払方法 =
                if [店舗コード] = "2" then
                    "デジマート"
                else if [店舗コード] = "3" or [店舗コード] = "4" then
                    "楽天ペイ"
                else if [店舗コード] = "5" or [店舗コード] = "6" or [店舗コード] = "17" then
                    "Yahoo"
                else if [店舗コード] = "20" then
                    "MS クレジットカード"
                else
                    "",
            支払番号 = [受注番号],
            支払額 = Number.From([総合計])
                - (if [オプション３] = " " then 0 else Number.From([オプション３]))
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(
        レコード列を追加,
        "レコード",
        {"支払方法", "支払番号", "支払額"}
    ),
    列を削除 = Table.RemoveColumns(レコード列を展開, {"支払区分", "総合計", "オプション３"}),
    列順を並替 = Table.ReorderColumns(
        列を削除,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// NE_代金引換
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_IM_NE_SALES WHERE 法人 = '000'"),
    列を選択 = Table.SelectColumns(
        ソース,
        {"店舗コード", "伝票番号", "受注番号", "支払区分", "発送方法区分", "総合計", "発送伝票番号", "オプション３"}
    ),
    行を選択 = Table.SelectRows(列を選択, each ([支払区分] = "1" and [総合計] <> "0.00")),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            支払方法 =
                if [発送方法区分] = "13" then
                    "佐川コレクト"
                else if [発送方法区分] = "21" then
                    "ヤマトコレクト"
                else if [発送方法区分] = "30" then
                    "ゆうパックコレクト"
                else
                    "",
            支払額 = Number.From([総合計])
                - (if [オプション３] = " " then 0 else Number.From([オプション３]))
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(レコード列を追加, "レコード", {"支払方法", "支払額"}),
    列を削除 = Table.RemoveColumns(レコード列を展開, {"支払区分", "発送方法区分", "総合計", "オプション３"}),
    列名を変更 = Table.RenameColumns(列を削除, {{"発送伝票番号", "支払番号"}}),
    列順を並替 = Table.ReorderColumns(
        列名を変更,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// NE_コンビニ
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_IM_NE_SALES WHERE 法人 = '000'"),
    列を選択 = Table.SelectColumns(
        ソース,
        {"店舗コード", "伝票番号", "受注番号", "支払区分", "総合計", "オプション３"}
    ),
    行を選択 = Table.SelectRows(
        列を選択,
        each (
            [支払区分] = "32" or [支払区分] = "35" or [支払区分] = "36" and [総合計] <> "0.00"
        )
    ),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            支払方法 =
                if [店舗コード] = "3" or [店舗コード] = "4" then
                    "楽天ペイ"
                else if [店舗コード] = "10" then
                    "Amazon"
                else if [店舗コード] = "17" then
                    "Yahoo"
                else if [店舗コード] = "20" then
                    "MS コンビニ"
                else
                    "",
            支払番号 = [受注番号],
            支払額 = Number.From([総合計])
                - (if [オプション３] = " " then 0 else Number.From([オプション３]))
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(
        レコード列を追加,
        "レコード",
        {"支払方法", "支払番号", "支払額"}
    ),
    列を削除 = Table.RemoveColumns(レコード列を展開, {"支払区分", "総合計", "オプション３"}),
    列順を並替 = Table.ReorderColumns(
        列を削除,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// NE_PayPay
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_IM_NE_SALES WHERE 法人 = '000'"),
    列を選択 = Table.SelectColumns(
        ソース,
        {"店舗コード", "伝票番号", "受注番号", "支払区分", "総合計", "オプション３"}
    ),
    行を選択 = Table.SelectRows(
        列を選択,
        each ([支払区分] = "72" or [支払区分] = "76" and [総合計] <> "0.00")
    ),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            支払方法 =
                if [店舗コード] = "1" then
                    "SB PayPay"
                else if [店舗コード] = "5" or [店舗コード] = "6" or [店舗コード] = "17" then
                    "Yahoo"
                else if [店舗コード] = "20" then
                    "MS PayPay"
                else
                    "",
            支払番号 = [受注番号],
            支払額 = Number.From([総合計])
                - (if [オプション３] = " " then 0 else Number.From([オプション３]))
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(
        レコード列を追加,
        "レコード",
        {"支払方法", "支払番号", "支払額"}
    ),
    列を削除 = Table.RemoveColumns(レコード列を展開, {"支払区分", "総合計", "オプション３"}),
    列順を並替 = Table.ReorderColumns(
        列を削除,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// NE_他支払
let
    ソース = OleDb.Query(接続文字列, "SELECT * FROM dbo_IM_NE_SALES WHERE 法人 = '000'"),
    列を選択 = Table.SelectColumns(
        ソース,
        {"店舗コード", "伝票番号", "受注番号", "支払区分", "総合計", "クレジット承認番号", "オプション３"}
    ),
    行を選択 = Table.SelectRows(
        列を選択,
        each List.Contains(
            {
                "30",
                "31",
                "42",
                "43",
                "48",
                "53",
                "54",
                "56",
                "57",
                "60",
                "63",
                "67",
                "70",
                "95",
                "96",
                "99"
            },
            [支払区分]
        )
            and [総合計] <> "0.00"
    ),
    支払方法変換表 = Table.Buffer(
        #table(
            type table [支払区分 = text, 支払方法 = text],
            {
                {"30", "JACCSショッピングクレジット"},
                {"31", "ORICOショッピングクレジット"},
                {"42", "Shopify ペイメント"},
                {"43", "Shopify KOMOJU"},
                {"48", "Amazon Pay"},
                {"53", "PAYGENT VISA/MASTER"},
                {"54", "PAYGENT コンビニ"},
                {"56", "PAYGENT ATM"},
                {"57", "PAYGENT JCB"},
                {"60", "PayPal"},
                {"63", "Yahoo"},
                {"67", "Payoneer"},
                {"70", "MS バーチャル口座"},
                {"95", "売掛"},
                {"96", "Amazon"},
                {"99", "支払済"}
            }
        )
    ),
    レコード列を追加 = Table.AddColumn(
        行を選択,
        "レコード",
        each [
            支払方法 = 支払方法変換表{[支払区分 = [支払区分]]}[支払方法]?,
            支払番号 = if [クレジット承認番号] = " " then [受注番号] else [クレジット承認番号],
            支払額 = Number.From([総合計])
                - (if [オプション３] = " " then 0 else Number.From([オプション３]))
        ]
    ),
    レコード列を展開 = Table.ExpandRecordColumn(
        レコード列を追加,
        "レコード",
        {"支払方法", "支払番号", "支払額"}
    ),
    列を削除 = Table.RemoveColumns(レコード列を展開, {"支払区分", "総合計", "クレジット承認番号", "オプション３"}),
    列順を並替 = Table.ReorderColumns(
        列を削除,
        {"伝票番号", "店舗コード", "支払方法", "支払番号", "支払額", "受注番号"}
    )
in
    列順を並替

// 売上統合
let
    ソース = Table.Combine(
        {
            POS_現金,
            POS_ポイント,
            POS_クレジット,
            POS_他支払,
            POS_前受金,
            NE_ポイント,
            NE_銀行振込_1,
            NE_銀行振込_2,
            NE_クレジット,
            NE_代金引換,
            NE_コンビニ,
            NE_PayPay,
            NE_他支払,
            取込売上
        }
    ),
    データ型を変更 = Table.TransformColumnTypes(
        ソース,
        {
            {"伝票番号", Int64.Type},
            {"店舗コード", Int64.Type},
            {"支払方法", type text},
            {"支払番号", type text},
            {"支払額", Int64.Type}
        }
    ),
    セクション変換表 = Table.Buffer(
        #table(
            type table [店舗コード = Int64.Type, セクション = text],
            {
                {-1, "取込売上"},
                {0, "スマレジ"},
                {1, "自社EC"},
                {2, "デジマート"},
                {3, "楽天WEBSHOP"},
                {4, "楽天17SHOPS"},
                {5, "Yahoo!WEBSHOP"},
                {6, "Yahoo!17SHOPS"},
                {7, "Amazon"},
                {8, "楽天UBOX"},
                {9, "調整"},
                {10, "FBA"},
                {11, "旧越境EC"},
                {12, "eBay"},
                {13, "Reverb"},
                {14, "海外バイヤー"},
                {15, "上海UBOX"},
                {16, "ヤフオク店"},
                {17, "Yahoo!オークション"},
                {18, "Shopify"},
                {19, "店頭"},
                {20, "自社ECM"}
            }
        )
    ),
    セクションを追加 = Table.AddColumn(
        データ型を変更,
        "セクション",
        each セクション変換表{[店舗コード = [店舗コード]]}[セクション]?,
        type text
    ),
    列を選択 = Table.SelectColumns(
        セクションを追加,
        {"伝票番号", "セクション", "支払方法", "支払番号", "支払額", "受注番号"}
    ),
    重複を削除 = Table.Distinct(列を選択)
in
    重複を削除

// 売上履歴
let
    ソース = OleDb.Query(
        接続文字列,
        "SELECT * FROM dbo_APV_RT_SALES WHERE 売上額 <> 0 AND 備考 NOT IN ('66307', '66317')"
    ),
    列を選択 = Table.SelectColumns(
        ソース,
        {"出荷先", "伝票日付", "伝票番号", "取引区分", "備考", "作成ＰＧＭ"}
    ),
    #"伝票番号'を追加" = Table.AddColumn(
        列を選択,
        "伝票番号'",
        each if [作成ＰＧＭ] = "NNB200E" then [伝票番号] else [備考],
        type text
    ),
    列を削除 = Table.RemoveColumns(#"伝票番号'を追加", {"伝票番号", "備考", "作成ＰＧＭ"}),
    列名を変更 = Table.RenameColumns(
        列を削除,
        {{"出荷先", "店舗"}, {"伝票日付", "売上日"}, {"伝票番号'", "伝票番号"}}
    ),
    データ型を変更 = Table.TransformColumnTypes(
        列名を変更,
        {{"店舗", Int64.Type}, {"売上日", type date}, {"伝票番号", Int64.Type}}
    ),
    売上統合と結合 = Table.NestedJoin(
        データ型を変更,
        {"伝票番号"},
        売上統合,
        {"伝票番号"},
        "売上統合",
        JoinKind.LeftOuter
    ),
    売上統合を展開 = Table.ExpandTableColumn(
        売上統合と結合,
        "売上統合",
        {"セクション", "支払方法", "支払番号", "支払額", "受注番号"},
        {"セクション", "支払方法", "支払番号", "支払額", "受注番号"}
    ),
    #"支払額'を追加" = Table.AddColumn(
        売上統合を展開,
        "支払額'",
        each if [取引区分] = 1100 then [支払額] else - [支払額],
        Int64.Type
    ),
    列を選択2 = Table.SelectColumns(
        #"支払額'を追加",
        {"売上日", "店舗", "伝票番号", "セクション", "支払方法", "支払番号", "支払額'", "受注番号"}
    ),
    列名を変更2 = Table.RenameColumns(列を選択2, {{"支払額'", "支払額"}}),
    行を並替 = Table.Sort(
        列名を変更2,
        {
            {"売上日", Order.Ascending},
            {"店舗", Order.Ascending},
            {"伝票番号", Order.Ascending}
        }
    )
in
    行を並替
